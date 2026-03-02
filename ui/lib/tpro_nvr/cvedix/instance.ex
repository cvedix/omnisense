defmodule TProNVR.CVEDIX.Instance do
  @moduledoc """
  CVEDIX-RT instance management.
  Handles SecuRT and RTCore instance lifecycle.
  """

  alias TProNVR.CVEDIX.Client

  @doc """
  Create a new SecuRT instance for a device.

  ## Options
    - `:name` - Instance display name (default: device name)
    - `:group` - Instance group (default: "default")
    - `:solution` - Solution ID: "securt", "crowdestimation", "its", "uav" (default: "securt")
    - `:detector_mode` - "SmartDetection" or "Detection" (default: "SmartDetection")
    - `:detection_sensitivity` - "Low", "Medium", "High" (default: "Medium")
    - `:movement_sensitivity` - "Low", "Medium", "High" (default: "Medium")
    - `:frame_rate_limit` - FPS limit, 0 = unlimited (default: 0)
    - `:auto_start` - Auto start after load (default: false)
    - `:auto_restart` - Auto restart on error (default: true)
  """
  def create(device, opts \\ []) do
    # Use device name as default instance name
    name = Keyword.get(opts, :name, device.name || "Instance")

    # IMPORTANT: CVEDIX API requires "name" to appear first in the JSON body.
    # Jason encodes maps alphabetically, putting "autoRestart" before "name" which
    # causes a 400 error. Use ordered key-value pairs to ensure correct ordering.
    body = Jason.OrderedObject.new([
      {"name", name},
      {"group", Keyword.get(opts, :group, "default")},
      {"persistent", true},
      {"sensorModality", "RGB"},
      {"detectorMode", Keyword.get(opts, :detector_mode, "SmartDetection")},
      {"detectionSensitivity", Keyword.get(opts, :detection_sensitivity, "Medium")},
      {"movementSensitivity", Keyword.get(opts, :movement_sensitivity, "Medium")},
      {"autoStart", Keyword.get(opts, :auto_start, false)},
      {"autoRestart", Keyword.get(opts, :auto_restart, true)},
      {"frameRateLimit", Keyword.get(opts, :frame_rate_limit, 0)},
      {"metadataMode", true},
      {"statisticsMode", true},
      {"diagnosticsMode", true},
      {"debugMode", false},
      {"inputOrientation", 0},
      {"inputPixelLimit", 0}
    ])

    case Client.post("/v1/securt/instance", body) do
      {:ok, %{"instanceId" => instance_id}} ->
        # Set input source from device RTSP URL
        with :ok <- set_input(instance_id, device) do
          {:ok, %{id: instance_id, name: name, device_id: device.id}}
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Create a SecuRT instance with a specific ID.
  """
  def create_with_id(instance_id, device, opts \\ []) do
    name = Keyword.get(opts, :name, device.name || "Instance")

    body = %{
      name: name,
      detectorMode: Keyword.get(opts, :detector_mode, "SmartDetection"),
      detectionSensitivity: Keyword.get(opts, :detection_sensitivity, "Medium"),
      movementSensitivity: Keyword.get(opts, :movement_sensitivity, "Medium"),
      sensorModality: "RGB",
      frameRateLimit: Keyword.get(opts, :frame_rate_limit, 10),
      metadataMode: true,
      statisticsMode: true
    }

    case Client.put("/v1/securt/instance/#{instance_id}", body) do
      :ok ->
        with :ok <- set_input(instance_id, device) do
          {:ok, %{id: instance_id, name: name, device_id: device.id}}
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Get instance details.
  """
  def get(instance_id) do
    Client.get("/v1/core/instance/#{instance_id}")
  end

  @doc """
  Get all instances.
  """
  def list do
    case Client.get("/v1/core/instances") do
      {:ok, %{"instances" => instances}} -> {:ok, instances}
      {:error, _} = error -> error
    end
  end

  @doc """
  Update SecuRT instance settings.
  """
  def update(instance_id, params) do
    Client.patch("/v1/securt/instance/#{instance_id}", params)
  end

  @doc """
  Delete an instance.
  """
  def delete(instance_id) do
    Client.delete("/v1/core/instance/#{instance_id}")
  end

  @doc """
  Load instance into memory (required before starting).
  """
  def load(instance_id) do
    Client.post("/v1/core/instance/#{instance_id}/load")
  end

  @doc """
  Unload instance from memory.
  """
  def unload(instance_id) do
    Client.post("/v1/core/instance/#{instance_id}/unload")
  end

  @doc """
  Start processing on an instance.
  """
  def start(instance_id) do
    Client.post("/v1/core/instance/#{instance_id}/start")
  end

  @doc """
  Stop processing on an instance.
  """
  def stop(instance_id) do
    Client.post("/v1/core/instance/#{instance_id}/stop")
  end

  @doc """
  Restart an instance.
  """
  def restart(instance_id) do
    Client.post("/v1/core/instance/#{instance_id}/restart")
  end

  @doc """
  Get instance statistics.
  """
  def get_stats(instance_id) do
    Client.get("/v1/core/instance/#{instance_id}/statistics")
  end

  @doc """
  Get instance configuration.
  """
  def get_config(instance_id) do
    Client.get("/v1/core/instance/#{instance_id}/config")
  end

  @doc """
  Get all analytics entities (areas and lines) for an instance.
  """
  def get_analytics_entities(instance_id) do
    Client.get("/v1/securt/instance/#{instance_id}/analytics_entities")
  end

  @doc """
  Enable HLS output for an instance.
  """
  def enable_hls_output(instance_id, enabled \\ true) do
    Client.post("/v1/core/instance/#{instance_id}/output/hls", %{enabled: enabled})
  end

  @doc """
  Enable RTSP output for an instance.
  """
  def enable_rtsp_output(instance_id, uri, enabled \\ true) do
    Client.post("/v1/core/instance/#{instance_id}/output/rtsp", %{enabled: enabled, uri: uri})
  end

  # Private helpers

  defp set_input(instance_id, device) do
    rtsp_url = build_rtsp_url(device)

    body = %{
      type: "RTSP",
      uri: rtsp_url
    }

    Client.post("/v1/core/instance/#{instance_id}/input", body)
  end

  defp build_rtsp_url(device) do
    # Always use ZLMediaKit RTSP (push is always-on from GStreamer pipeline)
    # ZLMediaKit serves as intermediary for CVEDIX AI Analytics
    zlm_config = Application.get_env(:tpro_nvr, :zlmediakit, [])
    host = zlm_config[:host] || "127.0.0.1"
    port = zlm_config[:rtsp_port] || 8554
    "rtsp://#{host}:#{port}/live/#{device.id}"
  end
end
