# Axiom CLI

**Terminal Control Plane**

> If you need a browser to debug → system is immature.

## Overview

`axiom_cli` provides a terminal-first interface for managing workflows, tasks, and cluster state.

## Commands

```bash
# Workflow management
axiom workflow list              # List all workflows
axiom workflow inspect <id>      # Detailed workflow state
axiom workflow replay <id>       # Replay from event log
axiom workflow cancel <id>       # Cancel a workflow

# Task management
axiom task list                  # List active tasks
axiom task kill <id>             # Terminate a task

# Cluster status
axiom node status                # Cluster node health
axiom node list                  # List all nodes

# Event log
axiom log tail                   # Stream event log
axiom log search <query>         # Search events
```

## Building

```bash
# Build escript
mix escript.build

# Run
./axiom --help
```

## Why CLI-First

- **DevOps friendly** — Works over SSH
- **Scriptable** — Integrate with automation
- **Fast** — No browser overhead
- **Reliable** — Works when UI is down
