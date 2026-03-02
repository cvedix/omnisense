defmodule TProNVRWeb.DeviceTabs.CropLogTab do
  @moduledoc """
  AI Crop Log tab for device details page.
  Shows cropped images from CVEDIX-RT object detection.
  """
  use TProNVRWeb, :live_component

  alias TProNVR.CVEDIX.Crop
  alias TProNVR.Repo

  import Ecto.Query

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-3">
      <!-- Filters row -->
      <div class="flex items-center gap-6">
        <.form for={@filter_form} phx-change="filter" phx-target={@myself} class="flex items-center gap-3" style="width: 400px;">
          <input
            type="text"
            name="ref_tracking_id"
            value={@filters["ref_tracking_id"] || ""}
            placeholder="Search Tracking ID..."
            class="flex-1 bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm"
            phx-debounce="500"
          />
          
          <select name="view_mode" phx-change="change_view" phx-target={@myself} class="flex-1 bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm">
            <option value="grid" selected={@view_mode == "grid"}>Grid</option>
            <option value="table" selected={@view_mode == "table"}>Table</option>
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

      <!-- Grid View -->
      <%= if @view_mode == "grid" do %>
        <div class="border border-green-600 rounded p-3">
          <%= if Enum.empty?(@crops) do %>
            <div class="text-center text-white/50 py-8">
              No crop images found
            </div>
          <% else %>
            <div class="grid grid-cols-3 md:grid-cols-5 lg:grid-cols-8 gap-2">
              <%= for crop <- @crops do %>
                <div class="bg-black border border-green-900 rounded overflow-hidden">
                  <%= if crop.image_path && File.exists?(crop.image_path) do %>
                    <img src={get_base64_image(crop.image_path)} 
                         alt="Crop" class="w-full aspect-square object-contain bg-black" />
                  <% else %>
                    <div class="w-full aspect-square bg-green-900/20 flex items-center justify-center text-white/30 text-xs">
                      No Img
                    </div>
                  <% end %>
                  <div class="p-1 text-center">
                    <div class="text-xs text-green-400 truncate">
                      <%= String.slice(crop.ref_tracking_id || "", 0..5) %>..
                    </div>
                    <div class="text-xs text-white/40">
                      <%= Calendar.strftime(crop.inserted_at, "%H:%M:%S") %>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% else %>
        <!-- Table View -->
        <div class="border border-green-600 rounded overflow-hidden">
          <div class="overflow-x-auto">
            <div class="overflow-y-auto max-h-[60vh]">
              <table class="w-full">
                <thead class="bg-black border-b border-green-600">
                  <tr>
                    <th class="px-3 py-2 text-left text-xs font-medium text-white uppercase">Time</th>
                    <th class="px-3 py-2 text-left text-xs font-medium text-white uppercase">Tracking ID</th>
                    <th class="px-3 py-2 text-left text-xs font-medium text-white uppercase">Event ID</th>
                    <th class="px-3 py-2 text-left text-xs font-medium text-white uppercase">Confidence</th>
                    <th class="px-3 py-2 text-left text-xs font-medium text-white uppercase">Location</th>
                    <th class="px-3 py-2 text-left text-xs font-medium text-white uppercase">Image</th>
                  </tr>
                </thead>
                <tbody class="bg-black divide-y divide-green-900">
                  <%= if Enum.empty?(@crops) do %>
                    <tr>
                      <td colspan="6" class="px-4 py-8 text-center text-white/50">
                        No crop images found
                      </td>
                    </tr>
                  <% else %>
                    <%= for crop <- @crops do %>
                      <tr class="hover:bg-green-900/20">
                        <td class="px-3 py-2 text-xs text-white whitespace-nowrap">
                          <%= Calendar.strftime(crop.inserted_at, "%H:%M:%S") %>
                        </td>
                        <td class="px-3 py-2 text-xs font-mono text-green-400">
                          <%= String.slice(crop.ref_tracking_id || "", 0..7) %>...
                        </td>
                        <td class="px-3 py-2 text-xs font-mono text-white">
                          <%= String.slice(crop.ref_event_id || "", 0..7) %>...
                        </td>
                        <td class="px-3 py-2 text-xs text-white">
                          <%= if crop.confidence, do: "#{Float.round(crop.confidence * 100, 1)}%", else: "-" %>
                        </td>
                        <td class="px-3 py-2 text-xs font-mono text-white">
                          <%= format_location(crop) %>
                        </td>
                        <td class="px-3 py-2">
                          <%= if crop.image_path do %>
                            <span class="text-xs text-green-400">✓</span>
                          <% else %>
                            <span class="text-xs text-white/30">-</span>
                          <% end %>
                        </td>
                      </tr>
                    <% end %>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      <% end %>

      <!-- Pagination -->
      <div class="flex justify-between items-center text-sm">
        <span class="text-white/60">
          Showing <%= length(@crops) %> of <%= @meta.total_count || 0 %>
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
    # Auto-refresh triggered - reload and schedule next
    timer_ref = if socket.assigns.auto_refresh > 0 do
      Process.send_after(self(), {:auto_refresh_component, socket.assigns.myself}, socket.assigns.auto_refresh * 1000)
    else
      nil
    end
    
    {:ok,
     socket
     |> load_crops()
     |> assign(:timer_ref, timer_ref)}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:filters, fn -> %{} end)
     |> assign_new(:filter_form, fn -> to_form(%{}) end)
     |> assign_new(:view_mode, fn -> "grid" end)
     |> assign_new(:per_page, fn -> 50 end)
     |> assign_new(:auto_refresh, fn -> 0 end)
     |> assign_new(:timer_ref, fn -> nil end)
     |> load_crops()}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters = Map.take(params, ["ref_tracking_id"])
    |> Enum.reject(fn {_k, v} -> v == "" end)
    |> Map.new()

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:page, 1)
     |> load_crops()}
  end

  @impl true
  def handle_event("change_view", %{"view_mode" => view_mode}, socket) do
    {:noreply, assign(socket, :view_mode, view_mode)}
  end

  @impl true
  def handle_event("change_per_page", %{"per_page" => per_page}, socket) do
    {:noreply,
     socket
     |> assign(:per_page, String.to_integer(per_page))
     |> assign(:page, 1)
     |> load_crops()}
  end

  @impl true
  def handle_event("paginate", %{"page" => page}, socket) do
    {:noreply,
     socket
     |> assign(:page, String.to_integer(page))
     |> load_crops()}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_crops(socket)}
  end

  @impl true
  def handle_event("set_auto_refresh", %{"value" => value}, socket) do
    interval = String.to_integer(value)
    
    # Cancel existing timer if any
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

  defp load_crops(socket) do
    device_id = socket.assigns.device.id
    filters = Map.get(socket.assigns, :filters, %{})
    page = Map.get(socket.assigns, :page, 1)
    per_page = Map.get(socket.assigns, :per_page, 50)

    query = from(c in Crop,
      where: c.device_id == ^device_id,
      order_by: [desc: c.inserted_at]
    )

    query = apply_filters(query, filters)
    
    total_count = Repo.aggregate(query, :count)
    total_pages = max(ceil(total_count / per_page), 1)
    
    crops = query
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()

    meta = %{
      total_count: total_count,
      total_pages: total_pages,
      current_page: page
    }

    assign(socket, crops: crops, meta: meta)
  end

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {"ref_tracking_id", id}, q -> where(q, [c], ilike(c.ref_tracking_id, ^"%#{id}%"))
      _, q -> q
    end)
  end

  defp format_location(crop) do
    x = Float.round((crop.location_x || 0) * 100, 1)
    y = Float.round((crop.location_y || 0) * 100, 1)
    w = Float.round((crop.location_width || 0) * 100, 1)
    h = Float.round((crop.location_height || 0) * 100, 1)
    "#{x}%, #{y}%, #{w}%, #{h}%"
  end

  defp get_base64_image(path) when is_binary(path) do
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
      _ ->
        ""
    end
  end
  defp get_base64_image(_), do: ""
end
