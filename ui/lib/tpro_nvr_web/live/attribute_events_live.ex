defmodule TProNVRWeb.AttributeEventsLive do
  @moduledoc """
  Attribute Analytics Report - comprehensive analysis of object attributes (age).
  Shows aggregate stats, charts, and recent attribute recognitions with crops.
  """
  use TProNVRWeb, :live_view

  alias TProNVR.CVEDIX.Attribute
  alias TProNVR.CVEDIX.Crop
  alias TProNVR.Repo

  import Ecto.Query

  @impl true
  def render(assigns) do
    ~H"""
    <div class="grow px-4 py-6">
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-xl font-semibold text-white">Báo Cáo Thuộc Tính</h2>
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

          <select name="attribute_name" class="bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm">
            <option value="age" selected={@filters["attribute_name"] == "age"}>Độ tuổi</option>
            <!-- Could add Gender, Glasses, etc. dynamically later -->
            <option value="gender" selected={@filters["attribute_name"] == "gender"}>Giới tính</option>
            <option value="glasses" selected={@filters["attribute_name"] == "glasses"}>Kính mắt</option>
            <option value="upper_clothing_color" selected={@filters["attribute_name"] == "upper_clothing_color"}>Màu áo</option>
            <option value="lower_clothing_color" selected={@filters["attribute_name"] == "lower_clothing_color"}>Màu quần</option>
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
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
        <div class="bg-black border border-green-600 rounded p-4 text-center">
          <div class="text-3xl font-bold text-green-400"><%= @summary.total_events %></div>
          <div class="text-sm text-white/60">Tổng Số Nhận Diện Thuộc Tính</div>
        </div>
        <div class="bg-black border border-green-600 rounded p-4 text-center">
          <div class="text-3xl font-bold text-blue-400"><%= @summary.unique_values %></div>
          <div class="text-sm text-white/60">Số Nhóm Phân Loại Giá Trị</div>
        </div>
      </div>

      <!-- Charts Row -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-6">
        <!-- Occurrences Over Time -->
        <div class="border border-green-600 rounded p-4 bg-black">
          <h3 class="text-sm font-semibold text-white mb-2">Nhận Diện Theo Thời Gian</h3>
          <div
            id="attribute-time-chart"
            phx-hook="BarChart"
            phx-update="ignore"
            data-chart={Jason.encode!(@time_chart_data)}
            data-group-by={@filters["group_by"] || "hour"}
            data-color-mode="single"
            style="width: 100%; height: 280px;"
          >
          </div>
        </div>

        <!-- Demographic / Value Breakdown (Pie Chart) -->
        <div class="border border-green-600 rounded p-4 bg-black">
          <h3 class="text-sm font-semibold text-white mb-2">Phân Bổ Theo Phân Loại</h3>
          <div
            id="attribute-value-pie"
            phx-hook="PieChart"
            phx-update="ignore"
            data-chart={Jason.encode!(@value_chart_data)}
            style="width: 100%; height: 280px;"
          >
          </div>
        </div>
      </div>

      <!-- Recent Attributes List (Hidden per request) -->
      <div class="mb-6 hidden">
        <h3 class="text-lg font-semibold text-white mb-3">Lịch Sử Nhận Diện Mới Nhất</h3>
        <div class="border border-green-600 rounded overflow-hidden">
          <div class="overflow-y-auto max-h-[60vh]">
            <%= if @recent_events == [] do %>
              <div class="px-4 py-6 text-center text-white/50">Không có dữ liệu nhận diện gần đây</div>
            <% else %>
              <table class="w-full">
                <thead class="bg-green-900/30 sticky top-0 z-10">
                  <tr class="text-left text-xs text-green-400 uppercase border-b border-green-800">
                    <th class="px-3 py-3 w-16 text-center">Hình Ảnh</th>
                    <th class="px-3 py-3">ID Theo Dõi</th>
                    <th class="px-3 py-3">Thuộc Tính</th>
                    <th class="px-3 py-3">Giá Trị</th>
                    <th class="px-3 py-3">Thời Gian</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-green-900/50">
                  <%= for evt <- @recent_events do %>
                    <tr class="hover:bg-green-900/20 transition-colors">
                      <td class="px-3 py-2 flex justify-center">
                        <%= if evt.img_src do %>
                          <img src={evt.img_src} alt="Crop" class="w-12 h-12 object-cover rounded border border-green-700 hover:scale-150 transition-transform origin-left" />
                        <% else %>
                          <div class="w-12 h-12 bg-black/50 rounded border border-green-700 flex items-center justify-center">
                            <span class="text-white/20 text-sm">👤</span>
                          </div>
                        <% end %>
                      </td>
                      <td class="px-3 py-2 text-green-400 font-mono text-xs"><%= String.slice(evt.tracking_id || "", 0..7) %></td>
                      <td class="px-3 py-2 text-gray-300 text-xs font-mono"><%= evt.name || "-" %></td>
                      <td class="px-3 py-2 text-yellow-400 text-sm font-bold uppercase"><%= evt.value || "-" %></td>
                      <td class="px-3 py-2 text-white/50 text-xs whitespace-nowrap"><%= if evt.timestamp, do: Calendar.strftime(evt.timestamp, "%d/%m/%Y %H:%M:%S"), else: "-" %></td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    devices = TProNVR.Devices.list()

    filters = %{
      "period" => "24h",
      "device_id" => "",
      "attribute_name" => "age",
      "group_by" => "hour"
    }

    {:ok,
     socket
     |> assign(:devices, devices)
     |> assign(:filters, filters)
     |> assign(:filter_form, to_form(%{}))
     |> load_all_data()}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters =
      socket.assigns.filters
      |> Map.merge(Map.take(params, ["device_id", "attribute_name", "period", "group_by"]))

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

  # ── Data Loading ──

  defp load_all_data(socket) do
    socket
    |> load_summary()
    |> load_time_chart()
    |> load_value_chart()
    |> load_recent_events()
  end

  defp base_query(filters) do
    period = filters["period"] || "24h"
    start_date = period_to_start_date(period)
    attr_name = filters["attribute_name"] || "age"

    query = from(a in Attribute,
      where: a.name == ^attr_name,
      where: a.inserted_at >= ^start_date
    )

    if filters["device_id"] != "" and filters["device_id"] != nil do
      where(query, [a], a.device_id == ^filters["device_id"])
    else
      query
    end
  end

  defp load_summary(socket) do
    query = base_query(socket.assigns.filters)

    total = query |> select([a], count(a.id)) |> Repo.one() || 0

    unique_values = query
    |> where([a], not is_nil(a.value))
    |> select([a], count(a.value, :distinct))
    |> Repo.one() || 0

    assign(socket, :summary, %{
      total_events: total,
      unique_values: unique_values
    })
  end

  defp load_time_chart(socket) do
    filters = socket.assigns.filters
    group_by = filters["group_by"] || "hour"
    format = group_by_format(group_by)

    query = base_query(filters)

    chart_data = query
    |> group_by([a], fragment("strftime(?, ?)", ^format, a.inserted_at))
    |> select([a], %{
      label: fragment("strftime(?, ?)", ^format, a.inserted_at),
      count: count(a.id)
    })
    |> order_by([a], asc: fragment("strftime(?, ?)", ^format, a.inserted_at))
    |> Repo.all()
    |> Enum.map(fn row -> %{"label" => row.label || "Không rõ", "count" => row.count} end)

    assign(socket, :time_chart_data, chart_data)
  end

  defp load_value_chart(socket) do
    query = base_query(socket.assigns.filters)

    chart_data = query
    |> where([a], not is_nil(a.value) and a.value != "")
    |> group_by([a], a.value)
    |> select([a], %{label: a.value, count: count(a.id)})
    |> order_by([a], desc: count(a.id))
    |> Repo.all()
    |> Enum.map(fn row -> %{"label" => row.label, "count" => row.count} end)

    assign(socket, :value_chart_data, chart_data)
  end

  defp load_recent_events(socket) do
    query = base_query(socket.assigns.filters)

    # Get most recent attribute records
    events = query
    |> order_by([a], desc: a.inserted_at)
    |> limit(50)
    |> Repo.all()

    recent = events
    |> Enum.map(fn evt ->
      %{
        tracking_id: evt.ref_tracking_id,
        name: evt.name,
        value: evt.value,
        timestamp: evt.inserted_at,
        img_src: get_crop_image(evt.ref_tracking_id)
      }
    end)

    assign(socket, :recent_events, recent)
  end

  defp push_chart_updates(socket) do
    socket
    |> push_event("chart_update", %{
      data: socket.assigns.time_chart_data,
      group_by: socket.assigns.filters["group_by"] || "hour"
    })
    # Since we use pie chart, we could push pie updates, but BarChart handles chart_update event.
    # PieChart js hook usually listens for dataset changes directly or we'd need to extend it.
    # We will trigger both.
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

  defp period_to_start_date("24h"), do: DateTime.add(DateTime.utc_now(), -24, :hour)
  defp period_to_start_date("7d"), do: DateTime.add(DateTime.utc_now(), -7, :day)
  defp period_to_start_date("30d"), do: DateTime.add(DateTime.utc_now(), -30, :day)
  defp period_to_start_date("90d"), do: DateTime.add(DateTime.utc_now(), -90, :day)
  defp period_to_start_date(_), do: DateTime.add(DateTime.utc_now(), -24, :hour)

  defp group_by_format("hour"), do: "%Y-%m-%d %H:00"
  defp group_by_format("day"), do: "%Y-%m-%d"
  defp group_by_format("month"), do: "%Y-%m"
  defp group_by_format(_), do: "%Y-%m-%d %H:00"
end
