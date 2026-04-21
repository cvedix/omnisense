defmodule TProNVRWeb.CrossingChartLive do
  @moduledoc """
  Bar chart page showing line crossing event counts grouped by time period.
  Uses D3.js for client-side rendering via a Phoenix LiveView hook.
  """
  use TProNVRWeb, :live_view

  alias TProNVR.CVEDIX.AIAnalyticsEvent
  alias TProNVR.CVEDIX.Crop
  alias TProNVR.Repo

  import Ecto.Query

  @impl true
  def render(assigns) do
    ~H"""
    <div class="grow px-4 py-6">
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-xl font-semibold text-white">Báo Cáo Phân Tích Vượt Tuyến</h2>
        <button phx-click="refresh" class="px-3 py-1.5 bg-green-700 hover:bg-green-600 text-white text-sm rounded">↻ Làm Mới</button>
      </div>

      <!-- Filters -->
      <div class="flex items-center gap-3 mb-4">
        <.form for={@filter_form} phx-change="filter" class="flex items-center gap-3 flex-wrap">
          <select name="device_id" class="bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm">
            <option value="">Tất cả thiết bị</option>
            <%= for device <- @devices do %>
              <option value={device.id} selected={@filters["device_id"] == device.id}><%= device.name %></option>
            <% end %>
          </select>

          <select name="object_class" class="bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm">
            <option value="">Tất cả đối tượng</option>
            <%= for cls <- @object_classes do %>
              <option value={cls} selected={@filters["object_class"] == cls}><%= cls %></option>
            <% end %>
          </select>

          <select name="tripwire_name" class="bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm">
            <option value="">Tất cả ranh giới</option>
            <%= for tw <- @tripwire_names do %>
              <option value={tw} selected={@filters["tripwire_name"] == tw}><%= tw %></option>
            <% end %>
          </select>

          <select name="group_by" class="bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm">
            <option value="hour" selected={@filters["group_by"] == "hour"}>Theo Giờ</option>
            <option value="day" selected={@filters["group_by"] == "day"}>Theo Ngày</option>
            <option value="month" selected={@filters["group_by"] == "month"}>Theo Tháng</option>
          </select>

          <select name="period" class="bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm">
            <option value="24h" selected={@filters["period"] == "24h"}>24 giờ qua</option>
            <option value="7d" selected={@filters["period"] == "7d"}>7 ngày qua</option>
            <option value="30d" selected={@filters["period"] == "30d"}>30 ngày qua</option>
            <option value="90d" selected={@filters["period"] == "90d"}>90 ngày qua</option>
          </select>
        </.form>
      </div>

      <!-- Summary Stats -->
      <div class="grid grid-cols-3 gap-4 mb-4">
        <div class="bg-black border border-green-600 rounded p-4 text-center">
          <div class="text-3xl font-bold text-green-400"><%= @total_count %></div>
          <div class="text-sm text-white/60">Tổng Sự Kiện Vượt Khách</div>
        </div>
        <div class="bg-black border border-green-600 rounded p-4 text-center">
          <div class="text-3xl font-bold text-green-400"><%= @peak_count %></div>
          <div class="text-sm text-white/60">Đỉnh Điểm Đo Được</div>
        </div>
        <div class="bg-black border border-green-600 rounded p-4 text-center">
          <div class="text-3xl font-bold text-green-400"><%= @avg_count %></div>
          <div class="text-sm text-white/60">Trung Bình Mỗi Kỳ</div>
        </div>
      </div>

      <!-- Counts by Tripwire, Object & Device -->
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-4 mb-4">
        <!-- By Tripwire -->
        <div class="bg-black border border-green-600 rounded p-3">
          <h4 class="text-xs font-semibold text-white/60 uppercase mb-2">Số Lượt Theo Ranh Giới</h4>
          <div class="flex flex-wrap gap-2">
            <%= for item <- @zone_chart_data do %>
              <div class="flex items-center gap-2 bg-green-900/20 border border-green-700/40 rounded-lg px-3 py-1.5">
                <span class="text-sm text-white font-medium"><%= item["label"] %></span>
                <span class="text-sm font-bold text-green-400"><%= item["count"] %></span>
              </div>
            <% end %>
            <%= if @zone_chart_data == [] do %>
              <span class="text-xs text-white/30">Không có dữ liệu</span>
            <% end %>
          </div>
        </div>

        <!-- By Object Class -->
        <div class="bg-black border border-green-600 rounded p-3">
          <h4 class="text-xs font-semibold text-white/60 uppercase mb-2">Số Lượt Theo Đối Tượng</h4>
          <div class="flex flex-wrap gap-2">
            <%= for item <- @object_chart_data do %>
              <div class="flex items-center gap-2 bg-blue-900/20 border border-blue-700/40 rounded-lg px-3 py-1.5">
                <span class="text-sm text-white font-medium"><%= item["label"] %></span>
                <span class="text-sm font-bold text-blue-400"><%= item["count"] %></span>
              </div>
            <% end %>
            <%= if @object_chart_data == [] do %>
              <span class="text-xs text-white/30">Không có dữ liệu</span>
            <% end %>
          </div>
        </div>

        <!-- By Device -->
        <div class="bg-black border border-green-600 rounded p-3">
          <h4 class="text-xs font-semibold text-white/60 uppercase mb-2">Số Lượt Theo Thiết Bị</h4>
          <div class="flex flex-wrap gap-2">
            <%= for item <- @device_chart_data do %>
              <div class="flex items-center gap-2 bg-purple-900/20 border border-purple-700/40 rounded-lg px-3 py-1.5">
                <span class="text-sm text-white font-medium"><%= item["label"] %></span>
                <span class="text-sm font-bold text-purple-400"><%= item["count"] %></span>
              </div>
            <% end %>
            <%= if @device_chart_data == [] do %>
              <span class="text-xs text-white/30">Không có dữ liệu</span>
            <% end %>
          </div>
        </div>
      </div>
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-4">
        <!-- Crossing Events Over Time -->
        <div class="border border-green-600 rounded p-4 bg-black">
          <h3 class="text-sm font-semibold text-white mb-2">Số Lượt Khách Theo Thời Gian</h3>
          <div
            id="crossing-bar-chart"
            phx-hook="BarChart"
            phx-update="ignore"
            data-chart={Jason.encode!(@chart_data)}
            data-group-by={@filters["group_by"] || "hour"}
            data-color-mode="single"
            style="width: 100%; height: 280px;"
          >
          </div>
        </div>

        <!-- Crossings by Tripwire (Pie Chart) -->
        <div class="border border-green-600 rounded p-4 bg-black">
          <h3 class="text-sm font-semibold text-white mb-2">Tỉ Lệ Theo Ranh Giới</h3>
          <div
            id="crossing-zone-pie"
            phx-hook="PieChart"
            phx-update="ignore"
            data-chart={Jason.encode!(@zone_chart_data)}
            style="width: 100%; height: 240px;"
          >
          </div>
        </div>
      </div>

      <!-- Tripwire Bar Chart (full width) -->
      <div class="border border-green-600 rounded p-4 bg-black mb-4">
        <h3 class="text-sm font-semibold text-white mb-2">Số Lượng Lượt Khách Theo Ranh Giới (Cột)</h3>
        <div
          id="crossing-tripwire-bar"
          phx-hook="BarChart"
          phx-update="ignore"
          data-chart={Jason.encode!(@zone_chart_data)}
          data-group-by="tripwire"
          data-color-mode="multi"
          style="width: 100%; height: 250px;"
        >
        </div>
      </div>

      <!-- Charts Row 2: Device Pie + Device Bar -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-4">
        <!-- Device Pie Chart -->
        <div class="border border-green-600 rounded p-4 bg-black">
          <h3 class="text-sm font-semibold text-white mb-2">Sự Kiện Theo Thiết Bị</h3>
          <div
            id="crossing-device-pie"
            phx-hook="PieChart"
            phx-update="ignore"
            data-chart={Jason.encode!(@device_chart_data)}
            style="width: 100%; height: 240px;"
          >
          </div>
        </div>

        <!-- Device Bar Chart -->
        <div class="border border-green-600 rounded p-4 bg-black">
          <h3 class="text-sm font-semibold text-white mb-2">Sự Kiện Theo Thiết Bị (Cột)</h3>
          <div
            id="crossing-device-bar"
            phx-hook="BarChart"
            phx-update="ignore"
            data-chart={Jason.encode!(@device_chart_data)}
            data-group-by="device"
            data-color-mode="multi"
            style="width: 100%; height: 280px;"
          >
          </div>
        </div>
      </div>

      <!-- Object Class Breakdown -->
      <div class="border border-green-600 rounded p-4 bg-black mb-4">
        <h3 class="text-sm font-semibold text-white mb-2">Sự Kiện Theo Loại Đối Tượng</h3>
        <div
          id="crossing-object-chart"
          phx-hook="BarChart"
          phx-update="ignore"
          data-chart={Jason.encode!(@object_chart_data)}
          data-group-by="object"
          data-color-mode="multi"
          style="width: 100%; height: 200px;"
        >
        </div>
      </div>

      <!-- Data Table -->
      <div class="border border-green-600 rounded overflow-hidden mt-4">
        <table class="w-full">
          <thead class="bg-black border-b border-green-600">
            <tr>
              <th class="px-4 py-2 text-left text-xs font-medium text-white uppercase">Thời Khoảng</th>
              <th class="px-4 py-2 text-right text-xs font-medium text-white uppercase">Số Lượt</th>
              <th class="px-4 py-2 text-left text-xs font-medium text-white uppercase">Biểu Đồ</th>
            </tr>
          </thead>
          <tbody class="bg-black divide-y divide-green-900">
            <%= for item <- @chart_data do %>
              <tr class="hover:bg-green-900/20">
                <td class="px-4 py-2 text-sm text-white font-mono"><%= item["label"] %></td>
                <td class="px-4 py-2 text-sm text-green-400 text-right font-bold"><%= item["count"] %></td>
                <td class="px-4 py-2">
                  <div class="bg-green-900/30 rounded h-4 w-full">
                    <div
                      class="bg-green-500 rounded h-4"
                      style={"width: #{if @peak_count > 0, do: item["count"] / @peak_count * 100, else: 0}%"}
                    ></div>
                  </div>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>

      <!-- Recent Crossing Events -->
      <div class="mt-6">
        <h3 class="text-lg font-semibold text-white mb-3">Sự Kiện Vượt Tuyến Gần Đây</h3>
        <div class="border border-green-600 rounded overflow-hidden">
          <div class="overflow-y-auto max-h-[50vh]">
            <%= if @recent_events == [] do %>
              <div class="px-4 py-6 text-center text-white/50">Không có sự kiện vượt tuyến nào gần đây</div>
            <% else %>
              <table class="w-full">
                <thead class="bg-green-900/30 sticky top-0 z-10">
                  <tr class="text-left text-xs text-green-400 uppercase">
                    <th class="px-3 py-2 w-16"></th>
                    <th class="px-3 py-2">ID Theo Dõi</th>
                    <th class="px-3 py-2">Đối Tượng</th>
                    <th class="px-3 py-2">Ranh Giới</th>
                    <th class="px-3 py-2">Hướng</th>
                    <th class="px-3 py-2">Thời Điểm</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-green-900/50">
                  <%= for evt <- @recent_events do %>
                    <tr phx-click="show_crossing_detail" phx-value-idx={evt.idx} class="hover:bg-green-900/20 cursor-pointer transition-colors">
                      <td class="px-3 py-2">
                        <%= if evt.img_src do %>
                          <img src={evt.img_src} alt="Crop" class="w-10 h-10 object-cover rounded border border-green-700" />
                        <% else %>
                          <div class="w-10 h-10 bg-black/50 rounded border border-green-700 flex items-center justify-center">
                            <span class="text-white/20 text-sm">👤</span>
                          </div>
                        <% end %>
                      </td>
                      <td class="px-3 py-2 text-green-400 font-mono text-xs"><%= String.slice(evt.tracking_id || "", 0..7) %></td>
                      <td class="px-3 py-2 text-white text-xs"><%= evt.object_class || "-" %></td>
                      <td class="px-3 py-2 text-orange-400 text-xs"><%= evt.tripwire_name || "-" %></td>
                      <td class="px-3 py-2 text-xs">
                        <%= if evt.direction do %>
                          <span class={"px-1.5 py-0.5 rounded text-[11px] font-medium #{if evt.direction == "left_to_right", do: "bg-blue-900/50 border border-blue-600 text-blue-300", else: "bg-purple-900/50 border border-purple-600 text-purple-300"}"}>
                            <%= if evt.direction == "left_to_right", do: "→ L→R", else: "← R→L" %>
                          </span>
                        <% else %>
                          <span class="text-white/30">-</span>
                        <% end %>
                      </td>
                      <td class="px-3 py-2 text-white/50 text-xs whitespace-nowrap"><%= Calendar.strftime(evt.timestamp, "%H:%M:%S") %></td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            <% end %>
          </div>
        </div>
      </div>

      <!-- Crossing Detail Modal -->
      <%= if @selected_crossing do %>
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/80" phx-click="close_crossing_detail">
          <div class="bg-[#0a0a0a] border border-green-600 rounded-xl max-w-lg w-full mx-4 max-h-[85vh] overflow-y-auto shadow-2xl" phx-click="noop_crossing" phx-target="">
            <% evt = @selected_crossing %>
            <div class="flex items-center justify-between px-5 py-3 border-b border-green-900 sticky top-0 bg-[#0a0a0a] z-10">
              <div class="flex items-center gap-3">
                <span class="text-green-400 font-mono text-sm">Theo Dõi: <%= String.slice(evt.tracking_id || "", 0..7) %></span>
                <span class="px-2 py-0.5 bg-orange-900/50 border border-orange-600 rounded text-orange-300 text-xs font-medium">Vượt Tuyến</span>
              </div>
              <button phx-click="close_crossing_detail" class="text-white/50 hover:text-white text-xl">✕</button>
            </div>
            <!-- Image -->
            <%= if evt.img_src do %>
              <div class="px-5 py-3 border-b border-green-900/50 flex justify-center">
                <img src={evt.img_src} alt="Crop" class="max-h-64 object-contain rounded-lg border border-green-700" />
              </div>
            <% end %>
            <!-- Details -->
            <div class="px-5 py-4 space-y-3">
              <div class="grid grid-cols-2 gap-3">
                <div class="bg-green-900/10 border border-green-900/30 rounded-lg px-3 py-2">
                  <div class="text-white/40 text-[10px] uppercase mb-0.5">Đối Tượng</div>
                  <div class="text-white text-sm font-medium"><%= evt.object_class || "-" %></div>
                </div>
                <div class="bg-green-900/10 border border-green-900/30 rounded-lg px-3 py-2">
                  <div class="text-white/40 text-[10px] uppercase mb-0.5">Ranh Giới</div>
                  <div class="text-orange-400 text-sm font-medium"><%= evt.tripwire_name || "-" %></div>
                </div>
                <div class="bg-green-900/10 border border-green-900/30 rounded-lg px-3 py-2">
                  <div class="text-white/40 text-[10px] uppercase mb-0.5">Hướng Đi</div>
                  <div class="text-sm font-medium">
                    <%= if evt.direction == "left_to_right" do %>
                      <span class="text-blue-400">→ Trái sang Phải</span>
                    <% else %>
                      <span class="text-purple-400">← Phải sang Trái</span>
                    <% end %>
                  </div>
                </div>
                <div class="bg-green-900/10 border border-green-900/30 rounded-lg px-3 py-2">
                  <div class="text-white/40 text-[10px] uppercase mb-0.5">Thời Điểm</div>
                  <div class="text-white text-sm font-medium"><%= Calendar.strftime(evt.timestamp, "%d/%m/%Y %H:%M:%S") %></div>
                </div>
              </div>
              <%= if evt.confidence do %>
                <div class="bg-green-900/10 border border-green-900/30 rounded-lg px-3 py-2">
                  <div class="text-white/40 text-[10px] uppercase mb-0.5">Độ Chính Xác</div>
                  <div class="text-white text-sm font-medium"><%= Float.round(evt.confidence * 100, 1) %>%</div>
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
    devices = TProNVR.Devices.list() |> TProNVR.Accounts.Permissions.filter_devices(socket.assigns.current_user)
    object_classes = get_object_classes()

    tripwire_names = get_tripwire_names()

    filters = %{
      "group_by" => "hour",
      "period" => "24h",
      "device_id" => "",
      "object_class" => "",
      "tripwire_name" => ""
    }

    {:ok,
     socket
     |> assign(:devices, devices)
     |> assign(:object_classes, object_classes)
     |> assign(:tripwire_names, tripwire_names)
     |> assign(:filters, filters)
     |> assign(:filter_form, to_form(%{}))
     |> assign(:selected_crossing, nil)
     |> load_chart_data()
     |> load_zone_chart()
     |> load_device_chart()
     |> load_object_chart()
     |> load_recent_events()}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters =
      socket.assigns.filters
      |> Map.merge(Map.take(params, ["device_id", "object_class", "group_by", "period", "tripwire_name"]))

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> load_chart_data()
     |> load_zone_chart()
     |> load_device_chart()
     |> load_object_chart()
     |> load_recent_events()
     |> push_chart_update()}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply,
     socket
     |> load_chart_data()
     |> load_zone_chart()
     |> load_device_chart()
     |> load_object_chart()
     |> load_recent_events()
     |> push_chart_update()}
  end

  @impl true
  def handle_event("show_crossing_detail", %{"idx" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    selected = Enum.find(socket.assigns.recent_events, fn e -> e.idx == idx end)
    {:noreply, assign(socket, :selected_crossing, selected)}
  end

  @impl true
  def handle_event("close_crossing_detail", _params, socket) do
    {:noreply, assign(socket, :selected_crossing, nil)}
  end

  @impl true
  def handle_event("noop_crossing", _params, socket) do
    {:noreply, socket}
  end

  defp base_query(filters) do
    period = filters["period"] || "24h"
    start_date = period_to_start_date(period)

    query = from(e in AIAnalyticsEvent,
      where: e.event_type == "event-line-crossing",
      where: e.inserted_at >= ^start_date
    )

    query = if filters["device_id"] != "" and filters["device_id"] != nil do
      where(query, [e], e.device_id == ^filters["device_id"])
    else
      query
    end

    query = if filters["object_class"] != "" and filters["object_class"] != nil do
      where(query, [e], e.object_class == ^filters["object_class"])
    else
      query
    end

    if filters["tripwire_name"] != "" and filters["tripwire_name"] != nil do
      where(query, [e], fragment("json_extract(?, '$.tripwire_name')", e.raw_data) == ^filters["tripwire_name"])
    else
      query
    end
  end

  defp load_chart_data(socket) do
    filters = socket.assigns.filters
    group_by = filters["group_by"] || "hour"
    query = base_query(filters)

    format = group_by_format(group_by)

    chart_data =
      query
      |> group_by([e], fragment("strftime(?, ?)", ^format, e.inserted_at))
      |> select([e], %{
        label: fragment("strftime(?, ?)", ^format, e.inserted_at),
        count: count(e.id)
      })
      |> order_by([e], asc: fragment("strftime(?, ?)", ^format, e.inserted_at))
      |> Repo.all()
      |> Enum.map(fn row ->
        %{"label" => row.label || "Unknown", "count" => row.count}
      end)

    total = Enum.sum(Enum.map(chart_data, & &1["count"]))
    peak = if chart_data == [], do: 0, else: Enum.max_by(chart_data, & &1["count"]) |> Map.get("count")
    avg = if chart_data == [], do: 0, else: Float.round(total / max(length(chart_data), 1), 1)

    socket
    |> assign(:chart_data, chart_data)
    |> assign(:total_count, total)
    |> assign(:peak_count, peak)
    |> assign(:avg_count, avg)
  end

  defp load_zone_chart(socket) do
    query = base_query(socket.assigns.filters)
    devices = socket.assigns.devices
    device_map = Map.new(devices, fn d -> {d.id, d.name} end)

    chart_data = query
    |> where([e], fragment("json_extract(?, '$.tripwire_name') IS NOT NULL AND json_extract(?, '$.tripwire_name') != ''", e.raw_data, e.raw_data))
    |> group_by([e], [e.device_id, fragment("json_extract(?, '$.tripwire_name')", e.raw_data)])
    |> select([e], %{
      device_id: e.device_id,
      tripwire_name: fragment("json_extract(?, '$.tripwire_name')", e.raw_data),
      count: count(e.id)
    })
    |> order_by([e], desc: count(e.id))
    |> Repo.all()
    |> Enum.map(fn row -> 
      device_name = Map.get(device_map, row.device_id, "Device #{row.device_id}")
      %{"label" => "#{device_name} - #{row.tripwire_name}", "count" => row.count}
    end)

    assign(socket, :zone_chart_data, chart_data)
  end

  defp load_device_chart(socket) do
    query = base_query(socket.assigns.filters)
    devices = socket.assigns.devices
    device_map = Map.new(devices, fn d -> {d.id, d.name} end)

    chart_data = query
    |> where([e], not is_nil(e.device_id))
    |> group_by([e], e.device_id)
    |> select([e], %{device_id: e.device_id, count: count(e.id)})
    |> order_by([e], desc: count(e.id))
    |> Repo.all()
    |> Enum.map(fn row ->
      name = Map.get(device_map, row.device_id, "Device #{row.device_id}")
      %{"label" => name, "count" => row.count}
    end)

    assign(socket, :device_chart_data, chart_data)
  end

  defp load_object_chart(socket) do
    query = base_query(socket.assigns.filters)

    chart_data = query
    |> where([e], not is_nil(e.object_class))
    |> group_by([e], e.object_class)
    |> select([e], %{label: e.object_class, count: count(e.id)})
    |> order_by([e], desc: count(e.id))
    |> Repo.all()
    |> Enum.map(fn row -> %{"label" => row.label, "count" => row.count} end)

    assign(socket, :object_chart_data, chart_data)
  end

  defp push_chart_update(socket) do
    push_event(socket, "chart_update", %{
      data: socket.assigns.chart_data,
      group_by: socket.assigns.filters["group_by"] || "hour"
    })
  end

  defp period_to_start_date("24h"), do: DateTime.add(DateTime.utc_now(), -24, :hour)
  defp period_to_start_date("7d"), do: DateTime.add(DateTime.utc_now(), -7, :day)
  defp period_to_start_date("30d"), do: DateTime.add(DateTime.utc_now(), -30, :day)
  defp period_to_start_date("90d"), do: DateTime.add(DateTime.utc_now(), -90, :day)
  defp period_to_start_date(_), do: DateTime.add(DateTime.utc_now(), -24, :hour)

  defp group_by_format("hour"), do: "%Y-%m-%d %H:00"
  defp group_by_format("day"), do: "%Y-%m-%d"
  defp group_by_format("month"), do: "%Y-%m"
  defp group_by_format(_), do: "%Y-%m-%d %H:00"

  defp get_object_classes do
    from(e in AIAnalyticsEvent,
      where: e.event_type == "event-line-crossing",
      where: not is_nil(e.object_class),
      distinct: true,
      select: e.object_class,
      order_by: e.object_class
    )
    |> Repo.all()
  end

  defp get_tripwire_names do
    from(e in AIAnalyticsEvent,
      where: e.event_type == "event-line-crossing",
      where: fragment("json_extract(?, '$.tripwire_name') IS NOT NULL AND json_extract(?, '$.tripwire_name') != ''", e.raw_data, e.raw_data),
      distinct: true,
      select: fragment("json_extract(?, '$.tripwire_name')", e.raw_data),
      order_by: fragment("json_extract(?, '$.tripwire_name')", e.raw_data)
    )
    |> Repo.all()
  end

  defp load_recent_events(socket) do
    filters = socket.assigns.filters
    period = filters["period"] || "24h"
    start_date = period_to_start_date(period)

    query = from(e in AIAnalyticsEvent,
      where: e.event_type == "event-line-crossing",
      where: e.inserted_at >= ^start_date,
      order_by: [desc: e.inserted_at],
      limit: 50
    )

    query = if filters["device_id"] != "" and filters["device_id"] != nil do
      where(query, [e], e.device_id == ^filters["device_id"])
    else
      query
    end

    query = if filters["object_class"] != "" and filters["object_class"] != nil do
      where(query, [e], e.object_class == ^filters["object_class"])
    else
      query
    end

    events = Repo.all(query)

    recent = events
    |> Enum.with_index()
    |> Enum.map(fn {e, idx} ->
      raw = e.raw_data || %{}
      
      # Try to find a crop image for this event's tracking_id
      crop = if e.ref_tracking_id do
        from(c in Crop,
          where: c.ref_tracking_id == ^e.ref_tracking_id,
          order_by: [desc: c.inserted_at],
          limit: 1
        ) |> Repo.one()
      end

      img_src = cond do
        crop && crop.base64_image ->
          "data:image/jpeg;base64," <> crop.base64_image
        crop && crop.image_path && File.exists?(crop.image_path) ->
          data = File.read!(crop.image_path)
          "data:image/jpeg;base64," <> Base.encode64(data)
        true -> nil
      end

      %{
        idx: idx,
        tracking_id: e.ref_tracking_id,
        object_class: e.object_class,
        tripwire_name: raw["tripwire_name"],
        direction: raw["crossing_direction"],
        timestamp: e.inserted_at,
        confidence: if(crop, do: crop.confidence, else: nil),
        img_src: img_src
      }
    end)

    assign(socket, :recent_events, recent)
  end
end
