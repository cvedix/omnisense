defmodule TProNVR.Repo.Migrations.AddHeatmapFieldsToAnalyticsEvents do
  use Ecto.Migration

  def change do
    alter table("analytics_events") do
      # Centroid coordinates for heatmap visualization
      # These represent the center point of the detected object (normalized 0-1)
      add :centroid_x, :float
      add :centroid_y, :float
      
      # Track path for trajectory visualization
      # Array of {x, y, timestamp} points
      add :track_path, {:array, :map}, default: []
      
      # Frame dimensions for coordinate normalization
      add :frame_width, :integer
      add :frame_height, :integer
    end

    # Index for spatial queries (heatmap aggregation)
    create index("analytics_events", [:centroid_x, :centroid_y])
    create index("analytics_events", [:device_id, :event_time, :centroid_x, :centroid_y])
  end
end
