defmodule TProNVRWeb.API.SystemStatusController do
  @moduledoc false

  use TProNVRWeb, :controller

  import TProNVR.Authorization

  alias TProNVR.SystemStatus

  action_fallback TProNVRWeb.API.FallbackController

  def status(conn, _params) do
    user = conn.assigns.current_user

    with :ok <- authorize(user, :system, :read) do
      json(conn, SystemStatus.get_all())
    end
  end

  @doc """
  Returns system metrics (CPU temp, CPU%, RAM%, Disk%) for topbar display.
  No authorization required for basic metrics.
  """
  def metrics(conn, _params) do
    metrics = try do
      TProNVR.SystemMonitor.get_metrics()
    rescue
      _ -> %{cpu_temp: nil, cpu_usage: 0, ram_usage: 0, disk_usage: 0}
    catch
      _, _ -> %{cpu_temp: nil, cpu_usage: 0, ram_usage: 0, disk_usage: 0}
    end

    json(conn, metrics)
  end
end
