defmodule Axiom.API.Router do
  @moduledoc """
  Main API router supporting both REST and GraphQL.
  """

  use Plug.Router

  plug Plug.Logger
  plug :match
  plug Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  plug :dispatch

  # ============================================================================
  # HEALTH CHECK
  # ============================================================================

  get "/health" do
    send_json(conn, 200, %{status: "ok", node: Node.self()})
  end

  get "/ready" do
    checks = Axiom.API.Health.check_all()
    status = if checks.healthy, do: 200, else: 503
    send_json(conn, status, checks)
  end

  # ============================================================================
  # REST API - WORKFLOWS
  # ============================================================================

  get "/api/v1/workflows" do
    params = conn.query_params
    limit = Map.get(params, "limit", "20") |> String.to_integer()
    offset = Map.get(params, "offset", "0") |> String.to_integer()

    case Axiom.API.Workflows.list(limit: limit, offset: offset) do
      {:ok, workflows} ->
        send_json(conn, 200, %{data: workflows, meta: %{limit: limit, offset: offset}})
      {:error, reason} ->
        send_json(conn, 500, %{error: inspect(reason)})
    end
  end

  post "/api/v1/workflows" do
    case conn.body_params do
      %{"name" => name, "steps" => steps} = params ->
        input = Map.get(params, "input", %{})
        step_atoms = Enum.map(steps, &String.to_atom/1)

        case Axiom.API.Workflows.create(name, input, step_atoms) do
          {:ok, workflow} ->
            send_json(conn, 201, %{data: workflow})
          {:error, reason} ->
            send_json(conn, 400, %{error: inspect(reason)})
        end

      _ ->
        send_json(conn, 400, %{error: "Missing required fields: name, steps"})
    end
  end

  get "/api/v1/workflows/:id" do
    case Axiom.API.Workflows.get(id) do
      {:ok, workflow} ->
        send_json(conn, 200, %{data: workflow})
      {:error, :not_found} ->
        send_json(conn, 404, %{error: "Workflow not found"})
    end
  end

  get "/api/v1/workflows/:id/events" do
    case Axiom.API.Workflows.get_events(id) do
      {:ok, events} ->
        send_json(conn, 200, %{data: events})
      {:error, :not_found} ->
        send_json(conn, 404, %{error: "Workflow not found"})
    end
  end

  post "/api/v1/workflows/:id/advance" do
    case Axiom.API.Workflows.advance(id) do
      :ok ->
        send_json(conn, 200, %{status: "advanced"})
      {:error, reason} ->
        send_json(conn, 400, %{error: inspect(reason)})
    end
  end

  # ============================================================================
  # REST API - TASKS
  # ============================================================================

  get "/api/v1/tasks" do
    case Axiom.API.Tasks.list() do
      {:ok, tasks} ->
        send_json(conn, 200, %{data: tasks})
      {:error, reason} ->
        send_json(conn, 500, %{error: inspect(reason)})
    end
  end

  get "/api/v1/tasks/pending" do
    case Axiom.API.Tasks.list_pending() do
      {:ok, tasks} ->
        send_json(conn, 200, %{data: tasks})
      {:error, reason} ->
        send_json(conn, 500, %{error: inspect(reason)})
    end
  end

  # ============================================================================
  # REST API - METRICS
  # ============================================================================

  get "/api/v1/metrics" do
    metrics = Axiom.API.Metrics.collect()
    send_json(conn, 200, %{data: metrics})
  end

  get "/api/v1/metrics/prometheus" do
    metrics = Axiom.API.Metrics.prometheus_format()

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, metrics)
  end

  # ============================================================================
  # REST API - CHAOS
  # ============================================================================

  get "/api/v1/chaos/scenarios" do
    scenarios = AxiomChaos.scenarios()
    send_json(conn, 200, %{data: scenarios})
  end

  post "/api/v1/chaos/run" do
    case conn.body_params do
      %{"scenario" => scenario} = params ->
        opts = [duration_ms: Map.get(params, "duration_ms", 10_000)]

        # Run async
        Task.start(fn -> AxiomChaos.run(scenario, opts) end)

        send_json(conn, 202, %{status: "started", scenario: scenario})

      _ ->
        send_json(conn, 400, %{error: "Missing required field: scenario"})
    end
  end

  post "/api/v1/verify" do
    case AxiomChaos.verify() do
      {:ok, result} ->
        send_json(conn, 200, %{status: "passed", data: result})
      {:error, result} ->
        send_json(conn, 500, %{status: "failed", data: result})
    end
  end

  # ============================================================================
  # GRAPHQL
  # ============================================================================

  forward "/graphql", to: Axiom.API.GraphQL.Plug

  get "/graphiql" do
    html = """
    <!DOCTYPE html>
    <html>
    <head>
      <title>Axiom GraphQL</title>
      <link href="https://unpkg.com/graphiql/graphiql.min.css" rel="stylesheet" />
    </head>
    <body style="margin: 0;">
      <div id="graphiql" style="height: 100vh;"></div>
      <script crossorigin src="https://unpkg.com/react/umd/react.production.min.js"></script>
      <script crossorigin src="https://unpkg.com/react-dom/umd/react-dom.production.min.js"></script>
      <script crossorigin src="https://unpkg.com/graphiql/graphiql.min.js"></script>
      <script>
        const fetcher = GraphiQL.createFetcher({ url: '/graphql' });
        ReactDOM.render(
          React.createElement(GraphiQL, { fetcher }),
          document.getElementById('graphiql'),
        );
      </script>
    </body>
    </html>
    """

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  # ============================================================================
  # FALLBACK
  # ============================================================================

  match _ do
    send_json(conn, 404, %{error: "Not found"})
  end

  # ============================================================================
  # HELPERS
  # ============================================================================

  defp send_json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
