defmodule AxiomGateway.GraphQL.Schema do
  use Absinthe.Schema

  import_types AxiomGateway.GraphQL.Types.Workflow

  alias AxiomGateway.GraphQL.Resolvers

  query do
    @desc "Get a list of workflows"
    field :workflows, list_of(:workflow) do
      arg :limit, :integer, default_value: 100
      resolve &Resolvers.Workflow.list_workflows/3
    end

    @desc "Get a specific workflow by ID"
    field :workflow, :workflow do
      arg :id, non_null(:id)
      resolve &Resolvers.Workflow.get_workflow/3
    end
  end

  mutation do
    @desc "Create a new workflow"
    field :create_workflow, :workflow do
      arg :name, non_null(:string)
      arg :steps, non_null(list_of(non_null(:string)))
      arg :input, :string # JSON string

      resolve &Resolvers.Workflow.create_workflow/3
    end
  end
end
