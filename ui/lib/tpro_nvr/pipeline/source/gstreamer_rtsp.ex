defmodule TProNVR.Pipeline.Source.GStreamerRTSP do
  @moduledoc """
  GStreamer-based RTSP pipeline source.

  Uses GStreamer subprocess (gst-launch-1.0) to read RTSP streams, providing better
  compatibility with cameras that have issues with native RTSP clients (e.g., Tapo cameras).
  """

  use Membrane.Source

  require Membrane.Logger

  alias TProNVR.Model.Device
  alias TProNVR.Pipeline.Track
  alias TProNVR.Gst.HardwareCaps

  @base_back_off_in_ms 10
  @max_back_off_in_ms :timer.minutes(2)

  def_output_pad :main_stream_output,
    accepted_format: _any,
    flow_control: :push,
    availability: :on_request

  def_output_pad :sub_stream_output,
    accepted_format: _any,
    flow_control: :push,
    availability: :on_request

  def_options device: [
                spec: Device.t(),
                description: "The device struct"
              ]

  defmodule Stream do
    @moduledoc false

    defstruct type: nil,
              stream_uri: nil,
              tracks: %{},
              port: nil,
              buffer: <<>>,
              all_pads_connected?: false,
              stream_format_sent?: false,
              reconnect_attempt: 0,
              buffered_actions: []
  end

  @impl true
  def handle_init(_ctx, options) do
    {main_stream_uri, sub_stream_uri} = Device.streams(options.device)

    Membrane.Logger.info("""
    [GStreamerRTSP] Start streaming for
    main stream: #{TProNVR.Utils.redact_url(main_stream_uri)}
    sub stream: #{TProNVR.Utils.redact_url(sub_stream_uri)}
    """)

    streams = %{
      main_stream: nil,
      sub_stream: nil
    }

    state = %{
      device: options.device,
      streams: streams,
      main_stream_uri: main_stream_uri,
      sub_stream_uri: sub_stream_uri
    }

    {[], state}
  end

  @impl true
  def handle_playing(_ctx, state) do
    # Start GStreamer processes for each stream
    main_stream = start_gstreamer_stream(state.main_stream_uri, :main_stream)
    sub_stream = start_gstreamer_stream(state.sub_stream_uri, :sub_stream)

    streams = %{main_stream: main_stream, sub_stream: sub_stream}

    # Notify parent about tracks
    main_actions = if main_stream, do: build_track_notification(:main_stream), else: []
    sub_actions = if sub_stream, do: build_track_notification(:sub_stream), else: []

    {main_actions ++ sub_actions, %{state | streams: streams}}
  end

  @impl true
  def handle_pad_added(Pad.ref(:main_stream_output, control_path), ctx, state) do
    do_handle_pad_added(:main_stream, control_path, ctx, state)
  end

  @impl true
  def handle_pad_added(Pad.ref(:sub_stream_output, control_path), ctx, state) do
    do_handle_pad_added(:sub_stream, control_path, ctx, state)
  end

  @impl true
  def handle_tick({:reconnect, stream_type}, _ctx, state) do
    stream_uri = if stream_type == :main_stream, do: state.main_stream_uri, else: state.sub_stream_uri
    stream = start_gstreamer_stream(stream_uri, stream_type)
    state = put_in(state, [:streams, stream_type], stream)

    actions = if stream, do: build_track_notification(stream_type), else: []
    {[stop_timer: {:reconnect, stream_type}] ++ actions, state}
  end

  @impl true
  def handle_info({port, {:data, data}}, _ctx, state) when is_port(port) do
    # Find which stream this port belongs to
    stream_type = find_stream_by_port(state.streams, port)

    if stream_type do
      stream = state.streams[stream_type]
      
      # Debug: log data reception
      if byte_size(stream.buffer) == 0 do
        Membrane.Logger.info("[GStreamerRTSP] First data received for #{stream_type}: #{byte_size(data)} bytes")
      end
      
      {actions, stream} = process_gstreamer_data(stream, data)
      
      # Debug: log when actions are generated
      if length(actions) > 0 do
        Membrane.Logger.debug("[GStreamerRTSP] Generated #{length(actions)} actions for #{stream_type}")
      end
      
      {actions, put_in(state, [:streams, stream_type], stream)}
    else
      {[], state}
    end
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, _ctx, state) when is_port(port) do
    stream_type = find_stream_by_port(state.streams, port)

    if stream_type do
      Membrane.Logger.warning("[GStreamerRTSP] GStreamer process exited with status #{status} for #{stream_type}")
      {reconnect_actions, stream} = schedule_reconnect(state.streams[stream_type])
      {reconnect_actions, put_in(state, [:streams, stream_type], stream)}
    else
      {[], state}
    end
  end

  @impl true
  def handle_info(msg, _ctx, state) do
    Membrane.Logger.debug("[GStreamerRTSP] Received message: #{inspect(msg)}")
    {[], state}
  end

  @impl true
  def handle_terminate_request(_ctx, state) do
    # Stop all GStreamer processes
    Enum.each(state.streams, fn
      {_type, nil} -> :ok
      {_type, stream} when is_port(stream.port) ->
        try do
          Port.close(stream.port)
        catch
          _, _ -> :ok
        end
      _ -> :ok
    end)

    {[terminate: :normal], state}
  end

  # Private functions

  defp start_gstreamer_stream(nil, _type), do: nil

  defp start_gstreamer_stream(stream_uri, type) do
    hw_caps = HardwareCaps.detect()
    Membrane.Logger.info("[GStreamerRTSP] Starting GStreamer for #{type}: #{TProNVR.Utils.redact_url(stream_uri)}")
    Membrane.Logger.info("[GStreamerRTSP] Hardware platform: #{hw_caps[:platform]}")

    # Build pipeline with auto-detect for both H.264 and H.265
    # Uses decodebin to automatically select correct depayloader and parser
    # Output as Annex B byte-stream for Membrane compatibility
    pipeline_cmd = build_rtsp_pipeline_cmd(stream_uri, hw_caps)
    
    Membrane.Logger.debug("[GStreamerRTSP] Pipeline: #{pipeline_cmd}")

    try do
      port = Port.open({:spawn, pipeline_cmd}, [
        :binary,
        :exit_status,
        :use_stdio
      ])

      # Default to H.265, actual codec will be determined from stream
      %Stream{
        type: type,
        stream_uri: stream_uri,
        port: port,
        buffer: <<>>,
        tracks: %{"video" => Track.new(:video, :h265, timescale: 90_000)}
      }
    rescue
      e ->
        Membrane.Logger.error("[GStreamerRTSP] Failed to start GStreamer: #{inspect(e)}")
        nil
    end
  end

  # Build RTSP pipeline command based on hardware platform
  defp build_rtsp_pipeline_cmd(stream_uri, %{platform: :rockchip}) do
    # Rockchip MPP - use mppvideodec for hardware decoding
    # decodebin3 will use mppvideodec automatically if available
    """
    gst-launch-1.0 -q \\
      rtspsrc location="#{stream_uri}" latency=100 protocols=tcp \\
      ! decodebin3 \\
      ! video/x-raw \\
      ! mppvideodec \\
      ! video/x-h265,stream-format=byte-stream,alignment=au \\
      ! fdsink fd=1
    """ |> String.replace("\n", " ") |> String.trim()
  end

  defp build_rtsp_pipeline_cmd(stream_uri, _hw_caps) do
    # Generic pipeline - auto-detect H.264 or H.265
    # Uses parsebin for automatic parser selection
    """
    gst-launch-1.0 -q \\
      rtspsrc location="#{stream_uri}" latency=100 protocols=tcp \\
      ! application/x-rtp,media=video \\
      ! rtph265depay \\
      ! h265parse \\
      ! video/x-h265,stream-format=byte-stream,alignment=au \\
      ! fdsink fd=1
    """ |> String.replace("\n", " ") |> String.trim()
  end


  defp find_stream_by_port(streams, port) do
    Enum.find_value(streams, fn
      {type, %Stream{port: ^port}} -> type
      _ -> nil
    end)
  end

  defp process_gstreamer_data(%Stream{} = stream, data) do
    # Append new data to buffer
    buffer = stream.buffer <> data

    # Parse H265 NAL units from Annex B stream (AU aligned from h265parse)
    {nalus, remaining} = parse_annexb_nalus(buffer)

    # Process NALUs and build actions
    {actions, stream_format_sent?} = 
      Enum.reduce(nalus, {[], stream.stream_format_sent?}, fn nalu, {acc_actions, format_sent?} ->
        keyframe? = is_h265_keyframe?(nalu)
        pad = pad_from_stream_type(stream.type, "video")

        if not format_sent? and keyframe? do
          # H.265 stream format with AU alignment (matching h265parse output)
          format_action = [stream_format: {pad, %Membrane.H265{
            alignment: :au,
            stream_structure: :annexb
          }}]
          
          buffer_action = [buffer: {pad, %Membrane.Buffer{
            payload: nalu,
            dts: System.monotonic_time(:nanosecond),
            pts: System.monotonic_time(:nanosecond),
            metadata: %{
              :timestamp => DateTime.utc_now(),
              :h265 => %{key_frame?: keyframe?}
            }
          }}]
          
          {acc_actions ++ format_action ++ buffer_action, true}
        else
          if format_sent? do
            buffer_action = [buffer: {pad, %Membrane.Buffer{
              payload: nalu,
              dts: System.monotonic_time(:nanosecond),
              pts: System.monotonic_time(:nanosecond),
              metadata: %{
                :timestamp => DateTime.utc_now(),
                :h265 => %{key_frame?: keyframe?}
              }
            }}]
            {acc_actions ++ buffer_action, format_sent?}
          else
            {acc_actions, format_sent?}
          end
        end
      end)


    stream = %{stream | buffer: remaining, stream_format_sent?: stream_format_sent?}

    if stream.all_pads_connected? do
      {actions, stream}
    else
      {[], %{stream | buffered_actions: [actions | stream.buffered_actions]}}
    end
  end

  defp parse_annexb_nalus(data) do
    parse_annexb_nalus(data, [])
  end

  defp parse_annexb_nalus(<<0, 0, 0, 1, rest::binary>>, acc) do
    case find_next_start_code(rest) do
      {:ok, nalu, remaining} ->
        parse_annexb_nalus(remaining, [nalu | acc])
      :incomplete ->
        {Enum.reverse(acc), <<0, 0, 0, 1>> <> rest}
    end
  end

  defp parse_annexb_nalus(<<0, 0, 1, rest::binary>>, acc) do
    case find_next_start_code(rest) do
      {:ok, nalu, remaining} ->
        parse_annexb_nalus(remaining, [nalu | acc])
      :incomplete ->
        {Enum.reverse(acc), <<0, 0, 1>> <> rest}
    end
  end

  defp parse_annexb_nalus(data, acc) when byte_size(data) < 4 do
    {Enum.reverse(acc), data}
  end

  defp parse_annexb_nalus(<<_byte, rest::binary>>, acc) do
    parse_annexb_nalus(rest, acc)
  end

  defp find_next_start_code(data) do
    find_next_start_code(data, <<>>)
  end

  defp find_next_start_code(<<0, 0, 0, 1, _rest::binary>> = remaining, acc) when byte_size(acc) > 0 do
    {:ok, acc, remaining}
  end

  defp find_next_start_code(<<0, 0, 1, _rest::binary>> = remaining, acc) when byte_size(acc) > 0 do
    {:ok, acc, remaining}
  end

  defp find_next_start_code(<<byte, rest::binary>>, acc) do
    find_next_start_code(rest, acc <> <<byte>>)
  end

  defp find_next_start_code(<<>>, _acc) do
    :incomplete
  end


  # H.265 keyframe detection
  defp is_h265_keyframe?(nalu) when byte_size(nalu) > 1 do
    # H.265 NAL unit header is 2 bytes:
    # forbidden_zero_bit(1) | nal_unit_type(6) | nuh_layer_id(6) | nuh_temporal_id_plus1(3)
    <<_forbidden::1, nal_type::6, _rest::bitstring>> = nalu
    # HEVC keyframe NAL types:
    # IRAP pictures: BLA_W_LP(16), BLA_W_RADL(17), BLA_N_LP(18), IDR_W_RADL(19), IDR_N_LP(20), CRA(21)
    # VPS(32), SPS(33), PPS(34) also indicate sequence start
    nal_type in [16, 17, 18, 19, 20, 21, 32, 33, 34]
  end

  defp is_h265_keyframe?(_), do: false

  defp build_track_notification(stream_type) do
    # H.265 track for Tapo camera
    tracks = %{"video" => Track.new(:video, :h265, timescale: 90_000)}
    [notify_parent: {stream_type, tracks}]
  end

  defp schedule_reconnect(%Stream{} = stream) do
    delay = calculate_retry_delay(stream.reconnect_attempt)

    Membrane.Logger.warning("""
    [GStreamerRTSP] Scheduling reconnect for #{stream.type} in #{delay} ms
    """)

    actions = [start_timer: {{:reconnect, stream.type}, Membrane.Time.milliseconds(delay)}]
    stream = %{stream | reconnect_attempt: stream.reconnect_attempt + 1, port: nil}

    if stream.reconnect_attempt == 1 do
      {actions ++ [notify_parent: {:connection_lost, stream.type}], stream}
    else
      {actions, stream}
    end
  end

  defp calculate_retry_delay(reconnect_attempt) do
    :math.pow(2, reconnect_attempt)
    |> Kernel.*(@base_back_off_in_ms)
    |> min(@max_back_off_in_ms)
    |> trunc()
  end

  defp do_handle_pad_added(stream_type, control_path, ctx, state) do
    stream = state.streams[stream_type]

    if stream == nil or not Map.has_key?(stream.tracks, control_path) do
      Membrane.Logger.warning("[GStreamerRTSP] Unknown control path: #{control_path}")
      {[], state}
    else
      pad_name = if stream_type == :main_stream, do: :main_stream_output, else: :sub_stream_output

      connected_pads =
        Enum.count(ctx.pads, fn
          {Pad.ref(^pad_name, _control_path), _} -> true
          _other -> false
        end)

      stream = %{stream | all_pads_connected?: connected_pads == map_size(stream.tracks)}
      state = put_in(state, [:streams, stream_type], stream)

      if stream.all_pads_connected? do
        actions = Enum.reverse(stream.buffered_actions) |> List.flatten()
        {actions, state}
      else
        {[], state}
      end
    end
  end

  defp pad_from_stream_type(:main_stream, ref), do: Pad.ref(:main_stream_output, ref)
  defp pad_from_stream_type(:sub_stream, ref), do: Pad.ref(:sub_stream_output, ref)
end
