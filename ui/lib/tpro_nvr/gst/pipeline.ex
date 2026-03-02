defmodule TProNVR.Gst.Pipeline do
  @moduledoc """
  Hybrid FFmpeg-GStreamer streaming pipeline for TProNVR.
  
  Uses FFmpeg as RTSP source for better camera compatibility (especially Dahua),
  and GStreamer for hardware-accelerated encoding/muxing.
  
  Architecture:
  ```
  Camera → FFmpeg (RTSP) → pipe → GStreamer (MPP decode/encode)
       ↓                                     ↓
  ZLMediaKit (RTSP push) ←───────────────────┘
       ↓
  HLS/FLV/WebRTC → Browser
  ```
  
  Provides:
  - RTSP input via FFmpeg (compatible with more cameras)
  - RTSP push to ZLMediaKit (for HLS/FLV/WebRTC streaming)
  - MP4 recording via splitmuxsink (H.265 for storage efficiency)
  
  ## Streaming (via ZLMediaKit)
  
  Live streaming is handled by ZLMediaKit which receives RTSP push from GStreamer.
  ZLMediaKit automatically generates HLS, HTTP-FLV, and WebRTC outputs.
  
  ## Recording
  
  Recording is enabled by default and uses GStreamer's `splitmuxsink` to create
  segmented MP4 files. Each segment is approximately 60 seconds by default.
  
  ## Usage
  
      # Start pipeline with recording
      {:ok, pid} = TProNVR.Gst.Pipeline.start_link(device)
      
      # Control recording
      TProNVR.Gst.Pipeline.start_recording(device.id)
      TProNVR.Gst.Pipeline.stop_recording(device.id)
      TProNVR.Gst.Pipeline.is_recording?(device.id)
  """

  use GenServer
  require Logger

  alias TProNVR.Model.Device
  alias TProNVR.Gst.HardwareCaps

  # Default segment duration: 60 seconds in nanoseconds
  @default_segment_duration 60_000_000_000
  @hls_dir Application.compile_env(:tpro_nvr, :hls_directory, "/tmp/hls")

  defstruct [
    :device_id,
    :device,
    :rtsp_url,
    :ffmpeg_port,      # Port for FFmpeg RTSP source process
    :gst_port,         # Port for GStreamer encode/mux process  
    :sub_stream_port,  # Port for GStreamer sub_stream push to ZLMediaKit
    :pipeline_pid,     # OS PID for the combined pipeline script
    :webrtc_peers,
    :hls_path,
    :recording_path,
    :recording_enabled,
    :segment_duration,
    :segment_index,
    :status,
    :hardware_caps,
    :stream_codec,  # :h264 or :h265
    :stream_resolution,  # {width, height} or nil
    sub_stream_retries: 0,  # counter for sub-stream push retry attempts
    pipeline_mode: :hybrid  # :hybrid (FFmpeg+GStreamer) or :pure_gst (GStreamer rtspsrc)
  ]

  # ============================================================
  # Public API
  # ============================================================

  def start_link(%Device{} = device) do
    GenServer.start_link(__MODULE__, device, name: via_tuple(device.id))
  end

  def stop(device_id) do
    GenServer.stop(via_tuple(device_id), :normal)
  end

  @doc """
  Get the HLS playlist URL for a device (via ZLMediaKit).
  """
  def get_hls_url(device_id) do
    TProNVR.ZLMediaKit.Stream.get_hls_url(device_id)
  end

  @doc """
  Start recording for a device.
  """
  def start_recording(device_id) do
    GenServer.call(via_tuple(device_id), :start_recording)
  end

  @doc """
  Stop recording for a device.
  """
  def stop_recording(device_id) do
    GenServer.call(via_tuple(device_id), :stop_recording)
  end

  @doc """
  Check if recording is active for a device.
  """
  def is_recording?(device_id) do
    GenServer.call(via_tuple(device_id), :is_recording)
  end

  @doc """
  Get the current recording path for a device.
  """
  def get_recording_path(device_id) do
    GenServer.call(via_tuple(device_id), :get_recording_path)
  end

  def get_webrtc_offer(device_id, peer_id) do
    GenServer.call(via_tuple(device_id), {:webrtc_offer, peer_id})
  end

  def handle_webrtc_answer(device_id, peer_id, answer_sdp) do
    GenServer.cast(via_tuple(device_id), {:webrtc_answer, peer_id, answer_sdp})
  end

  def handle_ice_candidate(device_id, peer_id, candidate) do
    GenServer.cast(via_tuple(device_id), {:ice_candidate, peer_id, candidate})
  end

  @doc """
  Get pipeline status.
  """
  def status(device_id) do
    GenServer.call(via_tuple(device_id), :status)
  end

  @doc """
  Capture a live snapshot from the stream.
  Returns {:ok, jpeg_binary} on success.
  """
  def capture_snapshot(device_id) do
    GenServer.call(via_tuple(device_id), :capture_snapshot, 10_000)
  end

  # ============================================================
  # GenServer Callbacks
  # ============================================================

  @impl true
  def init(%Device{} = device) do
    Logger.info("[GstPipeline] Starting for device: #{device.id}")

    # Detect hardware capabilities
    hw_caps = HardwareCaps.detect()
    Logger.info("[GstPipeline] Hardware platform: #{hw_caps[:platform]}, decoder: #{hw_caps[:decoder]}")

    rtsp_url = build_rtsp_url(device)
    # Controller expects HLS files in `/hls/{device_id}/live/` subdirectory
    hls_path = Path.join([@hls_dir, device.id, "live"])
    recording_path = build_recording_path(device)

    # Ensure directories exist
    File.mkdir_p!(hls_path)
    File.mkdir_p!(recording_path)

    # Probe stream codec (H.264 or H.265)
    stream_codec = probe_stream_codec(rtsp_url)
    Logger.info("[GstPipeline] Detected stream codec: #{stream_codec} for #{device.id}")

    # Probe stream resolution for dynamic bitrate
    stream_resolution = probe_stream_resolution(rtsp_url)
    Logger.info("[GstPipeline] Detected resolution: #{inspect(stream_resolution)} for #{device.id}")

    # Cloud RTSP streams (non-local) don't need FFmpeg hybrid — use pure GStreamer
    initial_mode = if cloud_rtsp_url?(rtsp_url), do: :pure_gst, else: :hybrid
    if initial_mode == :pure_gst do
      Logger.info("[GstPipeline] Cloud URL detected for #{device.id}, using pure_gst mode (no FFmpeg)")
    end

    state = %__MODULE__{
      device_id: device.id,
      device: device,
      rtsp_url: rtsp_url,
      hls_path: hls_path,
      recording_path: recording_path,
      recording_enabled: true,
      segment_duration: @default_segment_duration,
      segment_index: 0,
      webrtc_peers: %{},
      ffmpeg_port: nil,
      gst_port: nil,
      pipeline_pid: nil,
      status: :starting,
      hardware_caps: hw_caps,
      stream_codec: stream_codec,
      stream_resolution: stream_resolution,
      pipeline_mode: initial_mode
    }

    # Start the GStreamer pipeline
    send(self(), :start_pipeline)

    {:ok, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status_info = %{
      status: state.status,
      device_id: state.device_id,
      recording_enabled: state.recording_enabled,
      recording_path: state.recording_path,
      hls_path: state.hls_path
    }
    {:reply, status_info, state}
  end

  def handle_call(:start_recording, _from, %{recording_enabled: true} = state) do
    {:reply, {:ok, :already_recording}, state}
  end

  def handle_call(:start_recording, _from, state) do
    Logger.info("[GstPipeline] Starting recording for #{state.device_id}")
    # Restart pipeline with recording enabled
    stop_hybrid_pipeline(state)
    new_state = %{state | recording_enabled: true}
    send(self(), :start_pipeline)
    {:reply, :ok, new_state}
  end

  def handle_call(:stop_recording, _from, %{recording_enabled: false} = state) do
    {:reply, {:ok, :already_stopped}, state}
  end

  def handle_call(:stop_recording, _from, state) do
    Logger.info("[GstPipeline] Stopping recording for #{state.device_id}")
    # Restart pipeline without recording
    stop_hybrid_pipeline(state)
    new_state = %{state | recording_enabled: false}
    send(self(), :start_pipeline)
    {:reply, :ok, new_state}
  end

  def handle_call(:is_recording, _from, state) do
    {:reply, state.recording_enabled, state}
  end

  def handle_call(:get_recording_path, _from, state) do
    {:reply, state.recording_path, state}
  end

  def handle_call(:capture_snapshot, _from, state) do
    # Capture snapshot using GStreamer with HW acceleration
    snapshot_path = Path.join(System.tmp_dir!(), "snapshot_#{state.device_id}_#{System.os_time(:millisecond)}.jpg")
    
    # Use ZLMediaKit RTSP as source (already available, avoids extra camera connection)
    zlm_url = "rtsp://#{zlm_host()}:#{zlm_port()}/live/#{state.device_id}"
    
    # HW-accelerated JPEG encode on Rockchip, software fallback elsewhere
    convert = if state.hardware_caps[:platform] == :rockchip, do: "", else: "videoconvert !"
    jpeg_enc = if state.hardware_caps[:platform] == :rockchip, do: "mppjpegenc", else: "jpegenc quality=85"
    
    snapshot_cmd = """
    gst-launch-1.0 -q \
      rtspsrc location="#{zlm_url}" latency=0 protocols=tcp num-buffers=1 \
      ! decodebin ! #{convert} #{jpeg_enc} \
      ! filesink location="#{snapshot_path}"
    """ |> String.replace("\n", " ") |> String.trim()
    
    case System.cmd("bash", ["-c", snapshot_cmd], stderr_to_stdout: true) do
      {_, 0} ->
        case File.read(snapshot_path) do
          {:ok, jpeg_data} ->
            File.rm(snapshot_path)
            {:reply, {:ok, jpeg_data}, state}
          {:error, reason} ->
            {:reply, {:error, {:file_read, reason}}, state}
        end
      {output, _code} ->
        Logger.warning("[GstPipeline] Snapshot failed: #{output}")
        {:reply, {:error, :capture_failed}, state}
    end
  end

  def handle_call({:webrtc_offer, peer_id}, _from, state) do
    offer = create_webrtc_offer(state.device_id, peer_id)
    {:reply, {:ok, offer}, put_in(state.webrtc_peers[peer_id], %{status: :offer_sent})}
  end

  @impl true
  def handle_cast({:webrtc_answer, peer_id, answer_sdp}, state) do
    handle_peer_answer(state.device_id, peer_id, answer_sdp)
    {:noreply, put_in(state.webrtc_peers[peer_id][:status], :connected)}
  end

  def handle_cast({:ice_candidate, peer_id, candidate}, state) do
    add_ice_candidate(state.device_id, peer_id, candidate)
    {:noreply, state}
  end

  @impl true
  def handle_info(:start_pipeline, state) do
    case start_hybrid_pipeline(state) do
      {:ok, pid} ->
        Logger.info("[GstPipeline] Hybrid pipeline started for #{state.device_id}, recording: #{state.recording_enabled}")
        # Start MSE streaming watcher
        TProNVR.LiveStream.Supervisor.start_streaming(state.device_id)
        # Start sub_stream GStreamer push to ZLMediaKit (if device has sub_stream)
        state = start_sub_stream_push(state)
        {:noreply, %{state | status: :running, pipeline_pid: pid, gst_port: pid}}

      {:error, reason} ->
        Logger.error("[GstPipeline] Failed to start hybrid pipeline: #{inspect(reason)}")
        Process.send_after(self(), :start_pipeline, 5_000)
        {:noreply, %{state | status: :error}}
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, state) do
    cond do
      port == state.gst_port ->
        Logger.debug("[GstPipeline] #{state.device_id}: #{data}")
      port == state.sub_stream_port ->
        Logger.debug("[GstPipeline] #{state.device_id} sub: #{data}")
      true ->
        :ok
    end
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, state) do
    cond do
      # Main GStreamer pipeline exited — restart everything
      state.gst_port != nil and port == state.gst_port ->
        Logger.warning("[GstPipeline] Main pipeline exited with status #{status} for #{state.device_id} (mode: #{state.pipeline_mode})")
        # If hybrid failed, try pure GStreamer as fallback
        new_mode = if state.pipeline_mode == :hybrid, do: :pure_gst, else: :hybrid
        Logger.info("[GstPipeline] Will retry with #{new_mode} mode for #{state.device_id}")
        Process.send_after(self(), :start_pipeline, 5_000)
        {:noreply, %{state | status: :stopped, pipeline_pid: nil, gst_port: nil, pipeline_mode: new_mode, sub_stream_retries: 0}}

      # Sub-stream GStreamer push exited — just log, don't restart main pipeline
      state.sub_stream_port != nil and port == state.sub_stream_port ->
        retries = state.sub_stream_retries + 1
        if retries < 3 do
          Logger.warning("[GstPipeline] Sub-stream push exited with status #{status} for #{state.device_id} (retry #{retries}/3)")
          Process.send_after(self(), :retry_sub_stream, 10_000)
          {:noreply, %{state | sub_stream_port: nil, sub_stream_retries: retries}}
        else
          Logger.warning("[GstPipeline] Sub-stream push failed after 3 retries for #{state.device_id}, giving up")
          {:noreply, %{state | sub_stream_port: nil}}
        end

      # FFmpeg or other port exited — ignore
      true ->
        Logger.debug("[GstPipeline] Port exited with status #{status} for #{state.device_id}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:retry_sub_stream, state) do
    if state.status == :running and state.sub_stream_port == nil do
      Logger.info("[GstPipeline] Retrying sub-stream push for #{state.device_id}")
      state = start_sub_stream_push(state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("[GstPipeline] Stopping for #{state.device_id}")
    # Stop MSE streaming watcher
    TProNVR.LiveStream.Supervisor.stop_streaming(state.device_id)
    stop_hybrid_pipeline(state)
    :ok
  end

  # ============================================================
  # Private Functions - Hybrid FFmpeg + GStreamer Pipeline
  # ============================================================

  # Start hybrid pipeline: FFmpeg for RTSP source, GStreamer for encode/mux
  # FFmpeg handles RTSP connection (better compatibility with Dahua, etc.)
  # GStreamer handles hardware encoding and muxing (Rockchip MPP)
  # Note: ZLMediaKit push is handled separately (only for AI Analytics)
  # to avoid duplicate FFmpeg processes which consume ~45MB RAM each
  defp start_hybrid_pipeline(state) do
    pipeline_cmd = case state.pipeline_mode do
      :pure_gst ->
        build_pure_gst_cmd(state)
      _ ->
        ffmpeg_cmd = build_ffmpeg_cmd(state)
        gst_cmd = build_gstreamer_cmd(state)
        "#{ffmpeg_cmd} | #{gst_cmd}"
    end
    
    Logger.info("[GstPipeline] Starting #{state.pipeline_mode} pipeline: #{hide_credentials(pipeline_cmd)}")

    try do
      # Use bash to handle the pipe between processes
      port = Port.open(
        {:spawn, "bash -c '#{pipeline_cmd}'"},
        [:binary, :exit_status, :stderr_to_stdout]
      )
      {:ok, port}
    rescue
      e ->
        Logger.error("[GstPipeline] Failed to start hybrid pipeline: #{inspect(e)}")
        {:error, e}
    end
  end

  # Stop both FFmpeg and GStreamer processes
  defp stop_hybrid_pipeline(state) do
    device_id = state.device_id
    
    # Stop sub_stream GStreamer push
    if state.sub_stream_port do
      try do
        Port.close(state.sub_stream_port)
      catch
        :error, :badarg -> :ok
      end
    end
    
    # Kill GStreamer processes for this device
    System.cmd("pkill", ["-f", "gst-launch.*#{device_id}"], stderr_to_stdout: true)
    
    # Kill FFmpeg processes for this device (using RTSP URL pattern)
    System.cmd("pkill", ["-f", "ffmpeg.*#{device_id}"], stderr_to_stdout: true)
    
    :ok
  end

  # Build FFmpeg command for RTSP source
  # FFmpeg is more compatible with various cameras (especially Dahua)
  # Output: MPEG-TS to stdout (pipe:1)
  defp build_ffmpeg_cmd(state) do
    # FFmpeg options:
    # -hide_banner: Suppress FFmpeg startup info
    # -loglevel error: Only show errors
    # -fflags +genpts: Generate PTS if missing (fixes remote/cloud streams)
    # -rtsp_transport tcp: Use TCP for RTSP (more reliable)
    # -c:v copy: Copy video stream without re-encoding
    # -an: Disable audio (not needed for NVR)
    # -bsf:v h264_mp4toannexb: Ensure proper NAL unit framing for MPEG-TS
    # -muxdelay 0 -muxpreload 0: Don't wait for timestamps (fixes cloud streams)
    # -f mpegts: Output format is MPEG-TS (good for piping)
    # pipe:1: Output to stdout
    
    # Choose bitstream filter based on codec
    bsf = case state.stream_codec do
      :h265 -> "-bsf:v hevc_mp4toannexb"
      _ -> "-bsf:v h264_mp4toannexb"
    end
    
    [
      "ffmpeg -hide_banner -loglevel error",
      "-fflags +genpts",
      "-rtsp_transport tcp",
      "-i \"#{state.rtsp_url}\"",
      "-c:v copy -an",
      bsf,
      "-f mpegts -muxdelay 0 -muxpreload 0 pipe:1"
    ] |> Enum.join(" ")
  end

  # Build pure GStreamer pipeline (no FFmpeg)
  # Uses rtspsrc directly - works better for remote/cloud RTSP streams
  # that fail with FFmpeg MPEG-TS output due to PTS/DTS issues
  defp build_pure_gst_cmd(state) do
    {_decoder, h264_encoder, needs_convert, scale_caps} = get_hw_elements(state.hardware_caps, state.stream_resolution)
    
    convert_element = cond do
      scale_caps -> "videoconvert ! #{scale_caps} !"
      needs_convert -> "videoconvert !"
      true -> ""
    end
    
    # Choose depayloader based on codec
    depay = case state.stream_codec do
      :h265 -> "rtph265depay ! h265parse"
      _ -> "rtph264depay ! h264parse"
    end
    
    # Use mppvideodec for hardware decoding on Rockchip
    decoder = case state.hardware_caps do
      %{platform: :rockchip} -> "mppvideodec"
      _ -> "decodebin3"
    end
    
    zlm_url = "rtsp://#{zlm_host()}:#{zlm_port()}/live/#{state.device_id}"
    
    recording_branch = if state.recording_enabled, do: build_recording_branch(state), else: nil
    
    base_pipeline = [
      "gst-launch-1.0 -e",
      "rtspsrc location=\"#{state.rtsp_url}\" protocols=tcp latency=300 tcp-timeout=10000000 retry=5",
      "! #{depay} ! #{decoder} name=dec",
      "dec. ! tee name=raw_tee",
      "raw_tee. ! queue max-size-buffers=100 leaky=downstream ! #{convert_element} #{h264_encoder}",
      "! h264parse ! tee name=stream_tee",
      "stream_tee. ! queue max-size-buffers=50 leaky=downstream ! rtspclientsink location=\"#{zlm_url}\" protocols=tcp"
    ]
    
    pipeline_parts = base_pipeline
    pipeline_parts = if recording_branch, do: pipeline_parts ++ [recording_branch], else: pipeline_parts
    
    Enum.join(pipeline_parts, " ")
  end

  # Build GStreamer command for decode/encode/mux
  # Receives MPEG-TS from FFmpeg via stdin (fdsrc)
  # Outputs: ZLMediaKit (RTSP push for HLS) + local recording
  #
  # Pipeline topology (single encoder shared for streaming + recording):
  #   fdsrc → tsdemux → parse → decode → raw_tee
  #     raw_tee → encode H.264 → h264parse → stream_tee
  #       stream_tee → rtspclientsink (ZLMediaKit)
  #       stream_tee → splitmuxsink (recording)
  defp build_gstreamer_cmd(state) do
    {decoder, h264_encoder, needs_convert, scale_caps} = get_hw_elements(state.hardware_caps, state.stream_resolution)
    
    # videoconvert + optional scale for format normalization
    convert_element = cond do
      scale_caps -> "videoconvert ! #{scale_caps} !"
      needs_convert -> "videoconvert !"
      true -> ""
    end
    
    # Choose parse element based on detected codec
    input_parse = case state.stream_codec do
      :h265 -> "h265parse"
      _ -> "h264parse"
    end

    # Recording branch taps from stream_tee (already-encoded H.264)
    # This avoids a second encoder instance — saves 50% VPU/CPU
    recording_branch = 
      if state.recording_enabled do
        build_recording_branch(state)
      else
        nil
      end

    # ZLMediaKit RTSP push URL for main_stream
    zlm_url = "rtsp://#{zlm_host()}:#{zlm_port()}/live/#{state.device_id}"

    base_pipeline = [
      "gst-launch-1.0 -e",
      "fdsrc fd=0 ! tsdemux ! #{input_parse} ! #{decoder} name=dec",
      "dec. ! tee name=raw_tee",
      # Single H.264 encode → stream_tee (shared by streaming + recording)
      "raw_tee. ! queue max-size-buffers=100 leaky=downstream ! #{convert_element} #{h264_encoder}",
      "! h264parse ! tee name=stream_tee",
      "stream_tee. ! queue max-size-buffers=50 leaky=downstream ! rtspclientsink location=\"#{zlm_url}\" protocols=tcp"
    ]
    
    pipeline_parts = base_pipeline
    pipeline_parts = if recording_branch, do: pipeline_parts ++ [recording_branch], else: pipeline_parts
    
    Enum.join(pipeline_parts, " ")
  end


  # Get optimal decoder/encoder elements based on hardware platform
  # Returns: {decoder, h264_encoder, needs_convert}
  # Single encoder is shared between streaming (ZLMediaKit) and recording (splitmuxsink)
  # Bitrate scales dynamically based on resolution:
  #   SD (≤1280x720)     → 2 Mbps
  #   HD (≤1920x1080)    → 3 Mbps
  #   2K (≤2560x1440)    → 4 Mbps
  #   4MP+ (>2560x1440)  → 6 Mbps
  defp get_hw_elements(%{platform: :rockchip}, resolution) do
    {bps, scale_caps} = calculate_encode_params(resolution)
    bps_min = div(bps * 3, 4)
    Logger.info("[GstPipeline] MPP encoder: bps=#{bps}, bps-min=#{bps_min}, scale=#{inspect(scale_caps)} for resolution #{inspect(resolution)}")
    {"mppvideodec", "mpph264enc bps=#{bps} bps-min=#{bps_min} gop=30 rc-mode=cbr", false, scale_caps}
  end

  defp get_hw_elements(%{platform: :vaapi}, _resolution) do
    # Intel/AMD VAAPI
    {"vaapidecodebin", "vaapih264enc bitrate=2000 keyframe-period=30", true, nil}
  end

  defp get_hw_elements(%{platform: :nvidia}, _resolution) do
    # NVIDIA NVENC
    {"nvdec", "nvh264enc bitrate=2000 gop-size=30 preset=low-latency-hq", false, nil}
  end

  defp get_hw_elements(_software, _resolution) do
    # Software fallback
    {"decodebin3", "x264enc tune=zerolatency bitrate=2000 speed-preset=ultrafast key-int-max=30", true, nil}
  end

  # Calculate encoder bitrate and optional scale-down caps based on resolution
  # For cameras > 1080p: scale down to 1920x1080 to fix MPP alignment issues
  # (e.g., 2880x1620 has height not 16-aligned, causing green stripes)
  # Uses nearest-neighbor scaling (method=0) for minimal CPU usage
  defp calculate_encode_params(nil), do: {3_000_000, nil}
  defp calculate_encode_params({w, h}) do
    pixels = w * h
    cond do
      # >1080p: scale down to 1920x1080 (fixes alignment + saves encoder load)
      # method=0 = nearest-neighbor (fastest), n-threads=4 for RK3588
      pixels > 2_073_600 ->
        {4_000_000, "videoscale method=0 n-threads=4 ! video/x-raw,width=1920,height=1080"}
      # 1080p: no scaling needed
      pixels > 921_600 ->
        {3_000_000, nil}
      # 720p or lower
      true ->
        {2_000_000, nil}
    end
  end

  # Recording branch taps from stream_tee (already H.264 encoded)
  # No separate encoder needed — shares the single encode with ZLMediaKit push
  defp build_recording_branch(state) do
    # Get current date for directory structure - same as Membrane
    now = DateTime.utc_now()
    date_components = TProNVR.Utils.date_components(now)
    full_recording_path = Path.join([state.recording_path | date_components])

    # Ensure recording directory exists - handle disk full gracefully
    case File.mkdir_p(full_recording_path) do
      :ok ->
        # Build splitmuxsink with timestamp-based filenames (matching Membrane convention)
        base_timestamp = DateTime.to_unix(now, :microsecond)
        segment_template = Path.join(full_recording_path, "#{base_timestamp}_%05d.mp4")

        # stream_tee already has H.264 encoded data — just mux to MP4
        [
          "stream_tee. ! queue max-size-buffers=100 leaky=downstream",
          "! splitmuxsink location=\"#{segment_template}\"",
          "max-size-time=#{state.segment_duration}",
          "muxer=\"mp4mux faststart=true\""
        ] |> Enum.join(" ")

      {:error, reason} ->
        Logger.warning("[GstPipeline] Cannot create recording directory #{full_recording_path}: #{reason} - recording disabled for #{state.device_id}")
        nil
    end
  end

  defp build_recording_path(device) do
    # Use same path structure as Membrane: <storage>/nvr/<device_id>/hi_quality/
    TProNVR.Model.Device.recording_dir(device, :high)
  end

  defp build_rtsp_url(%Device{stream_config: config, credentials: credentials} = _device) do
    uri = (config && config.stream_uri) || ""
    username = credentials && credentials.username
    password = credentials && credentials.password

    if username && password && username != "" do
      uri
      |> URI.parse()
      |> Map.put(:userinfo, "#{username}:#{password}")
      |> URI.to_string()
    else
      uri
    end
  end

  defp hide_credentials(cmd) do
    # Hide password in logs
    Regex.replace(~r/:([^:@]+)@/, cmd, ":****@")
  end

  # Start sub_stream GStreamer push to ZLMediaKit
  # Uses lightweight rtspsrc → parsebin → rtspclientsink (no encoding, just relay)
  defp start_sub_stream_push(state) do
    device = state.device
    sub_url = Device.effective_rtsp_url(device, :sub)

    if sub_url do
      zlm_url = "rtsp://#{zlm_host()}:#{zlm_port()}/live/#{state.device_id}_sub"
      
      # GStreamer pipeline: RTSP source → parse → RTSP push (codec passthrough)
      gst_cmd = Enum.join([
        "gst-launch-1.0 -e",
        "rtspsrc location=\"#{sub_url}\" protocols=tcp latency=300 tcp-timeout=10000000 retry=5 ! parsebin",
        "! rtspclientsink location=\"#{zlm_url}\" protocols=tcp"
      ], " ")
      
      Logger.info("[GstPipeline] Starting sub_stream GStreamer push for #{state.device_id}")
      Logger.debug("[GstPipeline] Sub-stream cmd: #{hide_credentials(gst_cmd)}")
      
      try do
        port = Port.open(
          {:spawn, "bash -c '#{gst_cmd}'"},
          [:binary, :exit_status, :stderr_to_stdout]
        )
        %{state | sub_stream_port: port}
      rescue
        e ->
          Logger.error("[GstPipeline] Failed to start sub_stream push: #{inspect(e)}")
          state
      end
    else
      Logger.debug("[GstPipeline] No sub_stream configured for #{state.device_id}")
      state
    end
  end

  defp zlm_host do
    Application.get_env(:tpro_nvr, :zlmediakit, [])[:host] || "127.0.0.1"
  end

  defp zlm_port do
    Application.get_env(:tpro_nvr, :zlmediakit, [])[:rtsp_port] || 8554
  end

  defp create_webrtc_offer(_device_id, _peer_id) do
    %{type: "offer", sdp: "placeholder_sdp"}
  end

  defp handle_peer_answer(_device_id, _peer_id, _answer_sdp), do: :ok
  defp add_ice_candidate(_device_id, _peer_id, _candidate), do: :ok

  # Probe RTSP stream to detect codec (H.264 or H.265)
  # Uses ffprobe with a short timeout to avoid blocking
  defp probe_stream_codec(rtsp_url) do
    args = [
      "-v", "error",
      "-select_streams", "v:0",
      "-show_entries", "stream=codec_name",
      "-of", "csv=p=0",
      "-rtsp_transport", "tcp",
      rtsp_url
    ]

    case System.cmd("timeout", ["5", "ffprobe" | args], stderr_to_stdout: true) do
      {output, 0} ->
        codec = output |> String.trim() |> String.downcase()
        cond do
          String.contains?(codec, "hevc") or String.contains?(codec, "h265") -> :h265
          String.contains?(codec, "h264") or String.contains?(codec, "avc") -> :h264
          true -> :h264  # Default to H.264
        end

      {_output, _code} ->
        Logger.warning("[GstPipeline] Failed to probe codec for #{hide_credentials(rtsp_url)}, defaulting to H.264")
        :h264
    end
  end

  # Probe RTSP stream to detect resolution (width x height)
  defp probe_stream_resolution(rtsp_url) do
    args = [
      "-v", "error",
      "-select_streams", "v:0",
      "-show_entries", "stream=width,height",
      "-of", "csv=p=0",
      "-rtsp_transport", "tcp",
      rtsp_url
    ]

    case System.cmd("timeout", ["5", "ffprobe" | args], stderr_to_stdout: true) do
      {output, 0} ->
        case output |> String.trim() |> String.split(",") do
          [w_str, h_str] ->
            with {w, _} <- Integer.parse(w_str),
                 {h, _} <- Integer.parse(h_str) do
              {w, h}
            else
              _ -> nil
            end
          _ -> nil
        end

      {_output, _code} ->
        Logger.warning("[GstPipeline] Failed to probe resolution for #{hide_credentials(rtsp_url)}")
        nil
    end
  end

  # Detect if RTSP URL points to a cloud/remote server (not local network)
  # Cloud streams are already clean — no need for FFmpeg hybrid pipeline
  defp cloud_rtsp_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) ->
        not local_host?(host)
      _ ->
        false
    end
  end
  defp cloud_rtsp_url?(_), do: false

  defp local_host?(host) do
    cond do
      host == "localhost" or host == "127.0.0.1" -> true
      String.starts_with?(host, "192.168.") -> true
      String.starts_with?(host, "10.") -> true
      String.match?(host, ~r/^172\.(1[6-9]|2[0-9]|3[01])\./) -> true
      true -> false
    end
  end

  defp via_tuple(device_id) do
    {:via, Registry, {TProNVR.Gst.Registry, device_id}}
  end
end
