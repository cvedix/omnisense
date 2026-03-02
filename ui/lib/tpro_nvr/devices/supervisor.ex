defmodule TProNVR.Devices.Supervisor do
  @moduledoc false

  use Supervisor

  alias TProNVR.Model.Device
  alias TProNVR.Pipelines.Main
  alias TProNVR.Gst.Pipeline, as: GstPipeline

  # Pipeline engine: :gstreamer (recommended for hardware accel) or :membrane
  @default_pipeline_engine :gstreamer

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
    pipeline_engine = get_pipeline_engine()

    # Core children - always started
    children = [
      {TProNVR.DiskMonitor, params},
      {TProNVR.BIF.GeneratorServer, params},
      {TProNVR.Devices.SnapshotUploader, params}
    ]

    # Add pipeline based on engine selection
    children = case pipeline_engine do
      :gstreamer ->
        # GStreamer pipeline with hardware acceleration (recommended)
        [{GstPipeline, device} | children]
      :membrane ->
        # Membrane pipeline (fallback)
        [{Main, params} | children]
      :both ->
        # Both pipelines (for transition/testing)
        [{GstPipeline, device}, {Main, params} | children]
    end

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

  defp get_pipeline_engine do
    Application.get_env(:tpro_nvr, :pipeline_engine, @default_pipeline_engine)
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
        # We terminate the pipeline first to allow it to do cleanup.
        # Without this, the pipeline is killed directly.
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
    pipeline_engine = get_pipeline_engine()
    
    case pipeline_engine do
      :gstreamer ->
        # Stop GStreamer pipeline
        try do
          GstPipeline.stop(device.id)
        rescue
          _ -> :ok
        end
      :membrane ->
        # Stop Membrane pipeline
        device
        |> TProNVR.Utils.pipeline_name()
        |> Process.whereis()
        |> Membrane.Pipeline.terminate(force?: true, timeout: :timer.seconds(10))
      :both ->
        # Stop both
        try do
          GstPipeline.stop(device.id)
        rescue
          _ -> :ok
        end
        device
        |> TProNVR.Utils.pipeline_name()
        |> Process.whereis()
        |> Membrane.Pipeline.terminate(force?: true, timeout: :timer.seconds(10))
    end
  end

  defp supervisor_name(device), do: :"#{device.id}"
end
