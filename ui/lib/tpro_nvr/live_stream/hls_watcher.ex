defmodule TProNVR.LiveStream.HLSWatcher do
  @moduledoc """
  Watches HLS segments and broadcasts them via PubSub for MSE streaming.
  
  This is a simpler approach than modifying the GStreamer pipeline:
  - Watches the HLS directory for new .ts segments
  - Converts segments to fMP4 format for MSE
  - Broadcasts via PubSub to connected clients
  """

  use GenServer

  require Logger

  alias TProNVR.LiveStream.FrameBuffer

  @poll_interval 500  # Check for new segments every 500ms

  defstruct [
    :device_id,
    :hls_path,
    :last_segment,
    :init_sent
  ]

  # Client API

  def start_link(opts) do
    device_id = Keyword.fetch!(opts, :device_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(device_id))
  end

  def via_tuple(device_id) do
    {:via, Registry, {TProNVR.LiveStream.WatcherRegistry, device_id}}
  end

  def stop(device_id) do
    case Registry.lookup(TProNVR.LiveStream.WatcherRegistry, device_id) do
      [{pid, _}] -> GenServer.stop(pid)
      [] -> :ok
    end
  end

  # Server callbacks

  @impl true
  def init(opts) do
    device_id = Keyword.fetch!(opts, :device_id)
    hls_dir = Application.get_env(:tpro_nvr, :hls_directory, "/tmp/hls")
    hls_path = Path.join(hls_dir, device_id)

    Logger.info("[HLSWatcher] Started for device: #{device_id}, path: #{hls_path}")

    # Ensure FrameBuffer is started
    TProNVR.LiveStream.Supervisor.start_buffer(device_id)

    state = %__MODULE__{
      device_id: device_id,
      hls_path: hls_path,
      last_segment: nil,
      init_sent: false
    }

    # Start polling for new segments
    schedule_poll()

    {:ok, state}
  end

  @impl true
  def handle_info(:poll_segments, state) do
    state = check_for_new_segments(state)
    schedule_poll()
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("[HLSWatcher] Stopped for device: #{state.device_id}")
    :ok
  end

  # Private functions

  defp schedule_poll do
    Process.send_after(self(), :poll_segments, @poll_interval)
  end

  defp check_for_new_segments(state) do
    case list_segments(state.hls_path) do
      {:ok, segments} when segments != [] ->
        # Get the latest segment
        latest = Enum.max_by(segments, &segment_number/1)
        
        if latest != state.last_segment do
          process_segment(state, latest)
          %{state | last_segment: latest}
        else
          state
        end

      _ ->
        state
    end
  end

  defp list_segments(path) do
    case File.ls(path) do
      {:ok, files} ->
        segments = 
          files
          |> Enum.filter(&String.ends_with?(&1, ".ts"))
          |> Enum.sort()
        {:ok, segments}

      {:error, _} ->
        {:error, :not_found}
    end
  end

  defp segment_number(filename) do
    case Regex.run(~r/segment(\d+)\.ts/, filename) do
      [_, num] -> String.to_integer(num)
      _ -> 0
    end
  end

  defp process_segment(state, segment_filename) do
    segment_path = Path.join(state.hls_path, segment_filename)
    
    case File.read(segment_path) do
      {:ok, data} ->
        # For now, send raw TS data - browser may need remuxing
        # In production, would convert to fMP4 for better MSE compatibility
        frame = %{
          data: data,
          keyframe?: true,  # Assume each segment starts with keyframe
          timestamp: System.system_time(:millisecond),
          segment: segment_filename
        }
        
        # Send init segment if not sent (simplified - TS doesn't need init)
        unless state.init_sent do
          # For TS, we can use text/plain codec detection
          FrameBuffer.set_init_segment(state.device_id, <<>>, :mpegts)
        end
        
        FrameBuffer.push_frame(state.device_id, frame)
        Logger.debug("[HLSWatcher] Pushed segment: #{segment_filename}")

      {:error, reason} ->
        Logger.warning("[HLSWatcher] Failed to read segment: #{inspect(reason)}")
    end
  end
end
