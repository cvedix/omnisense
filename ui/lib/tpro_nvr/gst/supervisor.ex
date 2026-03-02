defmodule TProNVR.Gst.Supervisor do
  @moduledoc """
  Supervisor for GStreamer pipelines and recording watchers.
  Manages lifecycle of all streaming pipelines and their associated file watchers.
  """

  use DynamicSupervisor
  require Logger

  alias TProNVR.Gst.{Pipeline, RecordingWatcher}

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start a GStreamer pipeline and recording watcher for the given device.
  """
  def start_pipeline(device) do
    Logger.info("[GstSupervisor] Starting pipeline for device: #{device.id}")
    
    # Start the pipeline
    case DynamicSupervisor.start_child(__MODULE__, {Pipeline, device}) do
      {:ok, pipeline_pid} ->
        # Start the recording watcher
        case start_watcher(device) do
          {:ok, _watcher_pid} ->
            {:ok, pipeline_pid}
          {:error, reason} ->
            Logger.warning("[GstSupervisor] Failed to start watcher: #{inspect(reason)}")
            {:ok, pipeline_pid}
        end
        
      error ->
        error
    end
  end

  @doc """
  Start only the recording watcher for a device.
  Useful when pipeline is already running.
  """
  def start_watcher(device) do
    Logger.info("[GstSupervisor] Starting recording watcher for device: #{device.id}")
    spec = {RecordingWatcher, [device: device]}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  Stop pipeline and watcher for the given device.
  """
  def stop_pipeline(device_id) do
    Logger.info("[GstSupervisor] Stopping pipeline for device: #{device_id}")

    # Stop pipeline
    case Registry.lookup(TProNVR.Gst.Registry, device_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> :ok
    end
    
    # Stop watcher
    stop_watcher(device_id)
    
    :ok
  end

  @doc """
  Stop only the recording watcher for a device.
  """
  def stop_watcher(device_id) do
    case Registry.lookup(TProNVR.Gst.Registry, {:watcher, device_id}) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Check if a pipeline is running for the device.
  """
  def pipeline_running?(device_id) do
    case Registry.lookup(TProNVR.Gst.Registry, device_id) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  @doc """
  Check if a watcher is running for the device.
  """
  def watcher_running?(device_id) do
    case Registry.lookup(TProNVR.Gst.Registry, {:watcher, device_id}) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  @doc """
  List all running pipelines.
  """
  def list_pipelines do
    Registry.select(TProNVR.Gst.Registry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
  end
end

