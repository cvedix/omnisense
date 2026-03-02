defmodule TProNVR.LiveStream.FrameBuffer do
  @moduledoc """
  GenServer that buffers video frames for live streaming.
  
  Stores the initialization segment (codec info) and recent frames
  so new clients can start playback immediately from a keyframe.
  """

  use GenServer

  require Logger

  @max_buffer_size 30  # Keep last 30 frames (~1 second at 30fps)
  @pubsub TProNVR.PubSub

  # Client API

  def start_link(opts) do
    device_id = Keyword.fetch!(opts, :device_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(device_id))
  end

  def via_tuple(device_id) do
    {:via, Registry, {TProNVR.LiveStream.Registry, device_id}}
  end

  @doc """
  Push a video frame to the buffer.
  Frame should be a map with :data, :keyframe?, :timestamp, :codec
  """
  def push_frame(device_id, frame) do
    case Registry.lookup(TProNVR.LiveStream.Registry, device_id) do
      [{pid, _}] -> GenServer.cast(pid, {:push_frame, frame})
      [] -> :ok  # No buffer running for this device
    end
  end

  @doc """
  Set the initialization segment (SPS/PPS for H.264, VPS/SPS/PPS for H.265).
  This is needed before any frames can be decoded.
  """
  def set_init_segment(device_id, init_segment, codec) do
    case Registry.lookup(TProNVR.LiveStream.Registry, device_id) do
      [{pid, _}] -> GenServer.call(pid, {:set_init_segment, init_segment, codec})
      [] -> {:error, :not_started}
    end
  end

  @doc """
  Get the current init segment and buffered frames for a new client.
  Returns {:ok, init_segment, frames} or {:error, :not_ready}
  """
  def get_buffer(device_id) do
    case Registry.lookup(TProNVR.LiveStream.Registry, device_id) do
      [{pid, _}] -> GenServer.call(pid, :get_buffer)
      [] -> {:error, :not_started}
    end
  end

  @doc """
  Subscribe to frame updates for a device.
  """
  def subscribe(device_id) do
    Phoenix.PubSub.subscribe(@pubsub, "live_stream:#{device_id}")
  end

  @doc """
  Check if a buffer is running for a device.
  """
  def running?(device_id) do
    case Registry.lookup(TProNVR.LiveStream.Registry, device_id) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  # Server callbacks

  @impl true
  def init(opts) do
    device_id = Keyword.fetch!(opts, :device_id)
    
    Logger.info("[FrameBuffer] Started for device: #{device_id}")
    
    {:ok, %{
      device_id: device_id,
      init_segment: nil,
      codec: nil,
      frames: :queue.new(),
      frame_count: 0,
      last_keyframe_idx: nil
    }}
  end

  @impl true
  def handle_cast({:push_frame, frame}, state) do
    # Add frame to buffer
    frames = :queue.in(frame, state.frames)
    frame_count = state.frame_count + 1
    
    # Track last keyframe position
    last_keyframe_idx = if frame.keyframe?, do: frame_count, else: state.last_keyframe_idx
    
    # Trim old frames if buffer is full
    {frames, frame_count} = 
      if :queue.len(frames) > @max_buffer_size do
        {{:value, _}, new_queue} = :queue.out(frames)
        {new_queue, frame_count}
      else
        {frames, frame_count}
      end
    
    # Broadcast frame to subscribers
    Phoenix.PubSub.broadcast(@pubsub, "live_stream:#{state.device_id}", {:frame, frame})
    
    {:noreply, %{state | frames: frames, frame_count: frame_count, last_keyframe_idx: last_keyframe_idx}}
  end

  @impl true
  def handle_call({:set_init_segment, init_segment, codec}, _from, state) do
    Logger.info("[FrameBuffer] Init segment set for #{state.device_id}, codec: #{codec}")
    
    # Broadcast init segment to existing subscribers
    Phoenix.PubSub.broadcast(@pubsub, "live_stream:#{state.device_id}", {:init_segment, init_segment, codec})
    
    {:reply, :ok, %{state | init_segment: init_segment, codec: codec}}
  end

  @impl true
  def handle_call(:get_buffer, _from, state) do
    if state.init_segment do
      # Get frames from last keyframe
      frames = get_frames_from_keyframe(state)
      {:reply, {:ok, state.init_segment, state.codec, frames}, state}
    else
      {:reply, {:error, :not_ready}, state}
    end
  end

  # Private functions

  defp get_frames_from_keyframe(state) do
    frames_list = :queue.to_list(state.frames)
    
    # Find last keyframe and return all frames from there
    case Enum.find_index(Enum.reverse(frames_list), & &1.keyframe?) do
      nil -> frames_list  # No keyframe found, return all
      idx -> 
        # Take from the keyframe to end
        Enum.take(Enum.reverse(frames_list), idx + 1) |> Enum.reverse()
    end
  end
end
