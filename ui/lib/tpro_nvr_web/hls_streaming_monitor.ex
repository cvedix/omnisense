defmodule TProNVRWeb.HlsStreamingMonitor do
  @moduledoc """
  Monitors current HLS streaming pipelines.

  If an HLS streaming pipeline is not accessed by a client for 45 seconds,
  we stop creating HLS playlists and clean up resources.

  Also tracks active streams per device to ensure only one playback pipeline
  runs at a time — switching segments stops the previous pipeline immediately.
  """

  use GenServer

  require Logger

  @cleanup_interval :timer.seconds(15)
  @stale_time 45

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @doc """
  Register a new HLS stream with cleanup callback.
  If a previous stream exists for the same device, it is stopped first.
  """
  def register(id, cleanup_fn, device_id \\ nil) do
    # Stop previous stream for same device (playback segment switch)
    if device_id do
      stop_device_streams(device_id)
    end

    Logger.info("Register new HLS stream: #{id} (device: #{device_id || "unknown"})")
    :ets.insert(__MODULE__, {id, cleanup_fn, current_time_s(), device_id})
  end

  def update_last_access_time(id) do
    try do
      :ets.update_element(__MODULE__, id, {3, current_time_s()})
    rescue
      _ -> false
    end
  end

  @doc """
  Stop all streams for a specific device immediately.
  """
  def stop_device_streams(device_id) do
    :ets.tab2list(__MODULE__)
    |> Enum.filter(fn {_key, _fn, _time, dev_id} -> dev_id == device_id end)
    |> Enum.each(fn {key, clean_up_fn, _, _} ->
      Logger.info("Stopping previous stream #{key} for device #{device_id} (segment switch)")
      run_cleanup(clean_up_fn)
      :ets.delete(__MODULE__, key)
    end)
  end

  @impl true
  def init(nil) do
    :ets.new(__MODULE__, [:named_table, :public, :set])
    Process.send_after(self(), :tick, @cleanup_interval)
    {:ok, nil}
  end

  @impl true
  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, @cleanup_interval)
    maybe_clean_up()
    {:noreply, state}
  end

  @impl true
  def handle_info(_, state) do
    {:noreply, state}
  end

  defp current_time_s do
    DateTime.utc_now() |> DateTime.to_unix()
  end

  defp maybe_clean_up do
    :ets.tab2list(__MODULE__)
    |> Enum.filter(fn {_, _, last_access_time, _} ->
      current_time_s() - last_access_time >= @stale_time
    end)
    |> Enum.each(fn {key, clean_up_fn, _, _} ->
      Logger.info(
        "HLS stream not used for more than #{@stale_time} seconds, stop streaming and clean up"
      )

      run_cleanup(clean_up_fn)
      :ets.delete(__MODULE__, key)
    end)
  end

  defp run_cleanup(clean_up_fn) do
    Task.start(fn ->
      try do
        (clean_up_fn || fn -> :ok end).()
      catch
        :exit, _ -> :ok
      end
    end)
  end
end
