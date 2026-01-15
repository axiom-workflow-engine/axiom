defmodule Axiom.WAL.Entry do
  @moduledoc """
  WAL entry serialization with CRC32 checksums.

  Binary format:
  [4B length][4B CRC32][8B timestamp][payload]

  This ensures:
  - Corruption detection via CRC32
  - Ordering via timestamp
  - Recovery via length prefix
  """

  @header_size 16  # 4 + 4 + 8 bytes

  @type t :: %__MODULE__{
          offset: non_neg_integer(),
          timestamp: non_neg_integer(),
          payload: binary(),
          crc32: non_neg_integer()
        }

  defstruct [:offset, :timestamp, :payload, :crc32]

  @doc """
  Serializes a payload into a WAL entry binary.
  Returns {binary, entry_size}.
  """
  @spec serialize(binary(), non_neg_integer()) :: {binary(), non_neg_integer()}
  def serialize(payload, timestamp) when is_binary(payload) do
    payload_size = byte_size(payload)
    crc = :erlang.crc32(payload)

    entry = <<
      payload_size::unsigned-big-32,
      crc::unsigned-big-32,
      timestamp::unsigned-big-64,
      payload::binary
    >>

    {entry, byte_size(entry)}
  end

  @doc """
  Deserializes a WAL entry from binary.
  Returns {:ok, {entry, rest}} or {:error, reason}.
  """
  @spec deserialize(binary(), non_neg_integer()) ::
    {:ok, {t(), binary()}} | {:error, :incomplete | :corrupted | :empty}
  def deserialize(<<>>, _offset), do: {:error, :empty}

  def deserialize(binary, _offset) when byte_size(binary) < @header_size do
    {:error, :incomplete}
  end

  def deserialize(<<
    payload_size::unsigned-big-32,
    stored_crc::unsigned-big-32,
    timestamp::unsigned-big-64,
    rest::binary
  >>, offset) do
    if byte_size(rest) < payload_size do
      {:error, :incomplete}
    else
      <<payload::binary-size(payload_size), remaining::binary>> = rest
      computed_crc = :erlang.crc32(payload)

      if computed_crc == stored_crc do
        entry = %__MODULE__{
          offset: offset,
          timestamp: timestamp,
          payload: payload,
          crc32: stored_crc
        }
        {:ok, {entry, remaining}}
      else
        {:error, :corrupted}
      end
    end
  end

  @doc """
  Returns the header size in bytes.
  """
  @spec header_size() :: non_neg_integer()
  def header_size, do: @header_size
end
