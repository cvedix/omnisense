defmodule TProNVRWeb.LiveStreamChannel do
  @moduledoc """
  Phoenix Channel for live video streaming via WebSocket.
  
  Clients join with device_id and receive:
  - init_segment: Codec initialization data (SPS/PPS)
  - frame: Video frames as binary data
  """

  use TProNVRWeb, :channel

  require Logger

  alias TProNVR.LiveStream.FrameBuffer

  @impl true
  def join("live_stream:" <> device_id, _params, socket) do
    # Verify device exists
    case TProNVR.Devices.get(device_id) do
      nil ->
        {:error, %{reason: "device_not_found"}}

      _device ->
        # Subscribe to frame updates
        FrameBuffer.subscribe(device_id)
        
        # Send initial buffer if available
        send(self(), :send_initial_buffer)
        
        {:ok, assign(socket, :device_id, device_id)}
    end
  end

  @impl true
  def handle_info(:send_initial_buffer, socket) do
    device_id = socket.assigns.device_id
    
    case FrameBuffer.get_buffer(device_id) do
      {:ok, init_segment, codec, frames} ->
        # Send init segment first
        push(socket, "init_segment", %{
          data: Base.encode64(init_segment),
          codec: codec_string(codec)
        })
        
        # Send buffered frames
        Enum.each(frames, fn frame ->
          push(socket, "frame", %{
            data: Base.encode64(frame.data),
            keyframe: frame.keyframe?,
            timestamp: frame.timestamp
          })
        end)
        
      {:error, :not_ready} ->
        Logger.debug("[LiveStreamChannel] Buffer not ready for #{device_id}")
        
      {:error, :not_started} ->
        Logger.debug("[LiveStreamChannel] No buffer for #{device_id}")
    end
    
    {:noreply, socket}
  end

  @impl true
  def handle_info({:init_segment, init_segment, codec}, socket) do
    push(socket, "init_segment", %{
      data: Base.encode64(init_segment),
      codec: codec_string(codec)
    })
    {:noreply, socket}
  end

  @impl true
  def handle_info({:frame, frame}, socket) do
    push(socket, "frame", %{
      data: Base.encode64(frame.data),
      keyframe: frame.keyframe?,
      timestamp: frame.timestamp
    })
    {:noreply, socket}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # Convert codec atom to MIME type string for MSE
  defp codec_string(:h264), do: "video/mp4; codecs=\"avc1.42E01E\""
  defp codec_string(:h265), do: "video/mp4; codecs=\"hev1.1.6.L93.B0\""
  defp codec_string(_), do: "video/mp4"
end
