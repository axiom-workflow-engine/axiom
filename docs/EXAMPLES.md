---
layout: default
title: Workflow Examples
nav_order: 4
---

# Workflow Examples

## Ready-to-Use Workflow Definitions

This document provides copy-paste workflow definitions for common industry patterns.

---

## 🏦 Fintech: Payment Processing

### Card Payment

```elixir
# Elixir Definition
workflow = %{
  name: "card_payment_v1",
  steps: [
    :validate_card,
    :authorize_payment,
    :capture_funds,
    :send_receipt,
    :update_ledger
  ],
  timeout_ms: 30_000,
  retry_policy: %{max_attempts: 3, backoff_ms: 1000}
}
```

```json
// REST API
{
  "name": "card_payment_v1",
  "steps": [
    "validate_card",
    "authorize_payment",
    "capture_funds",
    "send_receipt",
    "update_ledger"
  ],
  "input": {
    "card_token": "tok_visa_123",
    "amount": 9999,
    "currency": "USD",
    "merchant_id": "merch_456"
  }
}
```

### Mobile Money Transfer (M-Pesa Style)

```json
{
  "name": "mobile_money_transfer_v1",
  "steps": [
    "validate_sender",
    "validate_recipient",
    "check_balance",
    "debit_sender",
    "credit_recipient",
    "send_sms_confirmation"
  ],
  "input": {
    "sender_phone": "+254712345678",
    "recipient_phone": "+254787654321",
    "amount": 1000,
    "currency": "KES"
  }
}
```

### Loan Disbursement

```json
{
  "name": "loan_disbursement_v1",
  "steps": [
    "verify_application",
    "credit_check",
    "calculate_terms",
    "manager_approval",
    "create_loan_account",
    "disburse_funds",
    "send_contract"
  ],
  "input": {
    "application_id": "LOAN-2024-001",
    "applicant_id": "CUS-789",
    "requested_amount": 50000
  }
}
```

---

## 🌐 ISP / Telco: Session Billing

### Prepaid Session

```json
{
  "name": "prepaid_session_v1",
  "steps": [
    "authenticate_device",
    "check_balance",
    "reserve_quota",
    "start_session",
    "track_usage",
    "apply_charges",
    "close_session"
  ],
  "input": {
    "device_mac": "AA:BB:CC:DD:EE:FF",
    "subscriber_id": "SUB-12345",
    "access_point": "AP-NAIROBI-001"
  }
}
```

### Postpaid Billing Cycle

```json
{
  "name": "postpaid_billing_cycle_v1",
  "steps": [
    "aggregate_usage",
    "calculate_charges",
    "apply_discounts",
    "generate_invoice",
    "send_invoice",
    "await_payment",
    "reconcile"
  ],
  "input": {
    "billing_period": "2024-01",
    "subscriber_id": "SUB-12345"
  }
}
```

### Voucher Activation

```json
{
  "name": "voucher_activation_v1",
  "steps": [
    "validate_voucher",
    "check_not_used",
    "mark_as_used",
    "credit_account",
    "send_confirmation"
  ],
  "input": {
    "voucher_code": "ABC123XYZ",
    "subscriber_phone": "+254712345678"
  }
}
```

---

## 🚚 Logistics: Order Fulfillment

### E-commerce Order (8-Step)

```json
{
  "name": "ecommerce_order_v1",
  "steps": [
    "receive_order",
    "validate_inventory",
    "pick_items",
    "sort_items",
    "package_order",
    "assign_carrier",
    "ship_order",
    "confirm_delivery"
  ],
  "input": {
    "order_id": "ORD-2024-001",
    "customer_id": "CUS-789",
    "items": [
      {"sku": "PROD-001", "qty": 2},
      {"sku": "PROD-002", "qty": 1}
    ],
    "shipping_address": {
      "street": "123 Main St",
      "city": "Nairobi",
      "country": "KE"
    }
  }
}
```

### Return Processing

```json
{
  "name": "return_processing_v1",
  "steps": [
    "receive_return_request",
    "validate_return_policy",
    "generate_return_label",
    "await_item_receipt",
    "inspect_item",
    "process_refund",
    "update_inventory",
    "send_confirmation"
  ],
  "input": {
    "order_id": "ORD-2024-001",
    "return_reason": "defective",
    "items_to_return": ["PROD-001"]
  }
}
```

---

## 🏥 Healthcare: Claims Processing

### Insurance Claim

