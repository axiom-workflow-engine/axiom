# Axiom Workflow Engine

## Enterprise-Grade, Exactly-Once Workflow Orchestration

> **"Our workflow engine guarantees exactly-once business outcomes for systems where retries, crashes, and long-running processes are unavoidable."**

---

## What This System Is

**Axiom** is a:

**Durable** — Events survive any crash  
**Exactly-Once** — Effects commit once, never twice  
**Crash-Safe** — Recovery is automatic  
**Long-Running** — Hours, days, weeks  
**Auditable** — Full replay from event log  

**It is NOT:**

A cron scheduler  
A job queue  
A BPM toy  

---

## When You Need Axiom

Use Axiom when:

| Condition | Axiom Handles It |
|-----------|------------------|
| **Failure is normal** | Automatic recovery |
| **Retries are dangerous** | Fenced execution |
| **Duplication is catastrophic** | Exactly-once semantics |
| **Audits matter** | Immutable event log |
| **Processes span hours/days** | Durable state |

---

## Universal Workflow Lifecycle

Every workflow follows this lifecycle — only step semantics change:

```
CREATED
    ↓
RUNNING
    ↓
WAITING (external systems, time, approvals)
    ↓
RUNNING
    ↓
COMPLETED | FAILED
```

### Core Guarantees

| Guarantee | Implementation |
|-----------|----------------|
| Steps execute at-least-once | Automatic retries |
| Effects commit exactly-once | Fencing tokens + idempotency |
| State is never lost | WAL with fsync |
| Recovery is automatic | Hydration from event log |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      CLIENT APPLICATIONS                        │
│                   (REST API / GraphQL / CLI)                    │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                     WORKFLOW ENGINE                             │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐                │
│  │  Workflow   │ │   Event     │ │   State     │                │
│  │  Process    │ │   Sourcing  │ │   Machine   │                │
│  └─────────────┘ └─────────────┘ └─────────────┘                │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                      EXECUTION LAYER                            │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐                │
│  │  Scheduler  │ │   Lease     │ │   Worker    │                │
│  │  (Dealer)   │ │   Manager   │ │  (Mercenary)│                │
│  └─────────────┘ └─────────────┘ └─────────────┘                │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│               DURABLE EVENT LOG (The Judge)                     │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  Append-Only │ fsync │ CRC32 │ Segment Rotation │ Replay   ││|
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

---

## Quick Start

### Define a Workflow

```json
{
  "name": "order_fulfillment_v1",
  "steps": ["RESERVE_INVENTORY", "PROCESS_PAYMENT", "DISPATCH", "CONFIRM_DELIVERY"],
  "input": {
    "order_id": "ORD-123456",
    "customer_id": "CUS-789"
  }
}
```

### Create via REST API

```bash
curl -X POST http://localhost:4000/api/v1/workflows \
  -H "Content-Type: application/json" \
  -d '{
    "name": "order_fulfillment_v1",
    "steps": ["RESERVE_INVENTORY", "PROCESS_PAYMENT", "DISPATCH"],
    "input": {"order_id": "ORD-123"}
  }'
```

### Create via GraphQL

```graphql
mutation {
  createWorkflow(
    name: "order_fulfillment_v1"
    steps: ["RESERVE_INVENTORY", "PROCESS_PAYMENT", "DISPATCH"]
    input: "{\"order_id\": \"ORD-123\"}"
  ) {
    id
    state
    steps
  }
}
```

### Monitor via CLI

```bash
axiom workflow list
axiom workflow inspect <id>
axiom workflow events <id>
axiom workflow replay <id>
```

---

## API Reference

### REST Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/ready` | GET | Readiness check |
| `/api/v1/workflows` | GET | List workflows |
| `/api/v1/workflows` | POST | Create workflow |
| `/api/v1/workflows/:id` | GET | Get workflow |
| `/api/v1/workflows/:id/events` | GET | Get events |
| `/api/v1/workflows/:id/advance` | POST | Advance step |
| `/api/v1/tasks` | GET | Task queue status |
| `/api/v1/metrics` | GET | System metrics |
| `/api/v1/metrics/prometheus` | GET | Prometheus format |
| `/graphql` | POST | GraphQL endpoint |
| `/graphiql` | GET | GraphQL IDE |

### GraphQL Schema

**Queries:**

- `workflow(id: ID!)` — Get workflow
- `workflows(limit: Int, offset: Int)` — List workflows
- `tasks` — Task queue status
- `metrics` — System metrics
- `health` — Health status

**Mutations:**

- `createWorkflow(name: String!, steps: [String!]!, input: JSON)` — Create
- `advanceWorkflow(id: ID!)` — Advance to next step
- `runChaos(scenario: String!, duration_ms: Int)` — Run chaos test
- `verify` — Verify consistency

**Subscriptions:**

- `workflowEvents(workflow_id: ID!)` — Real-time events
- `taskUpdates` — Task queue updates

---

## Deployment

### Requirements

- Elixir 1.14+
- Erlang/OTP 25+
- 2GB+ RAM recommended
- SSD storage for WAL

### Configuration

```elixir
# config/config.exs
config :axiom_wal,
  data_dir: "/var/lib/axiom/wal",
  max_segment_size: 64 * 1024 * 1024,  # 64MB
  fsync: true

config :axiom_scheduler,
  lease_duration_ms: 30_000,
  worker_timeout_ms: 60_000
```

### Start

```bash
# Development
mix phx.server

# Production
MIX_ENV=prod mix release
_build/prod/rel/axiom/bin/axiom start
```

---

## Resilience Testing

### Built-in Chaos Scenarios

| Scenario | What It Does |
|----------|--------------|
| `process_kill` | Randomly terminates processes |
| `delay_injection` | Injects random latency |
| `message_drop` | Simulates network partitions |

### Run Chaos

```bash
# CLI
axiom chaos run process_kill --duration 30000

# API
curl -X POST http://localhost:4000/api/v1/chaos/run \
  -H "Content-Type: application/json" \
  -d '{"scenario": "process_kill", "duration_ms": 30000}'
```

### Verify Consistency

```bash
axiom verify
# or
curl -X POST http://localhost:4000/api/v1/verify
```

---

## Why Universal

| Property | Value |
|----------|-------|
| Failure tolerance | Built-in |
| Exactly-once | Guaranteed |
| Long-running | Native |
| Human steps | Supported |
| Audits | First-class |
| Scaling | Horizontal |

**This is infrastructure, not an app.**

---

## License

MIT License

---

*Built with Elixir/OTP for production durability.*
