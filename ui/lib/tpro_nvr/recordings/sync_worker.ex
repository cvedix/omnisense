defmodule TProNVR.Recordings.SyncWorker do
  @moduledoc """
  Safety-net GenServer that syncs recordings from disk to database.
  Runs every 10 minutes as backup for the real-time inotify-based RecordingWatcher.
  """
  
  use GenServer
  require Logger
  
  @sync_interval 600_000  # 10 minutes (safety-net backup for inotify watcher)
  
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end
  
  @impl true
  def init(_state) do
    Logger.info("[RecordingSyncWorker] Starting continuous recording sync...")
    
    # Schedule first sync after 5 seconds (let other services start)
    Process.send_after(self(), :sync, 5_000)
    
    {:ok, %{sync_count: 0, last_sync: nil}}
  end
  
  @impl true
  def handle_info(:sync, state) do
    # Schedule next sync
    Process.send_after(self(), :sync, @sync_interval)
    
    # Run import for all devices
    try do
      do_sync()
      {:noreply, %{state | sync_count: state.sync_count + 1, last_sync: DateTime.utc_now()}}
    rescue
      e ->
        Logger.error("[RecordingSyncWorker] Sync failed: #{inspect(e)}")
        {:noreply, state}
    end
  end
  
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  defp do_sync do
    devices = TProNVR.Devices.list()
    
    Enum.each(devices, fn device ->
      recording_path = TProNVR.Model.Device.recording_dir(device, :high)
      
      # Find new files not in database
      files = Path.join(recording_path, "**/*.mp4") |> Path.wildcard()
      
      new_files = Enum.filter(files, fn path ->
        filename = Path.basename(path)
        # Only GStreamer files and not already in DB
        Regex.match?(~r/_\d{5}\.mp4$/, filename) &&
        !TProNVR.Recordings.get(device, :high, filename)
      end)
      
      if length(new_files) > 0 do
        Logger.info("[RecordingSyncWorker] Found #{length(new_files)} new files for device #{device.id}")
        
        Enum.each(new_files, fn path ->
          import_file(device, path)
        end)
      end
    end)
  end
  
  defp import_file(device, path) do
    filename = Path.basename(path)
    
    case File.stat(path) do
      {:ok, stat} when stat.size > 0 ->
        # Check file age - skip files less than 5 seconds old (still being written)
        mtime = stat.mtime |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")
        file_age = DateTime.diff(DateTime.utc_now(), mtime, :second)
        
        if file_age > 5 do
          try do
            # Parse filename: {base_timestamp}_{segment_index}.mp4
            # Example: 1770356568285982_00020.mp4
            ext = Path.extname(path)
            base_name = Path.basename(path, ext)
            parts = String.split(base_name, "_")
            
            {base_timestamp_str, segment_index_str} = 
              case parts do
                [base, idx] -> {base, idx}
                _ -> {base_name, "0"}
              end
            
            # Get segment index (e.g., "00020" -> 20)
            segment_index = case Integer.parse(segment_index_str) do
              {idx, _} -> idx
              :error -> 0
            end
            
            # Get actual duration from file
            duration_ms = get_duration(path)
            
            # Calculate start_date: base_timestamp + (segment_index * segment_duration)
            # Each segment is approximately 60 seconds
            segment_duration_sec = 60
            
            start_date = case Integer.parse(base_timestamp_str) do
              {unix_usec, ""} -> 
                base_dt = DateTime.from_unix!(unix_usec, :microsecond)
                # Add segment offset
                DateTime.add(base_dt, segment_index * segment_duration_sec, :second)
              _ -> 
                DateTime.utc_now() |> DateTime.add(-60, :second)
            end
            
            # End date = start_date + actual duration from file
            end_date = DateTime.add(start_date, duration_ms, :millisecond)
            
            recording_params = %{
              start_date: start_date,
              end_date: end_date,
              path: path,
              filename: filename,
              stream: :high,
              device_id: device.id
            }
            
            run = %TProNVR.Model.Run{
              start_date: start_date,
              end_date: end_date,
              device_id: device.id,
              stream: :high,
              active: true
            }
            
            case TProNVR.Recordings.create(device, run, recording_params, false) do
              {:ok, recording, _run} ->
                Logger.info("[RecordingSyncWorker] Imported: #{recording.id} - #{filename} (#{div(duration_ms, 1000)}s)")
              {:error, error} ->
                Logger.debug("[RecordingSyncWorker] Skip: #{inspect(error)}")
            end
          rescue
            e -> Logger.debug("[RecordingSyncWorker] Error importing #{filename}: #{inspect(e)}")
          end
        end
        
      _ -> :skip
    end
  end
  
  defp get_duration(path) do
    try do
      reader = ExMP4.Reader.new!(path)
      duration = ExMP4.Reader.duration(reader, :millisecond)
      ExMP4.Reader.close(reader)
      duration
    rescue
      _ -> 60_000
    end
  end
end
