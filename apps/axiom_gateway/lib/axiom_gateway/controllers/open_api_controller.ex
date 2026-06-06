defmodule AxiomGateway.Controllers.OpenApiController do
  @moduledoc """
  Serves the canonical OpenAPI 3.1.0 specification for the Axiom Gateway.

  The spec is the same file used to generate the official client SDKs
  (TypeScript, Python, Go). Keeping a single source of truth prevents
  drift between the served spec and the SDKs.

  Two endpoints:
    * `GET /api/v1/openapi.json` — JSON form
    * `GET /api/v1/openapi.yaml` — original YAML

  The YAML is shipped as a priv file. The JSON form is parsed on demand
  with the YamlElixir shim (YAML is a superset of JSON, so we parse the
  YAML once and return it under both content types).
  """

  use Phoenix.Controller
  require Logger

  @priv_path :code.priv_dir(:axiom_gateway)

  def spec(conn, %{"format" => "json"}), do: serve_json(conn)
  def spec(conn, _params), do: serve_json(conn)

  def yaml(conn, _params) do
    case read_spec() do
      {:ok, yaml} ->
        conn
        |> put_resp_content_type("application/yaml")
        |> send_resp(200, yaml)

      {:error, reason} ->
        Logger.error("Failed to load OpenAPI YAML: #{inspect(reason)}")
        send_resp(conn, 500, ~s({"error":"openapi_unavailable"}))
    end
  end

  defp serve_json(conn) do
    case load_spec() do
      {:ok, spec_map} ->
        json(conn, spec_map)

      {:error, reason} ->
        Logger.error("Failed to load OpenAPI spec: #{inspect(reason)}")
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "openapi_unavailable", reason: inspect(reason)})
    end
  end

  defp load_spec do
    case read_spec() do
      {:ok, yaml} -> parse_yaml(yaml)
      error -> error
    end
  end

  @doc false
  # Internal entry point used by tests; returns the parsed spec as a map.
  def load_spec_for_test, do: load_spec()

  defp read_spec do
    case File.read(Path.join(@priv_path, "openapi.yaml")) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, {:priv_read_failed, reason}}
    end
  end

  defp parse_yaml(yaml) do
    if Code.ensure_loaded?(YamlElixir) do
      case YamlElixir.read_from_string(yaml) do
        %{} = map ->
          {:ok, stringify_keys(map)}

        {:ok, %{} = map} ->
          {:ok, stringify_keys(map)}

        {:ok, list} when is_list(list) ->
          # Multi-document YAML — merge paths/components from all docs
          merged = merge_documents(list)
          {:ok, merged}

        {:error, reason} ->
          {:error, {:yaml_parse_failed, reason}}

        other ->
          {:error, {:unexpected_yaml, other}}
      end
    else
      # Fall back to a hand-rolled minimal YAML parser. The OpenAPI
      # spec is a strict subset of YAML so Jason.decode/1 works as
      # long as the document is also valid JSON. This is brittle and
      # only meant as a last resort — install :yaml_elixir for prod.
      case Jason.decode(yaml) do
        {:ok, map} -> {:ok, map}
        {:error, _} -> {:error, :yaml_parser_unavailable}
      end
    end
  end

  defp merge_documents(docs) do
    Enum.reduce(docs, %{}, fn doc, acc -> Map.merge(acc, doc) end)
    |> stringify_keys()
  end

  # Jason encodes atoms as strings already; we just normalize keys to
  # strings in case the parser returned atom keys.
  defp stringify_keys(value) when is_map(value) do
    Map.new(value, fn {k, v} -> {to_string(k), stringify_keys(v)} end)
  end

  defp stringify_keys(value) when is_list(value), do: Enum.map(value, &stringify_keys/1)
  defp stringify_keys(value), do: value
end
