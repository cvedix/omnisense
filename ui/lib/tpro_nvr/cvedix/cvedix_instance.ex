defmodule TProNVR.CVEDIX.CvedixInstance do
  @moduledoc """
  Ecto schema for CVEDIX-RT instance linked to a device.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias TProNVR.Model.Device
  alias TProNVR.CVEDIX.IntrusionArea

  @statuses ~w(stopped running error loading)

  @foreign_key_type :binary_id

  schema "cvedix_instances" do
    field :instance_id, Ecto.UUID
    field :name, :string
    field :status, :string, default: "stopped"
    field :detector_mode, :string, default: "SmartDetection"
    field :detection_sensitivity, :string, default: "Medium"
    field :movement_sensitivity, :string, default: "Medium"
    field :frame_rate_limit, :integer, default: 10
    field :enabled, :boolean, default: true
    field :config, :map, default: %{}

    belongs_to :device, Device
    has_many :intrusion_areas, IntrusionArea, foreign_key: :cvedix_instance_id

    timestamps()
  end

  @required_fields [:device_id, :instance_id, :name]
  @optional_fields [
    :status,
    :detector_mode,
    :detection_sensitivity,
    :movement_sensitivity,
    :frame_rate_limit,
    :enabled,
    :config
  ]

  def changeset(instance, attrs) do
    instance
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:detector_mode, ["SmartDetection", "FullFrame"])
    |> validate_inclusion(:detection_sensitivity, ["Low", "Medium", "High"])
    |> validate_inclusion(:movement_sensitivity, ["Low", "Medium", "High"])
    |> validate_number(:frame_rate_limit, greater_than: 0, less_than_or_equal_to: 30)
    |> unique_constraint(:device_id)
    |> unique_constraint(:instance_id)
    |> foreign_key_constraint(:device_id)
  end

  def update_status_changeset(instance, status) do
    instance
    |> cast(%{status: status}, [:status])
    |> validate_inclusion(:status, @statuses)
  end

  @doc """
  Changeset for updating instance configuration settings.
  """
  def update_config_changeset(instance, attrs) do
    instance
    |> cast(attrs, [
      :detector_mode,
      :detection_sensitivity,
      :movement_sensitivity,
      :frame_rate_limit,
      :enabled,
      :config
    ])
    |> validate_inclusion(:detector_mode, ["SmartDetection", "FullFrame"])
    |> validate_inclusion(:detection_sensitivity, ["Low", "Medium", "High"])
    |> validate_inclusion(:movement_sensitivity, ["Low", "Medium", "High"])
    |> validate_number(:frame_rate_limit, greater_than: 0, less_than_or_equal_to: 30)
  end
end
