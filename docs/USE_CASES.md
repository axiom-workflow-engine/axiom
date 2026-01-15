---
layout: default
title: Industry Use Cases
nav_order: 2
---

# Industry Use Cases

## Multi-Vertical Workflow Patterns

Axiom is a **universal workflow engine** that serves multiple high-value industries without changing the core system. Only step semantics differ.

---

## 🏦 Fintech & Payments

### Typical Workflows

- Card payment processing
- Mobile money (M-Pesa, retries, settlements)
- Loan disbursements
- Refund processing
- Reconciliation pipelines

### Why Axiom

| Challenge | Axiom Solution |
|-----------|----------------|
| Duplicate charges | Exactly-once execution |
| Failed payouts | Safe retries with fencing |
| Missing audit trail | Immutable event log |
| Network failures | Crash-safe recovery |

### Example: Payment Workflow

```
PAYMENT_INITIATED
      ↓
VALIDATE_ACCOUNT
      ↓
CHARGE_CUSTOMER
      ↓
NOTIFY_MERCHANT
      ↓
SETTLEMENT_COMPLETE
```

**Failure Handled:** Worker crashes after charging → result ignored → no duplicate charge.

---

## 🌐 ISPs & Telcos

### Typical Workflows

- User session accounting
- Bandwidth quota enforcement
- Postpaid billing
- Voucher activation
- Usage aggregation

### Why Axiom

| Challenge | Axiom Solution |
|-----------|----------------|
| Sessions counted twice | Exactly-once billing |
| Network drops | Automatic recovery |
| Device lies | Event sourcing truth |
| Billing errors | Full audit replay |

### Example: Session Billing

```
SESSION_START
      ↓
TRACK_USAGE
      ↓
APPLY_CHARGE
      ↓
UPDATE_BALANCE
      ↓
SESSION_CLOSE
```

**Result:** No overcharging. No missed sessions.

---

## 🚚 Logistics & Supply Chain

### Typical Workflows

- Order fulfillment
- Shipment handoff
- Warehouse processing
- Delivery confirmation
- Returns handling

### Why Axiom

| Challenge | Axiom Solution |
|-----------|----------------|
| Orders span days | Long-running native |
| Partial completion | Resume from any step |
| Double shipping | Fenced execution |
| External failures | Safe retries |

### Example: Order Fulfillment

```
ORDER_RECEIVED
      ↓
RESERVE_INVENTORY
      ↓
DISPATCH
      ↓
CONFIRM_DELIVERY
```

**Crash Handling:** Mid-dispatch crash → resumes without double shipping.

---

## 🏥 Healthcare & Insurance

### Typical Workflows

- Insurance claims
- Patient onboarding
- Pre-authorization
- Provider payments

### Why Axiom

| Challenge | Axiom Solution |
|-----------|----------------|
| Regulatory audits | Immutable logs |
| Long approvals | Human step support |
| Zero data loss | WAL durability |
| Compliance | Full traceability |

### Example: Insurance Claim

```
CLAIM_SUBMITTED
      ↓
VALIDATE_POLICY
      ↓
MANUAL_REVIEW
      ↓
APPROVE_PAYOUT
```

**Human Delays:** Do not break correctness. Days between steps are normal.

---

## 🏛️ Government & Regulated Systems

### Typical Workflows

- Permit approvals
- Licensing
- Grants
- Identity verification
- Compliance checks

### Why Axiom

| Challenge | Axiom Solution |
|-----------|----------------|
| Legal traceability | Deterministic replay |
| Silent failures | No hidden state |
| Multi-agency | Long-running support |
| Audits years later | Immutable history |

### Example: Permit Application

```
APPLICATION_RECEIVED
      ↓
DOCUMENT_VERIFICATION
      ↓
MULTI_AGENCY_APPROVAL
      ↓
ISSUE_PERMIT
```

**Audit:** Every decision replayable years later.

---

## 🧠 AI / Data / ML Platforms

### Typical Workflows

- Model training pipelines
- Data ingestion
- Feature generation
- Batch inference
- Evaluation loops

### Why Axiom

| Challenge | Axiom Solution |
|-----------|----------------|
| Hours/days runtime | Long-running native |
| Hardware failures | Resume from checkpoint |
| Restart costs | Never restart, resume |
| GPU time | Cost optimization |

### Example: ML Training Pipeline

```
DATA_INGEST
      ↓
TRAIN_MODEL
      ↓
EVALUATE
      ↓
DEPLOY
```

**Crash Recovery:** Training crash → resume from checkpoint, not restart.

---

## 🏭 Manufacturing & Industrial IoT

### Typical Workflows

- Production batch control
- Equipment maintenance
- Sensor aggregation
- Quality checks

### Why Axiom

| Challenge | Axiom Solution |
|-----------|----------------|
| Device failures | Fault tolerance |
| Network flaps | Message durability |
| Duplicate actions | Hardware damage prevention |
| Sensor noise | Event deduplication |

### Example: Production Batch

```
BATCH_START
      ↓
MONITOR_SENSORS
      ↓
QUALITY_CHECK
      ↓
BATCH_COMPLETE
```

**Safety:** Sensor duplication ≠ duplicated actions.

---

## 🏫 Education & Enterprise Admin

### Typical Workflows

- Fee processing
- Admissions
- Payroll
- Procurement approvals

### Why Axiom

| Challenge | Axiom Solution |
|-----------|----------------|
| Human + system steps | Native support |
| Long approvals | Durable state |
| Audit requirements | Full replay |
| Failure tolerance | Built-in |

---

## Common Usage Pattern (All Clients)

### 1. Define Workflow

```json
{
  "workflow_type": "order_fulfillment_v1",
  "steps": ["RESERVE", "DISPATCH", "CONFIRM"]
}
```

### 2. Submit Workflow

```bash
POST /api/v1/workflows
```

### 3. Monitor Progress

```bash
GET /api/v1/workflows/{id}
```

### 4. Inspect / Replay / Audit

```bash
axiom workflow inspect <id>
axiom workflow replay <id>
axiom workflow events <id>
```

---

## Why Universal

| Property | Value |
|----------|-------|
| Failure tolerance | Built-in |
| Exactly-once | Guaranteed |
| Long-running | Native |
| Human steps | Supported |
| Audits | First-class |
| Scaling | Horizontal |

**This is infrastructure, not an app.**

---

## Positioning Statement

> **"Our workflow engine guarantees exactly-once business outcomes for systems where retries, crashes, and long-running processes are unavoidable."**
