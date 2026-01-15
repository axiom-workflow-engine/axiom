# Axiom Chaos

**Failure Injection Engine — Sales Weapon**

> You can demo resilience live. That sells contracts.

## Overview

`axiom_chaos` provides built-in fault injection to prove system resilience during demos and testing.

## Scenarios

```bash
# Kill random processes
mix axiom.chaos --scenario process_kill --duration 60s

# Simulate network partition
mix axiom.chaos --scenario network_partition --duration 30s

# Inject disk I/O failures
mix axiom.chaos --scenario disk_failure --duration 10s

# Inject random delays
mix axiom.chaos --scenario delay_injection --duration 30s
```

## Fault Types

| Fault | Description |
|-------|-------------|
| Process Kill | Randomly terminate GenServers |
| Network Partition | Drop messages between nodes |
| Disk Failure | Simulate I/O errors |
| Delay Injection | Add latency to operations |

## Why This Matters

- **Sales demos** — Show the system recovering live
- **Confidence** — Prove correctness under failure
- **Testing** — Automated chaos in CI/CD

## Verification

```bash
# After chaos, verify consistency
mix axiom.verify_consistency
```
