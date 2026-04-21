defmodule TProNVRWeb.AnalyticsEventsLive do
  @moduledoc """
  LiveView for displaying AI Analytics events from CVEDIX-RT.
  Shows events with filtering and pagination.
  """
  use TProNVRWeb, :live_view

  alias TProNVR.Events
  alias TProNVR.Devices

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full space-y-6">
      <div class="flex justify-between items-center">
        <h1 class="text-2xl font-bold text-white">AI Analytics Events</h1>
        <div class="text-sm text-white/60">
          Total: <%= @meta.total_count || 0 %> events
        </div>
      </div>

      <!-- Filters -->
      <.form for={@filter_form} phx-change="filter" class="bg-green-900 rounded-lg p-4">
        <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
          <div>
            <label class="block text-sm font-medium text-white/80 mb-1">Event Type</label>
            <select name="event_type" class="w-full bg-green-800 border-green-700 text-white rounded-md px-3 py-2">
              <option value="">All Types</option>
              <option value="intrusion" selected={@filters["event_type"] == "intrusion"}>Intrusion</option>
              <option value="loitering" selected={@filters["event_type"] == "loitering"}>Loitering</option>
              <option value="crowding" selected={@filters["event_type"] == "crowding"}>Crowding</option>
              <option value="crossing" selected={@filters["event_type"] == "crossing"}>Crossing</option>
              <option value="tailgating" selected={@filters["event_type"] == "tailgating"}>Tailgating</option>
              <option value="line_counting" selected={@filters["event_type"] == "line_counting"}>Line Counting</option>
              <option value="face_detection" selected={@filters["event_type"] == "face_detection"}>Face Detection</option>
              <option value="fire_detection" selected={@filters["event_type"] == "fire_detection"}>Fire Detection</option>
            </select>
          </div>

          <div>
            <label class="block text-sm font-medium text-white/80 mb-1">Object Class</label>
            <select name="object_class" class="w-full bg-green-800 border-green-700 text-white rounded-md px-3 py-2">
              <option value="">All Classes</option>
              <option value="Person" selected={@filters["object_class"] == "Person"}>Person</option>
              <option value="Vehicle" selected={@filters["object_class"] == "Vehicle"}>Vehicle</option>
              <option value="Face" selected={@filters["object_class"] == "Face"}>Face</option>
              <option value="Fire" selected={@filters["object_class"] == "Fire"}>Fire</option>
            </select>
          </div>

          <div>
            <label class="block text-sm font-medium text-white/80 mb-1">Device</label>
            <select name="device_id" class="w-full bg-green-800 border-green-700 text-white rounded-md px-3 py-2">
              <option value="">All Devices</option>
              <%= for {name, id} <- @devices do %>
                <option value={id} selected={@filters["device_id"] == id}><%= name %></option>
              <% end %>
            </select>
          </div>

          <div>
            <label class="block text-sm font-medium text-white/80 mb-1">Zone Name</label>
            <input
              type="text"
              name="zone_name"
              value={@filters["zone_name"] || ""}
              placeholder="Filter by zone..."
              class="w-full bg-green-800 border-green-700 text-white rounded-md px-3 py-2"
              phx-debounce="500"
            />
          </div>
        </div>
      </.form>

      <!-- Events Table -->
      <div class="bg-green-900 rounded-lg overflow-hidden">
        <table class="w-full">
          <thead class="bg-black">
            <tr>
              <th class="px-4 py-3 text-left text-sm font-medium text-white/80">Time</th>
              <th class="px-4 py-3 text-left text-sm font-medium text-white/80">Device</th>
              <th class="px-4 py-3 text-left text-sm font-medium text-white/80">Event Type</th>
              <th class="px-4 py-3 text-left text-sm font-medium text-white/80">Object</th>
              <th class="px-4 py-3 text-left text-sm font-medium text-white/80">Zone</th>
              <th class="px-4 py-3 text-left text-sm font-medium text-white/80">Attributes</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-green-700">
            <%= if Enum.empty?(@events) do %>
              <tr>
                <td colspan="6" class="px-4 py-8 text-center text-white/60">
                  No analytics events found
                </td>
              </tr>
            <% else %>
              <%= for event <- @events do %>
                <tr class="hover:bg-green-800/50">
                  <td class="px-4 py-3 text-sm text-white/80">
                    <%= Calendar.strftime(event.event_time, "%Y-%m-%d %H:%M:%S") %>
                  </td>
                  <td class="px-4 py-3 text-sm text-white/80">
                    <%= if event.device, do: event.device.name, else: "N/A" %>
                  </td>
                  <td class="px-4 py-3">
                    <span class={"px-2 py-1 text-xs rounded-full #{event_type_color(event.event_type)}"}>
                      <%= format_event_type(event.event_type) %>
                    </span>
                  </td>
                  <td class="px-4 py-3 text-sm text-white/80">
                    <%= event.object_class || "N/A" %>
                  </td>
                  <td class="px-4 py-3 text-sm text-white/80">
                    <%= event.zone_name || "N/A" %>
                  </td>
                  <td class="px-4 py-3 text-sm text-white/60">
                    <%= format_attributes(event.attributes) %>
                  </td>
                </tr>
              <% end %>
            <% end %>
          </tbody>
        </table>
      </div>

      <!-- Pagination -->
      <div class="flex justify-center">
        <.simple_pagination meta={@meta} />
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    devices = Devices.list() |> TProNVR.Accounts.Permissions.filter_devices(socket.assigns.current_user) |> Enum.map(fn d -> {d.name, d.id} end)

    {:ok,
     socket
     |> assign(:devices, devices)
     |> assign(:filters, %{})
     |> assign(:filter_form, to_form(%{}))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = Map.take(params, ["event_type", "object_class", "device_id", "zone_name"])
    
    {:noreply,
     socket
     |> assign(:filters, filters)
     |> load_events(params)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters = Map.take(params, ["event_type", "object_class", "device_id", "zone_name"])
    |> Enum.reject(fn {_k, v} -> v == "" end)
    |> Map.new()

    {:noreply, push_patch(socket, to: ~p"/events/ai-analytics?#{filters}")}
  end

  @impl true
  def handle_event("paginate", %{"page" => page}, socket) do
    params = Map.merge(socket.assigns.filters, %{"page" => page})
    {:noreply, push_patch(socket, to: ~p"/events/ai-analytics?#{params}")}
  end

  defp load_events(socket, params) do
    case Events.list_analytics_events(params) do
      {:ok, {events, meta}} ->
        assign(socket, events: events, meta: meta)

      {:error, meta} ->
        assign(socket, events: [], meta: meta)
    end
  end

  defp format_event_type(nil), do: "Unknown"
  defp format_event_type(type) do
    type
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp event_type_color("intrusion"), do: "bg-red-600 text-white"
  defp event_type_color("loitering"), do: "bg-orange-600 text-white"
  defp event_type_color("crowding"), do: "bg-yellow-600 text-black"
  defp event_type_color("crossing"), do: "bg-blue-600 text-white"
  defp event_type_color("tailgating"), do: "bg-purple-600 text-white"
  defp event_type_color("line_counting"), do: "bg-green-600 text-white"
  defp event_type_color("face_detection"), do: "bg-pink-600 text-white"
  defp event_type_color("fire_detection"), do: "bg-red-800 text-white"
  defp event_type_color(_), do: "bg-green-700 text-white"

  defp format_attributes(nil), do: "-"
  defp format_attributes(attrs) when map_size(attrs) == 0, do: "-"
  defp format_attributes(attrs) do
    attrs
    |> Enum.take(3)
    |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
    |> Enum.join(", ")
  end

  # Simple pagination component
  defp simple_pagination(assigns) do
    ~H"""
    <nav class="flex items-center gap-2" :if={@meta.total_pages > 1}>
      <button
        :if={@meta.current_page > 1}
        phx-click="paginate"
        phx-value-page={@meta.current_page - 1}
        class="px-3 py-1 bg-green-800 hover:bg-green-700 text-white rounded"
      >
        Previous
      </button>
      
      <span class="text-white/60 px-2">
        Page <%= @meta.current_page %> of <%= @meta.total_pages %>
      </span>
      
      <button
        :if={@meta.current_page < @meta.total_pages}
        phx-click="paginate"
        phx-value-page={@meta.current_page + 1}
        class="px-3 py-1 bg-green-800 hover:bg-green-700 text-white rounded"
      >
        Next
      </button>
    </nav>
    """
  end
end
