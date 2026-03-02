defmodule TProNVR.Repo.Migrations.RenameTracksAndCreateStatistics do
  use Ecto.Migration

  def change do
    # Rename tracks table to ai_analytics_tracks
    rename table(:tracks), to: table(:ai_analytics_tracks)
    
    # Rename indexes
    drop_if_exists index(:tracks, [:instance_id])
    drop_if_exists index(:tracks, [:device_id])
    drop_if_exists index(:tracks, [:tracking_id])
    drop_if_exists index(:tracks, [:object_class])
    drop_if_exists index(:tracks, [:inserted_at])
    drop_if_exists index(:tracks, [:system_datetime])
    
    create index(:ai_analytics_tracks, [:instance_id])
    create index(:ai_analytics_tracks, [:device_id])
    create index(:ai_analytics_tracks, [:tracking_id])
    create index(:ai_analytics_tracks, [:object_class])
    create index(:ai_analytics_tracks, [:inserted_at])
    create index(:ai_analytics_tracks, [:system_datetime])
    
    # Create ai_analytics_statistics table
    create table(:ai_analytics_statistics, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :instance_id, :string, null: false
      add :device_id, references(:devices, type: :binary_id, on_delete: :delete_all)
      
      # Performance metrics
      add :current_framerate, :float
      add :source_framerate, :float
      add :dropped_frames_count, :integer
      add :frames_processed, :integer
      add :input_queue_size, :integer
      add :latency, :float
      
      # Format info
      add :format, :string
      add :resolution, :string
      add :source_resolution, :string
      
      # Timing
      add :start_time, :bigint
      
      # Raw data
      add :raw_data, :map, default: %{}
      
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end
    
    create index(:ai_analytics_statistics, [:instance_id])
    create index(:ai_analytics_statistics, [:device_id])
    create index(:ai_analytics_statistics, [:inserted_at])
  end
end
