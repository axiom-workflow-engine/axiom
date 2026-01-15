# Axiom Worker

**Execution Runtime — The Mercenary**

> Workers are liars until proven correct.

## Overview

`axiom_worker` executes side effects but **never commits state**. Workers:

1. Pull tasks from the scheduler
2. Execute with timeout
3. Report results
4. Wait for engine to commit

## Core Contract

```elixir
defstruct [
  :worker_id,     # uuid()
  :current_task,  # task | nil
  :lease_id       # lease_id | nil
]

# Report task completion
report_completed(workflow_id, step, lease_id, result)

# Report task failure
report_failed(workflow_id, step, lease_id, reason)
```

## Key Rules

- **Worker crashes = acceptable**
- **Double execution = NOT acceptable**

## Why Workers Are Untrusted

Workers can:

- Crash
- Stall
- Lie
- Disappear

Workers do NOT own truth — they report execution intent. **The engine decides commit.**

## Failure Handling

| Scenario | Result |
|----------|--------|
| Worker crashes mid-task | Lease expires → retry |
| Worker finishes after lease expiry | Result dropped |
| Worker reports duplicate | Idempotency key rejects |
