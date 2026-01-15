defmodule AxiomGateway.Controllers.SchemaController do
  use Phoenix.Controller

  alias AxiomGateway.Schemas.Store
  action_fallback AxiomGateway.Controllers.FallbackController

  def index(conn, _params) do
    schemas = Store.list_schemas()
    json(conn, %{data: schemas})
  end

  def show(conn, %{"name" => name}) do
    case Store.get_schema(name) do
      {:ok, schema} -> json(conn, %{data: schema})
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  def create(conn, %{"name" => name, "schema" => schema}) do
    case Store.register_schema(name, schema) do
      {:ok, _} ->
        conn
        |> put_status(:created)
        |> json(%{status: "registered", name: name})

      {:error, :invalid_json_schema} ->
        {:error, {:bad_request, "Invalid JSON Schema"}}
    end
  end
end
