defmodule TProNVR.Pipeline.Output.HLS do
  @moduledoc """
  HLS output element for Membrane pipelines.
  
  Receives audio/video streams and generates HLS playlist files.
  Used by both live streaming (Main pipeline) and recorded playback (HlsPlayback).
  
  Note: Live streaming now primarily uses ZLMediaKit. This module remains
  for the Membrane HlsPlayback pipeline (recorded video playback).
  """

  use Membrane.Sink

  require Logger

  def_input_pad :main_stream, accepted_format: _any, availability: :on_request
  def_input_pad :sub_stream, accepted_format: _any, availability: :on_request

  def_options location: [
    spec: String.t(),
    description: "Directory where HLS files will be stored"
  ]

  @impl true
  def handle_init(_ctx, options) do
    if File.exists?(options.location) do
      File.rm_rf!(options.location)
    end

    File.mkdir_p!(options.location)

    state = %{
      variants: %{},
      location: options.location,
      playlist: %{variants: %{}, segments: %{}},
      notified_playable: false
    }

    {[], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(variant_name, _ref), _ctx, state) do
    variant = %{
      name: variant_name,
      writer: nil,
      last_buffer: nil,
      track: nil,
      segment_duration: 0,
      segment_count: 0,
      media_init_count: 0,
      insert_discontinuity?: true
    }

    variants = Map.put(state.variants, variant_name, variant)
    {[], %{state | variants: variants}}
  end

  @impl true
  def handle_stream_format(Pad.ref(_variant_name, _ref), _format, _ctx, state) do
    if state.notified_playable do
      {[], state}
    else
      # Notify parent that the track is playable (HlsPlayback waits for this)
      {[notify_parent: {:track_playable, :video}], %{state | notified_playable: true}}
    end
  end

  @impl true
  def handle_buffer(Pad.ref(_variant_name, _ref), _buffer, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_event(Pad.ref(_variant_name, _ref), _event, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_info({:init_header, _variant_name, _uri}, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_info({:segment, _variant_name, _segment}, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_info(_message, _ctx, state) do
    {[], state}
  end
end
