defmodule TProNVR.CVEDIX.Intrusion do
  @moduledoc """
  Intrusion detection area configuration for CVEDIX-RT.
  """

  alias TProNVR.CVEDIX.Client

  @doc """
  Create an intrusion detection area.

  ## Parameters
    - `instance_id` - CVEDIX instance UUID
    - `params` - Map with:
      - `:name` - Area name (required)
      - `:coordinates` - List of %{x: float, y: float} (required, normalized 0-1)
      - `:classes` - List of object classes (default: ["Person"])
      - `:color` - RGBA color list (default: [255, 0, 0, 200])

  ## Example
      create_area(instance_id, %{
        name: "Restricted Zone",
        coordinates: [
          %{x: 0.1, y: 0.1},
          %{x: 0.1, y: 0.9},
          %{x: 0.9, y: 0.9},
          %{x: 0.9, y: 0.1}
        ],
        classes: ["Person", "Vehicle"]
      })
  """
  def create_area(instance_id, params) do
    body = build_area_body(params)
    Client.post("/v1/securt/instance/#{instance_id}/area/intrusion", body)
  end

  @doc """
  Create an intrusion detection area with a specific ID.
  """
  def create_area_with_id(instance_id, area_id, params) do
    body = build_area_body(params)
    Client.put("/v1/securt/instance/#{instance_id}/area/intrusion/#{area_id}", body)
  end

  @doc """
  Delete an intrusion area.
  """
  def delete_area(instance_id, area_id) do
    Client.delete("/v1/securt/instance/#{instance_id}/area/#{area_id}")
  end

  @doc """
  Delete all areas for an instance.
  """
  def delete_all_areas(instance_id) do
    Client.delete("/v1/securt/instance/#{instance_id}/areas")
  end

  @doc """
  Get all areas for an instance (includes all area types).
  """
  def list_areas(instance_id) do
    case Client.get("/v1/securt/instance/#{instance_id}/areas") do
      {:ok, areas} ->
        intrusion_areas = Map.get(areas, "intrusionAreas", [])
        {:ok, intrusion_areas}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Get all analytics entities including intrusion areas.
  """
  def get_analytics_entities(instance_id) do
    Client.get("/v1/securt/instance/#{instance_id}/analytics_entities")
  end

  @doc """
  Normalize coordinates from pixel values to 0-1 range.

  ## Example
      normalize_coordinates([{100, 100}, {100, 500}, {500, 500}, {500, 100}], 1920, 1080)
  """
  def normalize_coordinates(pixel_coords, width, height) do
    Enum.map(pixel_coords, fn {x, y} ->
      %{x: x / width, y: y / height}
    end)
  end

  @doc """
  Convert normalized coordinates back to pixel values.
  """
  def denormalize_coordinates(normalized_coords, width, height) do
    Enum.map(normalized_coords, fn %{"x" => x, "y" => y} ->
      {round(x * width), round(y * height)}
    end)
  end

  # Private helpers

  defp build_area_body(params) do
    %{
      name: Map.fetch!(params, :name),
      coordinates: Map.fetch!(params, :coordinates),
      classes: Map.get(params, :classes, ["Person"]),
      color: Map.get(params, :color, [255, 0, 0, 200])
    }
  end
end
