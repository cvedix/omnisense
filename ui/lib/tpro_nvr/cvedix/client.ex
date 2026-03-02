defmodule TProNVR.CVEDIX.Client do
  @moduledoc """
  HTTP client for CVEDIX-RT API calls.
  Uses Finch for connection pooling.
  """

  require Logger

  @default_timeout 30_000

  @doc """
  Get the base URL for CVEDIX-RT API.
  """
  def base_url do
    Application.get_env(:tpro_nvr, :cvedix, [])[:base_url] || "http://127.0.0.1:3546"
  end

  @doc """
  GET request to CVEDIX-RT API.
  """
  def get(path, opts \\ []) do
    request(:get, path, nil, opts)
  end

  @doc """
  POST request to CVEDIX-RT API.
  """
  def post(path, body \\ nil, opts \\ []) do
    Logger.info("[CVEDIX POST] #{path} body=#{inspect(body)}")
    request(:post, path, body, opts)
  end

  @doc """
  PUT request to CVEDIX-RT API.
  """
  def put(path, body \\ nil, opts \\ []) do
    url = build_url(path)
    Logger.info("[CVEDIX PUT] Full URL: #{url}")
    Logger.info("[CVEDIX PUT] Body: #{inspect(body)}")
    request(:put, path, body, opts)
  end

  @doc """
  PATCH request to CVEDIX-RT API.
  """
  def patch(path, body \\ nil, opts \\ []) do
    request(:patch, path, body, opts)
  end

  @doc """
  DELETE request to CVEDIX-RT API.
  """
  def delete(path, opts \\ []) do
    request(:delete, path, nil, opts)
  end

  @doc """
  GET frame (binary image) from CVEDIX-RT.
  Returns {:ok, binary, content_type} or {:error, reason}
  Note: CVEDIX returns frame as base64 string in JSON: {"frame": "base64..."}
  """
  def get_frame(instance_id) do
    url = build_url("/v1/core/instance/#{instance_id}/frame")

    headers = [
      {"accept", "application/json"}
    ]

    request = Finch.build(:get, url, headers)

    case Finch.request(request, TProNVR.Finch, receive_timeout: 5_000) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        # CVEDIX returns JSON with base64 frame: {"frame": "/9j/4AAQ..."}
        case Jason.decode(body) do
          {:ok, %{"frame" => base64_frame}} ->
            case Base.decode64(base64_frame) do
              {:ok, binary} ->
                {:ok, binary, "image/jpeg"}
              :error ->
                Logger.warning("[CVEDIX Client] Failed to decode base64 frame")
                {:error, :invalid_base64}
            end
          {:ok, _} ->
            Logger.warning("[CVEDIX Client] Unexpected JSON response format")
            {:error, :invalid_response}
          {:error, _} ->
            # Maybe it's raw binary after all
            {:ok, body, "image/jpeg"}
        end

      {:ok, %Finch.Response{status: status, body: body}} ->
        Logger.warning("[CVEDIX Client] Frame request failed: #{status}")
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Logger.error("[CVEDIX Client] Frame request error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private implementation

  defp request(method, path, body, opts) do
    url = build_url(path)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    headers = [
      {"content-type", "application/json"},
      {"accept", "application/json"}
    ]

    body_encoded = if body, do: Jason.encode!(body), else: ""

    request = Finch.build(method, url, headers, body_encoded)

    case Finch.request(request, TProNVR.Finch, receive_timeout: timeout) do
      {:ok, %Finch.Response{status: status, body: response_body}}
      when status in 200..299 ->
        parse_response(response_body)

      {:ok, %Finch.Response{status: 204}} ->
        :ok

      {:ok, %Finch.Response{status: status, body: response_body}} ->
        Logger.warning("CVEDIX API error: #{status} - #{response_body}")
        {:error, {:http_error, status, response_body}}

      {:error, reason} = error ->
        Logger.error("CVEDIX API request failed: #{inspect(reason)}")
        error
    end
  end

  defp build_url(path) do
    base_url = Application.get_env(:tpro_nvr, :cvedix, [])[:base_url] || "http://127.0.0.1:3546"
    "#{base_url}#{path}"
  end

  defp parse_response(""), do: :ok

  defp parse_response(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, data} -> {:ok, data}
      {:error, _} -> {:ok, body}
    end
  end
end
