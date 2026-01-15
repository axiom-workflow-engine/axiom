---
layout: default
title: Technical Architecture
nav_order: 3
---

# Technical Architecture

## System Design & Guarantees

---

## Core Principles

### 1. Events Are Facts

Events are **immutable facts** about what happened. They are:

- Never deleted
- Never modified
- Always replayable

```elixir
%Event{
  event_id: "uuid-v4",
  event_type: :step_completed,
  workflow_id: "wf-123",
  sequence: 5,
  timestamp: 1234567890000000000,  # Logical time
  payload: %{step: :process_payment, result: %{amount: 100}}
}
```

### 2. State Is Derived

State is **never stored directly**. It is computed by replaying events:

```
Current State = fold(initial_state, all_events, apply_event)
```

This guarantees:

- Consistency after crashes
- Audit-friendly reconstruction
- Time-travel debugging

### 3. Exactly-Once Execution

The **Three Pillars**:

| Mechanism | Purpose |
|-----------|---------|
| **Idempotency Keys** | Deduplicate duplicate requests |
| **Leases** | Time-bounded task ownership |
| **Fencing Tokens** | Reject stale worker results |

---

## Component Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         WAL (The Judge)                         │
│ "If it's not fsync'd, it didn't happen"                         │
├─────────────────────────────────────────────────────────────────┤
│ • Append-only log                                               │
│ • CRC32 checksums                                               │
│ • Segment rotation (64MB default)                               │
│ • fsync on every commit                                         │
│ • Replay for hydration                                          │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                    WorkflowProcess (The Lawyer)                 │
│ "One workflow = one GenServer. Deterministic or die."           │
├─────────────────────────────────────────────────────────────────┤
│ • Validates state transitions                                   │
│ • Emits intent events                                           │
│ • NEVER executes side effects                                   │
│ • Hydrates from WAL on startup                                  │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                      Scheduler (The Dealer)                     │
│ "Schedulers do not execute. They assign leases."                │
├─────────────────────────────────────────────────────────────────┤
│ • Task queue (pull-based)                                       │
│ • Lease acquisition                                             │
│ • Worker assignment                                             │
│ • Result routing                                                │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                       Worker (The Mercenary)                    │
│ "Workers are liars until proven correct."                       │
├─────────────────────────────────────────────────────────────────┤
│ • Executes side effects                                         │
│ • Reports outcomes                                              │
│ • NEVER commits state                                           │
│ • Expendable - crashes are normal                               │
└─────────────────────────────────────────────────────────────────┘
```

---

## Execution Protocol

### Commit Sequence

```
1. WorkflowProcess emits INTENT event
         ↓
2. Scheduler creates TASK in queue
         ↓
3. Worker PULLS task (with lease)
         ↓
4. Worker EXECUTES side effect
         ↓
5. Worker REPORTS result to Scheduler
         ↓
6. Scheduler VALIDATES lease + fencing token
         ↓
7. WorkflowProcess commits RESULT to WAL
         ↓
8. Subscriber is notified
```

### Failure Matrix

| Failure Point | Behavior |
|---------------|----------|
| Before WAL commit | Event doesn't exist, retry safe |
| After WAL, before reply | Event exists, idempotency key rejects duplicate |
| Worker crash during execution | Lease expires, task re-assigned |
| Network partition | Fencing token invalidates stale results |

---

## State Machine

### Workflow States

```
:pending → :running → :waiting → :running → :completed
                                         ↘ :failed
```

### Step States

```
:pending → :scheduled → :running → :completed
                               ↘ :failed
```

### Transitions

| From | Event | To |
|------|-------|----|
| pending | workflow_created | pending |
| pending | step_scheduled | running |
| running | step_completed | running/waiting |
| running | step_failed | waiting/failed |
| waiting | step_scheduled | running |
| running | workflow_completed | completed |

---

## Data Flow

### Event Creation

```elixir
# 1. Generate event
event = Events.step_completed(workflow_id, sequence, :process_payment, result, 150)

# 2. Commit to WAL (fsync)
{:ok, offset} = LogAppendServer.append_event(workflow_id, event)

# 3. Apply to state machine
new_state = StateMachine.apply_event(state, event)

# 4. Notify subscribers
:ok = Phoenix.PubSub.broadcast("workflow:#{workflow_id}", event)
```

### Hydration (Recovery)

```elixir
# On process startup
{:ok, events} = LogAppendServer.replay(workflow_id)

# Rebuild state
state = StateMachine.hydrate(workflow_id, events)

# Process is now consistent
```

---

## Fencing Protocol

### Why Fencing?

Without fencing, a slow worker returning after a retry could corrupt state:

```
T0: Worker A gets task (token=1)
T1: Worker A is slow
T2: Lease expires
T3: Worker B gets task (token=2)
T4: Worker B completes
T5: Worker A returns (stale!)  ← REJECTED by token check
```

### Token Validation

```elixir
def validate_for_commit(lease_id, fencing_token, state) do
  current_highest = Map.get(state.fencing_tokens, {workflow_id, step})
  
  cond do
    Lease.expired?(lease) -> {:error, :lease_expired}
    fencing_token < current_highest -> {:error, :fencing_token_stale}
    true -> :ok
  end
end
```

---

## Storage Format

### WAL Entry

```
┌──────────┬──────────┬────────────┬─────────────┐
│ Length   │ CRC32    │ Timestamp  │ Payload     │
│ (4 bytes)│ (4 bytes)│ (8 bytes)  │ (variable)  │
└──────────┴──────────┴────────────┴─────────────┘
```

### Segment Files

```
/var/lib/axiom/wal/
├── segment_000000.wal
├── segment_000001.wal
├── segment_000002.wal
└── segment_current.wal
```

---

## Scaling

### Horizontal

- Workflows are partitioned by workflow_id
- Each workflow is a single GenServer
- Cluster via libcluster / Horde

### Vertical

- Increase Erlang schedulers
- Tune WAL segment size
- Adjust lease durations

---

## Observability

### Metrics

- `axiom_memory_bytes` — Memory usage
- `axiom_process_count` — Erlang processes
- `axiom_wal_offset` — WAL position
- `axiom_queue_depth` — Task queue depth
- `axiom_active_leases` — Active leases
- `axiom_workers` — Registered workers

### Health Checks

- `/health` — Liveness
- `/ready` — Readiness (checks WAL, scheduler)

### Logging

All components log with structured metadata:

- `[WAL]` — Storage layer
- `[Workflow:id]` — Workflow processes
- `[Dispatcher]` — Scheduling
- `[Worker:id]` — Execution
- `[Chaos:*]` — Failure injection
