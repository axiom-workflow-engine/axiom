---
layout: default
title: Home
nav_order: 1
---

# Axiom Workflow Engine

## Enterprise-Grade, Exactly-Once Workflow Orchestration

> **"Our workflow engine guarantees exactly-once business outcomes for systems where retries, crashes, and long-running processes are unavoidable."**

---

## What Is This?

**Axiom** is a durable, exactly-once, crash-safe workflow execution engine for long-running, failure-prone, business-critical processes.

| ✅ IS | ❌ IS NOT |
|-------|-----------|
| Durable workflow engine | Cron scheduler |
| Exactly-once execution | Job queue |
| Crash-safe recovery | BPM toy |
| Long-running support | Request/response framework |

---

## When You Need Axiom

| Condition | Axiom Solution |
|-----------|----------------|
| **Failure is normal** | Automatic recovery |
| **Retries are dangerous** | Fenced execution |
| **Duplication is catastrophic** | Exactly-once semantics |
| **Audits matter** | Immutable event log |
| **Processes span hours/days** | Durable state |

---

## Universal Guarantees

| Guarantee | How |
|-----------|-----|
| Steps execute at-least-once | Automatic retries |
| Effects commit exactly-once | Fencing + idempotency |
| State is never lost | WAL with fsync |
| Recovery is automatic | Event sourcing |

---

## Quick Start

### Create Workflow (REST)

```bash
curl -X POST http://localhost:4000/api/v1/workflows \
  -H "Content-Type: application/json" \
  -d '{
    "name": "order_fulfillment_v1",
    "steps": ["reserve", "charge", "ship", "confirm"]
  }'
```

### Create Workflow (GraphQL)

```graphql
mutation {
  createWorkflow(
    name: "order_fulfillment_v1"
    steps: ["reserve", "charge", "ship", "confirm"]
  ) {
    id
    state
  }
}
```

### Monitor (CLI)

```bash
axiom workflow list
axiom workflow inspect <id>
axiom workflow events <id>
```

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
│           WorkflowProcess → StateMachine → Events               │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                    EXECUTION LAYER                              │
│            Scheduler → LeaseManager → Workers                   │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                DURABLE EVENT LOG (WAL)                          │
│           Append-Only │ fsync │ CRC32 │ Replay                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Industry Applications

| Industry | Example Workflows | Key Benefit |
|----------|-------------------|-------------|
| **Fintech** | Payments, Loans, Refunds | No duplicate charges |
| **Telco/ISP** | Session billing, Vouchers | No overbilling |
| **Logistics** | Order fulfillment, Returns | No double shipping |
| **Healthcare** | Claims, Onboarding | Complete audit trail |
| **Government** | Permits, Licensing | Legal traceability |
| **AI/ML** | Training pipelines | Cost-efficient recovery |
| **Manufacturing** | Batch control, IoT | Safe equipment commands |

---

## Documentation

- [**Use Cases**](USE_CASES.html) — Industry-specific patterns
- [**Architecture**](ARCHITECTURE.html) — Technical deep-dive
- [**Examples**](EXAMPLES.html) — Copy-paste workflow definitions

---

## Technology

Built with **Elixir/OTP** for:

- Fault tolerance via supervision trees
- Lightweight processes (millions concurrent)
- Hot code upgrades
- Battle-tested distributed primitives

---

## License

MIT License

---

<p align="center">
  <em>Built for systems where failure is normal and correctness is mandatory.</em>
</p>
