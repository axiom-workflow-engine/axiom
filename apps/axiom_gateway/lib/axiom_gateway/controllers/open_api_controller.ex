defmodule AxiomGateway.Controllers.OpenApiController do
  use Phoenix.Controller

  def spec(conn, _params) do
    json(conn, %{
      openapi: "3.0.3",
      info: %{
        title: "Axiom Gateway API",
        version: "0.1.0",
        description: "Durable ingress API for the Axiom workflow engine"
      },
      paths: %{
        "/health" => %{
          get: %{summary: "Liveness check"}
        },
        "/ready" => %{
          get: %{summary: "Readiness check"}
        },
        "/api/v1/workflows" => %{
          get: %{summary: "List workflows"},
          post: %{summary: "Create workflow"}
        },
        "/api/v1/workflows/{id}" => %{
          get: %{summary: "Get workflow by id"}
        },
        "/api/v1/metrics" => %{
          get: %{summary: "Gateway and engine metrics"}
        }
      }
    })
  end
end
