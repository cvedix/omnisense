defmodule TProNVR.CommanderSync.RTMPWorker do
  use GenServer
  require Logger

  @config_path "/home/cvedix/Documents/Github/omnimedia/release/linux/Debug/config.ini"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def trigger_sync do
    GenServer.cast(__MODULE__, :trigger_sync)
  end

  @impl true
  def init(_) do
    Process.flag(:trap_exit, true)
    schedule_tick(5_000)
    {:ok, %{ports: %{}}} # %{device_id => port_reference}
  end

  @impl true
  def handle_info(:tick, state) do
    state = ensure_rtmp_sync(state)
    schedule_tick(10_000)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:trigger_sync, state) do
    log_message("SYNC", "Nhận lệnh đồng bộ RTMP từ giao diện...")
    state = ensure_rtmp_sync(state)
    {:noreply, state}
  end

  # Handle Port exits so we can successfully spin them up again next tick
  @impl true
  def handle_info({port, {:exit_status, status}}, state) do
    device_id = find_device_by_port(state.ports, port)
    
    if device_id do
      msg = if status == 0, do: "Khép luồng an toàn (Clean exit)", else: "Lỗi thoát đột ngột (Code #{status})"
      log_message("WARN", "RTMP Stream cho Camera '#{device_id}' bị ngắt: #{msg}. Sẽ thử lại ở chu kỳ sau.")
      ports = Map.delete(state.ports, device_id)
      {:noreply, %{state | ports: ports}}
    else
      {:noreply, state}
    end
  end

  # Discard verbose stdout/stderr from FFmpeg to avoid overloading the mailbox
  @impl true
  def handle_info({_port, {:data, _output}}, state) do
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:EXIT, _port, _reason}, state) do
    {:noreply, state}
  end

  defp schedule_tick(ms) do
    Process.send_after(self(), :tick, ms)
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

  defp ensure_rtmp_sync(state) do
    rtmp_enable = read_config("rtmpEnable")
    rtmp_server = read_config("rtmpServer")

    if rtmp_enable == "1" and rtmp_server != "" do
      active_devices = TProNVR.Devices.list() 
                       |> Enum.filter(&(&1.state != :stopped and TProNVR.Model.Device.effective_rtsp_url(&1, :main) != nil))
      
      active_ids = Enum.map(active_devices, &(&1.id))
      
      # 1. Stop streams for deleted/stopped devices
      ports = Enum.reduce(state.ports, state.ports, fn {id, port}, acc ->
        if id not in active_ids do
          log_message("INFO", "Camera '#{id}' offline/bị xóa. Ngừng đẩy luồng RTMP.")
          stop_port(port)
          Map.delete(acc, id)
        else
          acc
        end
      end)

      # 2. Start streams for newly active devices
      ports = Enum.reduce(active_devices, ports, fn device, acc ->
        if not Map.has_key?(acc, device.id) do
          rtsp_uri = TProNVR.Model.Device.effective_rtsp_url(device, :main)
          # Traccar RTMP path convention
          rtmp_url = if String.ends_with?(rtmp_server, "/"), do: "#{rtmp_server}#{device.id}", else: "#{rtmp_server}/#{device.id}"
          
          log_message("SYNC", "Bơm luồng RTSP (Camera '#{device.id}') -> RTMP (Central) ...")
          
          # We use TCP transport for RTSP to fix UDP packet drops, copy video codec for near-zero 
          # CPU usage, and re-encode audio to aac (RTMP FLV strict requirement)
          args = [
            "-hide_banner", "-loglevel", "error",
            "-rtsp_transport", "tcp",
            "-i", rtsp_uri,
            "-c:v", "copy",
            "-c:a", "aac", "-ar", "44100", "-b:a", "128k",
            "-f", "flv", rtmp_url
          ]

          case System.find_executable("ffmpeg") do
            nil ->
              log_message("ERROR", "FFmpeg binary không tồn tại trên hệ thống!")
              acc
            ffmpeg_path ->
              port = Port.open({:spawn_executable, ffmpeg_path}, [:binary, :exit_status, args: args])
              Map.put(acc, device.id, port)
          end
        else
          acc
        end
      end)

      %{state | ports: ports}
    else
      # If feature disabled, terminate ALL running FFmpeg relay channels
      if map_size(state.ports) > 0 do
        log_message("INFO", "Tính năng RTMP Relay đã bị tắt. Đang dọn dẹp #{map_size(state.ports)} kênh...")
        Enum.each(state.ports, fn {_, port} -> stop_port(port) end)
      end
      %{state | ports: %{}}
    end
  end

  defp stop_port(port) do
    if is_port(port) do
      try do
        Port.close(port)
      rescue
        _ -> :ok
      end
    end
  end

  defp find_device_by_port(ports_map, target_port) do
    Enum.find_value(ports_map, fn {device_id, port} ->
      if port == target_port, do: device_id, else: nil
    end)
  end

  defp log_message(level, msg) do
    timestamp = DateTime.utc_now() |> DateTime.add(7, :hour) |> Calendar.strftime("%H:%M:%S")
    formatted = "[#{timestamp}] [#{level}] #{msg}"
    Logger.info("RTMPWorker: #{formatted}")
    Phoenix.PubSub.broadcast(TProNVR.PubSub, "commander_sync_logs", {:sync_log, :rtmp, formatted})
  end
end
