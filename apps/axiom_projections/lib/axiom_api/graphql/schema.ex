defmodule Axiom.API.GraphQL.Schema do
  @moduledoc """
  GraphQL schema for Axiom API.
  """

  use Absinthe.Schema

  alias Axiom.API.GraphQL.{WorkflowResolver, TaskResolver, MetricsResolver, ChaosResolver}

  # ============================================================================
  # TYPES
  # ============================================================================

  object :workflow do
    field :id, non_null(:id)
    field :name, non_null(:string)
    field :state, non_null(:string)
    field :steps, non_null(list_of(:string))
    field :step_states, :json
    field :version, :integer
    field :created_at, :integer

    field :events, list_of(:event) do
      resolve &WorkflowResolver.get_events/3
    end
  end

  object :event do
    field :id, non_null(:id)
    field :type, non_null(:string)
    field :sequence, non_null(:integer)
    field :timestamp, non_null(:integer)
    field :payload, :json
  end

  object :task do
    field :id, non_null(:id)
    field :workflow_id, non_null(:id)
    field :step, non_null(:string)
    field :attempt, non_null(:integer)
    field :enqueued_at, :integer
  end

  object :task_stats do
    field :queue_depth, non_null(:integer)
    field :pending_count, non_null(:integer)
    field :pending, list_of(:task)
  end

  object :metrics do
    field :system, :system_metrics
    field :wal, :wal_metrics
    field :scheduler, :scheduler_metrics
    field :engine, :engine_metrics
  end

  object :system_metrics do
    field :memory_total, :integer
    field :memory_processes, :integer
    field :process_count, :integer
    field :schedulers_online, :integer
    field :uptime_ms, :integer
  end

  object :wal_metrics do
    field :status, :string
    field :offset, :integer
  end

  object :scheduler_metrics do
    field :status, :string
    field :queue_depth, :integer
    field :active_leases, :integer
    field :workers, :integer
  end

  object :engine_metrics do
    field :active_workflows, :integer
    field :completed_workflows, :integer
    field :failed_workflows, :integer
  end

  object :chaos_scenario do
    field :id, non_null(:string)
    field :name, non_null(:string)
    field :description, non_null(:string)
    field :default_duration_ms, non_null(:integer)
  end

  object :health do
    field :healthy, non_null(:boolean)
    field :checks, :json
    field :timestamp, :integer
  end

  object :mutation_result do
    field :success, non_null(:boolean)
    field :message, :string
    field :id, :id
  end

  # Custom JSON scalar for flexible payloads
  scalar :json, name: "JSON" do
    serialize &Jason.encode!/1
    parse fn
      %Absinthe.Blueprint.Input.String{value: value} -> Jason.decode(value)
      _ -> :error
    end
  end

  # ============================================================================
  # QUERIES
  # ============================================================================

  query do
    @desc "Get a workflow by ID"
    field :workflow, :workflow do
      arg :id, non_null(:id)
      resolve &WorkflowResolver.get/3
    end

    @desc "List all workflows"
    field :workflows, list_of(:workflow) do
      arg :limit, :integer, default_value: 20
      arg :offset, :integer, default_value: 0
      resolve &WorkflowResolver.list/3
    end

    @desc "Get task queue status"
    field :tasks, :task_stats do
      resolve &TaskResolver.get_stats/3
    end

    @desc "Get system metrics"
    field :metrics, :metrics do
      resolve &MetricsResolver.get/3
    end

    @desc "Get health status"
    field :health, :health do
      resolve fn _, _, _ ->
        {:ok, Axiom.API.Health.check_all()}
      end
    end

    @desc "List chaos scenarios"
    field :chaos_scenarios, list_of(:chaos_scenario) do
      resolve &ChaosResolver.list/3
    end
  end

  # ============================================================================
  # MUTATIONS
  # ============================================================================

  mutation do
    @desc "Create a new workflow"
    field :create_workflow, :workflow do
      arg :name, non_null(:string)
      arg :steps, non_null(list_of(:string))
      arg :input, :json
      resolve &WorkflowResolver.create/3
    end

    @desc "Advance a workflow to next step"
    field :advance_workflow, :mutation_result do
      arg :id, non_null(:id)
      resolve &WorkflowResolver.advance/3
    end

    @desc "Run a chaos scenario"
    field :run_chaos, :mutation_result do
      arg :scenario, non_null(:string)
      arg :duration_ms, :integer, default_value: 10_000
      resolve &ChaosResolver.run/3
    end

    @desc "Verify system consistency"
    field :verify, :mutation_result do
      resolve &ChaosResolver.verify/3
    end
  end

  # ============================================================================
  # SUBSCRIPTIONS
  # ============================================================================

  subscription do
    @desc "Subscribe to workflow events"
    field :workflow_events, :event do
      arg :workflow_id, non_null(:id)

      config fn args, _context ->
        {:ok, topic: "workflow:#{args.workflow_id}"}
      end
    end

    @desc "Subscribe to task updates"
    field :task_updates, :task do
      config fn _args, _context ->
        {:ok, topic: "tasks"}
      end
    end
  end
end
