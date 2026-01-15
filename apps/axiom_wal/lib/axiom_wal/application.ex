defmodule AxiomWal.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Axiom.WAL.LogAppendServer, [
        data_dir: Application.get_env(:axiom_wal, :data_dir, "./data/wal")
      ]}
    ]

    opts = [strategy: :one_for_one, name: AxiomWal.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
