defmodule Axiom.Core.Lease do
  @moduledoc """
  Lease structure for exactly-once execution.

  Leases answer: "Who is allowed to execute right now?"
  Leases are time-bounded, not trust-based.
  """

  @type t :: %__MODULE__{
          lease_id: binary(),
          workflow_id: binary(),
          step: atom(),
          attempt: pos_integer(),
          expires_at: non_neg_integer(),
          fencing_token: non_neg_integer()
        }

  @enforce_keys [:lease_id, :workflow_id, :step, :attempt, :expires_at, :fencing_token]

  defstruct [
    :lease_id,
    :workflow_id,
    :step,
    :attempt,
    :expires_at,
    :fencing_token
  ]

  alias Axiom.Core.Event

  @default_lease_duration_ms 30_000

  @doc """
  Creates a new lease.
  """
  @spec new(binary(), atom(), pos_integer(), non_neg_integer(), keyword()) :: t()
  def new(workflow_id, step, attempt, fencing_token, opts \\ []) do
    duration_ms = Keyword.get(opts, :duration_ms, @default_lease_duration_ms)

    %__MODULE__{
      lease_id: Event.generate_uuid(),
      workflow_id: workflow_id,
      step: step,
      attempt: attempt,
      expires_at: Event.logical_time() + duration_ms * 1_000_000,
      fencing_token: fencing_token
    }
  end

  @doc """
  Checks if a lease is still valid (not expired).
  """
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{expires_at: expires_at}) do
    Event.logical_time() < expires_at
  end

  @doc """
  Checks if a lease is expired.
  Expired lease = worker is ignored, even if it finishes.
  """
  @spec expired?(t()) :: boolean()
  def expired?(lease), do: not valid?(lease)
end