```json
{
  "name": "insurance_claim_v1",
  "steps": [
    "receive_claim",
    "validate_policy",
    "check_coverage",
    "calculate_payout",
    "fraud_check",
    "manager_review",
    "approve_or_reject",
    "process_payment",
    "send_notification"
  ],
  "input": {
    "claim_id": "CLM-2024-001",
    "policy_number": "POL-12345",
    "claim_type": "medical",
    "amount_claimed": 25000,
    "documents": ["receipt.pdf", "prescription.pdf"]
  }
}
```

### Patient Onboarding

```json
{
  "name": "patient_onboarding_v1",
  "steps": [
    "receive_registration",
    "verify_identity",
    "check_insurance",
    "create_medical_record",
    "assign_primary_physician",
    "schedule_initial_visit",
    "send_welcome_kit"
  ],
  "input": {
    "patient_name": "John Doe",
    "date_of_birth": "1985-03-15",
    "insurance_provider": "BlueCross",
    "policy_number": "BC-12345"
  }
}
```

---

## 🏛️ Government: Permit Applications

### Construction Permit

```json
{
  "name": "construction_permit_v1",
  "steps": [
    "submit_application",
    "validate_documents",
    "planning_review",
    "environmental_review",
    "public_comment_period",
    "final_approval",
    "collect_fees",
    "issue_permit",
    "schedule_inspections"
  ],
  "input": {
    "application_id": "PERM-2024-001",
    "applicant_id": "APP-789",
    "property_address": "456 Oak Ave",
    "project_type": "residential_addition",
    "estimated_cost": 150000
  }
}
```

### Business License Renewal

```json
{
  "name": "business_license_renewal_v1",
  "steps": [
    "receive_renewal_request",
    "verify_current_license",
    "check_compliance_history",
    "collect_fees",
    "update_records",
    "issue_new_license",
    "send_certificate"
  ],
  "input": {
    "license_number": "BL-2023-001",
    "business_name": "Acme Corp",
    "renewal_period": "2024"
  }
}
```

---

## 🧠 AI/ML: Training Pipeline

### Model Training

```json
{
  "name": "model_training_v1",
  "steps": [
    "fetch_dataset",
    "validate_data",
    "preprocess",
    "split_train_test",
    "train_model",
    "evaluate_metrics",
    "validate_threshold",
    "save_artifacts",
    "register_model",
    "deploy_to_staging"
  ],
  "input": {
    "dataset_uri": "s3://data/training/2024-01/",
    "model_type": "xgboost",
    "hyperparameters": {
      "learning_rate": 0.1,
      "max_depth": 6
    },
    "target_metric": "auc",
    "threshold": 0.85
  }
}
```

### Batch Inference

```json
{
  "name": "batch_inference_v1",
  "steps": [
    "load_model",
    "fetch_input_data",
    "preprocess_inputs",
    "run_predictions",
    "postprocess_outputs",
    "store_results",
    "notify_completion"
  ],
  "input": {
    "model_version": "v1.2.3",
    "input_uri": "s3://data/inference/batch-001/",
    "output_uri": "s3://results/inference/batch-001/"
  }
}
```

---

## Step Handler Pattern

Each step needs a handler function:

```elixir
defmodule MyApp.Handlers do
  @doc "Step handler for payment authorization"
  def handle_step(:authorize_payment, context) do
    case PaymentGateway.authorize(context.card_token, context.amount) do
      {:ok, auth_code} ->
        {:ok, %{auth_code: auth_code, authorized_at: DateTime.utc_now()}}
      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end

  def handle_step(:capture_funds, context) do
    case PaymentGateway.capture(context.auth_code) do
      {:ok, transaction_id} ->
        {:ok, %{transaction_id: transaction_id}}
      {:error, reason} ->
        {:error, %{reason: reason}, retry: true}
    end
  end

  # ... handlers for other steps
end
```

---

## Registering Workflows

```elixir
# In your application startup
AxiomEngine.register_workflow(:card_payment_v1, %{
  steps: [:validate_card, :authorize_payment, :capture_funds, :send_receipt],
  handler_module: MyApp.Handlers,
  retry_policy: %{max: 3, backoff: :exponential}
})
```

---

## Monitoring Execution

```bash
# CLI
axiom workflow list
axiom workflow inspect card_payment_v1-abc123

# GraphQL
query {
  workflow(id: "abc123") {
    id
    state
    steps
    stepStates
    events { type timestamp }
  }
}
```
