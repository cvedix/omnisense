defmodule TProNVR.Gst.RecordingWatcher do
  @moduledoc """
  Watches GStreamer recording directories for new MP4 segments and registers
  them in the database.
  
  Uses FileSystem to monitor directory changes and calls `TProNVR.Recordings.create/4`
  when new segments are completed.
  """

  use GenServer
  require Logger

  alias TProNVR.Model.Device
  alias TProNVR.Recordings

  defstruct [
    :device_id,
    :device,
    :recording_path,
    :watcher_pid,
    :known_files
  ]

  # ============================================================
  # Public API
  # ============================================================

  def start_link(opts) do
    device = Keyword.fetch!(opts, :device)
    GenServer.start_link(__MODULE__, device, name: via_tuple(device.id))
  end

  def stop(device_id) do
    GenServer.stop(via_tuple(device_id), :normal)
  end

  # ============================================================
  # GenServer Callbacks
  # ============================================================

  @impl true
  def init(%Device{} = device) do
    # Use Device module directly instead of GenServer call (which would timeout)
    recording_path = TProNVR.Model.Device.recording_dir(device, :high)
    
    Logger.info("[GstRecordingWatcher] Starting for device: #{device.id}, path: #{recording_path}")

    # Ensure directory exists
    File.mkdir_p!(recording_path)

    # Start file system watcher
    {:ok, watcher_pid} = FileSystem.start_link(dirs: [recording_path], recursive: true)
    FileSystem.subscribe(watcher_pid)

    state = %__MODULE__{
      device_id: device.id,
      device: device,
      recording_path: recording_path,
      watcher_pid: watcher_pid,
      known_files: MapSet.new()
    }

    # Only use inotify for new files, no initial full scan
    # This prevents spamming logs with old recordings
    {:ok, state}
  end

  # Periodic scan disabled - using inotify only
  # defp schedule_scan do
  #   Process.send_after(self(), :scan_and_import, 30_000)
  # end

  @impl true
  def handle_info({:file_event, _watcher_pid, {path, events}}, state) do
    cond do
      # File was created and closed (completed)
      # On Linux, inotify sends :close_write instead of :closed
      (:closed in events or :close_write in events) and is_video_file?(path) ->
        handle_new_recording(path, state)
        # Bound known_files to prevent memory leak (keep last 200 entries)
        known = MapSet.put(state.known_files, path)
        known = if MapSet.size(known) > 200 do
          known |> MapSet.to_list() |> Enum.take(-200) |> MapSet.new()
        else
          known
        end
        {:noreply, %{state | known_files: known}}

      # File was modified (still being written)
      :modified in events and is_video_file?(path) ->
        # Ignore - file is still being written
        {:noreply, state}

      true ->
        {:noreply, state}
    end
  end

  def handle_info({:file_event, _watcher_pid, :stop}, state) do
    Logger.warning("[GstRecordingWatcher] File watcher stopped for #{state.device_id}")
    {:noreply, state}
  end

  # Periodic scan disabled - using inotify only for new files
  # This prevents spamming logs with hundreds of old recordings
  def handle_info(:scan_and_import, state) do
    # Do nothing - inotify handles new files
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    # FileSystem watcher will be stopped automatically when this process terminates
    :ok
  end

  # ============================================================
  # Private Functions
  # ============================================================

  defp handle_new_recording(path, state) do
    Logger.info("[GstRecordingWatcher] New recording segment: #{path}")

    # Skip if we already know about this file
    if MapSet.member?(state.known_files, path) do
      Logger.debug("[GstRecordingWatcher] Already processed: #{path}")
      :ok
    else
      # Only process GStreamer files (with splitmuxsink suffix pattern like _00000)
      # Membrane files (without suffix) are registered by storage.ex directly
      filename = Path.basename(path)
      if Regex.match?(~r/_\d{5}\.(mp4|mkv)$/, filename) do
        case extract_recording_info(path) do
          {:ok, info} ->
            register_recording(state, path, info)

          {:error, reason} ->
            Logger.warning("[GstRecordingWatcher] Failed to process #{path}: #{inspect(reason)}")
        end
      else
        Logger.debug("[GstRecordingWatcher] Skipping non-GStreamer file: #{filename}")
        :ok
      end
    end
  end

  defp extract_recording_info(path) do
    # Get file stats
    case File.stat(path) do
      {:ok, stat} ->
        # Try to extract duration from video file (supports both MP4 and MKV)
        duration = get_video_duration(path)
        
        # Extract start_date from filename (unix timestamp in microseconds)
        # GStreamer names files like: 1769317733761985_00000.mp4
        # The timestamp is the SESSION start, not segment start
        # We need to add segment_index * segment_duration to get actual start
        ext = Path.extname(path)
        filename = Path.basename(path, ext)
        
        # Parse base timestamp and segment index
        {base_timestamp_str, segment_index} = 
          case String.split(filename, "_") do
            [base, index_str] -> 
              {base, String.to_integer(index_str)}
            [base] -> 
              {base, 0}
          end
        
        # Each segment is ~60 seconds (configurable in pipeline)
        segment_duration_sec = 60
        
        start_date = 
          case Integer.parse(base_timestamp_str) do
            {unix_usec, ""} ->
              base_datetime = DateTime.from_unix!(unix_usec, :microsecond)
              # Add segment offset: segment_index * segment_duration
              DateTime.add(base_datetime, segment_index * segment_duration_sec, :second)
            _ ->
              # Fallback to file mtime if filename isn't a timestamp
              stat.mtime 
              |> NaiveDateTime.from_erl!({0, 6}) 
              |> DateTime.from_naive!("Etc/UTC")
              |> DateTime.add(-duration, :millisecond)
          end
        
        end_date = DateTime.add(start_date, duration, :millisecond)

        {:ok, %{
          start_date: start_date,
          end_date: end_date,
          duration: duration,
          size: stat.size
        }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Dispatch to appropriate duration reader based on file extension
  defp get_video_duration(path) do
    case Path.extname(path) do
      ".mp4" -> get_mp4_duration(path)
      ".mkv" -> get_mkv_duration(path)
      _ -> 60_000  # Default 60 seconds
    end
  end

  defp get_mp4_duration(path) do
    try do
      reader = ExMP4.Reader.new!(path)
      duration_ms = ExMP4.Reader.duration(reader, :millisecond)
      ExMP4.Reader.close(reader)
      duration_ms
    rescue
      _ -> 
        # Default to 60 seconds if we can't read the file
        60_000
    end
  end

  # Use ffprobe for MKV files (legacy GStreamer recordings)
  defp get_mkv_duration(path) do
    try do
      {output, 0} = System.cmd("ffprobe", [
        "-v", "error",
        "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1",
        path
      ])
      
      output
      |> String.trim()
      |> String.to_float()
      |> Kernel.*(1000)
      |> round()
    rescue
      _ -> 60_000
    end
  end

  defp register_recording(state, path, info) do
    # Use the actual filename from disk, not calculated from start_date
    actual_filename = Path.basename(path)
    
    # Check if this recording already exists (prevent duplicates from Membrane)
    if Recordings.get(state.device, :high, actual_filename) do
      Logger.debug("[GstRecordingWatcher] Recording already exists, skipping: #{actual_filename}")
      :ok
    else
      recording_params = %{
        start_date: info.start_date,
        end_date: info.end_date,
        path: path,
        filename: actual_filename,
        stream: :high,
        device_id: state.device_id
      }

      # Create a minimal run for this segment
      run = %TProNVR.Model.Run{
        start_date: info.start_date,
        end_date: info.end_date,
        device_id: state.device_id,
        stream: :high,
        active: true
      }

      try do
        case Recordings.create(state.device, run, recording_params, false) do
          {:ok, recording, _run} ->
            Logger.info("[GstRecordingWatcher] Registered recording: #{recording.id}")

          {:error, error} ->
            Logger.error("[GstRecordingWatcher] Failed to register: #{inspect(error)}")
        end
      rescue
        e in Ecto.ConstraintError ->
          Logger.warning("[GstRecordingWatcher] Constraint error registering #{actual_filename}: #{Exception.message(e)}")
      end
    end
  end

  # Scan disabled - using inotify only\n  # defp scan_existing_files(path) do\n  #   mp4_files = path |> Path.join(\"**/*.mp4\") |> Path.wildcard()\n  #   mkv_files = path |> Path.join(\"**/*.mkv\") |> Path.wildcard()\n  #   (mp4_files ++ mkv_files) |> MapSet.new()\n  # end

  defp is_video_file?(path) do
    Path.extname(path) in [".mp4", ".mkv"]
  end

  defp via_tuple(device_id) do
    {:via, Registry, {TProNVR.Gst.Registry, {:watcher, device_id}}}
  end
end
