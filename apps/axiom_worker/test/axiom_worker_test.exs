defmodule AxiomWorkerTest do
  use ExUnit.Case

  alias Axiom.Worker.Executor
  alias Axiom.Scheduler.{LeaseManager, TaskQueue, Dispatcher}

  setup do
    # Start scheduler components
    {:ok, lease_mgr} = LeaseManager.start_link(name: :test_worker_lease_mgr, lease_duration_ms: 5_000)
    {:ok, queue} = TaskQueue.start_link(name: :test_worker_queue)
    {:ok, dispatcher} = Dispatcher.start_link(
      name: :test_worker_dispatcher,
      task_queue: queue,
      lease_manager: lease_mgr
    )

    on_exit(fn ->
      if Process.alive?(dispatcher), do: GenServer.stop(dispatcher)
      if Process.alive?(queue), do: GenServer.stop(queue)
      if Process.alive?(lease_mgr), do: GenServer.stop(lease_mgr)
    end)

    {:ok, dispatcher: dispatcher}
  end

  describe "Executor" do
    test "starts and registers with dispatcher", %{dispatcher: dispatcher} do
      {:ok, worker} = Executor.start_link(
        dispatcher: dispatcher,
        poll_interval_ms: 100_000  # Don't auto-poll
      )

      state = Executor.get_state(worker)
      assert is_binary(state.worker_id)

      # Verify registered
      workers = Dispatcher.list_workers(dispatcher)
      assert length(workers) == 1

      Executor.stop(worker)
    end

    test "executes task and reports completion", %{dispatcher: dispatcher} do
      # Track execution
      test_pid = self()

      handler = fn step, context ->
        send(test_pid, {:executed, step, context})
        {:ok, %{result: "success"}}
      end

      {:ok, worker} = Executor.start_link(
        dispatcher: dispatcher,
        handler_fn: handler,
        poll_interval_ms: 100_000
      )

      # Schedule a task
      {:ok, _} = Dispatcher.schedule_step(dispatcher, "wf-test", :my_step, 1)

      # Trigger poll
      Executor.poll_now(worker)

      # Wait for execution
      assert_receive {:executed, :my_step, %{workflow_id: "wf-test"}}, 1000

      Executor.stop(worker)
    end

    test "handles task failure gracefully", %{dispatcher: dispatcher} do
      handler = fn _step, _context ->
        {:error, %{reason: "intentional failure"}}
      end

      {:ok, worker} = Executor.start_link(
        dispatcher: dispatcher,
        handler_fn: handler,
        poll_interval_ms: 100_000
      )

      {:ok, _} = Dispatcher.schedule_step(dispatcher, "wf-fail", :fail_step, 1)

      Executor.poll_now(worker)

      # Give time for execution
      Process.sleep(100)

      # Worker should be idle again
      state = Executor.get_state(worker)
      assert state.current_task == nil

      Executor.stop(worker)
    end
  end
end
