defmodule TProNVRWeb.API.CVEDIXController do
  @moduledoc """
  API controller for proxying CVEDIX-RT requests.
  """
  use TProNVRWeb, :controller

  alias TProNVR.CVEDIX.Client

  @doc """
  Proxy frame from CVEDIX-RT instance.
  GET /api/cvedix/instance/:instance_id/frame
  """
  def frame(conn, %{"instance_id" => instance_id}) do
    case Client.get_frame(instance_id) do
      {:ok, body, content_type} ->
        conn
        |> put_resp_content_type(content_type)
        |> put_resp_header("cache-control", "no-cache, no-store, must-revalidate")
        |> send_resp(200, body)

      {:error, {:http_error, status, _body}} ->
        conn
        |> put_status(status)
        |> json(%{error: "Failed to get frame from CVEDIX"})

      {:error, _reason} ->
        conn
        |> put_status(503)
        |> json(%{error: "CVEDIX service unavailable"})
    end
  end
end
