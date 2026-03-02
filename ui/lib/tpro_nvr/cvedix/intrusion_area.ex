defmodule TProNVR.CVEDIX.IntrusionArea do
  @moduledoc """
  Ecto schema for intrusion detection areas.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias TProNVR.CVEDIX.CvedixInstance

  @classes ~w(Person Vehicle Animal Unknown)

  schema "intrusion_areas" do
    field :area_id, Ecto.UUID
    field :name, :string
    field :coordinates, {:array, :map}
    field :classes, {:array, :string}, default: ["Person"]
    field :color, {:array, :integer}, default: [255, 0, 0, 200]
    field :enabled, :boolean, default: true

    belongs_to :cvedix_instance, CvedixInstance

    timestamps()
  end

  @required_fields [:cvedix_instance_id, :area_id, :name, :coordinates]
  @optional_fields [:classes, :color, :enabled]

  def changeset(area, attrs) do
    area
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_coordinates()
    |> validate_classes()
    |> validate_color()
    |> unique_constraint(:area_id)
    |> foreign_key_constraint(:cvedix_instance_id)
  end

  defp validate_coordinates(changeset) do
    validate_change(changeset, :coordinates, fn :coordinates, coords ->
      cond do
        length(coords) < 3 ->
          [coordinates: "must have at least 3 points to form a polygon"]

        not Enum.all?(coords, &valid_coordinate?/1) ->
          [coordinates: "each coordinate must have x and y between 0 and 1"]

        true ->
          []
      end
    end)
  end

  defp valid_coordinate?(%{"x" => x, "y" => y}) when is_number(x) and is_number(y) do
    x >= 0 and x <= 1 and y >= 0 and y <= 1
  end

  defp valid_coordinate?(%{x: x, y: y}) when is_number(x) and is_number(y) do
    x >= 0 and x <= 1 and y >= 0 and y <= 1
  end

  defp valid_coordinate?(_), do: false

  defp validate_classes(changeset) do
    validate_change(changeset, :classes, fn :classes, classes ->
      if Enum.all?(classes, &(&1 in @classes)) do
        []
      else
        [classes: "must be one of: #{Enum.join(@classes, ", ")}"]
      end
    end)
  end

  defp validate_color(changeset) do
    validate_change(changeset, :color, fn :color, color ->
      if length(color) == 4 and Enum.all?(color, &(is_integer(&1) and &1 >= 0 and &1 <= 255)) do
        []
      else
        [color: "must be [R, G, B, A] with values 0-255"]
      end
    end)
  end
end
