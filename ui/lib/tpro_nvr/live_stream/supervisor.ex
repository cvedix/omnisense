defmodule TProNVR.LiveStream.Supervisor do
  @moduledoc """
  Supervisor for live streaming components.
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {Registry, keys: :unique, name: TProNVR.LiveStream.Registry},
      {Registry, keys: :unique, name: TProNVR.LiveStream.WatcherRegistry},
      {DynamicSupervisor, name: TProNVR.LiveStream.BufferSupervisor, strategy: :one_for_one},
      {DynamicSupervisor, name: TProNVR.LiveStream.WatcherSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  @doc """
  Start a frame buffer for a device.
  """
  def start_buffer(device_id) do
    DynamicSupervisor.start_child(
      TProNVR.LiveStream.BufferSupervisor,
      {TProNVR.LiveStream.FrameBuffer, device_id: device_id}
    )
  end

  @doc """
  Stop a frame buffer for a device.
  """
  def stop_buffer(device_id) do
    case Registry.lookup(TProNVR.LiveStream.Registry, device_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(TProNVR.LiveStream.BufferSupervisor, pid)
      [] -> :ok
    end
  end

  @doc """
  Start HLS watcher for a device to enable MSE streaming.
  """
  def start_watcher(device_id) do
    DynamicSupervisor.start_child(
      TProNVR.LiveStream.WatcherSupervisor,
      {TProNVR.LiveStream.HLSWatcher, device_id: device_id}
    )
  end

  @doc """
  Stop HLS watcher for a device.
  """
  def stop_watcher(device_id) do
    TProNVR.LiveStream.HLSWatcher.stop(device_id)
  end

  @doc """
  Start all streaming components for a device.
  """
  def start_streaming(device_id) do
    start_buffer(device_id)
    start_watcher(device_id)
  end

  @doc """
  Stop all streaming components for a device.
  """
  def stop_streaming(device_id) do
    stop_watcher(device_id)
    stop_buffer(device_id)
  end
end
