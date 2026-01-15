# Axiom API Gateway

API Gateway for the Axiom Workflow Engine.
Provides REST and GraphQL APIs, durable acceptance, strict authentication, and distributed clustering.

## Features

- **Hybrid API**: REST (JSON) and GraphQL (Absinthe) interfaces.
- **Durable Acceptance**: Guarantees workflow persistence via WAL before acknowledging receipt.
- **Distributed Clustering**: `libring`-based consistent hashing for request routing across node clusters.
- **Strict Authentication**: Configurable API Key validation with encryption and constant-time comparison.
- **Idempotency**: Enforcement of `Idempotency-Key` headers with conflict detection.
- **Schema Registry**: Optional JSON Schema validation for workflow inputs.
- **Observability**: Prometheus metrics and structured logging.

## Architecture

The gateway is designed as a stateless (but cluster-aware) entry point.

### Components

- **Auth Plug**: `AxiomGateway.Plugs.Auth` handles API Keys and JWTs.
- **Idempotency Plug**: `AxiomGateway.Plugs.Idempotency` ensures exactly-once processing using Mnesia.
- **Durable Acceptor**: `AxiomGateway.Durable.Acceptor` routes requests to the correct engine node.
- **Node Selector**: `AxiomGateway.Distribution.NodeSelector` manages cluster topology.
- **Schema Store**: `AxiomGateway.Schemas.Store` maintains validation schemas in Mnesia.

## API Documentation

### REST API

- `GET /api/v1/workflows` - List active workflows
- `GET /api/v1/workflows/:id` - Get workflow details
- `POST /api/v1/workflows` - Create a workflow
- `POST /api/v1/workflows/:id/cancel` - Cancel a workflow

### GraphQL API

Endpoint: `/graphql`
GraphiQL: `/graphiql` (Dev only)

```graphql
query {
  workflow(id: "UUID") {
    id
    status
    steps {
      name
      status
    }
  }
}

mutation {
  createWorkflow(name: "OrderProcess", steps: ["validate", "charge"], input: "{\"amount\": 100}") {
    id
    status
  }
}
```

## Clustering

The gateway uses `libcluster` for node discovery. To join a cluster manually:

```bash
curl -X POST http://localhost:4000/api/v1/sys/cluster/join \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"node": "axiom_node_2@10.0.0.2"}'
```

## Configuration

Required environment variables:

- `SECRET_KEY_BASE`: Phoenix secret
- `PORT`: HTTP port (default 4000)
- `AXIOM_API_KEYS`: JSON map of valid API keys

## Development

```bash
mix deps.get
mix compile
mix test
iex -S mix phx.server
```
