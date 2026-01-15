defmodule AxiomSchedulerTest do
  use ExUnit.Case

  alias Axiom.Scheduler.{LeaseManager, TaskQueue, Dispatcher}
  alias Axiom.Core.Lease

  setup do
    # Start fresh instances for each test
    {:ok, lease_mgr} = LeaseManager.start_link(name: :test_lease_mgr, lease_duration_ms: 5_000)
    {:ok, queue} = TaskQueue.start_link(name: :test_queue)
    {:ok, dispatcher} = Dispatcher.start_link(
      name: :test_dispatcher,
      task_queue: queue,
      lease_manager: lease_mgr
    )

    on_exit(fn ->
      if Process.alive?(dispatcher), do: GenServer.stop(dispatcher)
      if Process.alive?(queue), do: GenServer.stop(queue)
      if Process.alive?(lease_mgr), do: GenServer.stop(lease_mgr)
    end)

    {:ok, lease_mgr: lease_mgr, queue: queue, dispatcher: dispatcher}
  end

  describe "LeaseManager" do
    test "acquires lease with fencing token", %{lease_mgr: mgr} do
      {:ok, lease} = LeaseManager.acquire_lease(mgr, "wf-1", :step_a, 1)

      assert lease.workflow_id == "wf-1"
      assert lease.step == :step_a
      assert lease.fencing_token == 1
      assert Lease.valid?(lease)
    end

    test "increments fencing token on subsequent leases", %{lease_mgr: mgr} do
      {:ok, lease1} = LeaseManager.acquire_lease(mgr, "wf-1", :step_a, 1)
      {:ok, lease2} = LeaseManager.acquire_lease(mgr, "wf-1", :step_a, 2)

      assert lease2.fencing_token == lease1.fencing_token + 1
    end

    test "validates lease for commit", %{lease_mgr: mgr} do
      {:ok, lease} = LeaseManager.acquire_lease(mgr, "wf-1", :step_a, 1)

      assert :ok = LeaseManager.validate_for_commit(mgr, lease.lease_id, lease.fencing_token)
    end

    test "rejects stale fencing token", %{lease_mgr: mgr} do
      {:ok, lease1} = LeaseManager.acquire_lease(mgr, "wf-1", :step_a, 1)
      {:ok, _lease2} = LeaseManager.acquire_lease(mgr, "wf-1", :step_a, 2)

      # Try to commit with old fencing token
      assert {:error, :fencing_token_stale} =
        LeaseManager.validate_for_commit(mgr, lease1.lease_id, lease1.fencing_token)
    end

    test "check_lease returns correct status", %{lease_mgr: mgr} do
      {:ok, lease} = LeaseManager.acquire_lease(mgr, "wf-1", :step_a, 1)

      assert :lease_valid = LeaseManager.check_lease(mgr, lease.lease_id)
      assert :lease_unknown = LeaseManager.check_lease(mgr, "nonexistent")
    end
  end

  describe "TaskQueue" do
    test "enqueue and pull tasks", %{queue: queue} do
      {:ok, task_id} = TaskQueue.enqueue(queue, "wf-1", :step_a, 1)

      assert is_binary(task_id)
      assert TaskQueue.depth(queue) == 1

      {:ok, task} = TaskQueue.pull(queue)
      assert task.workflow_id == "wf-1"
      assert task.step == :step_a
      assert TaskQueue.depth(queue) == 0
    end

    test "pull returns empty when queue is empty", %{queue: queue} do
      assert :empty = TaskQueue.pull(queue)
    end

    test "tracks pending tasks", %{queue: queue} do
      {:ok, _} = TaskQueue.enqueue(queue, "wf-1", :step_a, 1)
      {:ok, task} = TaskQueue.pull(queue)

      pending = TaskQueue.list_pending(queue)
      assert length(pending) == 1
      assert hd(pending).task_id == task.task_id

      TaskQueue.complete(queue, task.task_id)
      Process.sleep(10)  # Let cast complete

      assert TaskQueue.list_pending(queue) == []
    end

    test "requeue increments attempt", %{queue: queue} do
      {:ok, _} = TaskQueue.enqueue(queue, "wf-1", :step_a, 1)
      {:ok, task} = TaskQueue.pull(queue)

      assert task.attempt == 1

      :ok = TaskQueue.requeue(queue, task.task_id)
      {:ok, requeued} = TaskQueue.pull(queue)

      assert requeued.attempt == 2
    end
  end

  describe "Dispatcher" do
    test "schedules and assigns tasks", %{dispatcher: disp} do
      {:ok, _task_id} = Dispatcher.schedule_step(disp, "wf-1", :step_a, 1)

      # Register worker
      :ok = Dispatcher.register_worker(disp, "worker-1")

      # Request task
      {:task_lease, task, lease} = Dispatcher.request_task(disp, "worker-1")

      assert task.workflow_id == "wf-1"
      assert task.step == :step_a
      assert is_binary(lease.lease_id)
    end

    test "returns no_task when queue is empty", %{dispatcher: disp} do
      :ok = Dispatcher.register_worker(disp, "worker-1")
      assert :no_task = Dispatcher.request_task(disp, "worker-1")
    end

    test "tracks worker status", %{dispatcher: disp} do
      :ok = Dispatcher.register_worker(disp, "worker-1")

      workers = Dispatcher.list_workers(disp)
      assert length(workers) == 1

      {id, info} = hd(workers)
      assert id == "worker-1"
      assert info.status == :idle
    end

    test "report_completed releases lease", %{dispatcher: disp, lease_mgr: mgr} do
      {:ok, _} = Dispatcher.schedule_step(disp, "wf-1", :step_a, 1)
      :ok = Dispatcher.register_worker(disp, "worker-1")

      {:task_lease, _task, lease} = Dispatcher.request_task(disp, "worker-1")

      # Before completion, lease is active
      assert :lease_valid = LeaseManager.check_lease(mgr, lease.lease_id)

      # Complete the task
      :ok = Dispatcher.report_completed(disp, "worker-1", lease.lease_id, lease.fencing_token, %{})

      # After completion, lease is released
      Process.sleep(10)
      assert :lease_unknown = LeaseManager.check_lease(mgr, lease.lease_id)
    end
  end
end
