defmodule TProNVR.Repo.Migrations.CreateTracksTable do
  use Ecto.Migration

  def change do
    create table(:tracks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :instance_id, :string, null: false
      add :device_id, references(:devices, type: :binary_id, on_delete: :delete_all)
      
      # Track identification
      add :tracking_id, :string, null: false
      add :object_class, :string
      
      # Detection data
      add :detection_confidence, :float
      add :age_ms, :integer
      add :is_moving, :integer
      add :event_timestamp_ms, :bigint
      
      # Location (bounding box normalized 0-1)
      add :location_x, :float
      add :location_y, :float
      add :location_width, :float
      add :location_height, :float
      
      # Centroid (calculated from location)
      add :centroid_x, :float
      add :centroid_y, :float
      
      # Related events
      add :events, {:array, :string}, default: []
      
      # Timestamps from source
      add :system_datetime, :utc_datetime_usec
      add :system_timestamp, :bigint
      
      # Raw JSON for reference
      add :raw_data, :map, default: %{}
      
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end
    
    # Indexes for common queries
    create index(:tracks, [:instance_id])
    create index(:tracks, [:device_id])
    create index(:tracks, [:tracking_id])
    create index(:tracks, [:object_class])
    create index(:tracks, [:inserted_at])
    create index(:tracks, [:system_datetime])
  end
end
