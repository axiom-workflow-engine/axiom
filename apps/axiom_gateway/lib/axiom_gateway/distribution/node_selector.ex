defmodule AxiomGateway.Distribution.NodeSelector do
  @moduledoc """
  Selects the authoritative node for a given workflow ID using consistent hashing.

  Uses `libring` to distribute keys uniformly across the cluster.
  Automatically includes the local node and all connected remote nodes.
  """

  @doc """
  Determines which node should own the given workflow ID.
  """
  @spec select_node(binary()) :: atom()
  def select_node(workflow_id) when is_binary(workflow_id) do
    # Get all potential owner nodes (self + connected cluster members)
    nodes = [Node.self() | Node.list()]

    # Create the consistent hash ring
    ring = LibRing.new()
    |> LibRing.add_nodes(nodes)

    # Map the workflow ID to a specific node
    LibRing.key_to_node(ring, workflow_id)
  end
end
