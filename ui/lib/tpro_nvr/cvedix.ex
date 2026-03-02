defmodule TProNVR.CVEDIX do
  @moduledoc """
  Context module for CVEDIX-RT integration.
  Provides high-level API for video analytics including Intrusion Detection.
  """

  import Ecto.Query
  require Logger

  alias TProNVR.Repo
  alias TProNVR.CVEDIX.{Client, Instance, Intrusion, EventConsumer, CvedixInstance, IntrusionArea, SSEConsumer, SSEAutoStarter}
  alias TProNVR.Devices

  # ============================================================================
  # Instance Management
  # ============================================================================

  def setup_intrusion_detection(device_id, opts \\ []) do
    # Check if instance already exists (idempotent)
    case get_instance_by_device(device_id) do
      {:ok, existing_instance} ->
        Logger.info("CVEDIX instance already exists for device #{device_id}")
        {:ok, existing_instance}

      {:error, :instance_not_found} ->
        create_new_instance(device_id, opts)
    end
  end

  defp create_new_instance(device_id, opts) do
    with {:ok, device} <- get_device(device_id),
         {:ok, cvedix_result} <- Instance.create(device, opts),
         {:ok, db_instance} <- save_instance(device, cvedix_result, opts),
         :ok <- Instance.load(cvedix_result.id),
         {:ok, _} <- update_instance_status(db_instance, "loading"),
         :ok <- Instance.start(cvedix_result.id),
         {:ok, db_instance} <- update_instance_status(db_instance, "running"),
         :ok <- EventConsumer.subscribe(cvedix_result.id) do
      # Auto-start SSE consumer for the new running instance
      SSEAutoStarter.start_for_instance(cvedix_result.id, device_id)
      {:ok, db_instance}
    else
      {:error, reason} = error ->
        Logger.error("Failed to setup intrusion detection: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Stop and cleanup CVEDIX instance for a device.
  """
  def stop_intrusion_detection(device_id) do
    case get_instance_by_device(device_id) do
      {:ok, db_instance} ->
        # Stop SSE consumer first
        SSEConsumer.stop_consumer(db_instance.instance_id)
        EventConsumer.unsubscribe(db_instance.instance_id)
        Instance.stop(db_instance.instance_id)
        Instance.unload(db_instance.instance_id)
        Instance.delete(db_instance.instance_id)
        delete_instance(db_instance)

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Get CVEDIX instance for a device.
  """
  def get_instance(device_id) do
    get_instance_by_device(device_id)
  end

  @doc """
  List all CVEDIX instances.
  """
  def list_instances do
    CvedixInstance
    |> preload(:intrusion_areas)
    |> Repo.all()
  end

  @doc """
  Sync local instance status with CVEDIX-RT.
  """
  def sync_instance_status(device_id) do
    with {:ok, db_instance} <- get_instance_by_device(device_id),
         {:ok, remote_instance} <- Instance.get(db_instance.instance_id) do
      status = determine_status(remote_instance)
      update_instance_status(db_instance, status)
    end
  end

  # ============================================================================
  # Intrusion Zone Management
  # ============================================================================

  @doc """
  Add an intrusion zone to the device's CVEDIX instance.
  """
  def add_intrusion_zone(device_id, zone_params) do
    with {:ok, db_instance} <- get_instance_by_device(device_id),
         {:ok, %{"areaId" => area_id}} <- Intrusion.create_area(db_instance.instance_id, zone_params),
         {:ok, db_area} <- save_intrusion_area(db_instance, area_id, zone_params) do
      {:ok, db_area}
    end
  end

  @doc """
  Remove an intrusion zone.
  """
  def remove_intrusion_zone(device_id, area_id) do
    with {:ok, db_instance} <- get_instance_by_device(device_id),
         :ok <- Intrusion.delete_area(db_instance.instance_id, area_id),
         {:ok, _} <- delete_intrusion_area(area_id) do
      :ok
    end
  end

  @doc """
  Get all intrusion zones for a device.
  """
  def list_intrusion_zones(device_id) do
    case get_instance_by_device(device_id) do
      {:ok, db_instance} ->
        areas =
          IntrusionArea
          |> where([a], a.cvedix_instance_id == ^db_instance.id)
          |> where([a], a.enabled == true)
          |> Repo.all()

        {:ok, areas}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Get current analytics entities (areas and lines) from CVEDIX-RT.
  """
  def get_analytics_entities(device_id) do
    with {:ok, db_instance} <- get_instance_by_device(device_id) do
      Instance.get_analytics_entities(db_instance.instance_id)
    end
  end

  # ============================================================================
  # Instance Configuration Management
  # ============================================================================

  @doc """
  Update instance configuration (detector mode, sensitivities, frame rate).
  Syncs changes to both database and CVEDIX-RT.
  """
  def update_instance_config(device_id, config_params) do
    with {:ok, db_instance} <- get_instance_by_device(device_id) do
      # Update local database
      changeset = CvedixInstance.update_config_changeset(db_instance, config_params)
      
      case Repo.update(changeset) do
        {:ok, updated_instance} ->
          # Sync to CVEDIX-RT
          cvedix_params = %{
            detectorMode: updated_instance.detector_mode,
            detectionSensitivity: updated_instance.detection_sensitivity,
            movementSensitivity: updated_instance.movement_sensitivity,
            frameRateLimit: updated_instance.frame_rate_limit
          }
          
          case Instance.update(updated_instance.instance_id, cvedix_params) do
            :ok -> {:ok, updated_instance}
            {:ok, _} -> {:ok, updated_instance}
            {:error, reason} ->
              Logger.warning("Failed to sync config to CVEDIX-RT: #{inspect(reason)}")
              {:ok, updated_instance}  # Still return ok since DB was updated
          end
          
        {:error, _} = error ->
          error
      end
    end
  end

  @doc """
  Update instance input source (RTSP URL).
  """
  def update_instance_input(device_id, rtsp_url) do
    with {:ok, db_instance} <- get_instance_by_device(device_id) do
      body = %{type: "RTSP", uri: rtsp_url}
      
      case Client.post("/v1/core/instance/#{db_instance.instance_id}/input", body) do
        :ok -> {:ok, db_instance}
        {:ok, _} -> {:ok, db_instance}
        {:error, _} = error -> error
      end
    end
  end

  @doc """
  Get full instance details including configuration and analytics summary.
  """
  def get_instance_details(device_id) do
    with {:ok, db_instance} <- get_instance_by_device(device_id) do
      # Get analytics entities for summary
      analytics = case Instance.get_analytics_entities(db_instance.instance_id) do
        {:ok, entities} -> entities
        _ -> %{}
      end
      
      # Get remote instance status
      remote_status = case Instance.get(db_instance.instance_id) do
        {:ok, remote} -> remote
        _ -> %{}
      end
      
      {:ok, %{
        instance: db_instance,
        remote_status: remote_status,
        analytics: analytics,
        zone_count: count_zones(analytics),
        line_count: count_lines(analytics)
      }}
    end
  end

  defp count_zones(entities) do
    area_keys = ["intrusionAreas", "crossingAreas", "loiteringAreas", "crowdingAreas",
                 "occupancyAreas", "crowdEstimationAreas", "dwellingAreas", 
                 "armedPersonAreas", "fallenPersonAreas", "objectLeftAreas", "objectRemovedAreas"]
    
    Enum.reduce(area_keys, 0, fn key, acc ->
      acc + length(Map.get(entities, key, []))
    end)
  end

  defp count_lines(entities) do
    line_keys = ["crossingLines", "countingLines", "tailgatingLines"]
    
    Enum.reduce(line_keys, 0, fn key, acc ->
      acc + length(Map.get(entities, key, []))
    end)
  end

  # ============================================================================
  # Health & Status
  # ============================================================================

  @doc """
  Check if CVEDIX-RT is available.
  """
  def health_check do
    case Client.get("/v1/core/version") do
      {:ok, %{"engine" => version}} -> {:ok, version}
      {:ok, _} -> {:ok, "connected"}
      {:error, _} = error -> error
    end
  end

  @doc """
  Check if CVEDIX integration is enabled.
  """
  def enabled? do
    Application.get_env(:tpro_nvr, :cvedix, [])[:enabled] == true
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp get_device(device_id) do
    case Devices.get(device_id) do
      nil -> {:error, :device_not_found}
      device -> {:ok, device}
    end
  end

  defp get_instance_by_device(device_id) do
    case Repo.get_by(CvedixInstance, device_id: device_id) do
      nil -> {:error, :instance_not_found}
      instance -> {:ok, Repo.preload(instance, :intrusion_areas)}
    end
  end

  defp save_instance(device, cvedix_result, opts) do
    attrs = %{
      device_id: device.id,
      instance_id: cvedix_result.id,
      name: Keyword.get(opts, :name, device.name || "Instance"),
      status: "stopped",
      detector_mode: Keyword.get(opts, :detector_mode, "SmartDetection"),
      detection_sensitivity: Keyword.get(opts, :detection_sensitivity, "Medium"),
      movement_sensitivity: Keyword.get(opts, :movement_sensitivity, "Medium"),
      frame_rate_limit: Keyword.get(opts, :frame_rate_limit, 10),
      enabled: true
    }

    %CvedixInstance{}
    |> CvedixInstance.changeset(attrs)
    |> Repo.insert()
  end

  defp update_instance_status(db_instance, status) do
    db_instance
    |> CvedixInstance.update_status_changeset(status)
    |> Repo.update()
  end

  defp delete_instance(db_instance) do
    Repo.delete(db_instance)
  end

  defp save_intrusion_area(db_instance, area_id, params) do
    attrs = %{
      cvedix_instance_id: db_instance.id,
      area_id: area_id,
      name: Map.fetch!(params, :name),
      coordinates: Map.fetch!(params, :coordinates),
      classes: Map.get(params, :classes, ["Person"]),
      color: Map.get(params, :color, [255, 0, 0, 200]),
      enabled: true
    }

    %IntrusionArea{}
    |> IntrusionArea.changeset(attrs)
    |> Repo.insert()
  end

  defp delete_intrusion_area(area_id) do
    case Repo.get_by(IntrusionArea, area_id: area_id) do
      nil -> {:error, :area_not_found}
      area -> Repo.delete(area)
    end
  end

  defp determine_status(remote_instance) do
    cond do
      remote_instance["running"] == true -> "running"
      remote_instance["loaded"] == true -> "loading"
      true -> "stopped"
    end
  end
end
