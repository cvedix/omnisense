defmodule TProNVR.Pipelines.HlsPlayback do
  @moduledoc """
  A pipeline that converts recorded video into HLS playlists for streaming
  """

  use Membrane.Pipeline

  require Membrane.Logger

  alias TProNVR.Elements
  alias TProNVR.Pipeline.Output

  @call_timeout :timer.seconds(30)

  @spec start_link(Keyword.t()) :: Pipeline.on_start()
  def start_link(opts) do
    Pipeline.start_link(__MODULE__, opts, name: opts[:name])
  end

  @spec start(Keyword.t()) :: Pipeline.on_start()
  def start(opts) do
    Pipeline.start(__MODULE__, opts, name: opts[:name])
  end

  @spec start_streaming(pid() | atom()) :: :ok
  def start_streaming(pipeline) do
    Membrane.Logger.info("Start playback")
    Pipeline.call(pipeline, :start_streaming, @call_timeout)
  end

  @spec stop_streaming(pid() | atom()) :: :ok
  def stop_streaming(pipeline) do
    Pipeline.call(pipeline, :stop_streaming)
  end

  @impl true
  def handle_init(_ctx, options) do
    device_id = options[:device].id
    Logger.metadata(device_id: device_id)
    Membrane.Logger.info("Start playback pipeline with options: #{device_id}")

    Process.set_label({:hls_playback, options[:device].id})

    spec = [
      child(:source, %Elements.Recording{
        device: options[:device],
        start_date: options[:start_date],
        stream: options[:stream],
        duration: Membrane.Time.seconds(options[:duration])
      })
    ]

    state = %{
      directory: options[:directory],
      segment_name_prefix: options[:segment_name_prefix],
      resolution: options[:resolution],
      caller: nil
    }

    {[spec: spec], state}
  end

  @impl true
  def handle_setup(_ctx, state) do
    {[setup: :incomplete], state}
  end

  @impl true
  def handle_child_notification({:new_track, id, track}, :source, _ctx, state) do
    spec = [
      get_child(:source)
      |> via_out(Pad.ref(:video, id))
      |> child(:realtimer, Elements.Realtimer)
      |> add_transcoding_spec(id, track, state.resolution)
      |> via_in(Pad.ref(:main_stream, track.type))
      |> child(:sink, %Output.HLS{location: state.directory})
    ]

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification({:track_playable, _track}, :sink, _ctx, state) do
    {[reply_to: {state.caller, :ok}], %{state | caller: nil}}
  end

  @impl true
  def handle_child_notification(notification, _element, _ctx, state) do
    Membrane.Logger.warning("Received unexpected notification: #{inspect(notification)}")
    {[], state}
  end

  @impl true
  def handle_call(:start_streaming, %{from: from}, state) do
    {[setup: :complete], %{state | caller: from}}
  end

  @impl true
  def handle_call(:stop_streaming, _ctx, state) do
    Membrane.Logger.info("Stop playback")
    {[reply: :ok, terminate: :shutdown], state}
  end

  def child_spec(arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [arg]},
      restart: :temporary,
      type: :supervisor
    }
  end

  # Skip transcoding entirely - just pass video through to HLS
  # This keeps the original codec (H265 or H264) without decode/encode
  # Browser needs H265 support for H265 recordings (Safari, some Edge)
  defp add_transcoding_spec(builder, _ref, _track, _resolution) do
    # No transcoding - just pass through
    builder
  end
end
