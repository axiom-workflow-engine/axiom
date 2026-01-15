defmodule Axiom.API.GraphQL.ChaosResolver do
  @moduledoc """
  GraphQL resolvers for chaos operations.
  """

  def list(_parent, _args, _context) do
    scenarios = AxiomChaos.scenarios()
    {:ok, scenarios}
  end

  def run(_parent, %{scenario: scenario} = args, _context) do
    duration = Map.get(args, :duration_ms, 10_000)

    # Run async to not block the request
    Task.start(fn -> AxiomChaos.run(scenario, duration_ms: duration) end)

    {:ok, %{success: true, message: "Chaos scenario '#{scenario}' started"}}
  end

  def verify(_parent, _args, _context) do
    case AxiomChaos.verify() do
      {:ok, _result} ->
        {:ok, %{success: true, message: "All consistency checks passed"}}

      {:error, result} ->
        {:ok, %{success: false, message: "Checks failed: #{inspect(result.failures)}"}}
    end
  end
end
