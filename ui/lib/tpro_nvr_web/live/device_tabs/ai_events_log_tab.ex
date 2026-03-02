defmodule TProNVRWeb.DeviceTabs.AIEventsLogTab do
  @moduledoc """
  AI Analytics Events Log tab for device details page.
  Shows area-based events from CVEDIX-RT:
  - event-intrusion
  - event-intrusion-end
  - event-area-enter
  - event-area-exit
  """
  use TProNVRWeb, :live_component

  alias TProNVR.CVEDIX.AIAnalyticsEvent
  alias TProNVR.Repo

  import Ecto.Query

  @event_type_colors %{
    "event-intrusion" => "bg-red-600",
    "event-intrusion-end" => "bg-orange-500",
    "event-area-enter" => "bg-green-600",
    "event-area-exit" => "bg-yellow-500",
    "event-loitering" => "bg-purple-600",
    "event-loitering-end" => "bg-purple-400",
    "event-line-crossing" => "bg-blue-500",
    "event-crowd" => "bg-pink-600",
    "event-activity" => "bg-cyan-600",
    "event-activity-end" => "bg-cyan-400",
    "event-dwelling" => "bg-teal-600"
  }

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-3">
      <!-- Filters row -->
      <div class="flex items-center gap-6">
        <.form for={@filter_form} phx-change="filter" phx-target={@myself} class="flex items-center gap-3" style="width: 600px;">
          <select name="event_type" class="flex-1 bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm">
            <option value="" selected={@filters["event_type"] == nil}>All Events</option>
            <option value="event-intrusion" selected={@filters["event_type"] == "event-intrusion"}>🚨 Intrusion</option>
            <option value="event-intrusion-end" selected={@filters["event_type"] == "event-intrusion-end"}>🔶 Intrusion End</option>
            <option value="event-area-enter" selected={@filters["event_type"] == "event-area-enter"}>🟢 Area Enter</option>
            <option value="event-area-exit" selected={@filters["event_type"] == "event-area-exit"}>🟡 Area Exit</option>
            <option value="event-loitering" selected={@filters["event_type"] == "event-loitering"}>🟣 Loitering</option>
            <option value="event-loitering-end" selected={@filters["event_type"] == "event-loitering-end"}>🟪 Loitering End</option>
            <option value="event-line-crossing" selected={@filters["event_type"] == "event-line-crossing"}>🔵 Line Crossing</option>
            <option value="event-crowd" selected={@filters["event_type"] == "event-crowd"}>👥 Crowd</option>
            <option value="event-activity" selected={@filters["event_type"] == "event-activity"}>🏃 Activity</option>
            <option value="event-activity-end" selected={@filters["event_type"] == "event-activity-end"}>🛑 Activity End</option>
          </select>
          
          <input
            type="text"
            name="area_name"
            value={@filters["area_name"] || ""}
            placeholder="Area Name..."
            class="flex-1 bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm"
            phx-debounce="500"
          />
          
          <select name="object_class" class="flex-1 bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm">
            <option value="" selected={@filters["object_class"] == nil}>All Classes</option>
            <option value="Person" selected={@filters["object_class"] == "Person"}>Person</option>
            <option value="Vehicle" selected={@filters["object_class"] == "Vehicle"}>Vehicle</option>
            <option value="Animal" selected={@filters["object_class"] == "Animal"}>Animal</option>
          </select>
          
          <select name="per_page" phx-change="change_per_page" phx-target={@myself} class="flex-1 bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm">
            <option value="20" selected={@per_page == 20}>20</option>
            <option value="50" selected={@per_page == 50}>50</option>
            <option value="100" selected={@per_page == 100}>100</option>
          </select>
        </.form>
        
        <div class="flex items-center gap-3 whitespace-nowrap">
          <span class="text-sm text-green-400 font-medium"><%= @meta.total_count || 0 %></span>
          <select phx-change="set_auto_refresh" phx-target={@myself} class="bg-black border border-green-600 text-white rounded px-2 py-1.5 text-sm">
            <option value="0" selected={@auto_refresh == 0}>Manual</option>
            <option value="5" selected={@auto_refresh == 5}>5s</option>
            <option value="10" selected={@auto_refresh == 10}>10s</option>
            <option value="15" selected={@auto_refresh == 15}>15s</option>
          </select>
          <button
            phx-click="refresh"
            phx-target={@myself}
            class="px-3 py-1.5 bg-green-700 hover:bg-green-600 text-white text-sm rounded"
          >
            ↻ Refresh
          </button>
        </div>
      </div>

      <!-- Table -->
      <div class="border border-green-600 rounded overflow-hidden">
        <div class="overflow-x-auto">
          <div class="overflow-y-auto max-h-[60vh]">
            <table class="w-full">
              <thead class="bg-black border-b border-green-600">
                <tr>
                  <th class="px-3 py-2 text-left text-xs font-medium text-white uppercase">Time</th>
                  <th class="px-3 py-2 text-left text-xs font-medium text-white uppercase">Event Type</th>
                  <th class="px-3 py-2 text-left text-xs font-medium text-white uppercase">Duration</th>
                  <th class="px-3 py-2 text-left text-xs font-medium text-white uppercase">Area</th>
                  <th class="px-3 py-2 text-left text-xs font-medium text-white uppercase">Object</th>
                  <th class="px-3 py-2 text-left text-xs font-medium text-white uppercase">Tracking ID</th>
                  <th class="px-3 py-2 text-left text-xs font-medium text-white uppercase">Location</th>
                </tr>
              </thead>
              <tbody class="bg-black divide-y divide-green-900">
                <%= if Enum.empty?(@events) do %>
                  <tr>
                    <td colspan="7" class="px-4 py-8 text-center text-white/50">
                      No analytics events found
                    </td>
                  </tr>
                <% else %>
                  <%= for event <- @events do %>
                    <tr class={"hover:bg-green-900/20 #{if event.type == :grouped, do: "border-l-2 border-l-purple-500", else: ""}"}
                    >
                      <td class="px-3 py-2 text-xs text-white whitespace-nowrap">
                        <%= Calendar.strftime(event.inserted_at, "%H:%M:%S") %>
                        <%= if event.type == :grouped && event.last_seen do %>
                          <span class="text-white/40">→ <%= Calendar.strftime(event.last_seen, "%H:%M:%S") %></span>
                        <% end %>
                      </td>
                      <td class="px-3 py-2 text-xs">
                        <div class="flex items-center gap-1">
                          <span class={"px-2 py-1 rounded text-white text-xs font-medium #{event_type_color(event.event_type)}"}>
                            <%= format_event_type(event.event_type) %>
                          </span>
                          <%= if event.type == :grouped do %>
                            <%= if event.has_ended do %>
                              <span class="px-1.5 py-0.5 bg-gray-700 text-gray-300 text-xs rounded">ended</span>
                            <% else %>
                              <span class="px-1.5 py-0.5 bg-green-700 text-green-200 text-xs rounded animate-pulse">active</span>
                            <% end %>
                          <% end %>
                        </div>
                      </td>
                      <td class="px-3 py-2 text-xs text-yellow-400 font-medium">
                        <%= format_duration(event) %>
                      </td>
                      <td class="px-3 py-2 text-xs text-red-400 font-medium">
                        <%= event.area_name || "-" %>
                      </td>
                      <td class="px-3 py-2 text-xs text-white">
                        <%= event.object_class || "-" %>
                      </td>
                      <td class="px-3 py-2 text-xs font-mono text-green-400">
                        <%= String.slice(event.ref_tracking_id || "", 0..7) %>...
                        <%= if event.type == :grouped && event.event_count > 1 do %>
                          <span class="ml-1 px-1.5 py-0.5 bg-purple-900/50 border border-purple-600 text-purple-300 text-xs rounded">
                            ×<%= event.event_count %>
                          </span>
                        <% end %>
                      </td>
                      <td class="px-3 py-2 text-xs font-mono text-white">
                        <%= format_location(event) %>
                      </td>
                    </tr>
                  <% end %>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <!-- Pagination -->
      <div class="flex justify-between items-center text-sm">
        <span class="text-white/60">
          Showing <%= length(@events) %> of <%= @meta.total_count || 0 %>
        </span>
        <nav class="flex items-center gap-2" :if={@meta.total_pages && @meta.total_pages > 1}>
          <button
            :if={@meta.current_page > 1}
            phx-click="paginate"
            phx-value-page={@meta.current_page - 1}
            phx-target={@myself}
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
            phx-target={@myself}
            class="px-2 py-1 border border-green-600 text-white rounded text-xs hover:bg-green-900/30"
          >
            Next →
          </button>
        </nav>
      </div>
    </div>
    """
  end

  @impl true
  def update(%{action: :auto_refresh_tick} = _assigns, socket) do
    timer_ref = if socket.assigns.auto_refresh > 0 do
      Process.send_after(self(), {:auto_refresh_component, socket.assigns.myself}, socket.assigns.auto_refresh * 1000)
    else
      nil
    end
    
    {:ok,
     socket
     |> load_events()
     |> assign(:timer_ref, timer_ref)}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:filters, fn -> %{} end)
     |> assign_new(:filter_form, fn -> to_form(%{}) end)
     |> assign_new(:per_page, fn -> 50 end)
     |> assign_new(:auto_refresh, fn -> 0 end)
     |> assign_new(:timer_ref, fn -> nil end)
     |> load_events()}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters = Map.take(params, ["event_type", "area_name", "object_class"])
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
  def handle_event("set_auto_refresh", %{"value" => value}, socket) do
    interval = String.to_integer(value)
    
    if socket.assigns[:timer_ref] do
      Process.cancel_timer(socket.assigns.timer_ref)
    end
    
    timer_ref = if interval > 0 do
      Process.send_after(self(), {:auto_refresh_component, socket.assigns.myself}, interval * 1000)
    else
      nil
    end
    
    {:noreply,
     socket
     |> assign(:auto_refresh, interval)
     |> assign(:timer_ref, timer_ref)}
  end

  # Groupable event types — these share ref_tracking_id and should be consolidated
  @groupable_prefixes ["event-loitering", "event-activity", "event-intrusion", "event-line-crossing", "event-area-enter", "event-area-exit"]

  defp load_events(socket) do
    device_id = socket.assigns.device.id
    filters = Map.get(socket.assigns, :filters, %{})
    page = Map.get(socket.assigns, :page, 1)
    per_page = Map.get(socket.assigns, :per_page, 50)
    requested_type = Map.get(filters, "event_type")

    base_query = from(e in AIAnalyticsEvent,
      where: e.device_id == ^device_id,
      where: is_nil(e.area_name) or e.area_name != "__fs_attr_area"
    )
    base_query = apply_non_type_filters(base_query, filters)

    # Decide if we're showing grouped or individual events
    show_grouped = is_nil(requested_type) or is_groupable_type?(requested_type)
    show_individual = is_nil(requested_type) or not is_groupable_type?(requested_type)

    grouped_rows = if show_grouped do
      build_grouped_rows(base_query, requested_type)
    else
      []
    end

    individual_rows = if show_individual do
      build_individual_rows(base_query, requested_type)
    else
      []
    end

    # Merge and sort by latest timestamp desc
    all_rows = (grouped_rows ++ individual_rows)
    |> Enum.sort_by(& &1.sort_time, {:desc, DateTime})

    total_count = length(all_rows)
    total_pages = max(ceil(total_count / per_page), 1)

    page_rows = all_rows
    |> Enum.drop((page - 1) * per_page)
    |> Enum.take(per_page)

    meta = %{
      total_count: total_count,
      total_pages: total_pages,
      current_page: page
    }

    assign(socket, events: page_rows, meta: meta)
  end

  defp is_groupable_type?(type) do
    Enum.any?(@groupable_prefixes, &String.starts_with?(type, &1))
  end

  defp build_grouped_rows(base_query, requested_type) do
    # Get groupable events
    groupable_types = if requested_type do
      [requested_type]
    else
      Enum.flat_map(@groupable_prefixes, fn prefix ->
        [prefix, "#{prefix}-end"]
      end)
    end

    query = from(e in base_query,
      where: e.event_type in ^groupable_types,
      where: not is_nil(e.ref_tracking_id) and e.ref_tracking_id != "",
      group_by: [e.ref_tracking_id],
      select: %{
        ref_tracking_id: e.ref_tracking_id,
        first_seen: min(e.inserted_at),
        last_seen: max(e.inserted_at),
        event_count: count(e.id),
        area_name: max(e.area_name),
        object_class: max(e.object_class),
        location_x: max(e.location_x),
        location_y: max(e.location_y)
      }
    )

    groups = Repo.all(query)

    Enum.map(groups, fn g ->
      # Calculate duration
      duration_seconds = DateTime.diff(g.last_seen, g.first_seen, :second)
      
      # Determine the "latest" event type for this tracking ID
      latest_event = from(e in AIAnalyticsEvent,
        where: e.ref_tracking_id == ^g.ref_tracking_id,
        where: e.event_type in ^groupable_types,
        order_by: [desc: e.inserted_at],
        limit: 1,
        select: %{event_type: e.event_type}
      ) |> Repo.one()

      # Check if the event ended
      has_ended = latest_event && String.ends_with?(latest_event.event_type, "-end")

      # Get the base event type (without -end suffix)
      base_type = if latest_event do
        String.replace(latest_event.event_type, "-end", "")
      else
        "event-loitering"
      end

      %{
        type: :grouped,
        sort_time: g.last_seen,
        inserted_at: g.first_seen,
        last_seen: g.last_seen,
        event_type: base_type,
        has_ended: has_ended,
        duration_seconds: duration_seconds,
        event_count: g.event_count,
        area_name: g.area_name,
        object_class: g.object_class,
        ref_tracking_id: g.ref_tracking_id,
        location_x: g.location_x,
        location_y: g.location_y,
        raw_data: %{}
      }
    end)
  end

  defp build_individual_rows(base_query, requested_type) do
    # Non-groupable event types
    non_groupable_types = if requested_type do
      [requested_type]
    else
      ["event-crowd", "event-dwelling"]
    end

    query = from(e in base_query,
      where: e.event_type in ^non_groupable_types,
      order_by: [desc: e.inserted_at]
    )

    Repo.all(query)
    |> Enum.map(fn e ->
      %{
        type: :individual,
        sort_time: e.inserted_at,
        inserted_at: e.inserted_at,
        last_seen: nil,
        event_type: e.event_type,
        has_ended: false,
        duration_seconds: 0,
        event_count: 1,
        area_name: e.area_name,
        object_class: e.object_class,
        ref_tracking_id: e.ref_tracking_id,
        location_x: e.location_x,
        location_y: e.location_y,
        raw_data: e.raw_data
      }
    end)
  end

  defp apply_non_type_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {"area_name", name}, q -> where(q, [e], ilike(e.area_name, ^"%#{name}%"))
      {"object_class", class}, q -> where(q, [e], e.object_class == ^class)
      _, q -> q
    end)
  end

  defp format_location(event) do
    x = Float.round((event.location_x || 0.0) * 1.0 * 100, 1)
    y = Float.round((event.location_y || 0.0) * 1.0 * 100, 1)
    "(#{x}%, #{y}%)"
  end

  defp format_event_type(type) do
    case type do
      "event-intrusion" -> "🚨 Intrusion"
      "event-intrusion-end" -> "🔶 End"
      "event-area-enter" -> "🟢 Enter"
      "event-area-exit" -> "🟡 Exit"
      "event-loitering" -> "🟣 Loitering"
      "event-loitering-end" -> "🟪 Loitering End"
      "event-line-crossing" -> "🔵 Line Crossing"
      "event-crowd" -> "👥 Crowd"
      "event-activity" -> "🏃 Activity"
      "event-activity-end" -> "🛑 Activity End"
      "event-dwelling" -> "🏠 Dwelling"
      _ -> type
    end
  end

  defp event_type_color(type) do
    Map.get(@event_type_colors, type, "bg-green-700")
  end

  defp format_duration(event) do
    cond do
      event.type == :grouped && event.duration_seconds > 0 ->
        minutes = div(event.duration_seconds, 60)
        seconds = rem(event.duration_seconds, 60)
        if minutes > 0, do: "#{minutes}m #{seconds}s", else: "#{seconds}s"
      event.type == :grouped ->
        "<1s"
      true ->
        "-"
    end
  end
end
