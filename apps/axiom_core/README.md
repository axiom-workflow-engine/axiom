# Axiom Core

**Shared types, protocols, and utilities for Axiom**

## Overview

`axiom_core` provides the foundational types used across all Axiom applications:

- **Event** — Canonical event envelope for all workflow events
- **Events** — Factory functions for creating typed events
- **Lease** — Time-bounded task ownership with fencing tokens

## Event Envelope

Every event in Axiom uses this envelope:

```elixir
%Axiom.Core.Event{
  event_id: UUID,           # Globally unique
  event_type: atom(),       # Immutable forever
  schema_version: integer(), # Monotonic per type
  workflow_id: UUID,        # Partition key
  sequence: integer(),      # Strictly increasing per workflow
  causation_id: UUID | nil, # What caused this
  correlation_id: UUID,     # Trace boundary
  timestamp: integer(),     # Logical time (NOT wall clock)
  payload: map(),           # Business data
  metadata: map()           # Non-semantic hints
}
```

## Core Event Types (v1)

| Event | Description |
|-------|-------------|
| `workflow_created` | Workflow initialized (sequence=0) |
| `step_scheduled` | Step queued for execution |
| `step_started` | Worker acquired lease |
| `step_completed` | Step finished successfully |
| `step_failed` | Step failed (may retry) |
| `workflow_completed` | Terminal success |
| `workflow_failed` | Terminal failure |

## Usage

```elixir
alias Axiom.Core.{Event, Events, Lease}

# Create events
event = Events.workflow_created("wf-123", "payment", %{amount: 100}, [:validate, :charge])

# Generate idempotency key
key = Event.idempotency_key("wf-123", :charge, 1)

# Create lease
lease = Lease.new("wf-123", :charge, 1, fencing_token: 42)
```

## Key Rules

1. **Events are facts, not commands** — "PaymentCharged" ✅ / "ChargePayment" ❌
2. **Events are immutable** — Never edited, deleted, or reinterpreted
3. **Logical time only** — Never trust wall clocks
