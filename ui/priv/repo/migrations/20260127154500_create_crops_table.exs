defmodule TProNVR.Repo.Migrations.CreateCropsTable do
  use Ecto.Migration

  def change do
    create table(:ai_analytics_crops, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :instance_id, :string, null: false
      add :device_id, references(:devices, type: :binary_id, on_delete: :delete_all)
      
      # Crop identification
      add :ref_tracking_id, :string
      add :ref_event_id, :string
      
      # Detection data
      add :confidence, :float
      add :crop_timestamp_ms, :bigint
      add :event_timestamp_ms, :bigint
      
      # Location (bounding box normalized 0-1)
      add :location_x, :float
      add :location_y, :float
      add :location_width, :float
      add :location_height, :float
      
      # Image data - stored as file path (not base64)
      add :image_path, :string
      
      # Timestamps from source
      add :system_datetime, :utc_datetime_usec
      add :system_timestamp, :bigint
      
      # Raw JSON for reference (without image)
      add :raw_data, :map, default: %{}
      
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end
    
    # Indexes for common queries
    create index(:ai_analytics_crops, [:instance_id])
    create index(:ai_analytics_crops, [:device_id])
    create index(:ai_analytics_crops, [:ref_tracking_id])
    create index(:ai_analytics_crops, [:inserted_at])
    create index(:ai_analytics_crops, [:system_datetime])
  end
end
