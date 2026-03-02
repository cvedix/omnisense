defmodule TProNVRWeb.SystemMetricsHook do
  @moduledoc """
  LiveView hook to subscribe to system metrics and update assigns.
  
  This hook subscribes to system metrics PubSub and provides initial metrics.
  LiveViews using this hook should include `use TProNVRWeb.SystemMetricsHandler`
  to handle the incoming messages, or implement their own handle_info.
  """
  
  import Phoenix.LiveView
  import Phoenix.Component
  
  def on_mount(:default, _params, _session, socket) do
    socket = if connected?(socket) do
      TProNVR.SystemMonitor.subscribe()
      
      # Attach a hook to handle system_metrics messages
      attach_hook(socket, :system_metrics_handler, :handle_info, fn
        {:system_metrics, metrics}, sock ->
          {:halt, assign(sock, :system_metrics, metrics)}
        _msg, sock ->
          {:cont, sock}
      end)
    else
      socket
    end
    
    # Get initial metrics
    metrics = try do
      TProNVR.SystemMonitor.get_metrics()
    rescue
      _ -> %{cpu_temp: nil, cpu_usage: 0, ram_usage: 0, disk_usage: 0}
    catch
      _, _ -> %{cpu_temp: nil, cpu_usage: 0, ram_usage: 0, disk_usage: 0}
    end
    
    {:cont, assign(socket, :system_metrics, metrics)}
  end
end
