defmodule TProNVRWeb.DeviceTabs.AnalyticsEventsTab do
  @moduledoc """
  Analytics events tab for device details page.
  Shows AI Analytics events for a specific device.
  """
  use TProNVRWeb, :live_component

  alias TProNVR.Events

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <!-- Filters -->
      <.form for={@filter_form} phx-change="filter" phx-target={@myself} class="bg-green-900 rounded-lg p-4">
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div>
            <label class="block text-sm font-medium text-white/80 mb-1">Event Type</label>
            <select name="event_type" class="w-full bg-green-800 border-green-700 text-white rounded-md px-3 py-2">
              <option value="">All Types</option>
              <optgroup label="Detection Events">
                <option value="track" selected={@filters["event_type"] == "track"}>Track</option>
                <option value="crop" selected={@filters["event_type"] == "crop"}>Crop</option>
                <option value="attribute" selected={@filters["event_type"] == "attribute"}>Attribute</option>
                <option value="statistics" selected={@filters["event_type"] == "statistics"}>Statistics</option>
              </optgroup>
              <optgroup label="Zone Events">
                <option value="intrusion" selected={@filters["event_type"] == "intrusion"}>Intrusion</option>
                <option value="loitering" selected={@filters["event_type"] == "loitering"}>Loitering</option>
                <option value="crowding" selected={@filters["event_type"] == "crowding"}>Crowding</option>
                <option value="area_enter" selected={@filters["event_type"] == "area_enter"}>Area Enter</option>
                <option value="area_exit" selected={@filters["event_type"] == "area_exit"}>Area Exit</option>
                <option value="activity" selected={@filters["event_type"] == "activity"}>Activity</option>
              </optgroup>
              <optgroup label="Line Events">
                <option value="crossing" selected={@filters["event_type"] == "crossing"}>Crossing</option>
                <option value="tailgating" selected={@filters["event_type"] == "tailgating"}>Tailgating</option>
                <option value="line_counting" selected={@filters["event_type"] == "line_counting"}>Line Counting</option>
              </optgroup>
            </select>
          </div>

          <div>
            <label class="block text-sm font-medium text-white/80 mb-1">Object Class</label>
            <select name="object_class" class="w-full bg-green-800 border-green-700 text-white rounded-md px-3 py-2">
              <option value="">All Classes</option>
              <option value="Person" selected={@filters["object_class"] == "Person"}>Person</option>
              <option value="Vehicle" selected={@filters["object_class"] == "Vehicle"}>Vehicle</option>
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
        <div class="overflow-y-auto max-h-[60vh]">
          <table class="w-full">
            <thead class="bg-black sticky top-0">
              <tr>
                <th class="px-4 py-3 text-left text-sm font-medium text-white/80">Time</th>
                <th class="px-4 py-3 text-left text-sm font-medium text-white/80">Event Type</th>
                <th class="px-4 py-3 text-left text-sm font-medium text-white/80">Object</th>
                <th class="px-4 py-3 text-left text-sm font-medium text-white/80">Zone</th>
                <th class="px-4 py-3 text-left text-sm font-medium text-white/80">Direction</th>
                <th class="px-4 py-3 text-left text-sm font-medium text-white/80">Attributes</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-green-700">
              <%= if Enum.empty?(@events) do %>
                <tr>
                  <td colspan="6" class="px-4 py-8 text-center text-white/60">
                    No analytics events found for this device
                  </td>
                </tr>
              <% else %>
                <%= for event <- @events do %>
                  <tr class="hover:bg-green-800/50">
                    <td class="px-4 py-3 text-sm text-white/80">
                      <%= Calendar.strftime(event.event_time, "%Y-%m-%d %H:%M:%S") %>
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
                    <td class="px-4 py-3 text-sm text-white/80">
                      <%= event.direction || "-" %>
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
      </div>

      <!-- Pagination -->
      <div class="flex justify-between items-center">
        <div class="text-sm text-white/60">
          Total: <%= @meta.total_count || 0 %> events
        </div>
        <nav class="flex items-center gap-2" :if={@meta.total_pages && @meta.total_pages > 1}>
          <button
            :if={@meta.current_page > 1}
            phx-click="paginate"
            phx-value-page={@meta.current_page - 1}
            phx-target={@myself}
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
            phx-target={@myself}
            class="px-3 py-1 bg-green-800 hover:bg-green-700 text-white rounded"
          >
            Next
          </button>
        </nav>
      </div>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:filters, fn -> %{} end)
     |> assign_new(:filter_form, fn -> to_form(%{}) end)
     |> load_events()}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters = Map.take(params, ["event_type", "object_class", "zone_name"])
    |> Enum.reject(fn {_k, v} -> v == "" end)
    |> Map.new()

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> load_events()}
  end

  @impl true
  def handle_event("paginate", %{"page" => page}, socket) do
    {:noreply,
     socket
     |> assign(:page, String.to_integer(page))
     |> load_events()}
  end

  defp load_events(socket) do
    device_id = socket.assigns.device.id
    filters = Map.get(socket.assigns, :filters, %{})
    page = Map.get(socket.assigns, :page, 1)

    params = Map.merge(filters, %{"device_id" => device_id, "page" => page})

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

  defp event_type_color("track"), do: "bg-cyan-600 text-white"
  defp event_type_color("crop"), do: "bg-pink-600 text-white"
  defp event_type_color("attribute"), do: "bg-indigo-600 text-white"
  defp event_type_color("statistics"), do: "bg-teal-600 text-white"
  defp event_type_color("intrusion"), do: "bg-red-600 text-white"
  defp event_type_color("loitering"), do: "bg-orange-600 text-white"
  defp event_type_color("crowding"), do: "bg-yellow-600 text-black"
  defp event_type_color("crossing"), do: "bg-blue-600 text-white"
  defp event_type_color("tailgating"), do: "bg-purple-600 text-white"
  defp event_type_color("line_counting"), do: "bg-green-600 text-white"
  defp event_type_color("area_enter"), do: "bg-emerald-600 text-white"
  defp event_type_color("area_exit"), do: "bg-amber-600 text-white"
  defp event_type_color("activity"), do: "bg-lime-600 text-white"
  defp event_type_color(_), do: "bg-green-700 text-white"

  defp format_attributes(nil), do: "-"
  defp format_attributes(attrs) when map_size(attrs) == 0, do: "-"
  defp format_attributes(attrs) do
    attrs
    |> Enum.take(3)
    |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
    |> Enum.join(", ")
  end
end
