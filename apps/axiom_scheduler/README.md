# Axiom Scheduler

**Task Assignment — The Dealer**

> Schedulers do not execute. They assign leases.

## Overview

`axiom_scheduler` manages the distribution of tasks to workers through a lease-based system that ensures exactly-once execution.

## Core Components

### Dispatcher

Matches runnable steps to workers:

```elixir
defstruct [
  :runnable_queue,  # priority_queue()
  :active_leases,   # %{task_id => lease}
  :workers          # %{worker_id => status}
]
```

### LeaseManager (The Clock Police)

No system trusts wall clocks. Logical time only.

```elixir
# Check if lease is still valid
:lease_valid | :lease_expired = LeaseManager.check_lease(lease_id)
```

**Critical Rule:** Expired lease = worker is ignored, even if it finishes.

## The Three Pillars

| Pillar | Purpose |
|--------|---------|
| Idempotency Keys | `hash(workflow_id, step, attempt)` |
| Leases | Ownership in time |
| Fencing Tokens | Ownership in order |

## Commit Sequence

```
1. Scheduler assigns task → Lease(L1, fencing_token=42)
2. Worker executes → attaches idempotency_key K
3. Worker reports → includes lease_id, fencing_token, K
4. WorkflowProcess validates
5. LogAppendServer fsyncs
6. ONLY NOW is step "done"
```
