defmodule AxiomGateway.Plugs.Auth do
  @moduledoc """
  Multi-modal authentication plug.

  Supports:
  - API Keys (`X-Api-Key` header) for service-to-service
  - JWT (`Authorization: Bearer` header) for user/client access
  """
  import Plug.Conn
  require Logger

  # Configure Joken for JWT
  defmodule Token do
    use Joken.Config

    # Joken configuration
    def token_config do
      default_claims(iss: "axiom_auth", aud: "axiom_gateway")
    end
  end

  def init(opts), do: opts

  def call(conn, _opts) do
    credentials = extract_credentials(conn)
    result = validate_credentials(credentials)
    assign_identity(result, conn)
  end

  defp extract_credentials(conn) do
    cond do
      api_key = get_req_header(conn, "x-api-key") |> List.first() ->
        {:api_key, api_key}

      bearer = get_req_header(conn, "authorization") |> List.first() ->
        case bearer do
          "Bearer " <> token -> {:jwt, token}
          _ -> :no_credentials
        end

      true ->
        :no_credentials
    end
  end

  defp validate_credentials({:api_key, key}) do
    # Validate against persistent, secure store
    case AxiomGateway.Auth.ApiKeyStore.validate(key) do
      {:ok, tenant_id} ->
        {:ok, %{type: :api_key, key: key, role: "service", tenant_id: tenant_id}}
      {:error, _} ->
        {:error, :invalid_api_key}
    end
  end

  defp validate_credentials({:jwt, token}) do
    signer = Joken.Signer.create("HS256", Application.get_env(:axiom_gateway, :jwt_secret, "default_secret"))

    case Token.verify_and_validate(token, signer) do
      {:ok, claims} ->
        {:ok, %{
          type: :jwt,
          sub: claims["sub"],
          role: claims["role"] || "user",
          tenant_id: claims["tenant_id"] || "default"
        }}
      {:error, _reason} ->
        {:error, :invalid_jwt}
    end
  end

  defp validate_credentials(:no_credentials) do
    {:error, :unauthorized}
  end

  defp assign_identity({:ok, identity}, conn) do
    Logger.debug("Authenticated #{inspect(identity)}")
    assign(conn, :current_user, identity)
  end

  defp assign_identity({:error, reason}, conn) do
    Logger.warning("Authentication failed: #{inspect(reason)}")
    conn
    |> send_resp(401, Jason.encode!(%{error: reason}))
    |> halt()
  end

  # Helpers can be added here
end
