defmodule TProNVRWeb.LoiteringReportLive do
  @moduledoc """
  Loitering Analytics Report - comprehensive analysis of loitering events.
  Shows zone stats, duration analysis, charts, rankings, and recent events.
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
        <h2 class="text-xl font-semibold text-white">Báo Cáo Lảng Vảng</h2>
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

          <select name="period" class="bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm">
            <option value="24h" selected={@filters["period"] == "24h"}>24 giờ qua</option>
            <option value="7d" selected={@filters["period"] == "7d"}>7 ngày qua</option>
            <option value="30d" selected={@filters["period"] == "30d"}>30 ngày qua</option>
            <option value="90d" selected={@filters["period"] == "90d"}>90 ngày qua</option>
          </select>

          <select name="group_by" class="bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm">
            <option value="hour" selected={@filters["group_by"] == "hour"}>Theo Giờ</option>
            <option value="day" selected={@filters["group_by"] == "day"}>Theo Ngày</option>
            <option value="month" selected={@filters["group_by"] == "month"}>Theo Tháng</option>
          </select>
        </.form>
      </div>

      <!-- Summary Stats -->
      <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
        <div class="bg-black border border-green-600 rounded p-4 text-center">
          <div class="text-3xl font-bold text-green-400"><%= @summary.total_events %></div>
          <div class="text-sm text-white/60">Tổng Sự Kiện</div>
        </div>
        <div class="bg-black border border-green-600 rounded p-4 text-center">
          <div class="text-3xl font-bold text-blue-400"><%= @summary.unique_objects %></div>
          <div class="text-sm text-white/60">Đối Tượng Duy Nhất</div>
        </div>
        <div class="bg-black border border-green-600 rounded p-4 text-center">
          <div class="text-3xl font-bold text-purple-400"><%= @summary.active_zones %></div>
          <div class="text-sm text-white/60">Khu Vực Hoạt Động</div>
        </div>
        <div class="bg-black border border-green-600 rounded p-4 text-center">
          <div class="text-3xl font-bold animate-pulse" style={if @summary.ongoing > 0, do: "color: #f59e0b;", else: "color: rgba(255,255,255,0.3);"}><%= @summary.ongoing %></div>
          <div class="text-sm text-white/60">Cảnh Báo Đang Diễn Ra</div>
        </div>
      </div>

      <!-- Zone Analytics Table -->
      <div class="mb-6">
        <h3 class="text-lg font-semibold text-white mb-3">Phân Tích Khu Vực</h3>
        <div class="border border-green-600 rounded overflow-hidden">
          <table class="w-full">
            <thead class="bg-green-900/30">
              <tr class="text-left text-xs text-green-400 uppercase">
                <th class="px-4 py-2">Tên Khu Vực</th>
                <th class="px-4 py-2 text-center">Sự Kiện</th>
                <th class="px-4 py-2 text-center">Số Đối Tượng</th>
                <th class="px-4 py-2 text-center">TG Trung Bình</th>
                <th class="px-4 py-2 text-center">TG Dài Nhất</th>
                <th class="px-4 py-2 text-center">TG Ngắn Nhất</th>
                <th class="px-4 py-2 text-center">Đang Diễn Ra</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-green-900/50">
              <%= if @zone_stats == [] do %>
                <tr><td colspan="7" class="px-4 py-4 text-center text-white/40">Không có dữ liệu</td></tr>
              <% else %>
                <%= for zone <- @zone_stats do %>
                  <tr class="hover:bg-green-900/20">
                    <td class="px-4 py-2 text-blue-400 text-sm font-medium"><%= zone.name %></td>
                    <td class="px-4 py-2 text-white text-sm text-center font-bold"><%= zone.event_count %></td>
                    <td class="px-4 py-2 text-white/70 text-sm text-center"><%= zone.unique_objects %></td>
                    <td class="px-4 py-2 text-yellow-400 text-sm text-center font-medium"><%= zone.avg_duration %></td>
                    <td class="px-4 py-2 text-red-400 text-sm text-center"><%= zone.max_duration %></td>
                    <td class="px-4 py-2 text-green-400 text-sm text-center"><%= zone.min_duration %></td>
                    <td class="px-4 py-2 text-center">
                      <%= if zone.ongoing > 0 do %>
                        <span class="px-2 py-0.5 bg-yellow-700/50 border border-yellow-500 rounded text-yellow-300 text-xs font-medium animate-pulse"><%= zone.ongoing %></span>
                      <% else %>
                        <span class="text-white/30 text-sm">0</span>
                      <% end %>
                    </td>
                  </tr>
                <% end %>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Charts Row 1: Time + Zone -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-6">
        <!-- Loitering Events Over Time -->
        <div class="border border-green-600 rounded p-4 bg-black">
          <h3 class="text-sm font-semibold text-white mb-2">Số Cảnh Báo Lảng Vảng Theo Thời Gian</h3>
          <div
            id="loitering-time-chart"
            phx-hook="BarChart"
            phx-update="ignore"
            data-chart={Jason.encode!(@time_chart_data)}
            data-group-by={@filters["group_by"] || "hour"}
            data-color-mode="single"
            style="width: 100%; height: 280px;"
          >
          </div>
        </div>

        <!-- Loitering by Zone (Pie Chart) -->
        <div class="border border-green-600 rounded p-4 bg-black">
          <h3 class="text-sm font-semibold text-white mb-2">Tỉ Lệ Theo Khu Vực</h3>
          <div
            id="loitering-zone-pie"
            phx-hook="PieChart"
            phx-update="ignore"
            data-chart={Jason.encode!(@zone_chart_data)}
            style="width: 100%; height: 240px;"
          >
          </div>
        </div>
      </div>

      <!-- Charts Row 2: Device Pie + Device Bar -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-6">
        <!-- Device Pie Chart -->
        <div class="border border-green-600 rounded p-4 bg-black">
          <h3 class="text-sm font-semibold text-white mb-2">Sự Kiện Theo Thiết Bị</h3>
          <div
            id="loitering-device-pie"
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
            id="loitering-device-bar"
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
      <div class="border border-green-600 rounded p-4 bg-black mb-6">
        <h3 class="text-sm font-semibold text-white mb-2">Sự Kiện Theo Loại Đối Tượng</h3>
        <div
          id="loitering-object-chart"
          phx-hook="BarChart"
          phx-update="ignore"
          data-chart={Jason.encode!(@object_chart_data)}
          data-group-by="object"
          data-color-mode="multi"
          style="width: 100%; height: 200px;"
        >
        </div>
      </div>

      <!-- Top Duration Ranking -->
      <div class="mb-6">
        <h3 class="text-lg font-semibold text-white mb-3">Top 10 Lảng Vảng Lâu Nhất</h3>
        <div class="border border-green-600 rounded overflow-hidden">
          <table class="w-full">
            <thead class="bg-green-900/30">
              <tr class="text-left text-xs text-green-400 uppercase">
                <th class="px-3 py-2">#</th>
                <th class="px-3 py-2 w-14"></th>
                <th class="px-3 py-2">ID Theo Dõi</th>
                <th class="px-3 py-2">Vùng</th>
                <th class="px-3 py-2">Đối Tượng</th>
                <th class="px-3 py-2">Thời Gian</th>
                <th class="px-3 py-2">Thời Điểm</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-green-900/50">
              <%= if @top_durations == [] do %>
                <tr><td colspan="7" class="px-4 py-4 text-center text-white/40">Không có sự kiện lảng vảng hoàn tất</td></tr>
              <% else %>
                <%= for {rank, evt} <- @top_durations do %>
                  <tr class="hover:bg-green-900/20">
                    <td class="px-3 py-2 text-white/50 text-sm font-bold"><%= rank %></td>
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
                    <td class="px-3 py-2 text-blue-400 text-xs"><%= evt.area_name || "-" %></td>
                    <td class="px-3 py-2 text-white text-xs"><%= evt.object_class || "-" %></td>
                    <td class="px-3 py-2 text-yellow-400 text-sm font-bold"><%= evt.duration_str %></td>
                    <td class="px-3 py-2 text-white/50 text-xs whitespace-nowrap"><%= if evt.timestamp, do: Calendar.strftime(evt.timestamp, "%d/%m %H:%M:%S"), else: "-" %></td>
                  </tr>
                <% end %>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Recent Loitering Events -->
      <div class="mb-6">
        <h3 class="text-lg font-semibold text-white mb-3">Sự Kiện Lảng Vảng Gần Đây</h3>
        <div class="border border-green-600 rounded overflow-hidden">
          <div class="overflow-y-auto max-h-[50vh]">
            <%= if @recent_events == [] do %>
              <div class="px-4 py-6 text-center text-white/50">Không có sự kiện lảng vảng gần đây</div>
            <% else %>
              <table class="w-full">
                <thead class="bg-green-900/30 sticky top-0 z-10">
                  <tr class="text-left text-xs text-green-400 uppercase">
                    <th class="px-3 py-2 w-14"></th>
                    <th class="px-3 py-2">ID Theo Dõi</th>
                    <th class="px-3 py-2">Vùng</th>
                    <th class="px-3 py-2">Đối Tượng</th>
                    <th class="px-3 py-2">Thời Gian</th>
                    <th class="px-3 py-2">Trạng Thái</th>
                    <th class="px-3 py-2">Thời Điểm</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-green-900/50">
                  <%= for evt <- @recent_events do %>
                    <tr phx-click="show_detail" phx-value-idx={evt.idx} class="hover:bg-green-900/20 cursor-pointer transition-colors">
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
                      <td class="px-3 py-2 text-blue-400 text-xs"><%= evt.area_name || "-" %></td>
                      <td class="px-3 py-2 text-white text-xs"><%= evt.object_class || "-" %></td>
                      <td class="px-3 py-2 text-yellow-400 text-xs font-medium"><%= evt.duration_str || "-" %></td>
                      <td class="px-3 py-2 text-xs">
                        <%= if evt.status == :ongoing do %>
                          <span class="px-1.5 py-0.5 bg-green-700/60 border border-green-500 rounded text-green-300 text-[11px] font-medium animate-pulse">Đang Diễn Ra</span>
                        <% else %>
                          <span class="px-1.5 py-0.5 bg-gray-700/60 border border-gray-500 rounded text-gray-300 text-[11px] font-medium">Đã Kết Thúc</span>
                        <% end %>
                      </td>
                      <td class="px-3 py-2 text-white/50 text-xs whitespace-nowrap"><%= if evt.timestamp, do: Calendar.strftime(evt.timestamp, "%H:%M:%S"), else: "-" %></td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            <% end %>
          </div>
        </div>
      </div>

      <!-- Detail Modal -->
      <%= if @selected_event do %>
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/80" phx-click="close_detail">
          <div class="bg-[#0a0a0a] border border-green-600 rounded-xl max-w-lg w-full mx-4 max-h-[85vh] overflow-y-auto shadow-2xl" phx-click="noop">
            <% evt = @selected_event %>
            <div class="flex items-center justify-between px-5 py-3 border-b border-green-900 sticky top-0 bg-[#0a0a0a] z-10">
              <div class="flex items-center gap-3">
                <span class="text-green-400 font-mono text-sm">Theo Dõi: <%= String.slice(evt.tracking_id || "", 0..7) %></span>
                <span class="px-2 py-0.5 bg-yellow-900/50 border border-yellow-600 rounded text-yellow-300 text-xs font-medium">Lảng Vảng</span>
              </div>
              <button phx-click="close_detail" class="text-white/50 hover:text-white text-xl">✕</button>
            </div>
            <%= if evt.img_src do %>
              <div class="px-5 py-3 border-b border-green-900/50 flex justify-center">
                <img src={evt.img_src} alt="Crop" class="max-h-64 object-contain rounded-lg border border-green-700" />
              </div>
            <% end %>
            <div class="px-5 py-4 space-y-3">
              <div class="grid grid-cols-2 gap-3">
                <div class="bg-green-900/10 border border-green-900/30 rounded-lg px-3 py-2">
                  <div class="text-white/40 text-[10px] uppercase mb-0.5">Đối Tượng</div>
                  <div class="text-white text-sm font-medium"><%= evt.object_class || "-" %></div>
                </div>
                <div class="bg-green-900/10 border border-green-900/30 rounded-lg px-3 py-2">
                  <div class="text-white/40 text-[10px] uppercase mb-0.5">Vùng</div>
                  <div class="text-blue-400 text-sm font-medium"><%= evt.area_name || "-" %></div>
                </div>
                <div class="bg-green-900/10 border border-green-900/30 rounded-lg px-3 py-2">
                  <div class="text-white/40 text-[10px] uppercase mb-0.5">Thời Gian</div>
                  <div class="text-yellow-400 text-sm font-medium"><%= evt.duration_str || "-" %></div>
                </div>
                <div class="bg-green-900/10 border border-green-900/30 rounded-lg px-3 py-2">
                  <div class="text-white/40 text-[10px] uppercase mb-0.5">Trạng Thái</div>
                  <div class="text-sm font-medium">
                    <%= if evt.status == :ongoing do %>
                      <span class="text-green-400">🟢 Đang Diễn Ra</span>
                    <% else %>
                      <span class="text-gray-400">⬜ Đã Kết Thúc</span>
                    <% end %>
                  </div>
                </div>
                <div class="bg-green-900/10 border border-green-900/30 rounded-lg px-3 py-2 col-span-2">
                  <div class="text-white/40 text-[10px] uppercase mb-0.5">Thời Điểm</div>
                  <div class="text-white text-sm font-medium"><%= if evt.timestamp, do: Calendar.strftime(evt.timestamp, "%d/%m/%Y %H:%M:%S"), else: "-" %></div>
                </div>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <!-- Peak Hours Info -->
      <%= if @peak_hour do %>
        <div class="border border-yellow-600/50 rounded p-4 bg-yellow-900/10 mb-6">
          <div class="flex items-center gap-2 mb-1">
            <span class="text-yellow-400 text-sm font-bold">⚡ Khung Giờ Cao Điểm</span>
          </div>
          <div class="text-white/70 text-sm">
            Nhiều cảnh báo lảng vảng được ghi nhận nhất vào lúc <span class="text-yellow-400 font-bold"><%= @peak_hour.label %></span>
            với <span class="text-yellow-400 font-bold"><%= @peak_hour.count %></span> sự kiện.
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

    filters = %{
      "period" => "24h",
      "device_id" => "",
      "object_class" => "",
      "group_by" => "hour"
    }

    {:ok,
     socket
     |> assign(:devices, devices)
     |> assign(:object_classes, object_classes)
     |> assign(:filters, filters)
     |> assign(:filter_form, to_form(%{}))
     |> assign(:selected_event, nil)
     |> load_all_data()}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters =
      socket.assigns.filters
      |> Map.merge(Map.take(params, ["device_id", "object_class", "period", "group_by"]))

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> load_all_data()
     |> push_chart_updates()}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply,
     socket
     |> load_all_data()
     |> push_chart_updates()}
  end

  @impl true
  def handle_event("show_detail", %{"idx" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    selected = Enum.find(socket.assigns.recent_events, fn e -> e.idx == idx end)
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

  # ── Data Loading ──

  defp load_all_data(socket) do
    socket
    |> load_summary()
    |> load_zone_stats()
    |> load_time_chart()
    |> load_zone_chart()
    |> load_device_chart()
    |> load_object_chart()
    |> load_top_durations()
    |> load_recent_events()
    |> load_peak_hour()
  end

  defp base_query(filters) do
    period = filters["period"] || "24h"
    start_date = period_to_start_date(period)

    query = from(e in AIAnalyticsEvent,
      where: e.event_type in ["event-loitering", "event-loitering-end"],
      where: e.inserted_at >= ^start_date
    )

    query = if filters["device_id"] != "" and filters["device_id"] != nil do
      where(query, [e], e.device_id == ^filters["device_id"])
    else
      query
    end

    if filters["object_class"] != "" and filters["object_class"] != nil do
      where(query, [e], e.object_class == ^filters["object_class"])
    else
      query
    end
  end

  defp load_summary(socket) do
    query = base_query(socket.assigns.filters)

    total = query |> select([e], count(e.id)) |> Repo.one() || 0

    unique_objects = query
    |> where([e], not is_nil(e.ref_tracking_id))
    |> select([e], count(e.ref_tracking_id, :distinct))
    |> Repo.one() || 0

    active_zones = query
    |> where([e], not is_nil(e.area_name) and e.area_name != "")
    |> select([e], count(e.area_name, :distinct))
    |> Repo.one() || 0

    # Ongoing = tracking IDs that have event-loitering but no event-loitering-end
    start_tids = query
    |> where([e], e.event_type == "event-loitering" and not is_nil(e.ref_tracking_id))
    |> select([e], e.ref_tracking_id)
    |> Repo.all()
    |> MapSet.new()

    end_tids = query
    |> where([e], e.event_type == "event-loitering-end" and not is_nil(e.ref_tracking_id))
    |> select([e], e.ref_tracking_id)
    |> Repo.all()
    |> MapSet.new()

    ongoing = MapSet.difference(start_tids, end_tids) |> MapSet.size()

    assign(socket, :summary, %{
      total_events: total,
      unique_objects: unique_objects,
      active_zones: active_zones,
      ongoing: ongoing
    })
  end

  defp load_zone_stats(socket) do
    query = base_query(socket.assigns.filters)
    devices = socket.assigns.devices
    device_map = Map.new(devices, fn d -> {d.id, d.name} end)

    # Get all events grouped by device_id and area_name
    zones_raw = query
    |> where([e], not is_nil(e.area_name) and e.area_name != "")
    |> Repo.all()
    |> Enum.group_by(fn e -> {e.device_id, e.area_name} end)

    zone_stats = Enum.map(zones_raw, fn {{device_id, area_name}, events} ->
      # Count unique tracking IDs
      unique = events |> Enum.map(& &1.ref_tracking_id) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> length()

      # Get duration data from -end events
      end_events = Enum.filter(events, &(&1.event_type == "event-loitering-end"))
      durations_ms = end_events
      |> Enum.map(fn e -> (e.raw_data || %{})["event_duration_ms"] end)
      |> Enum.reject(&is_nil/1)

      avg_ms = if durations_ms != [], do: Enum.sum(durations_ms) / length(durations_ms), else: nil
      max_ms = if durations_ms != [], do: Enum.max(durations_ms), else: nil
      min_ms = if durations_ms != [], do: Enum.min(durations_ms), else: nil

      # Ongoing count
      start_tids = events |> Enum.filter(&(&1.event_type == "event-loitering")) |> Enum.map(& &1.ref_tracking_id) |> MapSet.new()
      end_tids = events |> Enum.filter(&(&1.event_type == "event-loitering-end")) |> Enum.map(& &1.ref_tracking_id) |> MapSet.new()
      ongoing = MapSet.difference(start_tids, end_tids) |> MapSet.size()

      device_name = Map.get(device_map, device_id, "Device #{device_id}")
      
      %{
        name: "#{device_name} - #{area_name}",
        event_count: length(events),
        unique_objects: unique,
        avg_duration: format_duration_ms(avg_ms),
        max_duration: format_duration_ms(max_ms),
        min_duration: format_duration_ms(min_ms),
        ongoing: ongoing
      }
    end)
    |> Enum.sort_by(& &1.event_count, :desc)

    assign(socket, :zone_stats, zone_stats)
  end

  defp load_time_chart(socket) do
    filters = socket.assigns.filters
    group_by = filters["group_by"] || "hour"
    format = group_by_format(group_by)

    query = base_query(filters)

    chart_data = query
    |> group_by([e], fragment("strftime(?, ?)", ^format, e.inserted_at))
    |> select([e], %{
      label: fragment("strftime(?, ?)", ^format, e.inserted_at),
      count: count(e.id)
    })
    |> order_by([e], asc: fragment("strftime(?, ?)", ^format, e.inserted_at))
    |> Repo.all()
    |> Enum.map(fn row -> %{"label" => row.label || "Unknown", "count" => row.count} end)

    assign(socket, :time_chart_data, chart_data)
  end

  defp load_zone_chart(socket) do
    query = base_query(socket.assigns.filters)
    devices = socket.assigns.devices
    device_map = Map.new(devices, fn d -> {d.id, d.name} end)

    chart_data = query
    |> where([e], not is_nil(e.area_name) and e.area_name != "")
    |> group_by([e], [e.device_id, e.area_name])
    |> select([e], %{
      device_id: e.device_id,
      area_name: e.area_name,
      count: count(e.id)
    })
    |> order_by([e], desc: count(e.id))
    |> Repo.all()
    |> Enum.map(fn row -> 
      device_name = Map.get(device_map, row.device_id, "Device #{row.device_id}")
      %{"label" => "#{device_name} - #{row.area_name}", "count" => row.count}
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

  defp load_top_durations(socket) do
    query = base_query(socket.assigns.filters)

    top = query
    |> where([e], e.event_type == "event-loitering-end")
    |> order_by([e], desc: e.inserted_at)
    |> limit(50)
    |> Repo.all()
    |> Enum.map(fn e ->
      duration_ms = (e.raw_data || %{})["event_duration_ms"]
      %{
        tracking_id: e.ref_tracking_id,
        area_name: e.area_name,
        object_class: e.object_class,
        duration_ms: duration_ms,
        duration_str: format_duration_ms(duration_ms),
        timestamp: e.inserted_at
      }
    end)
    |> Enum.reject(fn e -> is_nil(e.duration_ms) end)
    |> Enum.sort_by(& &1.duration_ms, :desc)
    |> Enum.take(10)
    |> Enum.with_index(1)
    |> Enum.map(fn {evt, rank} ->
      img_src = get_crop_image(evt.tracking_id)
      {rank, Map.put(evt, :img_src, img_src)}
    end)

    assign(socket, :top_durations, top)
  end

  defp load_recent_events(socket) do
    query = base_query(socket.assigns.filters)

    # Get distinct tracking IDs with their latest event
    events = query
    |> order_by([e], desc: e.inserted_at)
    |> limit(100)
    |> Repo.all()

    # Group by tracking_id to determine status
    grouped = events |> Enum.group_by(& &1.ref_tracking_id)

    recent = grouped
    |> Enum.map(fn {tid, evts} ->
      latest = List.first(evts)
      has_end = Enum.any?(evts, &(&1.event_type == "event-loitering-end"))
      duration_ms = evts
      |> Enum.find_value(fn e -> (e.raw_data || %{})["event_duration_ms"] end)

      %{
        tracking_id: tid,
        area_name: latest.area_name,
        object_class: latest.object_class,
        status: if(has_end, do: :ended, else: :ongoing),
        duration_str: format_duration_ms(duration_ms),
        timestamp: latest.inserted_at,
        img_src: get_crop_image(tid)
      }
    end)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
    |> Enum.take(30)
    |> Enum.with_index()
    |> Enum.map(fn {evt, idx} -> Map.put(evt, :idx, idx) end)

    assign(socket, :recent_events, recent)
  end

  defp load_peak_hour(socket) do
    query = base_query(socket.assigns.filters)

    peak = query
    |> group_by([e], fragment("strftime('%H:00', ?)", e.inserted_at))
    |> select([e], %{
      label: fragment("strftime('%H:00', ?)", e.inserted_at),
      count: count(e.id)
    })
    |> order_by([e], desc: count(e.id))
    |> limit(1)
    |> Repo.one()

    assign(socket, :peak_hour, peak)
  end

  defp push_chart_updates(socket) do
    socket
    |> push_event("chart_update", %{
      data: socket.assigns.time_chart_data,
      group_by: socket.assigns.filters["group_by"] || "hour"
    })
  end

  # ── Helpers ──

  defp get_crop_image(nil), do: nil
  defp get_crop_image(tracking_id) do
    crop = from(c in Crop,
      where: c.ref_tracking_id == ^tracking_id,
      order_by: [desc: c.inserted_at],
      limit: 1
    ) |> Repo.one()

    cond do
      crop && crop.base64_image ->
        "data:image/jpeg;base64," <> crop.base64_image
      crop && crop.image_path && File.exists?(crop.image_path) ->
        data = File.read!(crop.image_path)
        "data:image/jpeg;base64," <> Base.encode64(data)
      true -> nil
    end
  end

  defp format_duration_ms(nil), do: "-"
  defp format_duration_ms(ms) when is_number(ms) do
    seconds = round(ms / 1000)
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
      true -> "<1s"
    end
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
      where: e.event_type in ["event-loitering", "event-loitering-end"],
      where: not is_nil(e.object_class),
      distinct: true,
      select: e.object_class,
      order_by: e.object_class
    )
    |> Repo.all()
  end
end
