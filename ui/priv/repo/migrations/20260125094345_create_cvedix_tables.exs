defmodule TProNVR.Repo.Migrations.CreateCvediaTables do
  use Ecto.Migration

  def change do
    # CVEDIX-RT instances linked to devices
    create table(:cvedix_instances) do
      add :device_id, references(:devices, type: :binary_id, on_delete: :delete_all), null: false
      add :instance_id, :uuid, null: false
      add :name, :string, null: false
      add :status, :string, default: "stopped"
      add :detector_mode, :string, default: "SmartDetection"
      add :detection_sensitivity, :string, default: "Medium"
      add :movement_sensitivity, :string, default: "Medium"
      add :frame_rate_limit, :integer, default: 10
      add :enabled, :boolean, default: true
      add :config, :map, default: %{}

      timestamps()
    end

    create unique_index(:cvedix_instances, [:device_id])
    create unique_index(:cvedix_instances, [:instance_id])

    # Intrusion detection areas
    create table(:intrusion_areas) do
      add :cvedix_instance_id, references(:cvedix_instances, on_delete: :delete_all), null: false
      add :area_id, :uuid, null: false
      add :name, :string, null: false
      add :coordinates, {:array, :map}, null: false
      add :classes, {:array, :string}, default: ["Person"]
      add :color, {:array, :integer}, default: [255, 0, 0, 200]
      add :enabled, :boolean, default: true

      timestamps()
    end

    create unique_index(:intrusion_areas, [:area_id])
    create index(:intrusion_areas, [:cvedix_instance_id])
  end
end
