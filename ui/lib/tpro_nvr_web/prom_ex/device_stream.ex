defmodule TProNVRWeb.PromEx.DeviceStream do
  @moduledoc false

  use PromEx.Plugin

  alias PromEx.MetricTypes.Event

  @info_event [:tpro_nvr, :device, :stream]
  @frame_event [:tpro_nvr, :device, :stream, :frame]

  @impl true
  def event_metrics(_opts) do
    Event.build(
      :tpro_nvr_device_stream_event_metrics,
      [
        last_value(
          "cvr.device.stream.info",
          event_name: @info_event,
          description: "The device stream information",
          measurement: [:value],
          tags: [:device_id, :stream, :type, :codec, :profile, :width, :height]
        ),
        last_value(
          "cvr.device.stream.gop_size",
          event_name: @frame_event,
          description: "Group of Picture size of the stream",
          measurement: :gop_size,
          tags: [:device_id, :stream]
        ),
        counter(
          "cvr.device.stream.frames.total",
          event_name: @frame_event,
          description: "Total frames of the stream",
          measurement: :total_frames,
          tags: [:device_id, :stream]
        ),
        sum(
          "cvr.device.stream.receive.bytes.total",
          event_name: @frame_event,
          description: "Total bytes received from the stream",
          measurement: :size,
          tags: [:device_id, :stream]
        )
      ]
    )
  end
end
