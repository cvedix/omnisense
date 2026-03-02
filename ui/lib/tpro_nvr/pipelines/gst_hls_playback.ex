defmodule TProNVR.Pipelines.GstHlsPlayback do
  @moduledoc """
  FFmpeg-based HLS playback that concatenates recorded segments.
  
  Uses FFmpeg concat demuxer to join multiple MP4 recording segments
  into a continuous HLS stream for browser playback.
  """

  use GenServer

  require Logger

  alias TProNVR.Recordings

  @call_timeout :timer.seconds(60)

  defstruct [:device, :start_date, :stream, :directory, :port, :ready?]

  # Public API

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @spec start(Keyword.t()) :: GenServer.on_start()
  def start(opts) do
    GenServer.start(__MODULE__, opts)
  end

  @spec start_streaming(pid() | atom()) :: :ok | {:error, term()}
  def start_streaming(pipeline) do
    GenServer.call(pipeline, :start_streaming, @call_timeout)
  end

  @spec stop_streaming(pid() | atom()) :: :ok
  def stop_streaming(pipeline) do
    GenServer.call(pipeline, :stop_streaming)
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    device = opts[:device]
    Process.set_label({:gst_hls_playback, device.id})
    Logger.info("[GstHlsPlayback] Start for device: #{device.id}")

    state = %__MODULE__{
      device: device,
      start_date: opts[:start_date],
      stream: opts[:stream],
      directory: opts[:directory],
      port: nil,
      ready?: false
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:start_streaming, _from, state) do
    stream_type = if state.stream == :low, do: :low, else: :high
    end_date = ~U[2099-01-01 00:00:00Z]

    recordings =
      Recordings.get_recordings_between(
        state.device.id,
        stream_type,
        state.start_date,
        end_date,
        limit: 100
      )

    case recordings do
      [] ->
        Logger.warning("[GstHlsPlayback] No recordings found for device #{state.device.id}")
        {:reply, {:error, :no_recordings}, state}

      recordings ->
        # Build file list for FFmpeg concat (skip empty/in-progress files)
        file_paths =
          recordings
          |> Enum.map(&Recordings.recording_path(state.device, stream_type, &1))
          |> Enum.filter(fn path ->
            File.exists?(path) and match?(%{size: s} when s > 0, File.stat!(path))
          end)

        case file_paths do
          [] ->
            Logger.warning("[GstHlsPlayback] No recording files found on disk")
            {:reply, {:error, :no_recordings}, state}

          paths ->
            case start_ffmpeg(paths, state.directory) do
              {:ok, port} ->
                state = %{state | port: port, ready?: true}
                {:reply, :ok, state}

              {:error, reason} ->
                {:reply, {:error, reason}, state}
            end
        end
    end
  end

  @impl true
  def handle_call(:stop_streaming, _from, state) do
    cleanup(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({port, {:exit_status, 0}}, %{port: port} = state) do
    Logger.info("[GstHlsPlayback] FFmpeg completed successfully")
    {:noreply, %{state | port: nil}}
  end

  @impl true
  def handle_info({port, {:exit_status, code}}, %{port: port} = state) do
    Logger.warning("[GstHlsPlayback] FFmpeg exited with code #{code}")
    {:noreply, %{state | port: nil}}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    Logger.debug("[GstHlsPlayback] FFmpeg: #{data}")
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("[GstHlsPlayback] Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    cleanup(state)
    :ok
  end

  # Private functions

  defp start_ffmpeg(file_paths, output_dir) do
    File.mkdir_p!(output_dir)

    concat_file = Path.join(output_dir, "concat_list.txt")
    playlist_path = Path.join(output_dir, "main_stream.m3u8")
    segment_pattern = Path.join(output_dir, "main_stream_%05d.ts")

    # Write FFmpeg concat list
    concat_content =
      file_paths
      |> Enum.map(fn path -> "file '#{path}'" end)
      |> Enum.join("\n")

    File.write!(concat_file, concat_content)

    Logger.info("[GstHlsPlayback] Concat list (#{length(file_paths)} files): #{concat_file}")

    # FFmpeg command: concat → HLS output (copy codec, no transcoding)
    ffmpeg_cmd =
      "ffmpeg -y -f concat -safe 0 -i #{concat_file} " <>
      "-c copy " <>
      "-f hls " <>
      "-hls_time 3 " <>
      "-hls_list_size 0 " <>
      "-hls_segment_filename #{segment_pattern} " <>
      "#{playlist_path} 2>&1"

    Logger.info("[GstHlsPlayback] Starting FFmpeg: #{ffmpeg_cmd}")

    port =
      Port.open({:spawn, ffmpeg_cmd}, [
        :binary,
        :exit_status,
        :stderr_to_stdout
      ])

    # Wait for playlist file to appear
    if wait_for_playlist(playlist_path, 15, 500) do
      Logger.info("[GstHlsPlayback] Playlist generated: #{playlist_path}")
      {:ok, port}
    else
      try do
        Port.close(port)
      catch
        _, _ -> :ok
      end

      Logger.error("[GstHlsPlayback] Playlist not generated after timeout: #{playlist_path}")
      {:error, :playlist_not_generated}
    end
  end

  defp wait_for_playlist(_path, 0, _interval), do: false

  defp wait_for_playlist(path, attempts, interval) do
    Process.sleep(interval)

    if File.exists?(path) do
      true
    else
      wait_for_playlist(path, attempts - 1, interval)
    end
  end

  defp cleanup(state) do
    if state.port && Port.info(state.port) do
      try do
        Port.close(state.port)
      catch
        _, _ -> :ok
      end
    end

    :ok
  end
end
