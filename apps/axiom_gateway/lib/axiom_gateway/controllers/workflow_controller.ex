defmodule AxiomGateway.Controllers.WorkflowController do
  @moduledoc """
  REST surface for workflow lifecycle and the data plane (lease / result).

  Read paths use the projection index (eventually-consistent) and
  fall back to the WAL for hydration. Write paths route through the
  Durable Acceptor so the request is durably persisted before a 2xx
  is returned. The lease/result endpoints call directly into the
  scheduler because they are the data plane, not durable writes.
  """

  use Phoenix.Controller
  require Logger

  alias AxiomGateway.Durable.Acceptor
  alias Axiom.WAL.LogAppendServer
  alias Axiom.Engine.StateMachine
  alias AxiomGateway.Projections.WorkflowIndex
  alias Axiom.Scheduler.Dispatcher
  alias Axiom.Scheduler.TaskQueue
  alias Axiom.Core.Event

  action_fallback(AxiomGateway.Controllers.FallbackController)

  # Lease polling against a workflow-scoped URL. We pull from the global
  # queue and re-enqueue any task that doesn't match the requested
  # workflow. Cap the number of skips per request to avoid unbounded
  # work when many other workflows have tasks queued.
  @max_lease_skips_per_request 5

  # --------------------------------------------------------------------------
  # Read endpoints
  # --------------------------------------------------------------------------

  def index(conn, params) do
    limit = parse_int(Map.get(params, "limit"), 100, max: 1_000)
    offset = parse_int(Map.get(params, "offset"), 0, min: 0)
    status = Map.get(params, "status")
    name = Map.get(params, "name")

    workflows = WorkflowIndex.list_workflows(limit: limit, offset: offset, status: status, name: name)
    total = WorkflowIndex.count_workflows(status: status, name: name)

    json(conn, %{
      data: workflows,
      meta: %{
        total: total,
        limit: limit,
        offset: offset,
        has_more: offset + length(workflows) < total
      }
    })
  end

  def show(conn, %{"id" => id}) do
    case Registry.lookup(Axiom.Engine.Registry, id) do
      [{pid, _}] ->
        state_machine = Axiom.Engine.WorkflowProcess.get_state(pid)
        json(conn, %{data: serialize_state(state_machine)})

      [] ->
        # Fall back to WAL replay for a workflow whose process isn't running.
        case LogAppendServer.replay(LogAppendServer, id) do
          {:ok, events} when events != [] ->
            state_machine = StateMachine.hydrate(id, events)
            json(conn, %{data: serialize_state(state_machine)})

          _ ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Workflow not found"})
        end
    end
  end

  def events(conn, %{"id" => id} = params) do
    from_sequence = parse_int(Map.get(params, "from_sequence"), 0, min: 0)
    limit = parse_int(Map.get(params, "limit"), 100, max: 1_000)

    case LogAppendServer.replay(LogAppendServer, id) do
      {:ok, events} ->
        filtered =
          events
          |> Enum.filter(fn e -> e.sequence >= from_sequence end)
          |> Enum.take(limit)

        json(conn, %{data: filtered})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: inspect(reason)})
    end
  end

  # --------------------------------------------------------------------------
  # Write endpoints (durable, idempotent)
  # --------------------------------------------------------------------------

  def create(conn, params) do
    identity = conn.assigns[:current_user]

    case Acceptor.accept_workflow(params, identity) do
      {:ok, workflow_id} ->
        conn
        |> put_status(:created)
        |> put_resp_header("location", "/api/v1/workflows/#{workflow_id}")
        |> json(%{data: %{id: workflow_id, status: "accepted"}})

      {:error, reason} ->
        {:error, reason}
    end
  end

  def bulk_create(conn, %{"workflows" => workflows}) when is_list(workflows) do
    if length(workflows) > 100 do
      {:error, {:bad_request, "bulk_create accepts at most 100 workflows"}}
    else
      results = Enum.with_index(workflows, fn workflow, index -> {index, process_bulk(workflow)} end)
      {created, errors} = split_bulk_results(results)
      status = if errors == [], do: :created, else: :multi_status
      json(conn |> put_status(status), %{data: created, errors: errors})
    end
  end

  def bulk_create(conn, _params) do
    {:error, {:bad_request, "Missing 'workflows' array"}}
  end

  def cancel(conn, %{"id" => id}) do
    identity = conn.assigns[:current_user]

    case Acceptor.accept_cancellation(id, identity) do
      :ok ->
        json(conn, %{data: %{id: id, status: "cancelling"}})

      error ->
        error
    end
  end

  def advance(conn, %{"id" => id}) do
    identity = conn.assigns[:current_user]

    case Acceptor.accept_advancement(id, identity) do
      :ok ->
        json(conn, %{data: %{id: id, status: "advancing"}})

      error ->
        error
    end
  end

  # --------------------------------------------------------------------------
  # Data plane (worker operations)
  # --------------------------------------------------------------------------

  def lease(conn, %{"id" => workflow_id} = params) do
    worker_id = Map.get(params, "worker_id")

    if is_nil(worker_id) or worker_id == "" do
      {:error, {:bad_request, "worker_id query parameter is required"}}
    else
      case pull_lease_for_workflow(workflow_id, worker_id) do
        {:ok, lease} ->
          json(conn, %{data: serialize_lease(lease)})

        :no_task ->
          conn
          |> put_status(:no_content)
          |> send_resp(204, "")

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def lease(conn, _params) do
    {:error, {:bad_request, "Missing workflow id"}}
  end

  def submit_result(conn, %{"id" => workflow_id} = params) do
    worker_id = worker_id_from_headers(conn) || Event.generate_uuid()
    idempotency_key = get_req_header(conn, "idempotency-key") |> List.first()

    with :ok <- validate_submit_payload(params),
         {:ok, status} <- extract_status(params) do
      # Idempotency keys are forwarded to the workflow process via the
      # dispatcher -> engine -> WorkflowProcess path, but the current
      # dispatcher signature doesn't take opts. The key is included in
      # the response headers for clients that need to correlate retries.
      conn = put_resp_header(conn, "x-idempotency-key", idempotency_key || "")

      result =
        case status do
          :completed ->
            Dispatcher.report_completed(
              Dispatcher,
              worker_id,
              params["lease_id"],
              params["fencing_token"],
              params["result"] || %{}
            )

          :failed ->
            Dispatcher.report_failed(
              Dispatcher,
              worker_id,
              params["lease_id"],
              params["fencing_token"],
              params["error"] || default_error(params),
              Map.get(params, "retryable", true)
            )
        end

      case result do
        :ok ->
          json(conn, %{
            data: %{
              workflow_id: workflow_id,
              status: to_string(status),
              accepted_at: DateTime.utc_now()
            }
          })

        {:error, :fencing_token_stale} ->
          {:error, :fencing_token_stale}

        {:error, :lease_expired} ->
          {:error, :lease_expired}

        {:error, :lease_unknown} ->
          {:error, :lease_unknown}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def submit_result(conn, _params) do
    {:error, {:bad_request, "Missing workflow id"}}
  end

  # --------------------------------------------------------------------------
  # Internals
  # --------------------------------------------------------------------------

  defp pull_lease_for_workflow(workflow_id, worker_id) do
    do_pull(workflow_id, worker_id, @max_lease_skips_per_request)
  end

  defp do_pull(_workflow_id, _worker_id, 0), do: :no_task

  defp do_pull(workflow_id, worker_id, attempts_left) do
    case Dispatcher.request_task(Dispatcher, worker_id) do
      {:task_lease, task, lease} ->
        if task.workflow_id == workflow_id do
          {:ok, Map.merge(lease, %{task: serialize_task(task), input: task[:input] || lease[:input] || %{}})}
        else
          # Not for this workflow — re-enqueue and try again.
          TaskQueue.requeue(TaskQueue, task.task_id)
          do_pull(workflow_id, worker_id, attempts_left - 1)
        end

      :no_task ->
        :no_task

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_submit_payload(%{"lease_id" => lid, "fencing_token" => ft, "status" => status})
       when is_binary(lid) and byte_size(lid) > 0 and is_integer(ft) and ft > 0 and
              status in ["completed", "failed"] do
    :ok
  end

  defp validate_submit_payload(_), do: {:error, {:bad_request, "lease_id, fencing_token, and status (completed|failed) are required"}}

  defp extract_status(%{"status" => "completed"}), do: {:ok, :completed}
  defp extract_status(%{"status" => "failed"}), do: {:ok, :failed}

  defp default_error(params) do
    %{
      "message" => Map.get(params, "error_message", "step failed"),
      "code" => Map.get(params, "error_code"),
      "retryable" => Map.get(params, "retryable", true)
    }
  end

  defp worker_id_from_headers(conn) do
    case get_req_header(conn, "x-worker-id") |> List.first() do
      nil -> nil
      "" -> nil
      id -> id
    end
  end

  defp process_bulk(workflow) when is_map(workflow) do
    case Acceptor.accept_workflow(workflow, nil) do
      {:ok, workflow_id} -> {:ok, %{id: workflow_id, status: "accepted"}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp process_bulk(_), do: {:error, "workflow must be an object"}

  defp split_bulk_results(results) do
    {created, errors} =
      Enum.reduce(results, {[], []}, fn {index, result}, {created, errors} ->
        case result do
          {:ok, data} -> {created ++ [data], errors}
          {:error, reason} -> {created, errors ++ [%{index: index, error: inspect_error(reason)}]}
        end
      end)

    {created, errors}
  end

  defp inspect_error({:bad_request, reason}), do: %{type: "validation", detail: inspect(reason)}
  defp inspect_error(reason) when is_atom(reason), do: %{type: "engine", code: Atom.to_string(reason)}
  defp inspect_error(reason), do: %{type: "engine", detail: inspect(reason)}

  defp serialize_state(sm) do
    %{
      id: sm.workflow_id,
      status: if(StateMachine.terminal?(sm), do: "completed", else: "running"),
      current_step: List.first(sm.steps),
      current_step_index: sm.current_step_index,
      version: sm.version,
      context: sm.context,
      steps: serialize_steps(sm),
      created_at: nil,
      updated_at: nil
    }
  end

  defp serialize_steps(sm) do
    Enum.map(sm.steps, fn step ->
      %{
        name: step |> Atom.to_string(),
        status: Atom.to_string(Map.get(sm.step_states, step, :pending))
      }
    end)
  end

  defp serialize_lease(lease) do
    %{
      lease_id: lease.lease_id,
      workflow_id: lease.workflow_id,
      step: lease.step,
      attempt: lease.attempt,
      fencing_token: lease.fencing_token,
      expires_at: lease.expires_at,
      input: lease[:input] || %{}
    }
  end

  defp serialize_task(task) do
    %{
      task_id: task.task_id,
      workflow_id: task.workflow_id,
      step: task.step,
      attempt: task.attempt,
      priority: task.priority
    }
  end

  defp parse_int(nil, default, _opts), do: default
  defp parse_int(value, default, opts) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> clamp(n, default, opts)
      _ -> default
    end
  end
  defp parse_int(value, default, opts) when is_integer(value), do: clamp(value, default, opts)

  defp clamp(value, default, opts) do
    value = if min = opts[:min], do: max(value, min), else: value
    value = if max = opts[:max], do: min(value, max), else: value
    value
  end
end
