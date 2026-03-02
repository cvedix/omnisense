defmodule TProNVRWeb.AIEventsLive do
  @moduledoc """
  AI Events aggregation page - shows crop images grouped by ref_event_id
  with related tracking and event data.
  """
  use TProNVRWeb, :live_view

  alias TProNVR.CVEDIX.{Crop, Attribute, Track, AIAnalyticsEvent}
  alias TProNVR.Repo

  import Ecto.Query

  @impl true
  def render(assigns) do
    ~H"""
    <div class="grow px-4 py-6">
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-xl font-semibold text-white">AI Events Overview</h2>
        <div class="flex items-center gap-3">
          <span class="text-sm text-green-400 font-medium"><%= @meta.total_count || 0 %> events</span>
          <button phx-click="refresh" class="px-3 py-1.5 bg-green-700 hover:bg-green-600 text-white text-sm rounded">↻ Refresh</button>
        </div>
      </div>
      
      <!-- Filters -->
      <div class="flex items-center gap-4 mb-4">
        <.form for={@filter_form} phx-change="filter" class="flex items-center gap-3" style="width: 600px;">
          <select name="device_id" class="flex-1 bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm">
            <option value="">All Devices</option>
            <%= for device <- @devices do %>
              <option value={device.id} selected={@filters["device_id"] == device.id}><%= device.name %></option>
            <% end %>
          </select>
          
          <select name="min_confidence" class="flex-1 bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm">
            <option value="">All Confidence</option>
            <option value="0.3" selected={@filters["min_confidence"] == "0.3"}>≥ 30%</option>
            <option value="0.5" selected={@filters["min_confidence"] == "0.5"}>≥ 50%</option>
            <option value="0.7" selected={@filters["min_confidence"] == "0.7"}>≥ 70%</option>
            <option value="0.8" selected={@filters["min_confidence"] == "0.8"}>≥ 80%</option>
            <option value="0.9" selected={@filters["min_confidence"] == "0.9"}>≥ 90%</option>
          </select>
          
          <select name="object_type" class="flex-1 bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm">
            <option value="">All Types</option>
            <option value="Person" selected={@filters["object_type"] == "Person"}>Person</option>
            <option value="Vehicle" selected={@filters["object_type"] == "Vehicle"}>Vehicle</option>
            <option value="Bicycle" selected={@filters["object_type"] == "Bicycle"}>Bicycle</option>
            <option value="Animal" selected={@filters["object_type"] == "Animal"}>Animal</option>
          </select>
        </.form>
        
        <!-- Second row of filters -->
        <.form for={@filter_form} phx-change="filter" class="flex items-center gap-3" style="width: 800px;">
          <select name="event_type" class="flex-1 bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm">
            <option value="">All Event Types</option>
            <option value="event-intrusion" selected={@filters["event_type"] == "event-intrusion"}>Intrusion</option>
            <option value="event-intrusion-end" selected={@filters["event_type"] == "event-intrusion-end"}>Intrusion End</option>
            <option value="event-area-enter" selected={@filters["event_type"] == "event-area-enter"}>Area Enter</option>
            <option value="event-area-exit" selected={@filters["event_type"] == "event-area-exit"}>Area Exit</option>
            <option value="event-loitering" selected={@filters["event_type"] == "event-loitering"}>Loitering Start</option>
            <option value="event-loitering-end" selected={@filters["event_type"] == "event-loitering-end"}>Loitering End</option>
            <option value="event-line-crossing" selected={@filters["event_type"] == "event-line-crossing"}>Line Crossing</option>
            <option value="event-crowd" selected={@filters["event_type"] == "event-crowd"}>Crowd</option>
            <option value="event-activity" selected={@filters["event_type"] == "event-activity"}>Activity</option>
            <option value="event-activity-end" selected={@filters["event_type"] == "event-activity-end"}>Activity End</option>
          </select>
          
          <select name="upper_clothing_color" class="flex-1 bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm">
            <option value="">Upper Color</option>
            <option value="black" selected={@filters["upper_clothing_color"] == "black"}>Black</option>
            <option value="white" selected={@filters["upper_clothing_color"] == "white"}>White</option>
            <option value="red" selected={@filters["upper_clothing_color"] == "red"}>Red</option>
            <option value="blue" selected={@filters["upper_clothing_color"] == "blue"}>Blue</option>
            <option value="green" selected={@filters["upper_clothing_color"] == "green"}>Green</option>
            <option value="yellow" selected={@filters["upper_clothing_color"] == "yellow"}>Yellow</option>
          </select>
          
          <select name="lower_clothing_color" class="flex-1 bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm">
            <option value="">Lower Color</option>
            <option value="black" selected={@filters["lower_clothing_color"] == "black"}>Black</option>
            <option value="white" selected={@filters["lower_clothing_color"] == "white"}>White</option>
            <option value="red" selected={@filters["lower_clothing_color"] == "red"}>Red</option>
            <option value="blue" selected={@filters["lower_clothing_color"] == "blue"}>Blue</option>
            <option value="green" selected={@filters["lower_clothing_color"] == "green"}>Green</option>
            <option value="yellow" selected={@filters["lower_clothing_color"] == "yellow"}>Yellow</option>
          </select>
          
          <select name="age" class="flex-1 bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm">
            <option value="">All Ages</option>
            <option value="child" selected={@filters["age"] == "child"}>Child</option>
            <option value="young" selected={@filters["age"] == "young"}>Young</option>
            <option value="adult" selected={@filters["age"] == "adult"}>Adult</option>
            <option value="elderly" selected={@filters["age"] == "elderly"}>Elderly</option>
          </select>
          
          <select name="glasses" class="flex-1 bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm">
            <option value="">Glasses</option>
            <option value="yes" selected={@filters["glasses"] == "yes"}>Yes</option>
            <option value="no" selected={@filters["glasses"] == "no"}>No</option>
          </select>
          
          <select name="tattoo" class="flex-1 bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm">
            <option value="">Tattoo</option>
            <option value="yes" selected={@filters["tattoo"] == "yes"}>Yes</option>
            <option value="no" selected={@filters["tattoo"] == "no"}>No</option>
          </select>
        </.form>
      </div>
      <!-- Events Table -->
      <div class="border border-green-600 rounded overflow-hidden">
        <div class="overflow-y-auto max-h-[75vh]">
          <%= if Enum.empty?(@grouped_events) do %>
            <div class="px-4 py-8 text-center text-white/50">
              No AI events found
            </div>
          <% else %>
            <table class="w-full">
              <thead class="bg-green-900/30 sticky top-0 z-10">
                <tr class="text-left text-xs text-green-400 uppercase">
                  <th class="px-3 py-2 w-16"></th>
                  <th class="px-3 py-2">Event Type</th>
                  <th class="px-3 py-2">Track ID</th>
                  <th class="px-3 py-2">Object</th>
                  <th class="px-3 py-2">Area / Line</th>
                  <th class="px-3 py-2">Duration</th>
                  <th class="px-3 py-2">Status</th>
                  <th class="px-3 py-2">Events</th>
                  <th class="px-3 py-2">Crops</th>
                  <th class="px-3 py-2">Time</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-green-900/50">
                <%= for {event_id, event_data} <- @grouped_events do %>
                  <tr 
                    phx-click="show_detail" 
                    phx-value-tracking_id={event_id}
                    class="hover:bg-green-900/20 cursor-pointer transition-colors"
                  >
                    <td class="px-3 py-2">
                      <%= if event_data.crop do %>
                        <% img_src = get_base64_image(event_data.crop) %>
                        <%= if img_src do %>
                          <img src={img_src} alt="Crop" class="w-10 h-10 object-cover rounded border border-green-700" />
                        <% else %>
                          <div class="w-10 h-10 bg-black/50 rounded border border-green-700 flex items-center justify-center">
                            <span class="text-white/20 text-sm">👤</span>
                          </div>
                        <% end %>
                      <% else %>
                        <div class="w-10 h-10 bg-black/50 rounded border border-green-700 flex items-center justify-center">
                          <span class="text-white/20 text-sm">👤</span>
                        </div>
                      <% end %>
                    </td>
                    <td class="px-3 py-2">
                      <div class="flex flex-wrap gap-1">
                        <%= for et <- (Map.get(event_data, :event_types, []) |> Enum.reject(&is_nil/1)) do %>
                          <span class={"px-1.5 py-0.5 rounded text-[11px] font-medium #{event_type_color(et)}"}><%= format_event_type(et) %></span>
                        <% end %>
                      </div>
                    </td>
                    <td class="px-3 py-2 text-green-400 font-mono text-xs"><%= String.slice(event_id || "", 0..7) %></td>
                    <td class="px-3 py-2 text-white text-xs"><%= event_data.object_class || "-" %></td>
                    <td class="px-3 py-2 text-xs">
                      <%= if event_data.zone_name do %>
                        <span class="text-blue-400"><%= event_data.zone_name %></span>
                      <% end %>
                      <%= if event_data.line_name do %>
                        <%= if event_data.zone_name do %><span class="text-white/30"> · </span><% end %>
                        <span class="text-orange-400"><%= event_data.line_name %></span>
                      <% end %>
                      <%= if !event_data.zone_name && !event_data.line_name do %>
                        <span class="text-white/30">-</span>
                      <% end %>
                    </td>
                    <td class="px-3 py-2 text-yellow-400 text-xs font-medium"><%= event_data.duration || "-" %></td>
                    <td class="px-3 py-2 text-xs">
                      <%= case event_data.status do %>
                        <% :ongoing -> %>
                          <span class="px-1.5 py-0.5 bg-green-700/60 border border-green-500 rounded text-green-300 text-[11px] font-medium animate-pulse">Ongoing</span>
                        <% :ended -> %>
                          <span class="px-1.5 py-0.5 bg-gray-700/60 border border-gray-500 rounded text-gray-300 text-[11px] font-medium">Ended</span>
                        <% _ -> %>
                          <span class="text-white/30">-</span>
                      <% end %>
                    </td>
                    <td class="px-3 py-2 text-purple-400 text-xs font-medium"><%= event_data.event_count %></td>
                    <td class="px-3 py-2 text-white/60 text-xs"><%= event_data.crops_count %></td>
                    <td class="px-3 py-2 text-white/50 text-xs whitespace-nowrap">
                      <%= if event_data.timestamp, do: Calendar.strftime(event_data.timestamp, "%H:%M:%S"), else: "-" %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </div>
      </div>
      
      <!-- Pagination -->
      <div class="flex justify-between items-center text-sm mt-4">
        <span class="text-white/60">
          Showing <%= length(@grouped_events) %> of <%= @meta.total_count || 0 %>
        </span>
        <nav class="flex items-center gap-2" :if={@meta.total_pages && @meta.total_pages > 1}>
          <button
            :if={@meta.current_page > 1}
            phx-click="paginate"
            phx-value-page={@meta.current_page - 1}
            class="px-2 py-1 border border-green-600 text-white rounded text-xs hover:bg-green-900/30"
          >
            ← Prev
          </button>
          
          <span class="text-white/60 text-xs">
            <%= @meta.current_page %> / <%= @meta.total_pages %>
          </span>
          
          <button
            :if={@meta.current_page < @meta.total_pages}
            phx-click="paginate"
            phx-value-page={@meta.current_page + 1}
            class="px-2 py-1 border border-green-600 text-white rounded text-xs hover:bg-green-900/30"
          >
            Next →
          </button>
        </nav>
      </div>

      <!-- Detail Modal -->
      <%= if @selected_event do %>
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/80" phx-click="close_detail">
          <div class="bg-[#0a0a0a] border border-green-600 rounded-xl max-w-2xl w-full mx-4 max-h-[85vh] overflow-y-auto shadow-2xl shadow-green-900/20" phx-click="noop" phx-target="">
            <% {tid, data} = @selected_event %>
            <!-- Modal Header -->
            <div class="flex items-center justify-between px-5 py-3 border-b border-green-900 sticky top-0 bg-[#0a0a0a] z-10">
              <div class="flex items-center gap-3">
                <span class="text-green-400 font-mono text-sm">Track: <%= String.slice(tid || "", 0..7) %></span>
                <%= for et <- (Map.get(data, :event_types, []) |> Enum.reject(&is_nil/1)) do %>
                  <span class={"px-2 py-0.5 rounded text-xs font-medium #{event_type_color(et)}"}><%= format_event_type(et) %></span>
                <% end %>
              </div>
              <button phx-click="close_detail" class="text-white/50 hover:text-white text-xl">✕</button>
            </div>
            
            <!-- Crop Images -->
            <%= if data.crops != [] do %>
              <div class="px-5 py-3 border-b border-green-900/50">
                <div class="flex gap-3 overflow-x-auto pb-2">
                  <%= for crop <- data.crops do %>
                    <%= if img_src = get_base64_image(crop) do %>
                      <img src={img_src} alt="Crop" class="w-32 h-32 object-cover rounded-lg border border-green-700 flex-shrink-0" />
                    <% end %>
                  <% end %>
                </div>
              </div>
            <% end %>

            <!-- Event Details -->
            <div class="px-5 py-4 space-y-3">
              <!-- Stats Row -->
              <div class="grid grid-cols-3 gap-3">
                <div class="bg-green-900/10 border border-green-900/30 rounded-lg px-3 py-2">
                  <div class="text-white/40 text-[10px] uppercase mb-0.5">Object</div>
                  <div class="text-white text-sm font-medium"><%= data.object_class || "-" %></div>
                </div>
                <div class="bg-green-900/10 border border-green-900/30 rounded-lg px-3 py-2 col-span-2">
                  <div class="text-white/40 text-[10px] uppercase mb-0.5">Area / Line</div>
                  <div class="text-sm font-medium">
                    <%= if data.zone_name do %><span class="text-blue-400"><%= data.zone_name %></span><% end %>
                    <%= if data.line_name do %>
                      <%= if data.zone_name do %><span class="text-white/30"> · </span><% end %>
                      <span class="text-orange-400"><%= data.line_name %></span>
                    <% end %>
                    <%= if !data.zone_name && !data.line_name do %><span class="text-white/30">-</span><% end %>
                  </div>
                </div>
                <div class="bg-green-900/10 border border-green-900/30 rounded-lg px-3 py-2">
                  <div class="text-white/40 text-[10px] uppercase mb-0.5">Duration</div>
                  <div class="text-yellow-400 text-sm font-medium"><%= data.duration || "-" %></div>
                </div>
                <div class="bg-green-900/10 border border-green-900/30 rounded-lg px-3 py-2">
                  <div class="text-white/40 text-[10px] uppercase mb-0.5">Events</div>
                  <div class="text-purple-400 text-sm font-medium"><%= data.event_count %> events · <%= data.crops_count %> crops</div>
                </div>
              </div>

              <!-- Timestamp -->
              <div class="bg-green-900/10 border border-green-900/30 rounded-lg px-3 py-2">
                <div class="text-white/40 text-[10px] uppercase mb-0.5">Timestamp</div>
                <div class="text-white text-sm">
                  <%= if data.timestamp, do: Calendar.strftime(data.timestamp, "%d/%m/%Y %H:%M:%S"), else: "-" %>
                </div>
              </div>

              <!-- Confidence -->
              <%= if data.crop do %>
                <div class="bg-green-900/10 border border-green-900/30 rounded-lg px-3 py-2">
                  <div class="text-white/40 text-[10px] uppercase mb-0.5">Confidence</div>
                  <div class="text-white text-sm font-medium"><%= Float.round((data.crop.confidence || 0) * 100, 1) %>%</div>
                </div>
              <% end %>

              <!-- Attributes -->
              <%= if data.attributes != [] do %>
                <div class="bg-green-900/10 border border-green-900/30 rounded-lg px-3 py-2">
                  <div class="text-white/40 text-[10px] uppercase mb-1.5">Attributes</div>
                  <div class="flex flex-wrap gap-1.5">
                    <%= for attr <- data.attributes do %>
                      <span class="px-2 py-1 bg-cyan-900/30 border border-cyan-700 rounded text-xs text-white">
                        <span class="text-cyan-400"><%= format_attribute_name(attr.name) %></span>: <%= truncate_value(attr.value) %>
                      </span>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    devices = TProNVR.Devices.list()
    
    {:ok,
     socket
     |> assign(:devices, devices)
     |> assign(:filters, %{})
     |> assign(:filter_form, to_form(%{}))
     |> assign(:per_page, 20)
     |> assign(:page, 1)
     |> assign(:auto_refresh, 0)
     |> assign(:timer_ref, nil)
     |> assign(:selected_event, nil)
     |> load_events()}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters = Map.take(params, [
      "device_id", "ref_event_id", "min_confidence", "object_type",
      "event_type", "upper_clothing_color", "lower_clothing_color", "age", "glasses", "tattoo"
    ])
    |> Enum.reject(fn {_k, v} -> v == "" end)
    |> Map.new()

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:page, 1)
     |> load_events()}
  end

  @impl true
  def handle_event("change_per_page", %{"per_page" => per_page}, socket) do
    {:noreply,
     socket
     |> assign(:per_page, String.to_integer(per_page))
     |> assign(:page, 1)
     |> load_events()}
  end

  @impl true
  def handle_event("paginate", %{"page" => page}, socket) do
    {:noreply,
     socket
     |> assign(:page, String.to_integer(page))
     |> load_events()}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_events(socket)}
  end

  @impl true
  def handle_event("show_detail", %{"tracking_id" => tracking_id}, socket) do
    selected = Enum.find(socket.assigns.grouped_events, fn {id, _} -> id == tracking_id end)
    {:noreply, assign(socket, :selected_event, selected)}
  end

  @impl true
  def handle_event("close_detail", _params, socket) do
    {:noreply, assign(socket, :selected_event, nil)}
  end

  @impl true
  def handle_event("noop", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("set_auto_refresh", %{"value" => value}, socket) do
    interval = String.to_integer(value)
    
    if socket.assigns[:timer_ref] do
      Process.cancel_timer(socket.assigns.timer_ref)
    end
    
    timer_ref = if interval > 0 do
      Process.send_after(self(), :auto_refresh, interval * 1000)
    else
      nil
    end
    
    {:noreply,
     socket
     |> assign(:auto_refresh, interval)
     |> assign(:timer_ref, timer_ref)}
  end

  @impl true
  def handle_info(:auto_refresh, socket) do
    timer_ref = if socket.assigns.auto_refresh > 0 do
      Process.send_after(self(), :auto_refresh, socket.assigns.auto_refresh * 1000)
    else
      nil
    end
    
    {:noreply,
     socket
     |> load_events()
     |> assign(:timer_ref, timer_ref)}
  end

  defp load_events(socket) do
    filters = socket.assigns.filters
    page = socket.assigns.page
    per_page = socket.assigns.per_page
    object_type = Map.get(filters, "object_type")
    event_type = Map.get(filters, "event_type")
    
    # Extract attribute filters
    attr_filters = %{
      "upper_clothing_color" => Map.get(filters, "upper_clothing_color"),
      "lower_clothing_color" => Map.get(filters, "lower_clothing_color"),
      "age" => Map.get(filters, "age"),
      "glasses" => Map.get(filters, "glasses"),
      "tattoo" => Map.get(filters, "tattoo")
    } |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end) |> Map.new()
    
    # Filter out special filters from crop filters (they're handled separately)
    crop_filters = filters 
    |> Map.drop(["object_type", "event_type", "upper_clothing_color", "lower_clothing_color", "age", "glasses", "tattoo"])

    # === CROP-BASED TRACKING IDs ===
    crop_tracking_query = from(c in Crop,
      where: not is_nil(c.ref_tracking_id) and c.ref_tracking_id != "",
      group_by: c.ref_tracking_id,
      select: %{tracking_id: c.ref_tracking_id, latest: max(c.inserted_at)},
      order_by: [desc: max(c.inserted_at)]
    )
    crop_tracking_query = apply_filters_grouped_tracking(crop_tracking_query, crop_filters)
    
    # Apply event_type filter
    crop_tracking_query = if event_type do
      from(c in crop_tracking_query,
        join: ae in AIAnalyticsEvent, on: ae.ref_tracking_id == c.ref_tracking_id,
        where: ae.event_type == ^event_type,
        where: is_nil(ae.area_name) or ae.area_name != "__fs_attr_area"
      )
    else
      crop_tracking_query
    end
    
    # Apply object_type filter
    crop_tracking_query = if object_type do
      from(c in crop_tracking_query,
        join: t in Track, on: t.tracking_id == c.ref_tracking_id,
        where: t.object_class == ^object_type
      )
    else
      crop_tracking_query
    end
    
    # Apply attribute filters
    crop_tracking_query = apply_attribute_filters_tracking(crop_tracking_query, attr_filters)

    crop_results = Repo.all(crop_tracking_query)
    crop_tracking_ids = Enum.map(crop_results, & &1.tracking_id)

    # === CROPLESS TRACKING IDs (from AIAnalyticsEvent only) ===
    cropless_query = from(ae in AIAnalyticsEvent,
      where: not is_nil(ae.ref_tracking_id) and ae.ref_tracking_id != "",
      where: is_nil(ae.area_name) or ae.area_name != "__fs_attr_area",
      where: ae.event_type not in ["event-activity", "event-activity-end"],
      group_by: ae.ref_tracking_id,
      select: %{tracking_id: ae.ref_tracking_id, latest: max(ae.inserted_at)}
    )

    # Apply device filter
    cropless_query = if device_id = Map.get(crop_filters, "device_id") do
      from(ae in cropless_query, where: ae.device_id == ^device_id)
    else
      cropless_query
    end

    # Apply event_type filter
    cropless_query = if event_type do
      from(ae in cropless_query, where: ae.event_type == ^event_type)
    else
      cropless_query
    end

    # Apply object_class filter
    cropless_query = if object_type do
      from(ae in cropless_query, where: ae.object_class == ^object_type)
    else
      cropless_query
    end

    cropless_results = Repo.all(cropless_query)
    |> Enum.reject(fn r -> r.tracking_id in crop_tracking_ids end)

    # === MERGE & PAGINATE ===
    all_results = (Enum.map(crop_results, &{&1.tracking_id, &1.latest}) ++ 
                   Enum.map(cropless_results, &{&1.tracking_id, &1.latest}))
    |> Enum.sort_by(fn {_id, latest} -> latest end, {:desc, DateTime})

    total_count = length(all_results)
    total_pages = max(ceil(total_count / per_page), 1)

    page_tracking_ids = all_results
    |> Enum.drop((page - 1) * per_page)
    |> Enum.take(per_page)
    |> Enum.map(fn {id, _} -> id end)

    # Build grouped data for each tracking ID
    grouped_events = build_grouped_events(page_tracking_ids)

    meta = %{
      total_count: total_count,
      total_pages: total_pages,
      current_page: page
    }

    assign(socket, grouped_events: grouped_events, meta: meta)
  end


  defp apply_filters_grouped_tracking(query, filters) do
    Enum.reduce(filters, query, fn
      {"device_id", device_id}, q -> where(q, [c], c.device_id == ^device_id)
      {"min_confidence", min_conf}, q -> 
        min_val = String.to_float(min_conf)
        where(q, [c], c.confidence >= ^min_val)
      _, q -> q
    end)
  end

  defp apply_attribute_filters_tracking(query, attr_filters) when map_size(attr_filters) == 0, do: query
  defp apply_attribute_filters_tracking(query, attr_filters) do
    Enum.reduce(attr_filters, query, fn {attr_name, attr_value}, q ->
      db_attr_name = case attr_name do
        "upper_clothing_color" -> "upper_clothing_color"
        "lower_clothing_color" -> "lower_clothing_color"
        "age" -> "age"
        "glasses" -> "glasses"
        "tattoo" -> "tattoo"
        _ -> attr_name
      end
      
      tracking_subquery = from(a in Attribute,
        where: a.name == ^db_attr_name and like(fragment("lower(?)", a.value), ^"#{String.downcase(attr_value)}"),
        select: a.ref_tracking_id
      )
      
      from(c in q, where: c.ref_tracking_id in subquery(tracking_subquery))
    end)
  end

  defp build_grouped_events(tracking_ids) do
    Enum.map(tracking_ids, fn tracking_id ->
      # Get crops for this tracking ID
      crops = from(c in Crop,
        where: c.ref_tracking_id == ^tracking_id,
        order_by: [desc: c.inserted_at],
        limit: 10
      ) |> Repo.all()

      # Get the first/best crop
      first_crop = List.first(crops)

      # Get attributes for this tracking ID
      attributes = from(a in Attribute,
        where: a.ref_tracking_id == ^tracking_id,
        order_by: [asc: a.name]
      ) 
      |> Repo.all()
      |> Enum.uniq_by(fn a -> {a.name, a.value} end)

      # Get object_class from Track
      track = from(t in Track,
        where: t.tracking_id == ^tracking_id,
        order_by: [desc: t.inserted_at],
        limit: 1
      ) |> Repo.one()
      object_class = if track, do: track.object_class, else: nil

      # Get all events for this tracking ID
      events = from(e in AIAnalyticsEvent,
        where: e.ref_tracking_id == ^tracking_id,
        order_by: [desc: e.inserted_at]
      ) |> Repo.all()

      latest_event = List.first(events)

      # Get all distinct event types for display
      event_types = events
      |> Enum.map(& &1.event_type)
      |> Enum.uniq()
      |> Enum.reject(&is_nil/1)

      # Compute duration from min/max timestamps
      duration = if length(events) > 1 do
        first_time = events |> Enum.map(& &1.inserted_at) |> Enum.min(DateTime)
        last_time = events |> Enum.map(& &1.inserted_at) |> Enum.max(DateTime)
        seconds = DateTime.diff(last_time, first_time, :second)
        cond do
          seconds >= 3600 ->
            h = div(seconds, 3600)
            m = div(rem(seconds, 3600), 60)
            "#{h}h #{m}m"
          seconds >= 60 ->
            m = div(seconds, 60)
            s = rem(seconds, 60)
            "#{m}m #{s}s"
          seconds > 0 ->
            "#{seconds}s"
          true -> nil
        end
      else
        nil
      end

      # Determine primary event type (prefer non-end types)
      primary_type = if latest_event do
        non_end = Enum.find(event_types, fn t -> not String.ends_with?(t, "-end") end)
        non_end || latest_event.event_type
      else
        nil
      end

      timestamp = cond do
        first_crop -> first_crop.inserted_at
        latest_event -> latest_event.inserted_at
        true -> nil
      end

      # Extract zone_name (area_name) and line_name (tripwire_name) from events
      zone_name = events
      |> Enum.find_value(fn e -> e.area_name end)
      
      line_name = events
      |> Enum.find_value(fn e -> 
        raw = e.raw_data || %{}
        raw["tripwire_name"]
      end)

      # Determine if event is ongoing (has start but no end)
      paired_prefixes = ["event-loitering", "event-intrusion", "event-activity"]
      has_start = Enum.any?(event_types, fn t -> Enum.any?(paired_prefixes, fn p -> t == p end) end)
      has_end = Enum.any?(event_types, fn t -> String.ends_with?(t, "-end") end)
      status = cond do
        has_start && !has_end -> :ongoing
        has_start && has_end -> :ended
        true -> nil
      end

      {tracking_id, %{
        crop: first_crop,
        crops: crops,
        crops_count: length(crops),
        tracking_ids: [tracking_id],
        attributes: attributes,
        object_class: object_class,
        event_type: primary_type,
        event_types: event_types,
        area_name: zone_name,
        zone_name: zone_name,
        line_name: line_name,
        duration: duration,
        event_count: length(events),
        timestamp: timestamp,
        status: status
      }}
    end)
  end

  defp event_type_color("event-intrusion"), do: "bg-red-900/60 border border-red-600 text-red-300"
  defp event_type_color("event-intrusion-end"), do: "bg-red-900/40 border border-red-800 text-red-400"
  defp event_type_color("event-loitering"), do: "bg-yellow-900/60 border border-yellow-600 text-yellow-300"
  defp event_type_color("event-loitering-end"), do: "bg-yellow-900/40 border border-yellow-800 text-yellow-400"
  defp event_type_color("event-area-enter"), do: "bg-blue-900/60 border border-blue-600 text-blue-300"
  defp event_type_color("event-area-exit"), do: "bg-indigo-900/60 border border-indigo-600 text-indigo-300"
  defp event_type_color("event-line-crossing"), do: "bg-orange-900/60 border border-orange-600 text-orange-300"
  defp event_type_color("event-crowd"), do: "bg-pink-900/60 border border-pink-600 text-pink-300"
  defp event_type_color("event-activity"), do: "bg-cyan-900/60 border border-cyan-600 text-cyan-300"
  defp event_type_color("event-activity-end"), do: "bg-cyan-900/40 border border-cyan-800 text-cyan-400"
  defp event_type_color("event-dwelling"), do: "bg-purple-900/60 border border-purple-600 text-purple-300"
  defp event_type_color(_), do: "bg-green-900/50 border border-green-700 text-green-300"

  defp format_event_type(nil), do: nil
  defp format_event_type(event_type) do
    event_type
    |> String.replace("event-", "")
    |> String.replace("-", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp format_attribute_name(name) do
    name
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp truncate_value(value) when is_binary(value) do
    if String.length(value) > 15, do: String.slice(value, 0..12) <> "...", else: value
  end
  defp truncate_value(value), do: inspect(value)

  # Get base64 image from crop - supports both struct and path
  defp get_base64_image(nil), do: nil
  defp get_base64_image(crop) when is_struct(crop) do
    # Read from file if image_path exists
    if crop.image_path && crop.image_path != "" do
      read_image_as_base64(crop.image_path)
    else
      nil
    end
  end
  defp get_base64_image(path) when is_binary(path) do
    read_image_as_base64(path)
  end

  defp read_image_as_base64(nil), do: nil
  defp read_image_as_base64(""), do: nil
  defp read_image_as_base64(path) do
    case File.read(path) do
      {:ok, data} ->
        ext = Path.extname(path) |> String.downcase()
        mime = case ext do
          ".jpg" -> "image/jpeg"
          ".jpeg" -> "image/jpeg"
          ".png" -> "image/png"
          ".gif" -> "image/gif"
          ".webp" -> "image/webp"
          _ -> "image/jpeg"
        end
        "data:#{mime};base64,#{Base.encode64(data)}"
      {:error, _reason} -> 
        nil
    end
  end
end
