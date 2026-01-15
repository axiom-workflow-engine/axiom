---
layout: default
title: API Gateway Design
nav_order: 5
---

# Axiom API Gateway Design

## Executive Summary

The Axiom API Gateway serves as the **durable ingress layer** for the Axiom Workflow Engine. It provides:

- **Protocol unification** (REST & GraphQL → internal request model)
- **Durability guarantees** (requests are fsync'd before acknowledgment)
- **Security enforcement** (authentication, authorization, rate limiting)
- **Schema governance** (workflow definition validation)

> [!IMPORTANT]
> **Core Guarantee**: A `200 OK` from the gateway means the request is persisted and will be processed exactly once, even if the gateway crashes immediately after.

---

## 1. Core Design Philosophy

### 1.1 The Gateway as "Durable Ingress"

The API Gateway is **not** a stateless proxy—it is a **durable request acceptance layer** that guarantees at-least-once delivery to the Workflow Engine. It partners with the engine's WAL for accepted requests before acknowledging clients.

### 1.2 Hybrid Durability Strategy (Enhanced)

Based on industry best practices, we implement a **hybrid approach**:

| Strategy | Use Case | Trade-offs |
|----------|----------|------------|
| **Gateway-local WAL** | Synchronous mutations (workflow creation) | Lower latency, crash-recovery complexity |
| **Message Queue** | Async operations (bulk, webhooks) | Higher latency, simpler scaling |
| **Direct Engine WAL** | High-throughput mode | Lowest overhead, tighter coupling |

```
┌─────────────────────────────────────────────────────────────────┐
│                     CLIENTS (REST / GraphQL)                    │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                   API GATEWAY (Phoenix Application)             │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐                │
│  │  Protocol   │ │  Schema     │ │   Durable   │                │
│  │  Router     │ │  Registry   │ │   Acceptor  │                │
│  └─────────────┘ └─────────────┘ └─────────────┘                │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐                │
│  │  Auth &     │ │ Rate Limit  │ │  Observer   │                │
│  │  IAM Plug   │ │  Plug       │ │  & Telemetry│                │
│  └─────────────┘ └─────────────┘ └─────────────┘                │
└───────────────────────────┬─────────────────────────────────────┘
                            │ gRPC / Erlang Distribution
┌───────────────────────────▼─────────────────────────────────────┐
│              WORKFLOW ENGINE (axiom_engine)                     │
│  (WorkflowProcess, Scheduler, Workers, axiom_wal)               │
└─────────────────────────────────────────────────────────────────┘
```

### 1.3 Protocol Unification

REST and GraphQL are **first-class protocols**, converging on a shared internal request model:

```elixir
defmodule Axiom.Gateway.Request do
  @type t :: %__MODULE__{
    request_id: String.t(),
    idempotency_key: String.t() | nil,
    fencing_token: integer() | nil,
    traceparent: String.t() | nil,
    tenant_id: String.t(),
    accepted_at: DateTime.t(),
    protocol: :rest | :graphql,
    operation: atom(),
    payload: map()
  }
end
```

---

## 2. REST API Design

### 2.1 Endpoint Taxonomy

**Control Plane** (Workflow Lifecycle):

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/v1/workflows` | Create workflow (idempotent) |
| `GET` | `/api/v1/workflows/:id` | Get workflow state |
| `GET` | `/api/v1/workflows/:id/events` | List events (paginated) |
| `POST` | `/api/v1/workflows/:id/cancel` | Cancel workflow |
| `POST` | `/api/v1/workflows/:id/advance` | Manual step advancement |

**Data Plane** (Execution):

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/workflows/:id/lease` | Poll for step task |
| `POST` | `/api/v1/workflows/:id/result` | Submit step result |

**Operational Plane**:

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/health` | Liveness probe |
| `GET` | `/ready` | Readiness probe |
| `GET` | `/api/v1/metrics` | Prometheus metrics |
| `POST` | `/api/v1/chaos/run` | Inject chaos scenario |
| `POST` | `/api/v1/verify` | Consistency verification |

**Schema Governance**:

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/v1/schemas/workflows` | Register workflow schema |
| `GET` | `/api/v1/schemas/workflows/:name` | Get schema definition |
| `GET` | `/api/v1/openapi.json` | Auto-generated OpenAPI spec |

### 2.2 Idempotency Contract (Enhanced)

Based on industry best practices from Stripe, Shopify, and others:

**Client Contract**:

1. Generate unique `Idempotency-Key` header (UUIDv4 recommended, 128-char max)
2. Include same key on all retries of the same logical operation
3. Generate new key for new logical operations

**Server Processing**:

```elixir
defmodule Axiom.Gateway.Idempotency do
  @ttl_seconds 86_400  # 24 hours
  
  def process(key, api_key, endpoint, payload_hash) do
    fingerprint = :crypto.hash(:sha256, "#{key}:#{api_key}:#{endpoint}")
    
    case Cache.get(fingerprint) do
      nil ->
        # New request - process and cache
        {:ok, :new}
        
      %{payload_hash: ^payload_hash, response: response} ->
        # Duplicate - return cached response
        {:ok, :replay, response}
        
      %{payload_hash: _different} ->
        # Key reuse with different payload
        {:error, :conflict}
    end
  end
end
```

**Response Headers**:

- `201 Created` → First acceptance
- `200 OK` + `X-Idempotent-Replay: true` → Duplicate detected
- `409 Conflict` + `X-Idempotent-Key-Mismatch: true` → Key reused with different payload

### 2.3 Bulk Operations

**Endpoint**: `POST /api/v1/workflows/bulk`

**Semantics**:

- Validates each workflow independently
- Returns `207 Multi-Status` with per-workflow results
- Atomic validation: all valid or none accepted
- Uses message queue for async processing (configurable)

```elixir
# Response
%{
  "batch_id" => "batch-uuid",
  "results" => [
    %{"index" => 0, "status" => 201, "workflow_id" => "wf-1"},
    %{"index" => 1, "status" => 422, "error" => %{"code" => "validation_error"}}
  ]
}
```

### 2.4 Webhook Integration

**Endpoint**: `POST /api/v1/webhooks/:webhook_id`

**Security**:

- HMAC-SHA256 signature: `X-Webhook-Signature: sha256=<hex>`
- Timestamp tolerance: ±5 minutes
- Replay protection via idempotency

**Routing**:

```elixir
defmodule Axiom.Gateway.Webhook do
  def route(webhook_id, payload) do
    config = get_webhook_config(webhook_id)
    workflow_id = extract_workflow_id(payload, config.mapping)
    
    # Verify signature
    with :ok <- verify_hmac(payload, config.secret),
         :ok <- verify_timestamp(payload.timestamp) do
      forward_to_workflow(workflow_id, payload)
    end
  end
end
```

---

## 3. GraphQL API Design

### 3.1 Schema Overview

```graphql
type Query {
  workflow(id: ID!): Workflow
  workflows(filter: WorkflowFilter, first: Int, after: String): WorkflowConnection!
  tasks(filter: TaskFilter): TaskConnection!
  metrics: GatewayMetrics!
}

type Mutation {
  createWorkflow(input: CreateWorkflowInput!): WorkflowPayload!
  cancelWorkflow(id: ID!): CancelPayload!
  advanceWorkflow(id: ID!, step: String): AdvancePayload!
  runChaos(scenario: String!, durationMs: Int!): ChaosPayload!
}

type Subscription {
  workflowEvents(workflowId: ID!): WorkflowEvent!
  taskUpdates: TaskUpdate!
}

# Relay-spec connections for pagination
type WorkflowConnection {
  edges: [WorkflowEdge!]!
  pageInfo: PageInfo!
}

type WorkflowEdge {
  cursor: String!
  node: Workflow!
}

type PageInfo {
  hasNextPage: Boolean!
  endCursor: String
}
```

### 3.2 Complexity Analysis (Enhanced)

Based on research, we implement **cost-based rate limiting** instead of simple request counting:

```elixir
defmodule Axiom.Gateway.GraphQL.Complexity do
  @base_cost 1
  @depth_multiplier 2
  @page_cost 0.1
  @max_complexity 1000
  
  def calculate(query) do
    analyze_ast(query.ast, depth: 0, total: @base_cost)
  end
  
  defp analyze_ast(%{selections: selections}, opts) do
    Enum.reduce(selections, opts.total, fn field, acc ->
      field_cost = get_field_cost(field)
      depth_cost = opts.depth * @depth_multiplier
      connection_cost = get_connection_cost(field)
      
      acc + field_cost + depth_cost + connection_cost
    end)
  end
  
  defp get_connection_cost(%{name: name, arguments: args}) when name in ~w(workflows tasks events) do
    limit = args[:first] || args[:limit] || 10
    limit * @page_cost
  end
  defp get_connection_cost(_), do: 0
end
```

**Enforcement**:

- Per-tenant complexity budget: 1000 points/second (configurable)
- Rejected queries return `429 Too Many Requests` with:

  ```json
  {
    "errors": [{"message": "Query complexity 1200 exceeds limit 1000"}],
    "extensions": {"complexity": 1200, "limit": 1000}
  }
  ```

### 3.3 Subscription Lifecycle

**Protocols**: WebSocket (graphql-ws) with SSE fallback

**State Management**:

```elixir
defmodule Axiom.Gateway.SubscriptionRegistry do
  use GenServer
  
  # Registry: subscription_id -> {workflow_id, client_id, last_offset}
  
  def handle_subscribe(workflow_id, client_id) do
    subscription_id = generate_id()
    Phoenix.PubSub.subscribe(Axiom.PubSub, "workflow:#{workflow_id}")
    register(subscription_id, workflow_id, client_id, _offset = 0)
    {:ok, subscription_id}
  end
  
  def handle_reconnect(subscription_id, last_offset) do
    # Replay missed events from WAL
    events = Axiom.WAL.read_from(workflow_id, last_offset)
    {:ok, events}
  end
end
```

**Backpressure**:

- Buffer limit: 10,000 events per subscription
- Slow client protocol: `{"type": "connection_slow", "retry_after": 5000}`
- Unacknowledged subscriptions GC'd after TTL (default 1 hour)

---

## 4. Security & Authentication

### 4.1 Multi-Modal Authentication

| Mode | Use Case | Validation |
|------|----------|------------|
| **API Keys** | Service-to-service | Prefix: `ak_live_`, `ak_test_` |
| **JWT** | Web/mobile clients | RS256, configurable issuer |
| **mTLS** | Worker nodes | Certificate CN → worker pool |
| **Ephemeral Tokens** | Untrusted clients | Single-workflow, short-lived |

```elixir
defmodule Axiom.Gateway.Auth.Plug do
  def call(conn, _opts) do
    with {:ok, credentials} <- extract_credentials(conn),
         {:ok, identity} <- validate_credentials(credentials),
         :ok <- check_permissions(identity, conn.request_path, conn.method) do
      assign(conn, :identity, identity)
    else
      {:error, reason} -> 
        conn |> send_resp(401, error_json(reason)) |> halt()
    end
  end
  
  defp extract_credentials(conn) do
    cond do
      api_key = get_req_header(conn, "x-api-key") -> {:ok, {:api_key, api_key}}
      bearer = get_bearer_token(conn) -> {:ok, {:jwt, bearer}}
      cert = get_client_cert(conn) -> {:ok, {:mtls, cert}}
      true -> {:error, :no_credentials}
    end
  end
end
```

### 4.2 RBAC Model

```elixir
defmodule Axiom.Gateway.RBAC do
  @roles %{
    "admin" => ["*"],
    "workflow_editor" => [
      "workflows:create",
      "workflows:read:*",
      "workflows:cancel:*",
      "schemas:read"
    ],
    "worker" => [
      "workflows:lease:*",
      "workflows:result:*"
    ],
    "reader" => [
      "workflows:read:*",
      "metrics:read"
    ]
  }
  
  def permitted?(identity, permission) do
    permissions = Map.get(@roles, identity.role, [])
    Enum.any?(permissions, &match_permission(&1, permission))
  end
end
```

### 4.3 Rate Limiting (Enhanced)

Based on research, we use **multi-strategy rate limiting**:

| Strategy | Use Case | Algorithm |
|----------|----------|-----------|
| **Token Bucket** | REST mutations | Per-tenant, refill 100/sec |
| **Complexity Budget** | GraphQL | Per-tenant, 1000 points/sec |
| **Leaky Bucket** | Subscriptions | Prevent connection exhaustion |
| **Fixed Window** | Webhooks | Prevent callback flooding |

```elixir
defmodule Axiom.Gateway.RateLimiter do
  use Hammer, backend: {Hammer.Backend.Redis, []}
  
  def check_limit(tenant_id, endpoint, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :token_bucket)
    
    case strategy do
      :token_bucket ->
        Hammer.check_rate("#{tenant_id}:#{endpoint}", 60_000, 100)
        
      :complexity ->
        cost = Keyword.fetch!(opts, :cost)
        Hammer.check_rate_inc("#{tenant_id}:graphql", 1_000, 1000, cost)
        
      :fixed_window ->
        Hammer.check_rate("#{tenant_id}:webhooks", 60_000, 1000)
    end
  end
end
```

**Response Headers**:

- `X-RateLimit-Limit: 100`
- `X-RateLimit-Remaining: 45`
- `X-RateLimit-Reset: 1703980800`
- `Retry-After: 30` (on 429)

---

## 5. Observability

### 5.1 Metrics

Gateway-specific Prometheus metrics:

```elixir
defmodule Axiom.Gateway.Metrics do
  use PromEx, otp_app: :axiom_gateway
  
  @impl true
  def plugins do
    [
      PromEx.Plugins.Application,
      PromEx.Plugins.Beam,
      PromEx.Plugins.Phoenix,
      Axiom.Gateway.Metrics.Plugin
    ]
  end
end

# Custom metrics
:telemetry.execute(
  [:axiom, :gateway, :request, :accepted],
  %{duration: duration_ms},
  %{protocol: :rest, endpoint: endpoint, status: 201}
)
```

| Metric | Type | Description |
|--------|------|-------------|
| `axiom_gateway_request_total` | Counter | Requests by protocol/endpoint/status |
| `axiom_gateway_request_duration_ms` | Histogram | Request latency |
| `axiom_gateway_deduped_total` | Counter | Idempotent replays |
| `axiom_gateway_complexity_total` | Counter | GraphQL complexity consumed |
| `axiom_gateway_subscription_count` | Gauge | Active subscriptions |

### 5.2 Distributed Tracing

```elixir
defmodule Axiom.Gateway.Tracing do
  def start_span(conn) do
    traceparent = get_req_header(conn, "traceparent") |> parse_traceparent()
    
    span = OpenTelemetry.Tracer.start_span(
      "axiom.gateway.#{conn.method}.#{route_name(conn)}",
      parent: traceparent,
      attributes: [
        {"http.method", conn.method},
        {"http.url", conn.request_path},
        {"tenant.id", conn.assigns[:identity][:tenant_id]}
      ]
    )
    
    assign(conn, :span, span)
  end
end
```

### 5.3 Audit Logging

Separate audit WAL for compliance (7-year retention):

```elixir
defmodule Axiom.Gateway.AuditLog do
  @audit_events ~w(
    api_key_created api_key_revoked
    workflow_cancelled
    chaos_injected
    schema_modified
  )a
  
  def log(event_type, identity, metadata) when event_type in @audit_events do
    entry = %{
      event_type: event_type,
      actor: identity,
      timestamp: DateTime.utc_now(),
      metadata: metadata,
      signature: sign(entry)  # HSM-backed signing
    }
    
    Axiom.AuditWAL.append(entry)
  end
end
```

---

## 6. High Availability & Clustering (Enhanced)

Based on research into BEAM-native clustering:

### 6.1 Clustering Strategy

Using `libcluster` for automatic node discovery:

```elixir
# config/runtime.exs
config :libcluster,
  topologies: [
    axiom_gateway: [
      strategy: Cluster.Strategy.Kubernetes,
      config: [
        mode: :dns,
        kubernetes_node_basename: "axiom-gateway",
        kubernetes_selector: "app=axiom-gateway"
      ]
    ]
  ]
```

### 6.2 Active-Active with Consistent Hashing

```elixir
defmodule Axiom.Gateway.Router do
  @hash_ring :axiom_gateway_ring
  
  def route_workflow(workflow_id) do
    node = HashRing.key_to_node(@hash_ring, workflow_id)
    
    if node == Node.self() do
      {:local, workflow_id}
    else
      {:remote, node, workflow_id}
    end
  end
end
```

### 6.3 Graceful Degradation

```elixir
defmodule Axiom.Gateway.CircuitBreaker do
  use Fuse
  
  def call_engine(request) do
    case Fuse.check(:engine_connection) do
      :ok ->
        case Engine.execute(request) do
          {:ok, result} -> {:ok, result}
          {:error, reason} ->
            Fuse.melt(:engine_connection)
            {:error, reason}
        end
        
      :blown ->
        {:error, :circuit_open}
    end
  end
end
```

---

## 7. Configuration

### 7.1 Runtime Configuration

```elixir
# config/runtime.exs
config :axiom_gateway,
  port: System.get_env("PORT", "4000") |> String.to_integer(),
  
  # Durability
  durability_mode: System.get_env("DURABILITY_MODE", "hybrid") |> String.to_atom(),
  
  # Rate limiting
  rate_limit_backend: System.get_env("RATE_LIMIT_BACKEND", "ets"),
  rate_limit_requests_per_minute: 100,
  graphql_complexity_limit: 1000,
  
  # Auth
  jwt_issuer: System.get_env("JWT_ISSUER"),
  jwt_audience: System.get_env("JWT_AUDIENCE"),
  
  # Clustering
  cluster_strategy: System.get_env("CLUSTER_STRATEGY", "epmd"),
  
  # Observability
  otel_exporter: System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT")
```

### 7.2 Hot Reload

```elixir
defmodule Axiom.Gateway.Config do
  use GenServer
  
  # SIGHUP triggers reload
  def handle_info(:sighup, state) do
    new_config = reload_config()
    
    with :ok <- validate_config(new_config),
         :ok <- apply_config(new_config) do
      {:noreply, %{state | config: new_config}}
    else
      {:error, reason} ->
        Logger.error("Config reload failed: #{inspect(reason)}")
        {:noreply, state}
    end
  end
end
```

---

## 8. Project Structure

```
apps/
├── axiom_gateway/
│   ├── lib/
│   │   ├── axiom_gateway/
│   │   │   ├── application.ex
│   │   │   ├── router.ex           # Phoenix Router
│   │   │   ├── controllers/
│   │   │   │   ├── workflow_controller.ex
│   │   │   │   ├── schema_controller.ex
│   │   │   │   ├── health_controller.ex
│   │   │   │   └── webhook_controller.ex
│   │   │   ├── graphql/
│   │   │   │   ├── schema.ex
│   │   │   │   ├── resolvers/
│   │   │   │   ├── subscriptions/
│   │   │   │   └── complexity.ex
│   │   │   ├── plugs/
│   │   │   │   ├── auth.ex
│   │   │   │   ├── rate_limiter.ex
│   │   │   │   ├── idempotency.ex
│   │   │   │   └── tracing.ex
│   │   │   ├── durable/
│   │   │   │   ├── acceptor.ex
│   │   │   │   └── replay.ex
│   │   │   └── telemetry.ex
│   │   └── axiom_gateway.ex
│   ├── test/
│   └── mix.exs
├── axiom_core/              # Shared types & protocols
├── axiom_engine/            # Workflow engine
├── axiom_wal/               # Write-ahead log
└── ...
```

---

## 9. Design Decisions

| Decision | Rationale | Trade-offs |
|----------|-----------|------------|
| **Hybrid WAL + Message Queue** | Balances latency vs. simplicity; sync for critical, async for bulk | Configuration complexity |
| **Complexity-based GraphQL limiting** | Prevents DoS from nested queries; more accurate than request counting | Adds latency to all queries |
| **BEAM-native clustering via libcluster** | Leverages Erlang distribution; simpler than external coordination | Requires cluster topology planning |
| **Separate audit WAL** | Compliance isolation; immutable for legal requirements | Extra storage overhead |
| **Phoenix as gateway framework** | Consistent with engine; excellent WebSocket/SSE support | Less specialized than Kong/Envoy |

---

## Appendix: Error Response Format

All REST errors follow RFC 7807 Problem Details:

```json
{
  "type": "https://axiom.dev/errors/validation-failed",
  "title": "Validation Failed",
  "status": 422,
  "detail": "Workflow definition is missing required field 'steps'",
  "instance": "/api/v1/workflows",
  "errors": [
    {"field": "steps", "code": "required", "message": "Steps array is required"}
  ]
}
```
