# Axiom Workflow Engine

## Exactly-Once, Crash-Safe Workflow Orchestration

> **Positioning:** "Our workflow engine guarantees exactly-once business outcomes for systems where retries, crashes, and long-running processes are unavoidable."

---

## What Is This?

**Axiom** is a durable, exactly-once, crash-safe workflow execution engine for long-running, failure-prone, business-critical processes.

### It Is NOT

- A cron scheduler
- A job queue  
- A BPM toy

### Use Axiom When

- Failure is normal
- Retries are dangerous
- Duplication is catastrophic
- Audits matter

---

## Universal Guarantees

| Guarantee | Implementation |
|-----------|----------------|
| Steps execute at-least-once | Automatic retries |
| Effects commit exactly-once | Fencing + idempotency |
| State is never lost | WAL with fsync |
| Recovery is automatic | Event sourcing |

---

## Industry Applications

| Industry | Example Workflows |
|----------|-------------------|
| **Fintech** | Payments, Loans, Refunds |
| **Telco/ISP** | Session billing, Vouchers |
| **Logistics** | Order fulfillment, Returns |
| **Healthcare** | Claims, Patient onboarding |
| **Government** | Permits, Licensing |
| **AI/ML** | Training pipelines |

---

## Quick Start

```bash
# Create workflow
curl -X POST http://localhost:4000/api/v1/workflows \
  -d '{"name": "order_v1", "steps": ["reserve", "charge", "ship"]}'

# Monitor
axiom workflow inspect <id>

# GraphQL
query { workflow(id: "abc") { state steps events { type } } }
```

---

## Architecture

```
Clients → API (REST/GraphQL) → WorkflowProcess → Scheduler → Workers
                                      ↓
                              WAL (fsync, immutable)
```

---

## Documentation

- [Main Documentation](docs/README.md)
- [Industry Use Cases](docs/USE_CASES.md)
- [Technical Architecture](docs/ARCHITECTURE.md)
- [Workflow Examples](docs/EXAMPLES.md)

---

## Test Summary

```
55+ tests, 0 failures
8 applications, fully integrated
```

---

*Built with Elixir/OTP for production durability.*
