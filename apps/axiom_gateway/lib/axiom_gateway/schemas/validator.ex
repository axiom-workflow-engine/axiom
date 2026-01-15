defmodule AxiomGateway.Schemas.Validator do
  @moduledoc """
  Validates workflow inputs against registered schemas.
  """
  alias AxiomGateway.Schemas.Store

  def validate_input(workflow_name, input) do
    # Check if a schema exists for this workflow
    case Store.get_schema(workflow_name) do
      {:ok, schema_map} ->
        # Schema exists: MUST validate
        schema = ExJsonSchema.Schema.resolve(schema_map)
        case ExJsonSchema.Validator.validate(schema, input) do
          :ok -> :ok
          {:error, errors} ->
            formatted = Enum.map(errors, fn {err, path} -> "#{inspect(path)}: #{inspect(err)}" end)
            {:error, {:schema_validation_failed, formatted}}
        end

      {:error, :not_found} ->
        # No schema registered.
        # Strict mode: Reject unknown workflows
        # Permissive mode: Allow
        if Application.get_env(:axiom_gateway, :enforce_schemas, false) do
           {:error, {:schema_validation_failed, ["No schema registered for workflow: #{workflow_name}"]}}
        else
           :ok
        end
    end
  end
end
