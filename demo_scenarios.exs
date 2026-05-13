# demo_scenarios.exs
# This script demonstrates real-world workflow scenarios for the Axiom engine.

require Logger

# 1. Start some workers to process tasks
Logger.info("Starting demo workers...")
{:ok, _} = Axiom.Worker.Executor.start_link(name: :worker_1)
{:ok, _} = Axiom.Worker.Executor.start_link(name: :worker_2)

# 2. Define a "Order Processing" workflow (Happy Path)
# Steps: validate -> charge -> ship -> notify
order_input = %{
  order_id: "ORD-12345",
  customer: "Alice Smith",
  items: [%{sku: "IPHONE-15", qty: 1}],
  amount: 999.0
}

order_steps = [:validate_order, :charge_payment, :ship_order, :send_confirmation]

Logger.info("Submitting Happy Path: Order Processing...")
{:ok, order_id} = AxiomEngine.create_workflow("Order Processing", order_input, order_steps)
Logger.info("Order Workflow ID: #{order_id}")

# 3. Define a "Payment Retry" workflow (Failure case)
# We can simulate failure by having a custom handler for this specific workflow
retry_input = %{
  order_id: "ORD-666",
  customer: "Bob Brown",
  amount: 50.0
}

# Custom handler that fails the first time
{:ok, _} = Axiom.Worker.Executor.start_link(
  name: :specialized_worker,
  handler_fn: fn
    :charge_payment, %{attempt: 1} ->
      Logger.warning("Simulating transient payment failure...")
      {:error, %{reason: "Connection timeout", code: "TIMEOUT"}}
    
    step, _ctx ->
      Process.sleep(50)
      {:ok, %{step: step, status: "done"}}
  end
)

Logger.info("Submitting Retry Path: Payment Retry Scenario...")
{:ok, retry_id} = AxiomEngine.create_workflow("Payment Retry Demo", retry_input, [:charge_payment, :finalize])
Logger.info("Retry Workflow ID: #{retry_id}")

# 4. Wait for processing and show status
Process.sleep(2000)

Logger.info("--- CURRENT WORKFLOW STATUS ---")

case AxiomEngine.get_workflow(order_id) do
  {:ok, state} ->
    Logger.info("Order Workflow [#{order_id}]: Status=#{state.state}, Completed Steps=#{Enum.count(state.history, fn e -> e.event_type == :step_completed end)}")
  _ -> :ok
end

case AxiomEngine.get_workflow(retry_id) do
  {:ok, state} ->
    Logger.info("Retry Workflow [#{retry_id}]: Status=#{state.state}, History Events=#{length(state.history)}")
  _ -> :ok
end

# Keep running to allow background processing to finish if needed
Process.sleep(3000)
Logger.info("Demo scenarios completed.")
