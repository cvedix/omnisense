defmodule TProNVR.Repo.Migrations.AddAiEventsCompositeIndexes do
  use Ecto.Migration

  @doc """
  Adds composite indexes to optimize queries used in AiEventsLive.
  These indexes target the GROUP BY + ORDER BY patterns and JOIN conditions
  in the load_events function.
  """

  def change do
    # === Crops table ===
    # Optimizes the main crop_tracking_query: GROUP BY ref_tracking_id with device_id filter
    create_if_not_exists index(:ai_analytics_crops, [:device_id, :ref_tracking_id, :inserted_at],
      name: :ai_analytics_crops_device_tracking_inserted_idx)

    # Optimizes build_grouped_events crop query: WHERE ref_tracking_id IN (...) ORDER BY inserted_at
    create_if_not_exists index(:ai_analytics_crops, [:ref_tracking_id, :inserted_at],
      name: :ai_analytics_crops_tracking_inserted_idx)

    # === AI Analytics Events table ===
    # Optimizes cropless_query: GROUP BY ref_tracking_id with device_id + event_type filters
    create_if_not_exists index(:ai_analytics_events, [:device_id, :ref_tracking_id, :event_type, :inserted_at],
      name: :ai_analytics_events_device_tracking_type_inserted_idx)

    # Optimizes event_type filter join: WHERE ref_tracking_id = ? AND event_type = ?
    create_if_not_exists index(:ai_analytics_events, [:ref_tracking_id, :event_type],
      name: :ai_analytics_events_tracking_event_type_idx)

    # Optimizes build_grouped_events: WHERE ref_tracking_id IN (...) with area_name filter
    create_if_not_exists index(:ai_analytics_events, [:ref_tracking_id, :area_name, :inserted_at],
      name: :ai_analytics_events_tracking_area_inserted_idx)

    # === Tracks table ===
    # Optimizes object_type filter join: WHERE tracking_id = ? AND object_class = ?
    create_if_not_exists index(:ai_analytics_tracks, [:tracking_id, :object_class],
      name: :ai_analytics_tracks_tracking_object_class_idx)

    # === Attributes table ===
    # Optimizes attribute filter join: WHERE ref_tracking_id = ? AND name = ? AND value = ?
    create_if_not_exists index(:ai_analytics_attributes, [:ref_tracking_id, :name, :value],
      name: :ai_analytics_attributes_tracking_name_value_idx,
      where: "value IS NOT NULL")

    # Optimizes build_grouped_events attribute query
    create_if_not_exists index(:ai_analytics_attributes, [:ref_tracking_id, :name],
      name: :ai_analytics_attributes_tracking_name_idx)
  end
end
