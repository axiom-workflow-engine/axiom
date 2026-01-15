# Axiom Engine

**Workflow State Machines — The Lawyer**

> One workflow = one GenServer. Deterministic or die.

## Overview

`axiom_engine` manages workflow lifecycle through event-sourced state machines. Each workflow is a GenServer that:

1. Hydrates from the event log on startup
2. Computes deterministic state transitions
3. Emits events to the WAL
4. Never executes side effects directly

## Core Contract

```elixir
defmodule Axiom.Engine.WorkflowProcess do
  # STATE
  defstruct [
    :workflow_id,  # uuid()
    :state,        # :pending | :running | :waiting | :completed | :failed
    :step,         # atom()
    :history,      # [event()]
    :version       # integer()
  ]
  
  # Hydrate from event log on startup/restart
  def hydrate(events)
  
  # Compute next transition, emit event, wait for commit
  def advance()
end
```

## Forbidden Actions

- ❌ External calls
- ❌ Randomness
- ❌ Time-based branching

**Deterministic or die.**

## State Replay Contract

```
state₀ + e₁ + e₂ + e₃ = state₃
```

If `Replay ≠ Original outcome` → system is invalid.
