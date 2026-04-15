defmodule TProNVRWeb.AIHeatmapLive do
  @moduledoc """
  AI Heatmap page - visualizes movement patterns from track data.
  Shows heatmap overlay on camera frame based on centroid positions.
  """
  use TProNVRWeb, :live_view

  alias TProNVR.CVEDIX.Track
  alias TProNVR.{Repo, Devices}

  import Ecto.Query

  @grid_size 50  # 50x50 grid for heatmap resolution

  @impl true
  def render(assigns) do
    ~H"""
    <div class="grow px-4 py-6">
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-xl font-semibold text-white">🔥 AI Heatmap</h2>
        <div class="flex items-center gap-3">
          <span class="text-sm text-green-400 font-medium"><%= @track_count %> track points</span>
          <button phx-click="refresh" class="px-3 py-1.5 bg-green-700 hover:bg-green-600 text-white text-sm rounded">↻ Refresh</button>
        </div>
      </div>
      
      <!-- Filters -->
      <div class="flex items-center gap-4 mb-4">
        <.form for={@filter_form} phx-change="filter" class="flex items-center gap-3">
          <select name="device_id" class="bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm">
            <option value="">Select Device</option>
            <%= for device <- @devices do %>
              <option value={device.id} selected={@filters["device_id"] == device.id}><%= device.name %></option>
            <% end %>
          </select>
          
          <select name="time_range" class="bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm">
            <option value="1h" selected={@filters["time_range"] == "1h"}>Last 1 Hour</option>
            <option value="6h" selected={@filters["time_range"] == "6h"}>Last 6 Hours</option>
            <option value="24h" selected={@filters["time_range"] == "24h"}>Last 24 Hours</option>
            <option value="7d" selected={@filters["time_range"] == "7d"}>Last 7 Days</option>
          </select>
          
          <select name="object_class" class="bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm">
            <option value="">All Objects</option>
            <option value="Person" selected={@filters["object_class"] == "Person"}>Person</option>
            <option value="Vehicle" selected={@filters["object_class"] == "Vehicle"}>Vehicle</option>
            <option value="Bicycle" selected={@filters["object_class"] == "Bicycle"}>Bicycle</option>
            <option value="Animal" selected={@filters["object_class"] == "Animal"}>Animal</option>
          </select>
        </.form>
      </div>

      <!-- Heatmap Canvas with HLS Video Background -->
      <div class="border border-green-600 rounded overflow-hidden bg-black">
        <%= if @filters["device_id"] && @filters["device_id"] != "" do %>
          <div 
            id="heatmap-container" 
            phx-hook="HeatmapCanvas"
            data-heatmap={Jason.encode!(@heatmap_data)}
            data-grid-size={@grid_size}
            class="relative w-full"
            style="aspect-ratio: 16/9;"
          >
            <!-- HLS Video Player as Background -->
            <div id={"loading-#{@filters["device_id"]}"} phx-update="ignore" class="absolute inset-0 flex items-center justify-center bg-black z-10">
              <div class="text-center text-white">
                <div class="animate-spin w-8 h-8 border-2 border-green-600 border-t-transparent rounded-full mx-auto mb-2"></div>
                <p class="text-sm text-white/60">Loading stream...</p>
              </div>
            </div>
            
            <video 
              id={"video-heatmap-#{@filters["device_id"]}"}
              phx-hook="WebRTCPlayer"
              data-device-id={@filters["device_id"]}
              data-token={@user_token}
              class="absolute inset-0 w-full h-full object-contain"
              muted
              autoplay
              playsinline
            ></video>
            
            <!-- Heatmap Overlay Canvas -->
            <canvas id="heatmap-canvas" class="absolute inset-0 w-full h-full pointer-events-none" style="z-index: 20;"></canvas>
            
            <!-- Legend -->
            <div class="absolute bottom-4 left-4 bg-black/70 px-3 py-2 rounded" style="z-index: 30;">
              <div class="text-xs text-white mb-1">Activity Intensity</div>
              <div class="flex items-center gap-1">
                <div class="w-16 h-3 rounded" style="background: linear-gradient(to right, rgba(0,0,255,0.3), rgba(0,255,0,0.5), rgba(255,255,0,0.7), rgba(255,0,0,0.9));"></div>
                <span class="text-xs text-white/60 ml-2">Low → High</span>
              </div>
            </div>
            
            <%= if @max_intensity > 0 do %>
              <div class="absolute top-4 right-4 bg-black/70 px-3 py-2 rounded text-right" style="z-index: 30;">
                <div class="text-xs text-white/60">Hottest Zone</div>
                <div class="text-sm text-red-400 font-medium"><%= @hottest_zone %></div>
                <div class="text-xs text-white/60 mt-1">Max: <%= @max_intensity %> points</div>
              </div>
            <% end %>
          </div>
        <% else %>
          <div class="flex items-center justify-center h-96 text-white/50">
            <div class="text-center">
              <div class="text-4xl mb-2">🎯</div>
              <div>Select a device to view heatmap</div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    devices = Devices.list()
    
    # Auto-select first device
    first_device_id = case devices do
      [first | _] -> first.id
      _ -> nil
    end
    
    initial_filters = %{
      "time_range" => "1h",
      "device_id" => first_device_id
    }
    
    user = socket.assigns.current_user
    token = Phoenix.Token.sign(socket, "user socket", user.id)

    {:ok,
     socket
     |> assign(:devices, devices)
     |> assign(:filters, initial_filters)
     |> assign(:filter_form, to_form(%{}))
     |> assign(:heatmap_data, [])
     |> assign(:track_count, 0)
     |> assign(:max_intensity, 0)
     |> assign(:hottest_zone, "-")
     |> assign(:grid_size, @grid_size)
     |> assign(:user_token, token)
     |> load_heatmap_data()}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters = Map.take(params, ["device_id", "time_range", "object_class"])
    |> Enum.reject(fn {_k, v} -> v == "" end)
    |> Map.new()
    |> Map.put_new("time_range", "1h")

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> load_heatmap_data()}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_heatmap_data(socket)}
  end

  defp load_heatmap_data(socket) do
    filters = socket.assigns.filters
    device_id = Map.get(filters, "device_id")
    
    if device_id && device_id != "" do
      time_range = Map.get(filters, "time_range", "1h")
      object_class = Map.get(filters, "object_class")
      
      since = get_time_since(time_range)
      
      # Query track centroids
      query = from(t in Track,
        where: t.device_id == ^device_id,
        where: t.inserted_at >= ^since,
        where: not is_nil(t.centroid_x) and not is_nil(t.centroid_y),
        select: %{x: t.centroid_x, y: t.centroid_y}
      )
      
      query = if object_class && object_class != "" do
        where(query, [t], t.object_class == ^object_class)
      else
        query
      end
      
      tracks = Repo.all(query)
      track_count = length(tracks)
      
      # Generate heatmap grid data
      {grid_data, max_intensity, hottest_zone} = generate_heatmap_grid(tracks, @grid_size)
      
      socket
      |> assign(:heatmap_data, grid_data)
      |> assign(:track_count, track_count)
      |> assign(:max_intensity, max_intensity)
      |> assign(:hottest_zone, hottest_zone)
    else
      socket
      |> assign(:heatmap_data, [])
      |> assign(:track_count, 0)
      |> assign(:max_intensity, 0)
      |> assign(:hottest_zone, "-")
    end
  end

  defp get_time_since(time_range) do
    now = DateTime.utc_now()
    
    case time_range do
      "1h" -> DateTime.add(now, -1, :hour)
      "6h" -> DateTime.add(now, -6, :hour)
      "24h" -> DateTime.add(now, -24, :hour)
      "7d" -> DateTime.add(now, -7, :day)
      _ -> DateTime.add(now, -1, :hour)
    end
  end

  defp generate_heatmap_grid(tracks, grid_size) do
    # Initialize grid
    grid = for _ <- 0..(grid_size - 1), do: List.duplicate(0, grid_size)
    grid = List.to_tuple(Enum.map(grid, &List.to_tuple/1))
    
    # Count tracks per cell
    grid = Enum.reduce(tracks, grid, fn %{x: x, y: y}, acc ->
      # Clamp values to 0-1 range
      x = max(0.0, min(1.0, x || 0.0))
      y = max(0.0, min(1.0, y || 0.0))
      
      # Convert to grid coordinates
      col = min(trunc(x * grid_size), grid_size - 1)
      row = min(trunc(y * grid_size), grid_size - 1)
      
      # Increment cell count
      row_tuple = elem(acc, row)
      current = elem(row_tuple, col)
      new_row = put_elem(row_tuple, col, current + 1)
      put_elem(acc, row, new_row)
    end)
    
    # Convert to list and find max
    grid_list = for row <- 0..(grid_size - 1) do
      row_tuple = elem(grid, row)
      for col <- 0..(grid_size - 1), do: elem(row_tuple, col)
    end
    
    # Find max intensity and hottest zone
    {max_intensity, max_row, max_col} = 
      grid_list
      |> Enum.with_index()
      |> Enum.reduce({0, 0, 0}, fn {row, row_idx}, {max_val, max_r, max_c} ->
        row
        |> Enum.with_index()
        |> Enum.reduce({max_val, max_r, max_c}, fn {val, col_idx}, {mv, mr, mc} ->
          if val > mv, do: {val, row_idx, col_idx}, else: {mv, mr, mc}
        end)
      end)
    
    hottest_zone = if max_intensity > 0 do
      zone_x = if(max_col < grid_size / 3, do: "Left", else: if(max_col < grid_size * 2 / 3, do: "Center", else: "Right"))
      zone_y = if(max_row < grid_size / 3, do: "Top", else: if(max_row < grid_size * 2 / 3, do: "Middle", else: "Bottom"))
      "#{zone_y}-#{zone_x}"
    else
      "-"
    end
    
    {grid_list, max_intensity, hottest_zone}
  end
end
