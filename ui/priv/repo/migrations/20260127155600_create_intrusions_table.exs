defmodule TProNVR.Repo.Migrations.CreateIntrusionsTable do
  use Ecto.Migration

  def change do
    create table(:ai_analytics_intrusions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :device_id, references(:devices, type: :binary_id, on_delete: :delete_all)
      add :instance_id, :string
      
      # Event references
      add :event_id, :string
      add :ref_tracking_id, :string
      
      # Area info
      add :area_id, :string
      add :area_name, :string
      
      # Detection data
      add :object_class, :string
      add :event_timestamp_ms, :bigint
      
      # Location (bounding box normalized 0-1)
      add :location_x, :float
      add :location_y, :float
      add :location_width, :float
      add :location_height, :float
      
      # Timestamps from source
      add :system_datetime, :utc_datetime_usec
      add :system_timestamp, :bigint
      
      # Raw JSON
      add :raw_data, :map, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:ai_analytics_intrusions, [:device_id])
    create index(:ai_analytics_intrusions, [:instance_id])
    create index(:ai_analytics_intrusions, [:area_id])
    create index(:ai_analytics_intrusions, [:ref_tracking_id])
    create index(:ai_analytics_intrusions, [:inserted_at])
  end
end
