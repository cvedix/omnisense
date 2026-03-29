defmodule TProNVR.CommanderSync.Worker do
  use GenServer
  require Logger

  @config_path "/home/cvedix/Documents/Github/omnimedia/release/linux/Debug/config.ini"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end
  
  def trigger_sync do
    GenServer.cast(__MODULE__, :force_sync)
  end

  @impl true
  def init(_) do
    ref = schedule_sync(10_000) # Initial delay before starting the loop
    {:ok, %{last_sync: nil, timer_ref: ref}}
  end

  @impl true
  def handle_cast(:force_sync, state) do
    # Cancel any pending timer to avoid overlapping sync cycles
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    log_message("RECONNECT", "Cấu hình mới được lưu. Đang kết nối lại tới Commander ngay lập tức...")
    do_sync()

    # Reschedule with the (potentially new) interval from fresh config
    interval = get_interval()
    ref = schedule_sync(String.to_integer(interval) * 1000)
    {:noreply, %{state | timer_ref: ref, last_sync: DateTime.utc_now()}}
  end

  @impl true
  def handle_info(:sync, state) do
    do_sync()
    
    interval = get_interval()
    ref = schedule_sync(String.to_integer(interval) * 1000)
    
    {:noreply, %{state | timer_ref: ref, last_sync: DateTime.utc_now()}}
  end

  defp schedule_sync(ms) do
    Process.send_after(self(), :sync, ms)
  end

  defp get_interval do
    case read_config("interval") do
      "" -> "60"
      val -> val
    end
  end

  defp read_config(key) do
    if File.exists?(@config_path) do
      content = File.read!(@config_path)
      case Regex.run(~r/^[ \t]*#{key}[ \t]*=[ \t]*(.*)$/m, content) do
        [_, val] -> String.trim(val)
        _ -> ""
      end
    else
      ""
    end
  end

  defp do_sync do
    if read_config("enable") == "1" do
      server = read_config("server")
      device_id = read_config("deviceId")
      device_type = read_config("deviceType")
      device_type = if device_type == "", do: "omnisense", else: device_type
      lat = read_config("latitude")
      lon = read_config("longitude")

      if server != "" and device_id != "" do
        metrics = TProNVR.SystemMonitor.get_metrics()
        
        lat_val = case Float.parse(lat) do
          {f, _} -> f
          :error -> 0.0
        end

        lon_val = case Float.parse(lon) do
          {f, _} -> f
          :error -> 0.0
        end

        timestamp_iso = DateTime.utc_now() |> DateTime.to_iso8601()
        
        # Calculate NVR application specific statuses
        total_cameras = TProNVR.Devices.list() |> length()

        payload = %{
          "device_id" => device_id,
          "location" => %{
            "timestamp" => timestamp_iso,
            "coords" => %{
              "latitude" => lat_val,
              "longitude" => lon_val,
              "speed" => 0,
              "heading" => 0,
              "accuracy" => 0,
              "altitude" => 0
            }
          },
          "deviceType" => device_type,
          "hostname" => "omnisense-native-node",
          "serverVersion" => "omnisense-native-1.0",
          "cpuUsage" => metrics.cpu_usage || 0,
          "cpuTemp" => metrics.cpu_temp || 0,
          "memUsage" => metrics.ram_usage || 0,
          "diskUsage" => metrics.disk_usage || 0,
          "totalCameras" => total_cameras,
          "activeStreams" => total_cameras,
          "status" => "online"
        }

        url = if String.contains?(server, "?") do
          "#{server}&id=#{URI.encode_www_form(device_id)}"
        else
          "#{server}/?id=#{URI.encode_www_form(device_id)}"
        end

        log_message("SYNC", "Sending telemetry payload (Cameras: #{total_cameras}) to Commander: HTTP POST #{server}")
        
        # We must use a separate Task to avoid blocking the GenServer loop on HTTP timeouts
        Task.start(fn ->
          try do
            case Req.post(url, json: payload, connect_options: [timeout: 5000]) do
              {:ok, %{status: status}} ->
                if status == 200 do
                  log_message("SUCCESS", "HTTP 200 OK - Traccar received NVR telemetry data.")
                else
                  log_message("WARN", "HTTP #{status} received from Commander node.")
                end
              {:error, reason} ->
                log_message("ERROR", "Connection to Commander failed: #{inspect(reason)}")
            end
          rescue
            e -> log_message("FATAL", "Exception during HTTP transmit: #{inspect(e)}")
          end
        end)
      else
        log_message("WARN", "Telemetry bypassed. Endpoint Address or Device ID omitted in configuration.")
      end
    end
  end

  defp log_message(level, msg) do
    timestamp = DateTime.utc_now() |> DateTime.add(7, :hour) |> Calendar.strftime("%H:%M:%S")
    formatted = "[#{timestamp}] [#{level}] #{msg}"
    Logger.info("CommanderSync: #{formatted}")
    Phoenix.PubSub.broadcast(TProNVR.PubSub, "commander_sync_logs", {:sync_log, formatted})
  end
end
