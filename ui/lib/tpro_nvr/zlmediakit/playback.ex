defmodule TProNVR.ZLMediaKit.Playback do
  @moduledoc """
  ZLMediaKit-based playback for recorded videos.
  
  Instead of generating HLS directly, this module pushes the recorded video
  to ZLMediaKit via RTSP. ZLMediaKit handles transcoding (H265→H264) and
  HLS generation, making it browser-compatible.
  
  ## Architecture
  
  ```
  Recording (MP4 H265)
      ↓
  GStreamer push RTSP → ZLMediaKit (port 8554)
      ↓
  ZLMediaKit auto-transcode → HLS (port 8080)
      ↓
  Browser request HLS from ZLMediaKit
  ```
  """

  use GenServer

  require Logger

  alias TProNVR.Recordings

  @call_timeout :timer.seconds(60)
  @zlm_host "127.0.0.1"
  @zlm_rtsp_port 8554
  @zlm_http_port 8080

  defstruct [
    :device,
    :start_date,
    :stream,
    :stream_id,
    :port,
    :recordings,
    :current_index,
    :ready?
  ]

  @type t :: %__MODULE__{
    device: map(),
    start_date: DateTime.t(),
    stream: atom(),
    stream_id: String.t(),
    port: port() | nil,
    recordings: list(),
    current_index: integer(),
    ready?: boolean()
  }

  # Public API

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @spec start(Keyword.t()) :: {:ok, pid(), String.t()} | {:error, term()}
  def start(opts) do
    # Generate unique stream ID for this playback session
    stream_id = generate_stream_id()
    opts = Keyword.put(opts, :stream_id, stream_id)
    
    case GenServer.start(__MODULE__, opts) do
      {:ok, pid} -> {:ok, pid, stream_id}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec start_streaming(pid() | atom()) :: {:ok, String.t()} | {:error, term()}
  def start_streaming(pipeline) do
    GenServer.call(pipeline, :start_streaming, @call_timeout)
  end

  @spec stop_streaming(pid() | atom()) :: :ok
  def stop_streaming(pipeline) do
    GenServer.call(pipeline, :stop_streaming)
  end

  @doc """
  Get the ZLMediaKit HLS URL for playback.
  """
  @spec get_hls_url(String.t(), String.t()) :: String.t()
  def get_hls_url(_device_id, stream_id) do
    "http://#{zlm_host()}:#{zlm_http_port()}/live/#{stream_id}/hls.m3u8"
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    device = opts[:device]
    stream_id = opts[:stream_id]
    Process.set_label({:zlm_playback, device.id, stream_id})
    Logger.info("[ZLMPlayback] Start for device: #{device.id}, stream_id: #{stream_id}")

    state = %__MODULE__{
      device: device,
      start_date: opts[:start_date],
      stream: opts[:stream],
      stream_id: stream_id,
      port: nil,
      recordings: [],
      current_index: 0,
      ready?: false
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:start_streaming, _from, state) do
    # Get recordings for this device starting from start_date
    recordings = get_recordings(state.device, state.stream, state.start_date)

    case recordings do
      [] ->
        Logger.warning("[ZLMPlayback] No recordings found")
        {:reply, {:error, :no_recordings}, state}

      recordings ->
        # Get file paths for all recordings
        file_paths = recordings
          |> Enum.map(&Recordings.recording_path(state.device, state.stream, &1))
          |> Enum.filter(&File.exists?/1)
        
        if Enum.empty?(file_paths) do
          {:reply, {:error, :no_valid_recordings}, state}
        else
          rtsp_url = build_rtsp_url(state.device.id, state.stream_id)
          
          case start_ffmpeg_push(file_paths, rtsp_url, state.stream_id) do
            {:ok, port} ->
              hls_url = get_hls_url(state.device.id, state.stream_id)
              Logger.info("[ZLMPlayback] Started FFmpeg push to ZLMediaKit, HLS at: #{hls_url}")
              
              state = %{state | 
                port: port, 
                recordings: recordings, 
                current_index: 0,
                ready?: true
              }
              {:reply, {:ok, hls_url}, state}

            {:error, reason} ->
              {:reply, {:error, reason}, state}
          end
        end
    end
  end

  @impl true
  def handle_call(:stop_streaming, _from, state) do
    cleanup(state)
    {:reply, :ok, %{state | port: nil, ready?: false}}
  end

  @impl true
  def handle_info({_port, {:data, data}}, state) do
    data_str = String.trim(to_string(data))
    if data_str != "" do
      Logger.debug("[ZLMPlayback] GStreamer: #{data_str}")
    end
    {:noreply, state}
  end

  @impl true
  def handle_info({_port, {:exit_status, status}}, state) do
    if status == 0 do
      Logger.info("[ZLMPlayback] GStreamer completed successfully")
    else
      Logger.warning("[ZLMPlayback] GStreamer exited with status: #{status}")
    end
    {:noreply, %{state | port: nil}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    cleanup(state)
    :ok
  end

  # Private functions

  defp get_recordings(device, stream, start_date) do
    # Default to next 2 hours of recordings
    end_date = DateTime.add(start_date, 7200, :second)
    Recordings.get_recordings_between(device.id, stream, start_date, end_date)
  end

  defp build_rtsp_url(_device_id, stream_id) do
    "rtsp://#{zlm_host()}:#{zlm_rtsp_port()}/live/#{stream_id}"
  end

  defp start_ffmpeg_push(file_paths, rtsp_url, stream_id) do
    # Create concat playlist file
    concat_file = "/tmp/zlm_concat_#{stream_id}.txt"
    
    playlist_content = file_paths
      |> Enum.map(fn path -> "file '#{path}'" end)
      |> Enum.join("\n")
    
    File.write!(concat_file, playlist_content)
    
    Logger.info("[ZLMPlayback] Created concat file with #{length(file_paths)} recordings")
    
    # FFmpeg command with concat demuxer to push continuous stream
    # -f concat: use concat demuxer to read multiple files
    # -safe 0: allow absolute paths
    # -c:v copy: no re-encoding (just remux H265)
    # -an: no audio
    # -f rtsp: output to RTSP
    ffmpeg_cmd = [
      "ffmpeg -hide_banner -loglevel error",
      "-f concat -safe 0",
      "-i \"#{concat_file}\"",
      "-c:v copy -an",
      "-f rtsp -rtsp_transport tcp",
      "\"#{rtsp_url}\""
    ] |> Enum.join(" ")
    
    Logger.info("[ZLMPlayback] Starting FFmpeg push: #{ffmpeg_cmd}")

    try do
      port = Port.open(
        {:spawn, "bash -c '#{ffmpeg_cmd}'"},
        [:binary, :exit_status, :stderr_to_stdout]
      )
      
      # Wait for ZLMediaKit to register the stream and generate HLS
      Process.sleep(3000)
      
      {:ok, port}
    rescue
      e ->
        Logger.error("[ZLMPlayback] Failed to start FFmpeg: #{inspect(e)}")
        {:error, e}
    end
  end

  defp cleanup(state) do
    if state.port do
      try do
        Port.close(state.port)
      catch
        _, _ -> :ok
      end
    end
    :ok
  end

  defp generate_stream_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  defp zlm_host do
    Application.get_env(:tpro_nvr, :zlmediakit, [])[:host] || @zlm_host
  end

  defp zlm_rtsp_port do
    Application.get_env(:tpro_nvr, :zlmediakit, [])[:rtsp_port] || @zlm_rtsp_port
  end

  defp zlm_http_port do
    Application.get_env(:tpro_nvr, :zlmediakit, [])[:http_port] || @zlm_http_port
  end
end
