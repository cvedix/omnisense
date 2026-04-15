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
      
      <!-- Search + Filters (single row) -->
      <div class="mb-3 space-y-2">
        <div class="flex items-center gap-2">
          <form phx-submit="appearance_search" class="flex items-center gap-2 flex-1 min-w-0">
            <input 
              type="text" 
              name="query" 
              value={@search_query}
              placeholder="Ví dụ: Xe tải trắng, Phụ nữ áo đen quần xám, Nam đeo kính..."
              class="flex-1 min-w-0 bg-black border border-green-600 text-white rounded px-3 py-1.5 text-sm focus:outline-none focus:border-green-400 focus:ring-1 focus:ring-green-400/50 placeholder:text-white/30"
            />
            <button type="submit" class="px-3 py-1.5 bg-green-700 hover:bg-green-600 text-white text-sm rounded font-medium transition-colors whitespace-nowrap">Tìm kiếm</button>
            <%= if @search_query != "" do %>
              <button type="button" phx-click="clear_search" class="px-2.5 py-1.5 border border-red-800 hover:bg-red-900/30 text-red-400 text-sm rounded transition-colors whitespace-nowrap">Xóa</button>
            <% end %>
          </form>
          
          <div class="h-5 w-px bg-green-800/50 flex-shrink-0"></div>
          
          <.form for={@filter_form} phx-change="filter" class="flex items-center gap-2 flex-shrink-0">
            <select name="device_id" class="bg-black border border-green-600 text-white rounded px-2.5 py-1.5 text-sm">
              <option value="">Tất cả thiết bị</option>
              <%= for device <- @devices do %>
                <option value={device.id} selected={@filters["device_id"] == device.id}><%= device.name %></option>
              <% end %>
            </select>
            
            <select name="event_type" class="bg-black border border-green-600 text-white rounded px-2.5 py-1.5 text-sm">
              <option value="">Tất cả sự kiện</option>
              <option value="event-intrusion" selected={@filters["event_type"] == "event-intrusion"}>Xâm nhập</option>
              <option value="event-intrusion-end" selected={@filters["event_type"] == "event-intrusion-end"}>Hết xâm nhập</option>
              <option value="event-area-enter" selected={@filters["event_type"] == "event-area-enter"}>Vào vùng</option>
              <option value="event-area-exit" selected={@filters["event_type"] == "event-area-exit"}>Ra vùng</option>
              <option value="event-loitering" selected={@filters["event_type"] == "event-loitering"}>Lảng vảng</option>
              <option value="event-loitering-end" selected={@filters["event_type"] == "event-loitering-end"}>Hết lảng vảng</option>
              <option value="event-line-crossing" selected={@filters["event_type"] == "event-line-crossing"}>Vượt tuyến</option>
              <option value="event-crowd" selected={@filters["event_type"] == "event-crowd"}>Đám đông</option>
              <option value="event-activity" selected={@filters["event_type"] == "event-activity"}>Hoạt động</option>
              <option value="event-activity-end" selected={@filters["event_type"] == "event-activity-end"}>Hết hoạt động</option>
            </select>
            
            <select name="object_type" class="bg-black border border-green-600 text-white rounded px-2.5 py-1.5 text-sm">
              <option value="">Tất cả đối tượng</option>
              <option value="Person" selected={@filters["object_type"] == "Person"}>Người</option>
              <option value="Vehicle" selected={@filters["object_type"] == "Vehicle"}>Phương tiện</option>
              <option value="Bicycle" selected={@filters["object_type"] == "Bicycle"}>Xe đạp</option>
              <option value="Animal" selected={@filters["object_type"] == "Animal"}>Động vật</option>
            </select>
            
            <select name="min_confidence" class="bg-black border border-green-600 text-white rounded px-2.5 py-1.5 text-sm">
              <option value="">Độ tin cậy</option>
              <option value="0.3" selected={@filters["min_confidence"] == "0.3"}>≥ 30%</option>
              <option value="0.5" selected={@filters["min_confidence"] == "0.5"}>≥ 50%</option>
              <option value="0.7" selected={@filters["min_confidence"] == "0.7"}>≥ 70%</option>
              <option value="0.8" selected={@filters["min_confidence"] == "0.8"}>≥ 80%</option>
              <option value="0.9" selected={@filters["min_confidence"] == "0.9"}>≥ 90%</option>
            </select>
            
            <button type="button" phx-click="toggle_filters" class={"px-2.5 py-1.5 border rounded text-sm transition-colors whitespace-nowrap #{if @show_advanced_filters, do: "border-green-500 bg-green-900/40 text-green-300", else: "border-green-700 text-white/60 hover:border-green-500 hover:text-green-300"}"}>⚙ Nâng cao</button>
          </.form>
        </div>
        
        <!-- Active filter chips -->
        <%= if map_size(@filters) > 0 do %>
          <div class="flex flex-wrap items-center gap-1.5">
            <span class="text-white/40 text-xs">Đang lọc:</span>
            <%= for {key, value} <- @filters do %>
              <span class="inline-flex items-center gap-1 px-2 py-0.5 bg-green-900/30 border border-green-800 rounded text-xs text-green-300">
                <span class="text-green-500"><%= filter_display_name(key) %>:</span> <%= filter_display_value(key, value) %>
                <button type="button" phx-click="remove_filter" phx-value-key={key} class="text-green-600 hover:text-red-400 ml-0.5">×</button>
              </span>
            <% end %>
            <button type="button" phx-click="clear_all_filters" class="text-xs text-red-400/60 hover:text-red-400 ml-1">Xóa tất cả</button>
          </div>
        <% end %>
      </div>
      
      <!-- Advanced Filters -->
      <div class="mb-4">
        
        <!-- Row 2: Person attribute filters (collapsible) -->
        <%= if @show_advanced_filters do %>
          <div class="bg-green-900/10 border border-green-900/30 rounded-lg p-3 space-y-2">
            <!-- Person attributes -->
            <div class="flex items-center gap-2 mb-1">
              <span class="text-[10px] text-green-400 uppercase font-semibold tracking-wider">Thuộc tính người</span>
            </div>
            <.form for={@filter_form} phx-change="filter" class="flex flex-wrap items-center gap-2">
              <select name="gender" class="bg-black border border-green-800 text-white rounded px-2.5 py-1 text-xs min-w-[100px]">
                <option value="">Giới tính</option>
                <option value="male" selected={@filters["gender"] == "male"}>Nam</option>
                <option value="female" selected={@filters["gender"] == "female"}>Nữ</option>
              </select>
              <select name="age" class="bg-black border border-green-800 text-white rounded px-2.5 py-1 text-xs min-w-[100px]">
                <option value="">Tuổi</option>
                <option value="young" selected={@filters["age"] == "young"}>Trẻ</option>
                <option value="adult" selected={@filters["age"] == "adult"}>Người lớn</option>
                <option value="middle" selected={@filters["age"] == "middle"}>Trung niên</option>
                <option value="senior" selected={@filters["age"] == "senior"}>Cao tuổi</option>
              </select>
              <select name="upper_clothing_color" class="bg-black border border-green-800 text-white rounded px-2.5 py-1 text-xs min-w-[100px]">
                <option value="">Màu áo</option>
                <option value="black" selected={@filters["upper_clothing_color"] == "black"}>Đen</option>
                <option value="white" selected={@filters["upper_clothing_color"] == "white"}>Trắng</option>
                <option value="gray" selected={@filters["upper_clothing_color"] == "gray"}>Xám</option>
                <option value="red" selected={@filters["upper_clothing_color"] == "red"}>Đỏ</option>
                <option value="blue" selected={@filters["upper_clothing_color"] == "blue"}>Xanh dương</option>
                <option value="green" selected={@filters["upper_clothing_color"] == "green"}>Xanh lá</option>
                <option value="yellow" selected={@filters["yellow"] == "yellow"}>Vàng</option>
                <option value="pink" selected={@filters["upper_clothing_color"] == "pink"}>Hồng</option>
                <option value="beige" selected={@filters["upper_clothing_color"] == "beige"}>Be</option>
                <option value="orange" selected={@filters["upper_clothing_color"] == "orange"}>Cam</option>
              </select>
              <select name="lower_clothing_color" class="bg-black border border-green-800 text-white rounded px-2.5 py-1 text-xs min-w-[100px]">
                <option value="">Màu quần</option>
                <option value="black" selected={@filters["lower_clothing_color"] == "black"}>Đen</option>
                <option value="white" selected={@filters["lower_clothing_color"] == "white"}>Trắng</option>
                <option value="gray" selected={@filters["lower_clothing_color"] == "gray"}>Xám</option>
                <option value="red" selected={@filters["lower_clothing_color"] == "red"}>Đỏ</option>
                <option value="blue" selected={@filters["lower_clothing_color"] == "blue"}>Xanh dương</option>
                <option value="green" selected={@filters["lower_clothing_color"] == "green"}>Xanh lá</option>
                <option value="beige" selected={@filters["lower_clothing_color"] == "beige"}>Be</option>
                <option value="orange" selected={@filters["lower_clothing_color"] == "orange"}>Cam</option>
              </select>
              <select name="glasses" class="bg-black border border-green-800 text-white rounded px-2.5 py-1 text-xs min-w-[90px]">
                <option value="">Kính</option>
                <option value="true" selected={@filters["glasses"] == "true"}>Có</option>
                <option value="false" selected={@filters["glasses"] == "false"}>Không</option>
              </select>
              <select name="carrying_bag" class="bg-black border border-green-800 text-white rounded px-2.5 py-1 text-xs min-w-[90px]">
                <option value="">Mang túi</option>
                <option value="true" selected={@filters["carrying_bag"] == "true"}>Có</option>
                <option value="false" selected={@filters["carrying_bag"] == "false"}>Không</option>
              </select>
              <select name="phone" class="bg-black border border-green-800 text-white rounded px-2.5 py-1 text-xs min-w-[90px]">
                <option value="">Điện thoại</option>
                <option value="true" selected={@filters["phone"] == "true"}>Có</option>
                <option value="false" selected={@filters["phone"] == "false"}>Không</option>
              </select>
              <select name="smoking" class="bg-black border border-green-800 text-white rounded px-2.5 py-1 text-xs min-w-[90px]">
                <option value="">Hút thuốc</option>
                <option value="true" selected={@filters["smoking"] == "true"}>Có</option>
                <option value="false" selected={@filters["smoking"] == "false"}>Không</option>
              </select>
              <select name="face_covered" class="bg-black border border-green-800 text-white rounded px-2.5 py-1 text-xs min-w-[100px]">
                <option value="">Che mặt</option>
                <option value="true" selected={@filters["face_covered"] == "true"}>Có</option>
                <option value="false" selected={@filters["face_covered"] == "false"}>Không</option>
              </select>
              <select name="tattoo" class="bg-black border border-green-800 text-white rounded px-2.5 py-1 text-xs min-w-[90px]">
                <option value="">Hình xăm</option>
                <option value="true" selected={@filters["tattoo"] == "true"}>Có</option>
                <option value="false" selected={@filters["tattoo"] == "false"}>Không</option>
              </select>
            </.form>
            
            <!-- Vehicle attributes -->
            <div class="flex items-center gap-2 mb-1 mt-3">
              <span class="text-[10px] text-blue-400 uppercase font-semibold tracking-wider">Thuộc tính phương tiện</span>
            </div>
            <.form for={@filter_form} phx-change="filter" class="flex flex-wrap items-center gap-2">
              <select name="vehicle_class" class="bg-black border border-green-800 text-white rounded px-2.5 py-1 text-xs min-w-[110px]">
                <option value="">Loại xe</option>
                <option value="motorcycle" selected={@filters["vehicle_class"] == "motorcycle"}>Xe máy</option>
                <option value="car" selected={@filters["vehicle_class"] == "car"}>Ô tô</option>
                <option value="bicycle" selected={@filters["vehicle_class"] == "bicycle"}>Xe đạp</option>
                <option value="truck" selected={@filters["vehicle_class"] == "truck"}>Xe tải</option>
                <option value="bus" selected={@filters["vehicle_class"] == "bus"}>Xe buýt</option>
                <option value="van" selected={@filters["vehicle_class"] == "van"}>Xe van</option>
                <option value="construction" selected={@filters["vehicle_class"] == "construction"}>Xe công trình</option>
              </select>
              <select name="vehicle_color" class="bg-black border border-green-800 text-white rounded px-2.5 py-1 text-xs min-w-[100px]">
                <option value="">Màu xe</option>
                <option value="white" selected={@filters["vehicle_color"] == "white"}>Trắng</option>
                <option value="black" selected={@filters["vehicle_color"] == "black"}>Đen</option>
                <option value="silver" selected={@filters["vehicle_color"] == "silver"}>Bạc</option>
                <option value="red" selected={@filters["vehicle_color"] == "red"}>Đỏ</option>
                <option value="blue" selected={@filters["vehicle_color"] == "blue"}>Xanh dương</option>
                <option value="gray" selected={@filters["vehicle_color"] == "gray"}>Xám</option>
                <option value="yellow" selected={@filters["vehicle_color"] == "yellow"}>Vàng</option>
                <option value="green" selected={@filters["vehicle_color"] == "green"}>Xanh lá</option>
              </select>
            </.form>
          </div>
        <% end %>
      </div>
      
      <!-- Events Table -->
      <div class="border border-green-600 rounded overflow-hidden">
        <div class="overflow-y-auto max-h-[75vh]">
          <%= if Enum.empty?(@grouped_events) do %>
            <div class="px-4 py-8 text-center text-white/50">
              Không tìm thấy sự kiện AI
            </div>
          <% else %>
            <table class="w-full">
              <thead class="bg-green-900/30 sticky top-0 z-10">
                <tr class="text-left text-xs text-green-400 uppercase">
                  <th class="px-3 py-2 w-16"></th>
                  <th class="px-3 py-2">Loại sự kiện</th>
                  <th class="px-3 py-2">Track ID</th>
                  <th class="px-3 py-2">Đối tượng</th>
                  <th class="px-3 py-2">Thuộc tính</th>
                  <th class="px-3 py-2">Vùng / Tuyến</th>
                  <th class="px-3 py-2">Thời lượng</th>
                  <th class="px-3 py-2">Trạng thái</th>
                  <th class="px-3 py-2">SL</th>
                  <th class="px-3 py-2">Thời gian</th>
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
                    <td class="px-3 py-2">
                      <%= if event_data.attributes != [] do %>
                        <div class="flex flex-wrap gap-0.5 max-w-[280px]">
                          <%= for {label, color_class} <- build_attr_summary(event_data.attr_map) do %>
                            <span class={"inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium #{color_class}"}>
                              <%= label %>
                            </span>
                          <% end %>
                        </div>
                      <% else %>
                        <span class="text-white/20 text-xs">-</span>
                      <% end %>
                    </td>
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
                          <span class="px-1.5 py-0.5 bg-green-700/60 border border-green-500 rounded text-green-300 text-[11px] font-medium animate-pulse">Đang diễn ra</span>
                        <% :ended -> %>
                          <span class="px-1.5 py-0.5 bg-gray-700/60 border border-gray-500 rounded text-gray-300 text-[11px] font-medium">Kết thúc</span>
                        <% _ -> %>
                          <span class="text-white/30">-</span>
                      <% end %>
                    </td>
                    <td class="px-3 py-2 text-purple-400 text-xs font-medium"><%= event_data.event_count %></td>
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
          Hiển thị <%= length(@grouped_events) %> / <%= @meta.total_count || 0 %>
        </span>
        <nav class="flex items-center gap-2" :if={@meta.total_pages && @meta.total_pages > 1}>
          <button
            :if={@meta.current_page > 1}
            phx-click="paginate"
            phx-value-page={@meta.current_page - 1}
            class="px-2 py-1 border border-green-600 text-white rounded text-xs hover:bg-green-900/30"
          >
            ← Trước
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
            Sau →
          </button>
        </nav>
      </div>

      <!-- Detail Modal -->
      <%= if @selected_event do %>
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/80" phx-click="close_detail">
          <div class="bg-[#0a0a0a] border border-green-600 rounded-xl max-w-3xl w-full mx-4 max-h-[85vh] overflow-y-auto shadow-2xl shadow-green-900/20" phx-click="noop" phx-target="">
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
                <div class="flex gap-3 overflow-x-auto pb-2 items-start">
                  <%= for crop <- data.crops do %>
                    <%= if img_src = get_base64_image(crop) do %>
                      <img src={img_src} alt="Crop" class="max-h-48 w-auto object-contain rounded-lg border border-green-700 flex-shrink-0" />
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
                  <div class="text-white/40 text-[10px] uppercase mb-0.5">Đối tượng</div>
                  <div class="text-white text-sm font-medium"><%= data.object_class || "-" %></div>
                </div>
                <div class="bg-green-900/10 border border-green-900/30 rounded-lg px-3 py-2 col-span-2">
                  <div class="text-white/40 text-[10px] uppercase mb-0.5">Vùng / Tuyến</div>
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
                  <div class="text-white/40 text-[10px] uppercase mb-0.5">Thời lượng</div>
                  <div class="text-yellow-400 text-sm font-medium"><%= data.duration || "-" %></div>
                </div>
                <div class="bg-green-900/10 border border-green-900/30 rounded-lg px-3 py-2">
                  <div class="text-white/40 text-[10px] uppercase mb-0.5">Sự kiện</div>
                  <div class="text-purple-400 text-sm font-medium"><%= data.event_count %> sự kiện · <%= data.crops_count %> ảnh</div>
                </div>
                <div class="bg-green-900/10 border border-green-900/30 rounded-lg px-3 py-2">
                  <div class="text-white/40 text-[10px] uppercase mb-0.5">Thời gian</div>
                  <div class="text-white text-sm">
                    <%= if data.timestamp, do: Calendar.strftime(data.timestamp, "%d/%m/%Y %H:%M:%S"), else: "-" %>
                  </div>
                </div>
              </div>

              <!-- Confidence -->
              <%= if data.crop do %>
                <div class="bg-green-900/10 border border-green-900/30 rounded-lg px-3 py-2">
                  <div class="text-white/40 text-[10px] uppercase mb-0.5">Độ tin cậy</div>
                  <div class="flex items-center gap-2">
                    <div class="flex-1 bg-black/50 rounded-full h-2 max-w-[200px]">
                      <div class={"h-2 rounded-full #{confidence_bar_color(data.crop.confidence)}"} style={"width: #{Float.round((data.crop.confidence || 0) * 100, 1)}%"}></div>
                    </div>
                    <span class="text-white text-sm font-medium"><%= Float.round((data.crop.confidence || 0) * 100, 1) %>%</span>
                  </div>
                </div>
              <% end %>

              <!-- Grouped Attributes -->
              <%= if data.attributes != [] do %>
                <% grouped = group_attributes(data.attributes) %>
                
                <!-- Person Attributes -->
                <%= if grouped.person != [] do %>
                  <div class="bg-green-900/10 border border-green-900/30 rounded-lg px-3 py-2">
                    <div class="text-white/40 text-[10px] uppercase mb-1.5">Thuộc tính người</div>
                    <div class="grid grid-cols-2 sm:grid-cols-3 gap-1.5">
                      <%= for attr <- grouped.person do %>
                        <div class="flex items-center gap-1.5 px-2 py-1 bg-cyan-900/20 border border-cyan-900/40 rounded">
                          <span class="text-cyan-400 text-[10px] font-medium"><%= format_attribute_name_vi(attr.name) %></span>
                          <span class="text-white text-[11px]"><%= format_attribute_value_vi(attr.name, attr.value) %></span>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
                
                <!-- Appearance Attributes -->
                <%= if grouped.appearance != [] do %>
                  <div class="bg-green-900/10 border border-green-900/30 rounded-lg px-3 py-2">
                    <div class="text-white/40 text-[10px] uppercase mb-1.5">Trang phục</div>
                    <div class="flex flex-wrap gap-1.5">
                      <%= for attr <- grouped.appearance do %>
                        <div class="flex items-center gap-1.5 px-2 py-1 rounded" style={attr_color_bg(attr.name, attr.value)}>
                          <span class="text-white/70 text-[10px] font-medium"><%= format_attribute_name_vi(attr.name) %></span>
                          <span class="text-white text-[11px] font-medium"><%= format_attribute_value_vi(attr.name, attr.value) %></span>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
                
                <!-- Vehicle Attributes -->
                <%= if grouped.vehicle != [] do %>
                  <div class="bg-green-900/10 border border-green-900/30 rounded-lg px-3 py-2">
                    <div class="text-white/40 text-[10px] uppercase mb-1.5">Thuộc tính phương tiện</div>
                    <div class="grid grid-cols-2 gap-1.5">
                      <%= for attr <- grouped.vehicle do %>
                        <div class="flex items-center gap-1.5 px-2 py-1 bg-blue-900/20 border border-blue-900/40 rounded">
                          <span class="text-blue-400 text-[10px] font-medium"><%= format_attribute_name_vi(attr.name) %></span>
                          <span class="text-white text-[11px]"><%= format_attribute_value_vi(attr.name, attr.value) %></span>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
                
                <!-- Other Attributes -->
                <%= if grouped.other != [] do %>
                  <div class="bg-green-900/10 border border-green-900/30 rounded-lg px-3 py-2">
                    <div class="text-white/40 text-[10px] uppercase mb-1.5">Thuộc tính khác</div>
                    <div class="flex flex-wrap gap-1.5">
                      <%= for attr <- grouped.other do %>
                        <span class="px-2 py-1 bg-gray-800/50 border border-gray-700 rounded text-xs text-white">
                          <span class="text-gray-400"><%= format_attribute_name(attr.name) %></span>: <%= truncate_value(attr.value) %>
                        </span>
                      <% end %>
                    </div>
                  </div>
                <% end %>
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
     |> assign(:show_advanced_filters, false)
     |> assign(:search_query, "")
     |> load_events()}
  end

  @impl true
  def handle_event("appearance_search", %{"query" => query}, socket) do
    query = String.trim(query)
    
    if query == "" do
      {:noreply,
       socket
       |> assign(:search_query, "")
       |> assign(:filters, %{})
       |> assign(:page, 1)
       |> load_events()}
    else
      parsed_filters = parse_appearance_query(query)
      
      {:noreply,
       socket
       |> assign(:search_query, query)
       |> assign(:filters, parsed_filters)
       |> assign(:page, 1)
       |> load_events()}
    end
  end

  @impl true
  def handle_event("clear_search", _params, socket) do
    {:noreply,
     socket
     |> assign(:search_query, "")
     |> assign(:filters, %{})
     |> assign(:page, 1)
     |> load_events()}
  end

  @impl true
  def handle_event("remove_filter", %{"key" => key}, socket) do
    filters = Map.delete(socket.assigns.filters, key)
    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:page, 1)
     |> load_events()}
  end

  @impl true
  def handle_event("clear_all_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:search_query, "")
     |> assign(:filters, %{})
     |> assign(:page, 1)
     |> load_events()}
  end

  @impl true
  def handle_event("toggle_filters", _params, socket) do
    {:noreply, assign(socket, :show_advanced_filters, !socket.assigns.show_advanced_filters)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    all_filter_keys = [
      "device_id", "ref_event_id", "min_confidence", "object_type",
      "event_type", "upper_clothing_color", "lower_clothing_color", 
      "age", "gender", "glasses", "tattoo", "carrying_bag", "phone",
      "smoking", "face_covered", "vehicle_class", "vehicle_color"
    ]
    
    # Only process keys that are actually present in this form's params
    # This prevents one form from clearing filters set by another form or search
    present_keys = params |> Map.keys() |> Enum.filter(&(&1 in all_filter_keys))
    
    filters = Enum.reduce(present_keys, socket.assigns.filters, fn key, acc ->
      case Map.get(params, key) do
        "" -> Map.delete(acc, key)
        nil -> Map.delete(acc, key)
        val -> Map.put(acc, key, val)
      end
    end)

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
    attr_filter_keys = [
      "upper_clothing_color", "lower_clothing_color", "age", "gender",
      "glasses", "tattoo", "carrying_bag", "phone", "smoking",
      "face_covered", "vehicle_class", "vehicle_color"
    ]
    attr_filters = Map.take(filters, attr_filter_keys)
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end) 
    |> Map.new()
    
    # Filter out special filters from crop filters (they're handled separately)
    crop_filters = filters 
    |> Map.drop(["object_type", "event_type" | attr_filter_keys])

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
    crop_tracking_ids_set = MapSet.new(crop_results, & &1.tracking_id)

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
    |> Enum.reject(fn r -> MapSet.member?(crop_tracking_ids_set, r.tracking_id) end)

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

  defp build_grouped_events([]), do: []
  defp build_grouped_events(tracking_ids) do
    # === BATCH QUERIES: 4 queries total instead of 4*N ===
    
    # 1. Batch fetch all crops (ordered by inserted_at desc)
    all_crops = from(c in Crop,
      where: c.ref_tracking_id in ^tracking_ids,
      order_by: [desc: c.inserted_at]
    ) |> Repo.all()
    crops_by_tid = Enum.group_by(all_crops, & &1.ref_tracking_id)

    # 2. Batch fetch all attributes
    all_attributes = from(a in Attribute,
      where: a.ref_tracking_id in ^tracking_ids,
      order_by: [asc: a.name]
    ) |> Repo.all()
    attrs_by_tid = Enum.group_by(all_attributes, & &1.ref_tracking_id)

    # 3. Batch fetch object_class per tracking_id (lean query - only select what we need)
    tracks_by_tid = from(t in Track,
      where: t.tracking_id in ^tracking_ids,
      select: %{tracking_id: t.tracking_id, object_class: t.object_class},
      order_by: [desc: t.inserted_at]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.tracking_id)
    |> Map.new(fn {tid, tracks} -> {tid, List.first(tracks)} end)

    # 4. Batch fetch all events (exclude __fs_attr_area at DB level)
    all_events = from(e in AIAnalyticsEvent,
      where: e.ref_tracking_id in ^tracking_ids,
      where: is_nil(e.area_name) or e.area_name != "__fs_attr_area",
      order_by: [desc: e.inserted_at]
    ) |> Repo.all()
    events_by_tid = Enum.group_by(all_events, & &1.ref_tracking_id)

    # === BUILD GROUPED DATA IN-MEMORY ===
    Enum.map(tracking_ids, fn tracking_id ->
      crops = Map.get(crops_by_tid, tracking_id, []) |> Enum.take(10)
      first_crop = List.first(crops)

      attributes = Map.get(attrs_by_tid, tracking_id, [])
      |> Enum.uniq_by(fn a -> {a.name, a.value} end)

      track = Map.get(tracks_by_tid, tracking_id)
      object_class = if track, do: track.object_class, else: nil

      events = Map.get(events_by_tid, tracking_id, [])
      latest_event = List.first(events)

      event_types = events
      |> Enum.map(& &1.event_type)
      |> Enum.uniq()
      |> Enum.reject(&is_nil/1)

      # Compute duration from first/last timestamps (events already sorted desc)
      duration = case events do
        [latest | _] = evts when length(evts) > 1 ->
          earliest = List.last(evts)
          seconds = DateTime.diff(latest.inserted_at, earliest.inserted_at, :second)
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
        _ -> nil
      end

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

      zone_name = events |> Enum.find_value(fn e -> e.area_name end)
      line_name = events |> Enum.find_value(fn e -> 
        raw = e.raw_data || %{}
        raw["tripwire_name"]
      end)

      paired_prefixes = ["event-loitering", "event-intrusion", "event-activity"]
      has_start = Enum.any?(event_types, fn t -> Enum.any?(paired_prefixes, fn p -> t == p end) end)
      has_end = Enum.any?(event_types, fn t -> String.ends_with?(t, "-end") end)
      status = cond do
        has_start && !has_end -> :ongoing
        has_start && has_end -> :ended
        true -> nil
      end

      attr_map = attributes
      |> Enum.reduce(%{}, fn attr, acc ->
        Map.put_new(acc, attr.name, attr.value)
      end)

      {tracking_id, %{
        crop: first_crop,
        crops: crops,
        crops_count: length(crops),
        tracking_ids: [tracking_id],
        attributes: attributes,
        attr_map: attr_map,
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

  # Vietnamese attribute name formatting
  defp format_attribute_name_vi("age"), do: "Tuổi"
  defp format_attribute_name_vi("gender"), do: "Giới tính"
  defp format_attribute_name_vi("glasses"), do: "Kính"
  defp format_attribute_name_vi("smoking"), do: "Hút thuốc"
  defp format_attribute_name_vi("phone"), do: "ĐT"
  defp format_attribute_name_vi("face_covered"), do: "Che mặt"
  defp format_attribute_name_vi("carrying_bag"), do: "Mang túi"
  defp format_attribute_name_vi("tattoo"), do: "Hình xăm"
  defp format_attribute_name_vi("assisted"), do: "Hỗ trợ"
  defp format_attribute_name_vi("upper_clothing_color"), do: "Áo"
  defp format_attribute_name_vi("lower_clothing_color"), do: "Quần"
  defp format_attribute_name_vi("vehicle_class"), do: "Loại xe"
  defp format_attribute_name_vi("vehicle_color"), do: "Màu xe"
  defp format_attribute_name_vi("animal_class"), do: "Loại"
  defp format_attribute_name_vi(name), do: format_attribute_name(name)

  # Vietnamese attribute value formatting
  defp format_attribute_value_vi("gender", "male"), do: "Nam"
  defp format_attribute_value_vi("gender", "female"), do: "Nữ"
  defp format_attribute_value_vi("gender", "unknown"), do: "N/A"
  defp format_attribute_value_vi("age", "young"), do: "Trẻ"
  defp format_attribute_value_vi("age", "adult"), do: "Trưởng thành"
  defp format_attribute_value_vi("age", "middle"), do: "Trung niên"
  defp format_attribute_value_vi("age", "senior"), do: "Cao tuổi"
  defp format_attribute_value_vi("age", "unknown"), do: "N/A"
  defp format_attribute_value_vi(name, "true") when name in ["glasses", "smoking", "phone", "face_covered", "carrying_bag", "tattoo", "assisted"], do: "Có"
  defp format_attribute_value_vi(name, "false") when name in ["glasses", "smoking", "phone", "face_covered", "carrying_bag", "tattoo", "assisted"], do: "Không"
  defp format_attribute_value_vi("vehicle_class", "motorcycle"), do: "Xe máy"
  defp format_attribute_value_vi("vehicle_class", "car"), do: "Ô tô"
  defp format_attribute_value_vi("vehicle_class", "bicycle"), do: "Xe đạp"
  defp format_attribute_value_vi("vehicle_class", "truck"), do: "Xe tải"
  defp format_attribute_value_vi("vehicle_class", "bus"), do: "Xe buýt"
  defp format_attribute_value_vi("vehicle_class", "van"), do: "Xe van"
  defp format_attribute_value_vi("vehicle_class", "construction"), do: "Xe CT"
  defp format_attribute_value_vi(_color_attr, "black"), do: "Đen"
  defp format_attribute_value_vi(_color_attr, "white"), do: "Trắng"
  defp format_attribute_value_vi(_color_attr, "gray"), do: "Xám"
  defp format_attribute_value_vi(_color_attr, "red"), do: "Đỏ"
  defp format_attribute_value_vi(_color_attr, "blue"), do: "X.Dương"
  defp format_attribute_value_vi(_color_attr, "green"), do: "X.Lá"
  defp format_attribute_value_vi(_color_attr, "yellow"), do: "Vàng"
  defp format_attribute_value_vi(_color_attr, "pink"), do: "Hồng"
  defp format_attribute_value_vi(_color_attr, "beige"), do: "Be"
  defp format_attribute_value_vi(_color_attr, "orange"), do: "Cam"
  defp format_attribute_value_vi(_color_attr, "silver"), do: "Bạc"
  defp format_attribute_value_vi(_color_attr, "brown"), do: "Nâu"
  defp format_attribute_value_vi(_name, value), do: truncate_value(value)

  # Build compact attribute summary for table rows
  # Returns list of {label, color_class} tuples (text-only, no icons)
  defp build_attr_summary(attr_map) when map_size(attr_map) == 0, do: []
  defp build_attr_summary(attr_map) do
    person_attrs = []
    
    # Gender + Age combined
    person_attrs = case {Map.get(attr_map, "gender"), Map.get(attr_map, "age")} do
      {nil, nil} -> person_attrs
      {gender, nil} when gender != "unknown" -> [{format_attribute_value_vi("gender", gender), "bg-purple-900/40 border border-purple-800 text-purple-200"} | person_attrs]
      {nil, age} when age != "unknown" -> [{format_attribute_value_vi("age", age), "bg-purple-900/40 border border-purple-800 text-purple-200"} | person_attrs]
      {gender, age} -> 
        g = if gender != "unknown", do: format_attribute_value_vi("gender", gender), else: nil
        a = if age != "unknown", do: format_attribute_value_vi("age", age), else: nil
        label = [g, a] |> Enum.reject(&is_nil/1) |> Enum.join("/")
        if label != "", do: [{label, "bg-purple-900/40 border border-purple-800 text-purple-200"} | person_attrs], else: person_attrs
    end
    
    # Upper clothing color
    person_attrs = case Map.get(attr_map, "upper_clothing_color") do
      nil -> person_attrs
      color -> [{"Áo: #{format_attribute_value_vi("upper_clothing_color", color)}", clothing_color_class(color)} | person_attrs]
    end
    
    # Lower clothing color  
    person_attrs = case Map.get(attr_map, "lower_clothing_color") do
      nil -> person_attrs
      color -> [{"Quần: #{format_attribute_value_vi("lower_clothing_color", color)}", clothing_color_class(color)} | person_attrs]
    end
    
    # Boolean flags - only show "true" values
    bool_flags = [
      {"glasses", "Kính"},
      {"phone", "ĐT"},
      {"smoking", "Thuốc"},
      {"carrying_bag", "Túi"},
      {"face_covered", "Che mặt"},
      {"tattoo", "Xăm"}
    ]
    
    person_attrs = Enum.reduce(bool_flags, person_attrs, fn {key, label}, acc ->
      case Map.get(attr_map, key) do
        "true" -> [{label, "bg-amber-900/40 border border-amber-800 text-amber-200"} | acc]
        _ -> acc
      end
    end)
    
    # Vehicle attributes
    vehicle_attrs = []
    vehicle_attrs = case Map.get(attr_map, "vehicle_class") do
      nil -> vehicle_attrs
      vc -> [{format_attribute_value_vi("vehicle_class", vc), "bg-blue-900/40 border border-blue-800 text-blue-200"} | vehicle_attrs]
    end
    vehicle_attrs = case Map.get(attr_map, "vehicle_color") do
      nil -> vehicle_attrs
      "none" -> vehicle_attrs
      vc -> [{"Màu: #{format_attribute_value_vi("vehicle_color", vc)}", clothing_color_class(vc)} | vehicle_attrs]
    end
    
    # Animal attributes
    animal_attrs = case Map.get(attr_map, "animal_class") do
      nil -> []
      ac -> [{ac, "bg-green-900/40 border border-green-800 text-green-200"}]
    end
    
    Enum.reverse(person_attrs) ++ Enum.reverse(vehicle_attrs) ++ animal_attrs
  end

  # Color class for clothing color badges
  defp clothing_color_class("black"), do: "bg-gray-800 border border-gray-600 text-gray-200"
  defp clothing_color_class("white"), do: "bg-white/10 border border-white/30 text-white"
  defp clothing_color_class("gray"), do: "bg-gray-700/60 border border-gray-500 text-gray-200"
  defp clothing_color_class("red"), do: "bg-red-900/40 border border-red-700 text-red-200"
  defp clothing_color_class("blue"), do: "bg-blue-900/40 border border-blue-700 text-blue-200"
  defp clothing_color_class("green"), do: "bg-green-900/40 border border-green-700 text-green-200"
  defp clothing_color_class("yellow"), do: "bg-yellow-900/40 border border-yellow-700 text-yellow-200"
  defp clothing_color_class("pink"), do: "bg-pink-900/40 border border-pink-700 text-pink-200"
  defp clothing_color_class("beige"), do: "bg-amber-900/30 border border-amber-700 text-amber-200"
  defp clothing_color_class("orange"), do: "bg-orange-900/40 border border-orange-700 text-orange-200"
  defp clothing_color_class("silver"), do: "bg-gray-600/40 border border-gray-400 text-gray-200"
  defp clothing_color_class("brown"), do: "bg-amber-900/50 border border-amber-800 text-amber-200"
  defp clothing_color_class(_), do: "bg-gray-800/40 border border-gray-600 text-gray-200"

  # Group attributes by category for detail modal
  defp group_attributes(attributes) do
    person_keys = ~w(age gender glasses smoking phone face_covered carrying_bag tattoo assisted)
    appearance_keys = ~w(upper_clothing_color lower_clothing_color)
    vehicle_keys = ~w(vehicle_class vehicle_color)
    skip_keys = ~w(person_car_features face_features)
    
    Enum.reduce(attributes, %{person: [], appearance: [], vehicle: [], other: []}, fn attr, acc ->
      cond do
        attr.name in skip_keys -> acc
        attr.name in person_keys -> %{acc | person: acc.person ++ [attr]}
        attr.name in appearance_keys -> %{acc | appearance: acc.appearance ++ [attr]}
        attr.name in vehicle_keys -> %{acc | vehicle: acc.vehicle ++ [attr]}
        true -> %{acc | other: acc.other ++ [attr]}
      end
    end)
  end

  # Background style for color attributes in detail modal
  defp attr_color_bg(name, value) when name in ["upper_clothing_color", "lower_clothing_color"] do
    css_color = case value do
      "black" -> "#1a1a1a"
      "white" -> "#f0f0f0"
      "gray" -> "#6b7280"
      "red" -> "#991b1b"
      "blue" -> "#1e3a5f"
      "green" -> "#14532d"
      "yellow" -> "#713f12"
      "pink" -> "#831843"
      "beige" -> "#78350f"
      "orange" -> "#7c2d12"
      _ -> "#374151"
    end
    "background-color: #{css_color}; border: 1px solid #{css_color}88;"
  end
  defp attr_color_bg(_name, _value), do: "background-color: #1e293b; border: 1px solid #334155;"

  defp confidence_bar_color(conf) when is_number(conf) and conf >= 0.8, do: "bg-green-500"
  defp confidence_bar_color(conf) when is_number(conf) and conf >= 0.5, do: "bg-yellow-500"
  defp confidence_bar_color(_), do: "bg-red-500"

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

  # ============================================================
  # Appearance Search - Vietnamese Natural Language Parser
  # ============================================================

  @color_map %{
    # Vietnamese color names -> English DB values
    "đen" => "black", "den" => "black",
    "trắng" => "white", "trang" => "white",
    "xám" => "gray", "xam" => "gray",
    "đỏ" => "red", "do" => "red",
    "xanh dương" => "blue", "xanh duong" => "blue",
    "xanh lá" => "green", "xanh la" => "green",
    "vàng" => "yellow", "vang" => "yellow",
    "hồng" => "pink", "hong" => "pink",
    "be" => "beige",
    "cam" => "orange",
    "bạc" => "silver", "bac" => "silver",
    "nâu" => "brown", "nau" => "brown"
  }

  @vehicle_map %{
    "xe máy" => "motorcycle", "xe may" => "motorcycle",
    "ô tô" => "car", "o to" => "car", "oto" => "car",
    "xe hơi" => "car", "xe hoi" => "car",
    "xe tải" => "truck", "xe tai" => "truck",
    "xe buýt" => "bus", "xe buyt" => "bus", "xe bus" => "bus",
    "xe van" => "van",
    "xe đạp" => "bicycle", "xe dap" => "bicycle",
    "xe công trình" => "construction", "xe cong trinh" => "construction"
  }

  defp parse_appearance_query(query) do
    q = query |> String.downcase() |> String.trim()
    filters = %{}

    # 1. Detect gender
    filters = cond do
      match_any?(q, ["phụ nữ", "phu nu", "nữ", "nu ", "nữ ", "con gái", "con gai", "female"]) ->
        Map.put(filters, "gender", "female")
      match_any?(q, ["nam ", "nam,", "đàn ông", "dan ong", "male"]) ->
        Map.put(filters, "gender", "male")
      true -> filters
    end

    # 2. Detect age
    filters = cond do
      match_any?(q, ["trẻ", "tre ", "young"]) -> Map.put(filters, "age", "young")
      match_any?(q, ["trưởng thành", "truong thanh", "người lớn", "nguoi lon", "adult"]) -> Map.put(filters, "age", "adult")
      match_any?(q, ["trung niên", "trung nien", "middle"]) -> Map.put(filters, "age", "middle")
      match_any?(q, ["cao tuổi", "cao tuoi", "già", "gia ", "senior", "elderly"]) -> Map.put(filters, "age", "senior")
      true -> filters
    end

    # 3. Detect vehicle class (check multi-word phrases first)
    {filters, q_after_vehicle} = detect_vehicle(q, filters)

    # 4. Detect upper clothing color (áo)
    filters = case extract_color_after(q, ["áo", "ao "]) do
      nil -> filters
      color -> Map.put(filters, "upper_clothing_color", color)
    end

    # 5. Detect lower clothing color (quần)
    filters = case extract_color_after(q, ["quần", "quan "]) do
      nil -> filters
      color -> Map.put(filters, "lower_clothing_color", color)
    end

    # 6. Detect vehicle color (màu) - only if vehicle detected and no clothing color matched
    filters = if Map.has_key?(filters, "vehicle_class") do
      case extract_color_after(q, ["màu", "mau ", "color"]) do
        nil ->
          # Try standalone color if vehicle was detected and no explicit "màu" prefix
          detect_standalone_vehicle_color(q_after_vehicle, filters)
        color ->
          Map.put(filters, "vehicle_color", color)
      end
    else
      # If no vehicle but "màu" keyword exists and no upper/lower matched
      case extract_color_after(q, ["màu", "mau "]) do
        nil -> filters
        color ->
          if not Map.has_key?(filters, "upper_clothing_color") and not Map.has_key?(filters, "lower_clothing_color") do
            Map.put(filters, "upper_clothing_color", color)
          else
            filters
          end
      end
    end

    # 7. Detect boolean attributes
    filters = if match_any?(q, ["kính", "kinh", "đeo kính", "deo kinh", "glasses"]), do: Map.put(filters, "glasses", "true"), else: filters
    filters = if match_any?(q, ["túi", "tui", "mang túi", "mang tui", "ba lô", "ba lo", "bag"]), do: Map.put(filters, "carrying_bag", "true"), else: filters
    filters = if match_any?(q, ["điện thoại", "dien thoai", "phone"]), do: Map.put(filters, "phone", "true"), else: filters
    filters = if match_any?(q, ["hút thuốc", "hut thuoc", "thuốc lá", "thuoc la", "smoking"]), do: Map.put(filters, "smoking", "true"), else: filters
    filters = if match_any?(q, ["che mặt", "che mat", "khẩu trang", "khau trang", "mask"]), do: Map.put(filters, "face_covered", "true"), else: filters
    filters = if match_any?(q, ["xăm", "xam", "hình xăm", "hinh xam", "tattoo"]), do: Map.put(filters, "tattoo", "true"), else: filters

    # 8. Detect object type from context
    filters = cond do
      Map.has_key?(filters, "vehicle_class") -> Map.put_new(filters, "object_type", "Vehicle")
      match_any?(q, ["người", "nguoi", "person"]) or Map.has_key?(filters, "gender") or Map.has_key?(filters, "age") or Map.has_key?(filters, "upper_clothing_color") ->
        Map.put_new(filters, "object_type", "Person")
      true -> filters
    end

    filters
  end

  defp match_any?(text, keywords) do
    Enum.any?(keywords, fn kw -> String.contains?(text, kw) end)
  end

  defp detect_vehicle(q, filters) do
    case Enum.find(@vehicle_map, fn {vn_name, _en} -> String.contains?(q, vn_name) end) do
      {vn_name, en_value} ->
        remaining = String.replace(q, vn_name, "") |> String.trim()
        {Map.put(filters, "vehicle_class", en_value), remaining}
      nil ->
        {filters, q}
    end
  end

  defp extract_color_after(text, prefixes) do
    Enum.find_value(prefixes, fn prefix ->
      case :binary.match(text, prefix) do
        {start, len} ->
          after_prefix = String.slice(text, (start + len)..-1//1) |> String.trim_leading()
          find_color_at_start(after_prefix)
        :nomatch ->
          nil
      end
    end)
  end

  defp find_color_at_start(text) do
    # Try multi-word colors first, then single-word
    sorted_colors = @color_map |> Map.keys() |> Enum.sort_by(&(-String.length(&1)))
    Enum.find_value(sorted_colors, fn color_name ->
      if String.starts_with?(text, color_name), do: @color_map[color_name], else: nil
    end)
  end

  defp detect_standalone_vehicle_color(remaining_text, filters) do
    # After removing vehicle name, check if any color word remains
    remaining = String.trim(remaining_text)
    sorted_colors = @color_map |> Map.keys() |> Enum.sort_by(&(-String.length(&1)))
    case Enum.find_value(sorted_colors, fn color_name ->
      if String.contains?(remaining, color_name), do: @color_map[color_name], else: nil
    end) do
      nil -> filters
      color -> Map.put(filters, "vehicle_color", color)
    end
  end

  # ============================================================
  # Filter Display Helpers
  # ============================================================

  defp filter_display_name("device_id"), do: "Thiết bị"
  defp filter_display_name("event_type"), do: "Sự kiện"
  defp filter_display_name("object_type"), do: "Đối tượng"
  defp filter_display_name("min_confidence"), do: "Độ tin cậy"
  defp filter_display_name("gender"), do: "Giới tính"
  defp filter_display_name("age"), do: "Tuổi"
  defp filter_display_name("upper_clothing_color"), do: "Màu áo"
  defp filter_display_name("lower_clothing_color"), do: "Màu quần"
  defp filter_display_name("glasses"), do: "Kính"
  defp filter_display_name("carrying_bag"), do: "Mang túi"
  defp filter_display_name("phone"), do: "Điện thoại"
  defp filter_display_name("smoking"), do: "Hút thuốc"
  defp filter_display_name("face_covered"), do: "Che mặt"
  defp filter_display_name("tattoo"), do: "Hình xăm"
  defp filter_display_name("vehicle_class"), do: "Loại xe"
  defp filter_display_name("vehicle_color"), do: "Màu xe"
  defp filter_display_name(name), do: format_attribute_name(name)

  defp filter_display_value("gender", "male"), do: "Nam"
  defp filter_display_value("gender", "female"), do: "Nữ"
  defp filter_display_value("object_type", "Person"), do: "Người"
  defp filter_display_value("object_type", "Vehicle"), do: "Phương tiện"
  defp filter_display_value("object_type", "Bicycle"), do: "Xe đạp"
  defp filter_display_value("object_type", "Animal"), do: "Động vật"
  defp filter_display_value("min_confidence", val), do: "≥ #{Float.round(String.to_float(val) * 100, 0)}%"
  defp filter_display_value("event_type", val), do: format_event_type(val)
  defp filter_display_value(key, "true") when key in ["glasses", "carrying_bag", "phone", "smoking", "face_covered", "tattoo"], do: "Có"
  defp filter_display_value(key, "false") when key in ["glasses", "carrying_bag", "phone", "smoking", "face_covered", "tattoo"], do: "Không"
  defp filter_display_value("vehicle_class", val), do: format_attribute_value_vi("vehicle_class", val)
  defp filter_display_value("vehicle_color", val), do: format_attribute_value_vi("vehicle_color", val)
  defp filter_display_value("upper_clothing_color", val), do: format_attribute_value_vi("upper_clothing_color", val)
  defp filter_display_value("lower_clothing_color", val), do: format_attribute_value_vi("lower_clothing_color", val)
  defp filter_display_value("age", val), do: format_attribute_value_vi("age", val)
  defp filter_display_value(_key, val), do: val
end
