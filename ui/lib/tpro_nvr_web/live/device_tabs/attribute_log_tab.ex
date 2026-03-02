defmodule TProNVRWeb.DeviceTabs.AttributeLogTab do
  @moduledoc """
  AI Attribute Log tab for device details page.
  Shows detected object attributes from CVEDIX-RT.
  """
  use TProNVRWeb, :live_component

  alias TProNVR.CVEDIX.Attribute
  alias TProNVR.Repo

  import Ecto.Query

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-3">
      <!-- Filters row -->
      <div class="flex items-center gap-6">
        <.form for={@filter_form} phx-change="filter" phx-target={@myself} class="flex items-center gap-3" style="width: 500px;">
          <select name="name" class="flex-1 bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm">
            <option value="">All Attributes</option>
            <option value="age" selected={@filters["name"] == "age"}>Age</option>
            <option value="gender" selected={@filters["name"] == "gender"}>Gender</option>
            <option value="glasses" selected={@filters["name"] == "glasses"}>Glasses</option>
            <option value="upper_clothing_color" selected={@filters["name"] == "upper_clothing_color"}>Upper Clothing</option>
            <option value="carrying_bag" selected={@filters["name"] == "carrying_bag"}>Carrying Bag</option>
            <option value="tattoo" selected={@filters["name"] == "tattoo"}>Tattoo</option>
            <option value="phone" selected={@filters["name"] == "phone"}>Phone</option>
            <option value="smoking" selected={@filters["name"] == "smoking"}>Smoking</option>
            <option value="face_covered" selected={@filters["name"] == "face_covered"}>Face Covered</option>
          </select>
          
          <input
            type="text"
            name="ref_tracking_id"
            value={@filters["ref_tracking_id"] || ""}
            placeholder="Tracking ID..."
            class="flex-1 bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm"
            phx-debounce="500"
          />
          
          <select name="per_page" phx-change="change_per_page" phx-target={@myself} class="flex-1 bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm">
            <option value="50" selected={@per_page == 50}>50</option>
            <option value="100" selected={@per_page == 100}>100</option>
            <option value="200" selected={@per_page == 200}>200</option>
          </select>
        </.form>
        
        <div class="flex items-center gap-3 whitespace-nowrap">
          <span class="text-sm text-green-400 font-medium"><%= @meta.total_count || 0 %></span>
          <select phx-change="set_auto_refresh" phx-target={@myself} class="bg-black border border-green-600 text-white rounded px-2 py-1.5 text-sm">
            <option value="0" selected={@auto_refresh == 0}>Manual</option>
            <option value="5" selected={@auto_refresh == 5}>5s</option>
            <option value="10" selected={@auto_refresh == 10}>10s</option>
            <option value="15" selected={@auto_refresh == 15}>15s</option>
            <option value="30" selected={@auto_refresh == 30}>30s</option>
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

      <!-- Attribute Log Table with green border -->
      <div class="border border-green-600 rounded overflow-hidden">
        <div class="overflow-x-auto">
          <div class="overflow-y-auto max-h-[60vh]">
            <table class="w-full">
              <thead class="bg-black border-b border-green-600">
                <tr>
                  <th class="px-3 py-2 text-left text-xs font-medium text-white uppercase">Time</th>
                  <th class="px-3 py-2 text-left text-xs font-medium text-white uppercase">Tracking ID</th>
                  <th class="px-3 py-2 text-left text-xs font-medium text-white uppercase">Attribute</th>
                  <th class="px-3 py-2 text-left text-xs font-medium text-white uppercase">Value</th>
                </tr>
              </thead>
              <tbody class="bg-black divide-y divide-green-900">
                <%= if Enum.empty?(@attributes) do %>
                  <tr>
                    <td colspan="4" class="px-4 py-8 text-center text-white/50">
                      No attribute logs found
                    </td>
                  </tr>
                <% else %>
                  <%= for attr <- @attributes do %>
                    <tr class="hover:bg-green-900/20">
                      <td class="px-3 py-2 text-xs text-white whitespace-nowrap">
                        <%= Calendar.strftime(attr.inserted_at, "%d/%m/%Y %H:%M:%S") %>
                      </td>
                      <td class="px-3 py-2 text-xs font-mono text-green-400">
                        <%= String.slice(attr.ref_tracking_id || "", 0..7) %>...
                      </td>
                      <td class="px-3 py-2 text-xs text-white font-medium">
                        <%= format_attribute_name(attr.name) %>
                      </td>
                      <td class="px-3 py-2 text-xs text-white max-w-[200px] truncate" title={format_attribute_value(attr.name, attr.value)}>
                        <%= format_attribute_value(attr.name, attr.value) %>
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
          Showing <%= length(@attributes) %> of <%= @meta.total_count || 0 %>
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
     |> load_attributes()
     |> assign(:timer_ref, timer_ref)}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:filters, fn -> %{} end)
     |> assign_new(:filter_form, fn -> to_form(%{}) end)
     |> assign_new(:per_page, fn -> 100 end)
     |> assign_new(:auto_refresh, fn -> 0 end)
     |> assign_new(:timer_ref, fn -> nil end)
     |> load_attributes()}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters = Map.take(params, ["name", "ref_tracking_id"])
    |> Enum.reject(fn {_k, v} -> v == "" end)
    |> Map.new()

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:page, 1)
     |> load_attributes()}
  end

  @impl true
  def handle_event("change_per_page", %{"per_page" => per_page}, socket) do
    {:noreply,
     socket
     |> assign(:per_page, String.to_integer(per_page))
     |> assign(:page, 1)
     |> load_attributes()}
  end

  @impl true
  def handle_event("paginate", %{"page" => page}, socket) do
    {:noreply,
     socket
     |> assign(:page, String.to_integer(page))
     |> load_attributes()}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_attributes(socket)}
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

  defp load_attributes(socket) do
    device_id = socket.assigns.device.id
    filters = Map.get(socket.assigns, :filters, %{})
    page = Map.get(socket.assigns, :page, 1)
    per_page = Map.get(socket.assigns, :per_page, 100)

    query = from(a in Attribute,
      where: a.device_id == ^device_id,
      order_by: [desc: a.inserted_at]
    )

    query = apply_filters(query, filters)
    
    total_count = Repo.aggregate(query, :count)
    total_pages = max(ceil(total_count / per_page), 1)
    
    attributes = query
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()

    meta = %{
      total_count: total_count,
      total_pages: total_pages,
      current_page: page
    }

    assign(socket, attributes: attributes, meta: meta)
  end

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {"name", name}, q -> where(q, [a], a.name == ^name)
      {"ref_tracking_id", id}, q -> where(q, [a], ilike(a.ref_tracking_id, ^"%#{id}%"))
      _, q -> q
    end)
  end

  defp format_attribute_name(name) do
    name
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp format_attribute_value(name, value) when is_binary(value) do
    case name do
      "age" -> "#{value} years"
      "upper_clothing_color" -> String.upcase(value)
      _ -> value
    end
  end
  defp format_attribute_value(_name, value), do: inspect(value)
end
