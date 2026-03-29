defmodule TProNVR.EMaps do
  @moduledoc """
  Context for managing uploaded floor plans / E-Maps.
  Uses a local JSON file to persist metadata without requiring database migrations.
  """

  require Logger

  @emaps_json_file Path.join(:code.priv_dir(:tpro_nvr), "static/uploads/emaps.json")

  @doc """
  Lists all saved maps.
  Returns a list of maps, e.g. `[%{"id" => "uuid", "name" => "Floor 1", "filename" => "floor_1.png"}]`.
  """
  def list_maps do
    case File.read(@emaps_json_file) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, maps} when is_list(maps) -> maps
          _ -> []
        end
      _ ->
        []
    end
  end

  @doc """
  Gets a specific map by ID.
  """
  def get_map(id) do
    Enum.find(list_maps(), fn map -> map["id"] == id end)
  end

  @doc """
  Adds a new map and persists it to the JSON file.
  """
  def create_map(name, filename) do
    new_map = %{
      "id" => Ecto.UUID.generate(),
      "name" => name,
      "filename" => filename,
      "created_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    maps = list_maps() ++ [new_map]
    save_maps(maps)

    {:ok, new_map}
  end

  @doc """
  Deletes a map by its ID and removes the associated image file if possible.
  """
  def delete_map(id) do
    maps = list_maps()
    map_to_delete = Enum.find(maps, fn m -> m["id"] == id end)

    if map_to_delete do
      # Remove from list
      updated_maps = Enum.reject(maps, fn m -> m["id"] == id end)
      save_maps(updated_maps)

      # Attempt to delete the file
      filepath = Path.join(:code.priv_dir(:tpro_nvr), "static/uploads/#{map_to_delete["filename"]}")
      _ = File.rm(filepath)

      {:ok, map_to_delete}
    else
      {:error, :not_found}
    end
  end

  defp save_maps(maps) do
    # Ensure directory exists
    Path.dirname(@emaps_json_file) |> File.mkdir_p!()

    json = Jason.encode!(maps, pretty: true)
    File.write!(@emaps_json_file, json)
  end
end
