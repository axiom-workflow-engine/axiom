defmodule Axiom.Core.Event do
  @moduledoc """
  Canonical event envelope for all Axiom events.

  Every event — no exceptions — uses this envelope.
  Events are facts, not commands. Events are immutable.
  """

  @type t :: %__MODULE__{
          event_id: binary(),
          event_type: atom(),
          schema_version: non_neg_integer(),
          workflow_id: binary(),
          sequence: non_neg_integer(),
          causation_id: binary() | nil,
          correlation_id: binary(),
          timestamp: non_neg_integer(),
          payload: map(),
          metadata: map()
        }

  @enforce_keys [
    :event_id,
    :event_type,
    :schema_version,
    :workflow_id,
    :sequence,
    :correlation_id,
    :timestamp,
    :payload
  ]

  defstruct [
    :event_id,
    :event_type,
    :schema_version,
    :workflow_id,
    :sequence,
    :causation_id,
    :correlation_id,
    :timestamp,
    :payload,
    metadata: %{}
  ]

  @doc """
  Creates a new event with generated event_id and timestamp.
  """
  @spec new(atom(), binary(), non_neg_integer(), map(), keyword()) :: t()
  def new(event_type, workflow_id, sequence, payload, opts \\ []) do
    %__MODULE__{
      event_id: generate_uuid(),
      event_type: event_type,
      schema_version: Keyword.get(opts, :schema_version, 1),
      workflow_id: workflow_id,
      sequence: sequence,
      causation_id: Keyword.get(opts, :causation_id),
      correlation_id: Keyword.get(opts, :correlation_id, generate_uuid()),
      timestamp: logical_time(),
      payload: payload,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Generates a UUID v4.
  """
  @spec generate_uuid() :: binary()
  def generate_uuid do
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)

    <<a::32, b::16, 4::4, c::12, 2::2, d::14, e::48>>
    |> Base.encode16(case: :lower)
    |> String.replace(~r/(.{8})(.{4})(.{4})(.{4})(.{12})/, "\\1-\\2-\\3-\\4-\\5")
  end

  @doc """
  Returns logical time (monotonic + system time offset).
  This is NOT wall clock time - it's for ordering only.
  """
  @spec logical_time() :: non_neg_integer()
  def logical_time do
    System.monotonic_time(:nanosecond) + System.time_offset(:nanosecond)
  end

  @doc """
  Serializes an event to binary format for WAL storage.
  Format: [payload_bytes]
  """
  @spec to_binary(t()) :: binary()
  def to_binary(%__MODULE__{} = event) do
    :erlang.term_to_binary(event)
  end

  @doc """
  Deserializes an event from binary format.
  """
  @spec from_binary(binary()) :: {:ok, t()} | {:error, :invalid_format}
  def from_binary(binary) when is_binary(binary) do
    {:ok, :erlang.binary_to_term(binary, [:safe])}
  rescue
    _ -> {:error, :invalid_format}
  end

  @doc """
  Computes idempotency key for exactly-once semantics.
  """
  @spec idempotency_key(binary(), atom(), pos_integer()) :: binary()
  def idempotency_key(workflow_id, step, attempt) do
    data = "#{workflow_id}:#{step}:#{attempt}"
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
  end
end
