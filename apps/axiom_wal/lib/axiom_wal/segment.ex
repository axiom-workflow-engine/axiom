defmodule Axiom.WAL.Segment do
  @moduledoc """
  WAL segment file management.

  Segments are:
  - Fixed maximum size (default 64MB)
  - Append-only
  - Immutable after rotation
  - Named by segment_id
  """

  @default_max_size 64 * 1024 * 1024  # 64MB

  @type t :: %__MODULE__{
          segment_id: non_neg_integer(),
          path: String.t(),
          fd: :file.io_device() | nil,
          size: non_neg_integer(),
          max_size: non_neg_integer(),
          entry_count: non_neg_integer()
        }

  defstruct [
    :segment_id,
    :path,
    :fd,
    size: 0,
    max_size: @default_max_size,
    entry_count: 0
  ]

  @doc """
  Opens or creates a segment file.
  """
  @spec open(String.t(), non_neg_integer(), keyword()) :: {:ok, t()} | {:error, term()}
  def open(data_dir, segment_id, opts \\ []) do
    path = segment_path(data_dir, segment_id)
    max_size = Keyword.get(opts, :max_size, @default_max_size)

    # Ensure directory exists
    File.mkdir_p!(data_dir)

    case :file.open(path, [:read, :write, :binary, :raw, :append]) do
      {:ok, fd} ->
        size = case File.stat(path) do
          {:ok, %{size: s}} -> s
          _ -> 0
        end

        segment = %__MODULE__{
          segment_id: segment_id,
          path: path,
          fd: fd,
          size: size,
          max_size: max_size,
          entry_count: 0
        }
        {:ok, segment}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Writes data to the segment with fsync.
  Returns {:ok, updated_segment} or {:error, reason}.
  """
  @spec write(t(), binary()) :: {:ok, t()} | {:error, term()}
  def write(%__MODULE__{fd: fd, size: size, entry_count: count} = segment, data) do
    case :file.write(fd, data) do
      :ok ->
        # CRITICAL: fsync to ensure durability
        case :file.sync(fd) do
          :ok ->
            {:ok, %{segment |
              size: size + byte_size(data),
              entry_count: count + 1
            }}
          {:error, reason} ->
            {:error, {:sync_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:write_failed, reason}}
    end
  end

  @doc """
  Checks if the segment needs rotation (exceeded max size).
  """
  @spec needs_rotation?(t()) :: boolean()
  def needs_rotation?(%__MODULE__{size: size, max_size: max_size}) do
    size >= max_size
  end

  @doc """
  Closes the segment file.
  """
  @spec close(t()) :: :ok | {:error, term()}
  def close(%__MODULE__{fd: nil}), do: :ok
  def close(%__MODULE__{fd: fd}) do
    :file.close(fd)
  end

  @doc """
  Reads all entries from segment for replay.
  """
  @spec read_all(String.t(), non_neg_integer()) :: {:ok, [Axiom.WAL.Entry.t()]} | {:error, term()}
  def read_all(data_dir, segment_id) do
    path = segment_path(data_dir, segment_id)

    case File.read(path) do
      {:ok, binary} ->
        entries = read_entries(binary, 0, [])
        {:ok, Enum.reverse(entries)}

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helpers

  defp segment_path(data_dir, segment_id) do
    Path.join(data_dir, "segment_#{String.pad_leading(Integer.to_string(segment_id), 8, "0")}.wal")
  end

  defp read_entries(binary, offset, acc) do
    case Axiom.WAL.Entry.deserialize(binary, offset) do
      {:ok, {entry, rest}} ->
        new_offset = offset + Axiom.WAL.Entry.header_size() + byte_size(entry.payload)
        read_entries(rest, new_offset, [entry | acc])

      {:error, :empty} ->
        acc

      {:error, :incomplete} ->
        # Partial write, ignore trailing bytes
        acc

      {:error, :corrupted} ->
        # Stop at corruption
        acc
    end
  end
end
