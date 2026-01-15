# Axiom WAL

**Write-Ahead Log — The Spine of Axiom**

> If this fails → company-ending bug.

## Overview

`axiom_wal` is the durable event log that makes Axiom reliable. Every state change in the system is first written to the WAL before being applied.

## Core Rule

> **No GenServer may change durable state unless an event has already been committed to the WAL.**

## Components

### LogAppendServer (The Judge)

The only authority that makes events real.

```elixir
# Append an event (SYNC, fsync'd)
{:ok, offset} = Axiom.WAL.LogAppendServer.append_event(workflow_id, event)

# Replay events for a workflow
{:ok, events} = Axiom.WAL.LogAppendServer.replay(workflow_id)

# Subscribe to new events
:ok = Axiom.WAL.LogAppendServer.subscribe()
```

**Guarantees:**

- Event is fsync'd to disk
- Offset is final and survives crashes
- If crash before reply → event does not exist

### Entry

Binary format with CRC32 checksums:

```
[4B length][4B CRC32][8B timestamp][payload]
```

### Segment

- Fixed maximum size (default 64MB)
- Append-only, immutable after rotation
- Named by segment_id: `segment_00000001.wal`

## Configuration

```elixir
config :axiom_wal,
  data_dir: "/var/lib/axiom/wal",
  segment_size: 64 * 1024 * 1024,  # 64MB
  fsync_on_write: true
```

## Failure Modes

| Scenario | Result |
|----------|--------|
| Crash before fsync | Event does not exist |
| Crash after fsync | Event survives |
| Corruption detected | Stop at corrupted entry |
| Disk full | Return `{:error, :disk_failure}` |

## Why This Matters

The WAL is the **single source of truth**. Every other component rebuilds its state by replaying the log. This enables:

- Crash recovery
- Time-travel debugging
- Auditable history
- Zero-risk schema evolution
