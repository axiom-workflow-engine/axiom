# Axiom Projections

**Read Models — The Storytellers**

> Build views, never influence execution.

## Overview

`axiom_projections` consumes the event log to build materialized views for dashboards, queries, and metrics.

## Core Contract

```elixir
# Receive events from WAL
{:event, offset, event}

# Output
# - DB writes
# - Metrics
# - Alerts
```

## Key Properties

- **Crash = rebuild from log** — No exceptions
- **Never influence execution** — Read-only
- **Eventually consistent** — Derived from log

## Benefits

| Feature | Value |
|---------|-------|
| Zero-risk schema evolution | Drop and rebuild anytime |
| Time-travel debugging | Query any point in history |
| Auditable history | Enterprises love this |

## Example Projections

- **WorkflowView** — Current state of all workflows
- **Metrics** — Aggregated statistics (throughput, latency)
- **Alerts** — Trigger notifications on specific events
