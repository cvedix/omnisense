defmodule TProNVR.CVEDIX.Analytics do
  @moduledoc """
  CVEDIX-RT Analytics configuration for all plugin types.
  Supports Areas (Intrusion, Loitering, Crowding, etc.) and Lines (Crossing, Counting, Tailgating).
  """

  alias TProNVR.CVEDIX.Client

  # ============================================================================
  # AREA TYPES
  # ============================================================================

  @doc """
  Create an intrusion detection area.
  Triggers alarm when object enters the zone.
  """
  def create_intrusion_area(instance_id, params) do
    body = build_area_body(params, "AreaIntrusion")
    Client.post("/v1/securt/instance/#{instance_id}/area/intrusion", body)
  end

  @doc """
  Create an area enter/exit (crossing) area.
  Detects when objects enter or exit the area without triggering intrusion alarm.
  """
  def create_crossing_area(instance_id, params) do
    body = build_area_body(params)
    Client.post("/v1/securt/instance/#{instance_id}/area/crossing", body)
  end

  @doc """
  Create a loitering detection area.
  Triggers alarm when object stays in area for too long.

  Extra params:
    - `:seconds` - Alarm after x seconds of loitering (default: 120)
  """
  def create_loitering_area(instance_id, params) do
    body = build_area_body(params)
    |> Map.put(:seconds, Map.get(params, :seconds, 120))
    Client.post("/v1/securt/instance/#{instance_id}/area/loitering", body)
  end

  @doc """
  Create a crowding detection area.
  Triggers alarm when too many objects are in the area.

  Extra params:
    - `:object_count` - Alarm on crowd of x or more entities (default: 5)
    - `:seconds` - Alarm after x seconds of crowding (default: 0)
  """
  def create_crowding_area(instance_id, params) do
    body = build_area_body(params)
    |> Map.put(:objectCount, Map.get(params, :object_count, 5))
    |> Map.put(:seconds, Map.get(params, :seconds, 0))
    Client.post("/v1/securt/instance/#{instance_id}/area/crowding", body)
  end

  @doc """
  Create an occupancy area for measuring fill rate.
  """
  def create_occupancy_area(instance_id, params) do
    body = build_area_body(params)
    Client.post("/v1/securt/instance/#{instance_id}/area/occupancy", body)
  end

  @doc """
  Create a crowd estimation area.
  """
  def create_crowd_estimation_area(instance_id, params) do
    body = build_area_body(params)
    Client.post("/v1/securt/instance/#{instance_id}/area/crowd_estimation", body)
  end

  @doc """
  Create a dwelling area.
  Detects when objects stop/dwell in an area.

  Extra params:
    - `:seconds` - Minimum dwell time to trigger (default: 60)
  """
  def create_dwelling_area(instance_id, params) do
    body = build_area_body(params)
    |> Map.put(:seconds, Map.get(params, :seconds, 60))
    Client.post("/v1/securt/instance/#{instance_id}/area/dwelling", body)
  end

  @doc """
  Create an armed person detection area.
  """
  def create_armed_person_area(instance_id, params) do
    body = build_area_body(params)
    Client.post("/v1/securt/instance/#{instance_id}/area/armed_person", body)
  end

  @doc """
  Create a fallen person detection area.
  """
  def create_fallen_person_area(instance_id, params) do
    body = build_area_body(params)
    Client.post("/v1/securt/instance/#{instance_id}/area/fallen_person", body)
  end

  @doc """
  Create an object left behind detection area.

  Extra params:
    - `:seconds` - Alarm if object left for more than x seconds (default: 30)
  """
  def create_object_left_area(instance_id, params) do
    body = build_area_body(params)
    |> Map.put(:seconds, Map.get(params, :seconds, 30))
    Client.post("/v1/securt/instance/#{instance_id}/area/object_left", body)
  end

  @doc """
  Create an object removed/guarding area.

  Extra params:
    - `:seconds` - Alarm if object missing for more than x seconds (default: 4)
  """
  def create_object_removed_area(instance_id, params) do
    body = build_area_body(params)
    |> Map.put(:seconds, Map.get(params, :seconds, 4))
    Client.post("/v1/securt/instance/#{instance_id}/area/object_removed", body)
  end

  # ============================================================================
  # LINE TYPES
  # ============================================================================

  @doc """
  Create a line crossing detector.
  Triggers when objects cross the line.
  """
  def create_crossing_line(instance_id, params) do
    body = build_line_body(params)
    Client.post("/v1/securt/instance/#{instance_id}/line/crossing", body)
  end

  @doc """
  Create a line counting detector.
  Counts objects crossing the line by direction.

  Extra params:
    - `:direction` - "Up", "Down", or "Both" (default: "Both")
  """
  def create_counting_line(instance_id, params) do
    body = build_line_body(params)
    |> Map.put(:direction, Map.get(params, :direction, "Both"))
    Client.post("/v1/securt/instance/#{instance_id}/line/counting", body)
  end

  @doc """
  Create a tailgating detector.
  Detects when multiple people cross together (security violation).

  Extra params:
    - `:seconds` - Time window for tailgating detection (default: 3)
  """
  def create_tailgating_line(instance_id, params) do
    body = build_line_body(params)
    |> Map.put(:seconds, Map.get(params, :seconds, 3))
    Client.post("/v1/securt/instance/#{instance_id}/line/tailgating", body)
  end

  # ============================================================================
  # MANAGEMENT APIs
  # ============================================================================

  @doc """
  Get all areas for an instance.
  """
  def list_areas(instance_id) do
    Client.get("/v1/securt/instance/#{instance_id}/areas")
  end

  @doc """
  Get all lines for an instance.
  """
  def list_lines(instance_id) do
    Client.get("/v1/securt/instance/#{instance_id}/lines")
  end

  @doc """
  Delete a specific area.
  """
  def delete_area(instance_id, area_id) do
    Client.delete("/v1/securt/instance/#{instance_id}/area/#{area_id}")
  end

  @doc """
  Delete a specific line.
  """
  def delete_line(instance_id, line_id) do
    Client.delete("/v1/securt/instance/#{instance_id}/line/#{line_id}")
  end

  @doc """
  Update an existing area by deleting and recreating it.
  CVEDIX API does not support PUT for area updates, so we use DELETE + POST.
  """
  def update_area(instance_id, area_type, area_id, params) do
    require Logger
    Logger.info("[Analytics] Updating area via DELETE + POST: #{area_type}/#{area_id}")
    
    # First delete the existing area
    case Client.delete("/v1/securt/instance/#{instance_id}/area/#{area_id}") do
      :ok ->
        Logger.info("[Analytics] DELETE successful, creating new area")
        # Then create new area with updated params
        body = build_area_body(params, params[:type])
        Logger.info("[Analytics] POST body: #{inspect(body)}")
        result = Client.post("/v1/securt/instance/#{instance_id}/area/#{area_type}", body)
        Logger.info("[Analytics] POST result: #{inspect(result)}")
        result
        
      {:ok, _} ->
        Logger.info("[Analytics] DELETE successful (with response), creating new area")
        body = build_area_body(params, params[:type])
        Logger.info("[Analytics] POST body: #{inspect(body)}")
        result = Client.post("/v1/securt/instance/#{instance_id}/area/#{area_type}", body)
        Logger.info("[Analytics] POST result: #{inspect(result)}")
        result
        
      {:error, reason} = error ->
        Logger.error("[Analytics] DELETE failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Update only the coordinates of an existing area.
  """
  def update_area_coordinates(instance_id, area_type, area_id, coordinates) do
    Client.put("/v1/securt/instance/#{instance_id}/area/#{area_type}/#{area_id}", %{coordinates: coordinates})
  end

  @doc """
  Update an existing line by deleting and recreating it.
  CVEDIX API does not support PUT for line updates, so we use DELETE + POST.
  """
  def update_line(instance_id, line_type, line_id, params) do
    require Logger
    Logger.info("[Analytics] Updating line via DELETE + POST: #{line_type}/#{line_id}")
    
    # First delete the existing line
    case Client.delete("/v1/securt/instance/#{instance_id}/line/#{line_id}") do
      :ok ->
        Logger.info("[Analytics] DELETE successful, creating new line")
        body = build_line_body(params)
        Logger.info("[Analytics] POST body: #{inspect(body)}")
        result = Client.post("/v1/securt/instance/#{instance_id}/line/#{line_type}", body)
        Logger.info("[Analytics] POST result: #{inspect(result)}")
        result
        
      {:ok, _} ->
        Logger.info("[Analytics] DELETE successful (with response), creating new line")
        body = build_line_body(params)
        Logger.info("[Analytics] POST body: #{inspect(body)}")
        result = Client.post("/v1/securt/instance/#{instance_id}/line/#{line_type}", body)
        Logger.info("[Analytics] POST result: #{inspect(result)}")
        result
        
      {:error, reason} = error ->
        Logger.error("[Analytics] DELETE failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Update only the coordinates of an existing line.
  """
  def update_line_coordinates(instance_id, line_type, line_id, coordinates) do
    Client.put("/v1/securt/instance/#{instance_id}/line/#{line_type}/#{line_id}", %{coordinates: coordinates})
  end

  @doc """
  Delete all areas for an instance.
  """
  def delete_all_areas(instance_id) do
    Client.delete("/v1/securt/instance/#{instance_id}/areas")
  end

  @doc """
  Delete all lines for an instance.
  """
  def delete_all_lines(instance_id) do
    Client.delete("/v1/securt/instance/#{instance_id}/lines")
  end

  @doc """
  Get all analytics entities (areas + lines).
  """
  def get_analytics_entities(instance_id) do
    Client.get("/v1/securt/instance/#{instance_id}/analytics_entities")
  end

  # ============================================================================
  # HELPER: Create analytics by type
  # ============================================================================

  @area_types %{
    "intrusion" => &__MODULE__.create_intrusion_area/2,
    "crossing" => &__MODULE__.create_crossing_area/2,
    "loitering" => &__MODULE__.create_loitering_area/2,
    "crowding" => &__MODULE__.create_crowding_area/2,
    "occupancy" => &__MODULE__.create_occupancy_area/2,
    "crowd_estimation" => &__MODULE__.create_crowd_estimation_area/2,
    "dwelling" => &__MODULE__.create_dwelling_area/2,
    "armed_person" => &__MODULE__.create_armed_person_area/2,
    "fallen_person" => &__MODULE__.create_fallen_person_area/2,
    "object_left" => &__MODULE__.create_object_left_area/2,
    "object_removed" => &__MODULE__.create_object_removed_area/2
  }

  @line_types %{
    "crossing" => &__MODULE__.create_crossing_line/2,
    "counting" => &__MODULE__.create_counting_line/2,
    "tailgating" => &__MODULE__.create_tailgating_line/2
  }

  @doc """
  Create an area by type name.
  """
  def create_area(instance_id, area_type, params) when is_binary(area_type) do
    case Map.get(@area_types, area_type) do
      nil -> {:error, {:unknown_area_type, area_type}}
      func -> func.(instance_id, params)
    end
  end

  @doc """
  Create a line by type name.
  """
  def create_line(instance_id, line_type, params) when is_binary(line_type) do
    case Map.get(@line_types, line_type) do
      nil -> {:error, {:unknown_line_type, line_type}}
      func -> func.(instance_id, params)
    end
  end

  @doc """
  Get all supported area types.
  """
  def area_types, do: Map.keys(@area_types)

  @doc """
  Get all supported line types.
  """
  def line_types, do: Map.keys(@line_types)

  # ============================================================================
  # PRIVATE HELPERS
  # ============================================================================

  defp build_area_body(params, area_type \\ nil) do
    # Use color as-is from params (already normalized to 0-1 integers by caller)
    color = Map.get(params, :color, [1, 0, 0, 1])

    body = %{
      name: Map.fetch!(params, :name),
      coordinates: Map.fetch!(params, :coordinates),
      classes: Map.get(params, :classes, ["Person"]),
      color: color
    }

    # Add type - from params first, then from area_type argument
    type_value = Map.get(params, :type) || area_type
    if type_value do
      Map.put(body, :type, type_value)
    else
      body
    end
  end

  defp build_line_body(params) do
    body = %{
      name: Map.fetch!(params, :name),
      coordinates: Map.fetch!(params, :coordinates),
      classes: Map.get(params, :classes, ["Person"]),
      color: Map.get(params, :color, [0, 255, 0, 255])
    }
    
    # Add type from params if provided
    case Map.get(params, :type) do
      nil -> body
      type_value -> Map.put(body, :type, type_value)
    end
  end
end
