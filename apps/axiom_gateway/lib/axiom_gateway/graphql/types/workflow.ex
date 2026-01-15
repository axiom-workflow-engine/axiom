defmodule AxiomGateway.GraphQL.Types.Workflow do
  use Absinthe.Schema.Notation

  object :workflow do
    field :id, non_null(:id)
    field :name, non_null(:string)
    field :status, non_null(:string)
    field :created_at, non_null(:string) # ISO8601
    field :updated_at, non_null(:string)

    field :steps, list_of(:step)
    field :history, list_of(:history_event)
  end

  object :step do
    field :name, non_null(:string)
    field :status, non_null(:string) # scheduled, running, completed, failed
    field :attempt, :integer
    field :result, :string # JSON serialized
    field :error, :string # JSON serialized
  end

  object :history_event do
    field :sequence, non_null(:integer)
    field :event_type, non_null(:string)
    field :timestamp, non_null(:string)
    field :details, :string # JSON string of payload
  end
end
