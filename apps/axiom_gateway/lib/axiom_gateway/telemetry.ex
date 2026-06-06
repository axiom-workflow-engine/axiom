defmodule AxiomGateway.Telemetry do
  @moduledoc """
  Telemetry and metrics supervisor for Axiom Gateway.
  """
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry polling for periodic measurements
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),

      # Periodic memory measurements (sourced from periodic_measurements/0)
      last_value("process.memory.total", unit: :byte),
      last_value("process.memory.ets", unit: :byte),
      last_value("process.memory.binary", unit: :byte),
      last_value("process.memory.code", unit: :byte),

      # Periodic scheduler and process counts
      last_value("process.run_queue.total", unit: :integer),
      last_value("process.run_queue.cpu", unit: :integer),
      last_value("process.run_queue.io", unit: :integer),
      last_value("process.process_count.total", unit: :integer),
      last_value("process.port_count.total", unit: :integer),
      last_value("process.atom_count.total", unit: :integer)
    ]
  end

  defp periodic_measurements do
    [
      # Periodic VM and BEAM-level measurements. These fire every
      # 10s (see init/1) and produce the metrics listed in metrics/0.
      {Process, [:memory, :total], fn -> :erlang.memory(:total) end, :byte},
      {Process, [:memory, :ets], fn -> :erlang.memory(:ets) end, :byte},
      {Process, [:memory, :binary], fn -> :erlang.memory(:binary) end, :byte},
      {Process, [:memory, :code], fn -> :erlang.memory(:code) end, :byte},
      {Process, [:run_queue, :total], fn ->
        :erlang.statistics(:total_run_queue_lengths) |> Map.get(:total, 0)
      end, :integer},
      {Process, [:run_queue, :cpu], fn ->
        :erlang.statistics(:total_run_queue_lengths) |> Map.get(:cpu, 0)
      end, :integer},
      {Process, [:run_queue, :io], fn ->
        :erlang.statistics(:total_run_queue_lengths) |> Map.get(:io, 0)
      end, :integer},
      {Process, [:process_count, :total], fn ->
        :erlang.system_info(:process_count)
      end, :integer},
      {Process, [:port_count, :total], fn ->
        :erlang.system_info(:port_count)
      end, :integer},
      {Process, [:atom_count, :total], fn ->
        :erlang.system_info(:atom_count)
      end, :integer}
    ]
  end
end
