defmodule AxiomGateway.Controllers.ClusterController do
  use Phoenix.Controller

  action_fallback AxiomGateway.Controllers.FallbackController

  def index(conn, _params) do
    nodes = Node.list()
    self = Node.self()

    strategy = Application.get_env(:libcluster, :topologies, [])
              |> Keyword.get(:axiom, [])
              |> Keyword.get(:strategy, Cluster.Strategy.Epmd)

    conn
    |> json(%{
      data: %{
        self: self,
        connected_nodes: nodes,
        node_count: length(nodes) + 1,
        strategy: inspect(strategy)
      }
    })
  end

  def join(conn, %{"node" => node_name}) do
    # Manual join for ops
    node_atom = String.to_atom(node_name)
    if Node.connect(node_atom) do
      conn |> json(%{status: "connected", node: node_name})
    else
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Failed to connect to node"})
    end
  end
end
