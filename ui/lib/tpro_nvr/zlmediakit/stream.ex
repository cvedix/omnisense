defmodule TProNVR.ZLMediaKit.Stream do
  @moduledoc """
  Always-on RTSP push to ZLMediaKit for live streaming and AI analytics.
  
  Main stream is pushed by GStreamer's rtspclientsink (in Pipeline).
  Sub stream is pushed by a dedicated FFmpeg process managed here.
  
  ## Architecture
  
  ```
  main_stream: GStreamer rtspclientsink → ZLMediaKit → HLS/RTSP
  sub_stream:  FFmpeg (this module)     → ZLMediaKit → HLS/RTSP
  ```
  """
  
  use GenServer
  require Logger
  
  @registry TProNVR.ZLMediaKit.StreamRegistry
  
  defstruct [
    :device_id,
    :rtsp_url,
    :stream_type,
    :ffmpeg_port,
    :stream_key,
    :status,
    retry_count: 0
  ]
  
  @max_retries 10
  @base_retry_ms 5_000
  @max_retry_ms 60_000
  
  # ============================================================
  # Public API
  # ============================================================
  
  @doc """
  Start pushing a stream to ZLMediaKit on-demand.
  
  ## Parameters
    - device_id: The device UUID
    - rtsp_url: The camera's RTSP URL (with credentials)
    - stream_type: :main or :sub (default: :main)
  """
  def start_push(device_id, rtsp_url, stream_type \\ :main) do
    registry_key = registry_key(device_id, stream_type)
    
    case lookup(registry_key) do
      {:ok, _pid} ->
        Logger.info("[ZLMediaKit] Stream already pushing for #{registry_key}")
        {:ok, :already_started}
      
      :error ->
        DynamicSupervisor.start_child(
          TProNVR.ZLMediaKit.StreamSupervisor,
          {__MODULE__, device_id: device_id, rtsp_url: rtsp_url, stream_type: stream_type}
        )
    end
  end
  
  @doc """
  Stop pushing a stream to ZLMediaKit.
  """
  def stop_push(device_id, stream_type \\ :main) do
    registry_key = registry_key(device_id, stream_type)
    
    case lookup(registry_key) do
      {:ok, pid} ->
        GenServer.stop(pid, :normal)
        :ok
      
      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  Stop all streams (main + sub) for a device.
  """
  def stop_all(device_id) do
    stop_push(device_id, :main)
    stop_push(device_id, :sub)
    :ok
  end
  
  @doc """
  Get the ZLMediaKit HLS URL for a device.
  """
  def get_hls_url(device_id, stream_type \\ :main) do
    host = zlm_host()
    http_port = zlm_http_port()
    stream_key = stream_key(device_id, stream_type)
    "http://#{host}:#{http_port}/live/#{stream_key}/hls.m3u8"
  end

  @doc """
  Check if a stream is currently being pushed.
  """
  def pushing?(device_id, stream_type \\ :main) do
    case lookup(registry_key(device_id, stream_type)) do
      {:ok, _} -> true
      :error -> false
    end
  end
  
  @doc """
  List all active stream pushes.
  """
  def list_active do
    Registry.select(@registry, [{{:"$1", :"$2", :"$3"}, [], [%{key: :"$1", pid: :"$2"}]}])
  end
  
  def start_link(opts) do
    device_id = Keyword.fetch!(opts, :device_id)
    stream_type = Keyword.get(opts, :stream_type, :main)
    registry_key = registry_key(device_id, stream_type)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(registry_key))
  end
  
  def child_spec(opts) do
    device_id = Keyword.fetch!(opts, :device_id)
    stream_type = Keyword.get(opts, :stream_type, :main)
    %{
      id: {__MODULE__, device_id, stream_type},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end
  
  # ============================================================
  # GenServer Callbacks
  # ============================================================
  
  @impl true
  def init(opts) do
    device_id = Keyword.fetch!(opts, :device_id)
    rtsp_url = Keyword.fetch!(opts, :rtsp_url)
    stream_type = Keyword.get(opts, :stream_type, :main)
    
    Logger.info("[ZLMediaKit] Starting #{stream_type} stream push for device: #{device_id}")
    
    state = %__MODULE__{
      device_id: device_id,
      rtsp_url: rtsp_url,
      stream_type: stream_type,
      stream_key: stream_key(device_id, stream_type),
      ffmpeg_port: nil,
      status: :starting
    }
    
    send(self(), :start_ffmpeg)
    {:ok, state}
  end
  
  @impl true
  def handle_info(:start_ffmpeg, state) do
    case start_ffmpeg_push(state) do
      {:ok, port} ->
        Logger.info("[ZLMediaKit] FFmpeg push started for #{state.stream_key}")
        {:noreply, %{state | ffmpeg_port: port, status: :running, retry_count: 0}}
      
      {:error, reason} ->
        new_count = state.retry_count + 1
        if new_count >= @max_retries do
          Logger.error("[ZLMediaKit] Max retries (#{@max_retries}) reached for #{state.stream_key}, giving up")
          {:stop, :normal, %{state | status: :failed}}
        else
          delay = retry_delay(new_count)
          Logger.error("[ZLMediaKit] Failed to start FFmpeg push (attempt #{new_count}): #{inspect(reason)}, retry in #{div(delay, 1000)}s")
          Process.send_after(self(), :start_ffmpeg, delay)
          {:noreply, %{state | status: :error, retry_count: new_count}}
        end
    end
  end
  
  @impl true
  def handle_info({_port, {:data, data}}, state) do
    data_str = String.trim(to_string(data))
    if data_str != "" do
      Logger.debug("[ZLMediaKit] FFmpeg #{state.stream_key}: #{data_str}")
    end
    {:noreply, state}
  end
  
  @impl true
  def handle_info({_port, {:exit_status, status}}, state) do
    new_count = state.retry_count + 1
    if new_count >= @max_retries do
      Logger.error("[ZLMediaKit] FFmpeg #{state.stream_key} exited (status #{status}), max retries reached, giving up")
      {:stop, :normal, %{state | status: :failed, ffmpeg_port: nil}}
    else
      delay = retry_delay(new_count)
      Logger.warning("[ZLMediaKit] FFmpeg exited with status #{status} for #{state.stream_key} (attempt #{new_count}/#{@max_retries}), retry in #{div(delay, 1000)}s")
      Process.send_after(self(), :start_ffmpeg, delay)
      {:noreply, %{state | status: :stopped, ffmpeg_port: nil, retry_count: new_count}}
    end
  end
  
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  @impl true
  def terminate(_reason, state) do
    Logger.info("[ZLMediaKit] Stopping #{state.stream_type} stream push for #{state.device_id}")
    stop_ffmpeg(state)
    :ok
  end
  
  # ============================================================
  # Private Functions
  # ============================================================
  
  # Exponential backoff: 5s, 10s, 20s, 40s, 60s (capped)
  defp retry_delay(attempt) do
    delay = @base_retry_ms * :math.pow(2, attempt - 1) |> round()
    min(delay, @max_retry_ms)
  end
  
  defp start_ffmpeg_push(state) do
    zlm_url = "rtsp://#{zlm_host()}:#{zlm_port()}/live/#{state.stream_key}"
    
    ffmpeg_cmd = [
      "ffmpeg -hide_banner -loglevel error",
      "-rtsp_transport tcp",
      "-i \"#{state.rtsp_url}\"",
      "-c:v copy -an",
      "-f rtsp",
      "\"#{zlm_url}\""
    ] |> Enum.join(" ")
    
    Logger.info("[ZLMediaKit] Starting FFmpeg push: #{hide_credentials(ffmpeg_cmd)}")
    
    try do
      port = Port.open(
        {:spawn, "bash -c '#{ffmpeg_cmd}'"},
        [:binary, :exit_status, :stderr_to_stdout]
      )
      {:ok, port}
    rescue
      e ->
        Logger.error("[ZLMediaKit] Failed to start FFmpeg: #{inspect(e)}")
        {:error, e}
    end
  end
  
  defp stop_ffmpeg(state) do
    if state.ffmpeg_port do
      try do
        Port.close(state.ffmpeg_port)
      catch
        :error, :badarg -> :ok  # Port already closed/exited
      end
    end
    System.cmd("pkill", ["-f", "ffmpeg.*#{state.stream_key}"], stderr_to_stdout: true)
    :ok
  end
  
  defp hide_credentials(cmd) do
    Regex.replace(~r/:([^:@]+)@/, cmd, ":****@")
  end

  defp stream_key(device_id, :main), do: device_id
  defp stream_key(device_id, :sub), do: "#{device_id}_sub"

  defp registry_key(device_id, stream_type), do: "#{device_id}_#{stream_type}"
  
  defp lookup(registry_key) do
    case Registry.lookup(@registry, registry_key) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end
  
  defp via_tuple(registry_key) do
    {:via, Registry, {@registry, registry_key}}
  end
  
  defp zlm_host do
    Application.get_env(:tpro_nvr, :zlmediakit, [])[:host] || "127.0.0.1"
  end
  
  defp zlm_port do
    Application.get_env(:tpro_nvr, :zlmediakit, [])[:rtsp_port] || 8554
  end

  defp zlm_http_port do
    Application.get_env(:tpro_nvr, :zlmediakit, [])[:http_port] || 8080
  end
end
