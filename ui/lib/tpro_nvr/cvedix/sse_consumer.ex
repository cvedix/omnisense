defmodule TProNVR.CVEDIX.SSEConsumer do
  @moduledoc """
  GenServer to consume SSE (Server-Sent Events) from CVEDIX-RT API
  and save analytics events to database.

  Connects to: /v1/core/instance/{instance_id}/consume_events_sse
  """

  use GenServer
  require Logger

  alias TProNVR.CVEDIX.{AnalyticsEvent, Track, Statistic, Crop, AIAnalyticsEvent, Attribute, Client}
  alias TProNVR.Repo

  @reconnect_delay 5_000
  @sse_timeout 60_000

  # Client API

  @doc """
  Start the SSE consumer for an instance.
  """
  def start_link({instance_id, device_id}) do
    name = via_tuple(instance_id)
    GenServer.start_link(__MODULE__, {instance_id, device_id}, name: name)
  end

  def start_link(instance_id) when is_binary(instance_id) do
    start_link({instance_id, nil})
  end

  @doc """
  Start consuming SSE events for an instance.
  """
  def start_consumer(instance_id, device_id \\ nil) do
    DynamicSupervisor.start_child(
      TProNVR.CVEDIX.SSESupervisor,
      {__MODULE__, {instance_id, device_id}}
    )
  end

  @doc """
  Stop consuming SSE events for an instance.
  """
  def stop_consumer(instance_id) do
    case Registry.lookup(TProNVR.CVEDIX.SSERegistry, instance_id) do
      [{pid, _}] -> GenServer.stop(pid, :normal)
      [] -> :ok
    end
  end

  @doc """
  Check if SSE consumer is running for an instance.
  """
  def consumer_running?(instance_id) do
    case Registry.lookup(TProNVR.CVEDIX.SSERegistry, instance_id) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  @doc """
  Get the PubSub topic for SSE events.
  """
  def topic(instance_id), do: "cvedix:sse:#{instance_id}"

  # Server callbacks

  @impl true
  def init({instance_id, device_id}) do
    state = %{
      instance_id: instance_id,
      device_id: device_id,
      connection: nil,
      buffer: ""
    }

    # Check if instance exists before connecting
    send(self(), :check_and_connect)

    Logger.info("[SSE Consumer] 🚀 STARTED for instance #{instance_id}, device: #{device_id || "none"}")
    {:ok, state}
  end

  @impl true
  def handle_info(:check_and_connect, state) do
    case check_instance_status(state.instance_id) do
      :running ->
        Logger.info("[SSE Consumer] ✅ Instance #{state.instance_id} is running, connecting SSE...")
        state = connect_sse(state)
        {:noreply, state}
      :stopped ->
        Logger.warning("[SSE Consumer] ⚠️ Instance #{state.instance_id} is stopped, stopping SSE consumer")
        {:stop, :normal, state}
      :not_found ->
        Logger.warning("[SSE Consumer] ⚠️ Instance #{state.instance_id} not found, stopping SSE consumer")
        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_info(:connect, state) do
    state = connect_sse(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:sse_data, data}, state) do
    state = process_sse_data(data, state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:reconnect, state) do
    # Check instance status before reconnecting
    case check_instance_status(state.instance_id) do
      :running ->
        Logger.info("[SSE Consumer] 🔄 Reconnecting SSE for instance #{state.instance_id}")
        state = connect_sse(state)
        {:noreply, state}
      status ->
        Logger.warning("[SSE Consumer] ⚠️ Instance #{state.instance_id} is #{status}, stopping SSE consumer")
        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    Logger.warning("SSE connection down for instance #{state.instance_id}: #{inspect(reason)}")
    schedule_reconnect()
    {:noreply, %{state | connection: nil}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("SSE Consumer received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("CVEDIX SSE Consumer stopped for instance #{state.instance_id}: #{inspect(reason)}")
    :ok
  end

  # Private helpers

  defp check_instance_status(instance_id) do
    case Client.get("/v1/core/instance/#{instance_id}") do
      {:ok, %{"running" => true}} -> :running
      {:ok, %{"state" => "running"}} -> :running
      {:ok, %{"running" => false}} -> :stopped
      {:ok, %{"state" => state}} when state in ["stopped", "unloaded"] -> :stopped
      {:ok, _} -> :stopped
      {:error, %{status: 404}} -> :not_found
      {:error, _} -> :not_found
    end
  end

  defp connect_sse(state) do
    url = Client.base_url() <> "/v1/core/instance/#{state.instance_id}/consume_events_sse"
    
    Logger.info("[SSE Consumer] 🔌 Connecting to: #{url}")
    
    # Start async HTTP request for SSE
    parent = self()
    
    task = Task.async(fn ->
      stream_sse(url, parent)
    end)
    
    Process.monitor(task.pid)
    
    %{state | connection: task.pid}
  end

  defp stream_sse(url, parent) do
    # Use Finch to stream SSE
    request = Finch.build(:get, url, [{"accept", "text/event-stream"}])
    
    Logger.info("[SSE Consumer] 📡 Starting SSE stream...")
    
    Finch.stream(request, TProNVR.Finch, nil, fn
      {:status, status}, acc ->
        Logger.info("[SSE Consumer] 📊 Status: #{status}")
        acc
        
      {:headers, headers}, acc ->
        Logger.debug("[SSE Consumer] Headers: #{inspect(headers)}")
        acc
        
      {:data, data}, acc ->
        # Log only first 200 chars at debug level to reduce noise
        Logger.debug("[SSE Consumer] 📥 RAW DATA: #{String.slice(data, 0, 200)}...")
        send(parent, {:sse_data, data})
        acc
    end, receive_timeout: @sse_timeout)
  rescue
    e ->
      Logger.error("[SSE Consumer] ❌ Connection error: #{inspect(e)}")
      send(parent, :reconnect)
  end

  defp process_sse_data(data, state) do
    # Append to buffer and parse complete events
    buffer = state.buffer <> data
    
    # Try to parse directly if it looks like complete JSON
    {events, remaining_buffer} = parse_sse_events(buffer)
    
    if length(events) > 0 do
      Logger.debug("[SSE Consumer] 📦 Parsed #{length(events)} event(s)")
    end
    
    # Process each event
    Enum.each(events, fn event_data ->
      process_event(event_data, state)
    end)
    
    %{state | buffer: remaining_buffer}
  end

  defp parse_sse_events(buffer) do
    buffer = String.trim(buffer)
    
    cond do
      # Complete JSON array
      String.starts_with?(buffer, "[") and String.ends_with?(buffer, "]") ->
        case Jason.decode(buffer) do
          {:ok, data} when is_list(data) ->
          Logger.debug("[SSE Consumer] ✅ Parsed JSON array with #{length(data)} items")
            {[data], ""}
          {:ok, data} ->
            {[data], ""}
          {:error, _} ->
            # Incomplete, keep in buffer
            {[], buffer}
        end
      
      # Complete JSON object
      String.starts_with?(buffer, "{") and String.ends_with?(buffer, "}") ->
        case Jason.decode(buffer) do
          {:ok, data} ->
            Logger.debug("[SSE Consumer] ✅ Parsed JSON object")
            {[data], ""}
          {:error, _} ->
            {[], buffer}
        end
        
      # SSE format with data: prefix and newlines
      String.contains?(buffer, "\n\n") ->
        lines = String.split(buffer, "\n\n", trim: false)
        {complete_events, remaining} = 
          case lines do
            [] -> {[], ""}
            [single] -> {[], single}
            many -> {Enum.slice(many, 0..-2//1), List.last(many)}
          end
        
        events = 
          complete_events
          |> Enum.map(&parse_sse_line/1)
          |> Enum.reject(&is_nil/1)
        
        {events, remaining}
      
      # Not complete yet, keep buffering
      true ->
        {[], buffer}
    end
  end

  defp parse_sse_line(line) do
    line = String.trim(line)
    
    cond do
      # Standard SSE format: "data: {...}" or "data: [...]"
      String.starts_with?(line, "data:") ->
        json_str = String.trim_leading(line, "data:")
        |> String.trim()
        
        parse_json_data(json_str)
      
      # Raw JSON array (no data: prefix)
      String.starts_with?(line, "[") ->
        parse_json_data(line)
        
      # Raw JSON object (no data: prefix)  
      String.starts_with?(line, "{") ->
        parse_json_data(line)
        
      String.length(line) > 0 ->
        Logger.debug("[SSE Consumer] Skipping non-data line: #{String.slice(line, 0, 50)}")
        nil
        
      true ->
        nil
    end
  end
  
  defp parse_json_data(json_str) do
    case Jason.decode(json_str) do
      {:ok, data} -> 
        event_type = case data do
          [first | _] when is_map(first) -> first["type"]
          %{"type" => t} -> t
          _ -> "unknown"
        end
        Logger.info("[SSE Consumer] ✅ Parsed JSON, type: #{event_type}")
        data
      {:error, reason} -> 
        Logger.warning("[SSE Consumer] ❌ JSON parse error: #{inspect(reason)}")
        nil
    end
  end

  defp process_event(event_data, state) when is_list(event_data) do
    # Handle array of events
    Logger.debug("[SSE Consumer] 📨 Array of #{length(event_data)} events received")
    Enum.each(event_data, fn event -> process_single_event(event, state) end)
  end

  defp process_event(event_data, state) when is_map(event_data) do
    event_type = Map.get(event_data, "type", "unknown")
    Logger.info("[SSE Consumer] 📥 Single event type: #{event_type}")
    process_single_event(event_data, state)
  end

  defp process_event(event_data, _state) do
    Logger.warning("[SSE Consumer] ⚠️ Unknown event format: #{inspect(event_data)}")
  end

  # Unified handler - save ALL events regardless of type
  defp process_single_event(%{"type" => event_type, "object" => object_json} = _event, state) do
    # Only log non-frequent event types at info level
    if event_type not in ["track", "statistics"] do
      Logger.info("[SSE Consumer] 📥 Processing event type: #{event_type}")
    else
      Logger.debug("[SSE Consumer] 📥 Processing event type: #{event_type}")
    end
    
    case Jason.decode(object_json) do
      {:ok, data} ->
        save_generic_event(event_type, data, state)
      {:error, reason} ->
        Logger.warning("[SSE Consumer] ❌ Failed to parse #{event_type} object: #{inspect(reason)}")
    end
  end

  defp process_single_event(event_data, state) when is_map(event_data) do
    # Handle events without object wrapper
    event_type = Map.get(event_data, "type", Map.get(event_data, "$id", "unknown"))
    Logger.info("[SSE Consumer] 📥 Processing unwrapped event: #{event_type}")
    save_generic_event(event_type, event_data, state)
  end

  defp process_single_event(event_data, _state) do
    Logger.warning("[SSE Consumer] ⚠️ Unknown event format: #{inspect(event_data)}")
  end

  # Generic event saver - handles ALL event types
  defp save_generic_event("track", data, state) do
    # Save track events to dedicated tracks table
    save_track_to_table(data, state)
  end

  defp save_generic_event("statistics", data, state) do
    # Save statistics events to dedicated statistics table
    save_statistic_to_table(data, state)
  end

  defp save_generic_event("crop", data, state) do
    # Save crop events to dedicated crops table
    save_crop_to_table(data, state)
  end

  # Route all area-based events to unified ai_analytics_events table
  defp save_generic_event("event-intrusion" = event_type, data, state) do
    save_ai_analytics_event(event_type, data, state)
  end

  defp save_generic_event("event-intrusion-end" = event_type, data, state) do
    save_ai_analytics_event(event_type, data, state)
  end

  defp save_generic_event("event-area-enter" = event_type, data, state) do
    save_ai_analytics_event(event_type, data, state)
  end

  defp save_generic_event("event-area-exit" = event_type, data, state) do
    save_ai_analytics_event(event_type, data, state)
  end

  defp save_generic_event("event-loitering" = event_type, data, state) do
    save_ai_analytics_event(event_type, data, state)
  end

  defp save_generic_event("event-loitering-end" = event_type, data, state) do
    save_ai_analytics_event(event_type, data, state)
  end

  defp save_generic_event("event-line-crossing" = event_type, data, state) do
    save_ai_analytics_event(event_type, data, state)
  end

  defp save_generic_event("event-crowd" = event_type, data, state) do
    save_ai_analytics_event(event_type, data, state)
  end

  defp save_generic_event("event-dwelling" = event_type, data, state) do
    save_ai_analytics_event(event_type, data, state)
  end

  defp save_generic_event("event-activity-end" = event_type, data, state) do
    save_ai_analytics_event(event_type, data, state)
  end

  defp save_generic_event("event-activity" = event_type, data, state) do
    save_ai_analytics_event(event_type, data, state)
  end

  defp save_generic_event("attribute", data, state) do
    save_attribute_to_table(data, state)
  end

  defp save_generic_event(event_type, data, state) do
    location = data["location"] || %{}
    bounding_box = %{
      "x" => location["x"],
      "y" => location["y"],
      "w" => location["width"],
      "h" => location["height"]
    }
    {centroid_x, centroid_y} = extract_centroid(data, bounding_box)
    
    # Determine event_type and subtype
    {normalized_type, subtype} = normalize_event_type_with_subtype(event_type)
    
    # Save image if it's a crop event
    thumbnail_path = if event_type == "crop" do
      save_crop_image(data, state)
    else
      nil
    end
    
    event_params = %{
      instance_id: data["instance_id"] || state.instance_id,
      device_id: state.device_id,
      event_type: normalized_type,
      event_subtype: subtype || data["subType"] || data["name"],
      zone_name: data["area_name"] || data["line_name"] || data["zone_name"],
      zone_id: data["area_id"] || data["line_id"] || data["zoneId"],
      object_class: data["object_class"],
      object_id: nil,
      confidence: data["confidence"] || data["detection_confidence"],
      direction: data["direction"],
      bounding_box: bounding_box,
      centroid_x: centroid_x,
      centroid_y: centroid_y,
      thumbnail_path: thumbnail_path,
      attributes: extract_attributes(data),
      event_time: parse_system_datetime(data) || DateTime.utc_now(),
      raw_data: if(event_type == "crop", do: Map.delete(data, "image"), else: data)
    }

    try do
      case save_event(event_params) do
        {:ok, saved_event} ->
          broadcast_event(state.instance_id, saved_event)
          Logger.info("[SSE Consumer] ✅ SAVED #{normalized_type} event, id: #{saved_event.id}")
        {:error, changeset} ->
          Logger.error("[SSE Consumer] ❌ Failed to save #{normalized_type}: #{inspect(changeset.errors)}")
      end
    rescue
      e in Exqlite.Error ->
        Logger.warning("[SSE Consumer] DB busy, dropped #{normalized_type} event: #{inspect(e.message)}")
    end
  end

  # Save track event to dedicated tracks table
  defp save_track_to_table(data, state) do
    location = data["location"] || %{}
    
    track_params = %{
      instance_id: data["instance_id"] || state.instance_id,
      device_id: state.device_id,
      tracking_id: data["tracking_id"],
      object_class: data["object_class"],
      detection_confidence: data["detection_confidence"],
      age_ms: data["age_ms"],
      is_moving: data["is_moving"],
      event_timestamp_ms: data["event_timestamp_ms"],
      location_x: location["x"],
      location_y: location["y"],
      location_width: location["width"],
      location_height: location["height"],
      centroid_x: (location["x"] || 0) + (location["width"] || 0) / 2,
      centroid_y: (location["y"] || 0) + (location["height"] || 0) / 2,
      events: data["events"] || [],
      system_datetime: parse_system_datetime(data),
      system_timestamp: data["system_timestamp"],
      raw_data: data
    }

    try do
      case save_track(track_params) do
        {:ok, saved_track} ->
          broadcast_track(state.instance_id, saved_track)
          Logger.debug("[SSE Consumer] ✅ SAVED track #{data["object_class"]}, id: #{saved_track.id}")
        {:error, changeset} ->
          Logger.error("[SSE Consumer] ❌ Failed to save track: #{inspect(changeset.errors)}")
      end
    rescue
      e in Exqlite.Error ->
        Logger.debug("[SSE Consumer] DB busy, dropped track event: #{inspect(e.message)}")
    end
  end

  # Save statistic event to dedicated statistics table
  defp save_statistic_to_table(data, state) do
    stat_params = %{
      instance_id: data["instance_id"] || state.instance_id,
      device_id: state.device_id,
      current_framerate: data["current_framerate"],
      source_framerate: data["source_framerate"],
      dropped_frames_count: data["dropped_frames_count"],
      frames_processed: data["frames_processed"],
      input_queue_size: data["input_queue_size"],
      latency: data["latency"],
      format: data["format"],
      resolution: data["resolution"],
      source_resolution: data["source_resolution"],
      start_time: data["start_time"],
      raw_data: data
    }

    try do
      case save_statistic(stat_params) do
        {:ok, saved_stat} ->
          broadcast_statistic(state.instance_id, saved_stat)
          Logger.debug("[SSE Consumer] ✅ SAVED statistics #{data["resolution"]} @ #{data["current_framerate"]}fps")
        {:error, changeset} ->
          Logger.error("[SSE Consumer] ❌ Failed to save statistics: #{inspect(changeset.errors)}")
      end
    rescue
      e in Exqlite.Error ->
        Logger.debug("[SSE Consumer] DB busy, dropped statistics event: #{inspect(e.message)}")
    end
  end

  # Save crop event to dedicated crops table
  defp save_crop_to_table(data, state) do
    location = data["location"] || %{}
    
    # Save image to file system (persistent storage)
    image_path = save_crop_image_to_file(data, state)
    
    crop_params = %{
      instance_id: data["instance_id"] || state.instance_id,
      device_id: state.device_id,
      ref_tracking_id: data["ref_tracking_id"],
      ref_event_id: data["ref_event_id"],
      confidence: data["confidence"],
      crop_timestamp_ms: data["crop_timestamp_ms"],
      event_timestamp_ms: data["event_timestamp_ms"],
      location_x: location["x"],
      location_y: location["y"],
      location_width: location["width"],
      location_height: location["height"],
      image_path: image_path,
      system_datetime: parse_system_datetime(data),
      system_timestamp: data["system_timestamp"],
      raw_data: Map.delete(data, "image")
    }

    try do
      case save_crop(crop_params) do
        {:ok, saved_crop} ->
          broadcast_crop(state.instance_id, saved_crop)
          Logger.info("[SSE Consumer] ✅ SAVED crop #{data["ref_tracking_id"] |> String.slice(0..7)}... -> #{image_path}")
        {:error, changeset} ->
          Logger.error("[SSE Consumer] ❌ Failed to save crop: #{inspect(changeset.errors)}")
      end
    rescue
      e in Exqlite.Error ->
        Logger.warning("[SSE Consumer] DB busy, dropped crop event: #{inspect(e.message)}")
    end
  end

  # Save crop image to file system
  defp save_crop_image_to_file(data, state) do
    case data["image"] do
      nil -> nil
      base64_image ->
        # Create directory structure
        crops_dir = Path.join([
          Application.get_env(:tpro_nvr, :storage_path, "/tmp/tpro_nvr"),
          "crops",
          state.device_id,
          Date.utc_today() |> Date.to_string()
        ])
        File.mkdir_p!(crops_dir)
        
        # Generate unique filename
        timestamp = System.system_time(:millisecond)
        filename = "crop_#{timestamp}_#{:rand.uniform(9999)}.jpg"
        filepath = Path.join(crops_dir, filename)
        
        # Decode and save
        case Base.decode64(base64_image) do
          {:ok, image_data} ->
            File.write!(filepath, image_data)
            filepath
          :error ->
            Logger.warning("[SSE Consumer] Failed to decode crop image")
            nil
        end
    end
  end

  # Normalize event types (e.g., "event-intrusion-end" -> {"intrusion", "end"})
  defp normalize_event_type_with_subtype(event_type) do
    cond do
      String.starts_with?(event_type, "event-intrusion-") ->
        {"intrusion", String.replace(event_type, "event-intrusion-", "")}
      String.starts_with?(event_type, "event-loitering-") ->
        {"loitering", String.replace(event_type, "event-loitering-", "")}
      String.starts_with?(event_type, "event-area-") ->
        {String.replace(event_type, "event-", "") |> String.replace("-", "_"), nil}
      String.starts_with?(event_type, "event-") ->
        {String.replace(event_type, "event-", "") |> String.replace("-", "_"), nil}
      true ->
        {event_type, nil}
    end
  end
  
  # Extract common attributes from event data
  defp extract_attributes(data) do
    %{
      "tracking_id" => data["tracking_id"],
      "event_id" => data["event_id"],
      "ref_tracking_id" => data["ref_tracking_id"],
      "ref_event_id" => data["ref_event_id"],
      "age_ms" => data["age_ms"],
      "is_moving" => data["is_moving"],
      "events" => data["events"],
      "event_duration_ms" => data["event_duration_ms"],
      "loiter_duration_ms" => data["loiter_duration_ms"],
      # Statistics fields
      "current_framerate" => data["current_framerate"],
      "resolution" => data["resolution"],
      "latency" => data["latency"],
      "start_time" => data["start_time"],
      "dropped_frames_count" => data["dropped_frames_count"],
      # Attribute event fields
      "name" => data["name"],
      "value" => data["value"]
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  # Save crop image to disk
  defp save_crop_image(%{"image" => base64_image} = data, state) when is_binary(base64_image) do
    try do
      # Create directory for crops
      device_id = state.device_id || "unknown"
      date = Date.utc_today() |> Date.to_string()
      dir = Path.join(["data", "crops", device_id, date])
      File.mkdir_p!(dir)
      
      # Generate filename
      tracking_id = data["ref_tracking_id"] || "unknown"
      timestamp = :erlang.system_time(:millisecond)
      filename = "#{tracking_id}_#{timestamp}.jpg"
      path = Path.join(dir, filename)
      
      # Decode and save
      case Base.decode64(base64_image) do
        {:ok, image_data} ->
          File.write!(path, image_data)
          path
        :error ->
          nil
      end
    rescue
      e ->
        Logger.warning("Failed to save crop image: #{inspect(e)}")
        nil
    end
  end
  defp save_crop_image(_, _), do: nil

  # Extract centroid from bounding box
  defp extract_centroid(data, bounding_box) do
    cond do
      data["centroidX"] && data["centroidY"] ->
        {data["centroidX"], data["centroidY"]}
      
      data["centroid_x"] && data["centroid_y"] ->
        {data["centroid_x"], data["centroid_y"]}
      
      data["centerX"] && data["centerY"] ->
        {data["centerX"], data["centerY"]}
      
      is_map(bounding_box) ->
        x = bounding_box["x"] || bounding_box[:x] || 0
        y = bounding_box["y"] || bounding_box[:y] || 0
        w = bounding_box["w"] || bounding_box[:w] || bounding_box["width"] || 0
        h = bounding_box["h"] || bounding_box[:h] || bounding_box["height"] || 0
        {x + w / 2, y + h / 2}
      
      true ->
        {nil, nil}
    end
  end

  defp parse_system_datetime(data) do
    cond do
      dt = data["system_datetime"] ->
        case DateTime.from_iso8601(dt) do
          {:ok, datetime, _} -> datetime
          _ -> nil
        end
      ts = data["system_timestamp"] ->
        DateTime.from_unix!(div(ts, 1000))
      true ->
        nil
    end
  end

  defp save_event(event_params) do
    %AnalyticsEvent{}
    |> AnalyticsEvent.changeset(event_params)
    |> Repo.insert()
  end

  defp broadcast_event(instance_id, event) do
    topic = topic(instance_id)
    Phoenix.PubSub.broadcast(TProNVR.PubSub, topic, {:analytics_event, event})
    
    if event.event_type do
      type_topic = "cvedix:#{event.event_type}:#{instance_id}"
      Phoenix.PubSub.broadcast(TProNVR.PubSub, type_topic, {:analytics_event, event})
    end
  end

  defp save_track(track_params) do
    %Track{}
    |> Track.changeset(track_params)
    |> Repo.insert()
  end

  defp broadcast_track(instance_id, track) do
    topic = topic(instance_id)
    Phoenix.PubSub.broadcast(TProNVR.PubSub, topic, {:track, track})
    
    # Also broadcast to track-specific topic
    track_topic = "cvedix:track:#{instance_id}"
    Phoenix.PubSub.broadcast(TProNVR.PubSub, track_topic, {:track, track})
  end

  defp save_statistic(stat_params) do
    %Statistic{}
    |> Statistic.changeset(stat_params)
    |> Repo.insert()
  end

  defp broadcast_statistic(instance_id, stat) do
    topic = topic(instance_id)
    Phoenix.PubSub.broadcast(TProNVR.PubSub, topic, {:statistic, stat})
    
    stat_topic = "cvedix:statistics:#{instance_id}"
    Phoenix.PubSub.broadcast(TProNVR.PubSub, stat_topic, {:statistic, stat})
  end

  defp save_crop(crop_params) do
    %Crop{}
    |> Crop.changeset(crop_params)
    |> Repo.insert()
  end

  defp broadcast_crop(instance_id, crop) do
    topic = topic(instance_id)
    Phoenix.PubSub.broadcast(TProNVR.PubSub, topic, {:crop, crop})
    
    crop_topic = "cvedix:crop:#{instance_id}"
    Phoenix.PubSub.broadcast(TProNVR.PubSub, crop_topic, {:crop, crop})
  end

  # Save AI Analytics events (intrusion, area-enter, area-exit, etc.) to unified table
  defp save_ai_analytics_event(event_type, data, state) do
    location = data["location"] || %{}
    
    event_params = %{
      instance_id: data["instance_id"] || state.instance_id,
      device_id: state.device_id,
      event_type: event_type,
      event_id: data["event_id"],
      ref_tracking_id: data["ref_tracking_id"],
      ref_event_id: data["ref_event_id"],
      area_id: data["area_id"],
      area_name: data["area_name"],
      object_class: data["object_class"],
      event_timestamp_ms: data["event_timestamp_ms"],
      location_x: location["x"],
      location_y: location["y"],
      location_width: location["width"],
      location_height: location["height"],
      system_datetime: parse_system_datetime(data),
      system_timestamp: data["system_timestamp"],
      raw_data: data
    }

    try do
      case Repo.insert(AIAnalyticsEvent.changeset(event_params)) do
        {:ok, saved_event} ->
          broadcast_ai_analytics_event(state.instance_id, saved_event)
          Logger.info("[SSE Consumer] ✅ SAVED #{event_type} in #{data["area_name"]}")
        {:error, changeset} ->
          Logger.error("[SSE Consumer] ❌ Failed to save #{event_type}: #{inspect(changeset.errors)}")
      end
    rescue
      e in Exqlite.Error ->
        Logger.warning("[SSE Consumer] DB busy, dropped #{event_type} event: #{inspect(e.message)}")
    end
  end

  defp broadcast_ai_analytics_event(instance_id, event) do
    topic = topic(instance_id)
    Phoenix.PubSub.broadcast(TProNVR.PubSub, topic, {:ai_analytics_event, event})
    
    event_topic = "cvedix:ai_analytics:#{instance_id}"
    Phoenix.PubSub.broadcast(TProNVR.PubSub, event_topic, {:ai_analytics_event, event})

    # Global topic for toast notifications
    Phoenix.PubSub.broadcast(TProNVR.PubSub, "ai_events:notifications", {:ai_event_notification, event})
  end

  # Save attribute events to dedicated attributes table
  defp save_attribute_to_table(data, state) do
    attribute_params = %{
      instance_id: data["instance_id"] || state.instance_id,
      device_id: state.device_id,
      name: data["name"],
      value: data["value"],
      ref_tracking_id: data["ref_tracking_id"],
      event_timestamp_ms: data["event_timestamp_ms"],
      system_datetime: parse_system_datetime(data),
      system_timestamp: data["system_timestamp"],
      raw_data: data
    }

    try do
      case Repo.insert(Attribute.changeset(attribute_params)) do
        {:ok, saved_attr} ->
          broadcast_attribute(state.instance_id, saved_attr)
          Logger.debug("[SSE Consumer] ✅ SAVED attribute #{data["name"]}=#{data["value"]}")
        {:error, changeset} ->
          Logger.error("[SSE Consumer] ❌ Failed to save attribute: #{inspect(changeset.errors)}")
      end
    rescue
      e in Exqlite.Error ->
        Logger.debug("[SSE Consumer] DB busy, dropped attribute event: #{inspect(e.message)}")
    end
  end

  defp broadcast_attribute(instance_id, attribute) do
    topic = topic(instance_id)
    Phoenix.PubSub.broadcast(TProNVR.PubSub, topic, {:attribute, attribute})
    
    attr_topic = "cvedix:attribute:#{instance_id}"
    Phoenix.PubSub.broadcast(TProNVR.PubSub, attr_topic, {:attribute, attribute})
  end

  defp schedule_reconnect do
    Process.send_after(self(), :reconnect, @reconnect_delay)
  end

  defp via_tuple(instance_id) do
    {:via, Registry, {TProNVR.CVEDIX.SSERegistry, instance_id}}
  end
end
