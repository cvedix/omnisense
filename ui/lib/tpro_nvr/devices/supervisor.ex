defmodule TProNVR.Devices.Supervisor do
  @moduledoc false

  use Supervisor

  alias TProNVR.Model.Device
  alias TProNVR.Pipelines.Main

  @spec start(Device.t()) :: DynamicSupervisor.on_start_child()
  def start(device) do
    spec = %{
      id: __MODULE__,
      start: {Supervisor, :start_link, [__MODULE__, device, [name: supervisor_name(device)]]},
      restart: :transient
    }

    DynamicSupervisor.start_child(TProNVR.PipelineSupervisor, spec)
  end

  @impl true
  def init(device) do
    params = [device: device]

    # Core children - always started
    children = [
      {TProNVR.DiskMonitor, params},
      {TProNVR.BIF.GeneratorServer, params},
      {TProNVR.Devices.SnapshotUploader, params},
      # Membrane pipeline (pure Elixir)
      {Main, params}
    ]

    children =
      if device.settings.enable_lpr && Device.http_url(device) do
        children ++ [{TProNVR.Devices.LPREventPuller, params}]
      else
        children
      end

    children =
      if device.settings.enable_face_detection do
        children ++ [{TProNVR.Devices.FaceDetectionServer, params}]
      else
        children
      end

    children =
      case :os.type() do
        {:unix, _name} -> children ++ [{TProNVR.UnixSocketServer, params}]
        _other -> children
      end

    Supervisor.init(children, strategy: :rest_for_one, max_restarts: 10_000)
  end

  @spec stop(Device.t()) :: :ok
  def stop(device) do
    device
    |> supervisor_name()
    |> Process.whereis()
    |> case do
      nil ->
        :ok

      pid ->
        # Terminate the pipeline first to allow cleanup
        terminate_pipeline(device)
        Supervisor.stop(pid)
    end
  end

  @spec restart(Device.t()) :: DynamicSupervisor.on_start_child()
  def restart(device) do
    stop(device)
    start(device)
  end

  defp terminate_pipeline(device) do
    case Process.whereis(TProNVR.Utils.pipeline_name(device)) do
      nil -> :ok
      pid -> Membrane.Pipeline.terminate(pid, force?: true, timeout: :timer.seconds(10))
    end
  end

  defp supervisor_name(device), do: :"#{device.id}"
end
