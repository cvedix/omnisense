defmodule TProNVR.Recordings.Importer do
  @moduledoc """
  Utility module to import existing recordings from disk into database.
  Useful when recordings exist on disk but not in database.
  """
  
  require Logger
  
  alias TProNVR.{Devices, Recordings}
  alias TProNVR.Model.{Device, Run}
  
  @doc """
  Import all recordings for all devices.
  """
  def import_all do
    Devices.list()
    |> Enum.each(&import_for_device/1)
  end
  
  @doc """
  Import recordings for a specific device.
  """
  def import_for_device(%Device{} = device) do
    recording_path = Device.recording_dir(device, :high)
    Logger.info("[Importer] Scanning #{recording_path} for device #{device.id}")
    
    # Find all MP4 files
    files = Path.join(recording_path, "**/*.mp4") |> Path.wildcard()
    Logger.info("[Importer] Found #{length(files)} MP4 files")
    
    imported = files
    |> Enum.filter(&gstreamer_file?/1)
    |> Enum.map(fn path -> import_recording(device, path) end)
    |> Enum.count(fn result -> result == :ok end)
    
    Logger.info("[Importer] Imported #{imported} recordings for device #{device.id}")
    {:ok, imported}
  end
  
  defp gstreamer_file?(path) do
    filename = Path.basename(path)
    # Match GStreamer splitmuxsink pattern: timestamp_00000.mp4
    Regex.match?(~r/_\d{5}\.mp4$/, filename)
  end
  
  defp import_recording(device, path) do
    filename = Path.basename(path)
    
    # Check if already exists
    if Recordings.get(device, :high, filename) do
      Logger.debug("[Importer] Already exists: #{filename}")
      :exists
    else
      case extract_recording_info(path) do
        {:ok, info} ->
          register_recording(device, path, info)
        {:error, reason} ->
          Logger.warning("[Importer] Failed to process #{path}: #{inspect(reason)}")
          :error
      end
    end
  end
  
  defp extract_recording_info(path) do
    case File.stat(path) do
      {:ok, stat} ->
        # Skip empty files
        if stat.size == 0 do
          {:error, :empty_file}
        else
          duration = get_mp4_duration(path)
          
          # Extract start_date from filename
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
          
          # Each segment is ~60 seconds
          segment_duration_sec = 60
          
          start_date = 
            case Integer.parse(base_timestamp_str) do
              {unix_usec, ""} ->
                base_datetime = DateTime.from_unix!(unix_usec, :microsecond)
                # Add segment offset: segment_index * segment_duration
                DateTime.add(base_datetime, segment_index * segment_duration_sec, :second)
              _ ->
                stat.mtime 
                |> NaiveDateTime.from_erl!() 
                |> DateTime.from_naive!("Etc/UTC")
                |> DateTime.add(-duration, :millisecond)
            end
          
          # Calculate end_date using Unix timestamp to avoid timezone issues
          # Use microseconds for proper Ecto precision
          start_unix_us = DateTime.to_unix(start_date, :microsecond)
          duration_us = duration * 1000  # Convert ms to us
          end_unix_us = start_unix_us + duration_us
          end_date = DateTime.from_unix!(end_unix_us, :microsecond)

          {:ok, %{
            start_date: start_date,
            end_date: end_date,
            duration: duration,
            size: stat.size
          }}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp get_mp4_duration(path) do
    try do
      reader = ExMP4.Reader.new!(path)
      duration_ms = ExMP4.Reader.duration(reader, :millisecond)
      ExMP4.Reader.close(reader)
      duration_ms
    rescue
      _ -> 60_000
    end
  end
  
  defp register_recording(device, path, info) do
    filename = Path.basename(path)
    
    recording_params = %{
      start_date: info.start_date,
      end_date: info.end_date,
      path: path,
      filename: filename,
      stream: :high,
      device_id: device.id
    }

    run = %Run{
      start_date: info.start_date,
      end_date: info.end_date,
      device_id: device.id,
      stream: :high,
      active: true
    }

    case Recordings.create(device, run, recording_params, false) do
      {:ok, recording, _run} ->
        Logger.info("[Importer] Imported: #{recording.id} - #{filename}")
        :ok

      {:error, error} ->
        Logger.error("[Importer] Failed: #{inspect(error)}")
        :error
    end
  end
end
