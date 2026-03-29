defmodule TProNVRWeb.CommanderSyncLive do
  use TProNVRWeb, :live_view

  require Logger

  @config_path "/home/cvedix/Documents/Github/omnimedia/release/linux/Debug/config.ini"
  @conf_dir_path "/home/cvedix/Documents/Github/omnimedia/conf/config.ini"

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(TProNVR.PubSub, "commander_sync_logs")
    end
    
    config = read_watchdog_config()
    {:ok, assign(socket, config: config, saved: false, error: nil, logs: [])}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  def handle_event("save", %{"config" => params}, socket) do
    params = Map.put(params, "enable", Map.get(params, "enable", "0"))

    case write_watchdog_config(params) do
      :ok ->
        TProNVR.CommanderSync.Worker.trigger_sync()
        {:noreply, assign(socket, config: params, saved: true, error: nil)}
      {:error, reason} ->
        {:noreply, assign(socket, error: reason, saved: false)}
    end
  end

  def handle_event("save_rtmp", %{"rtmp" => params}, socket) do
    merged = Map.merge(socket.assigns.config, %{
      "rtmpEnable" => Map.get(params, "rtmpEnable", "0"),
      "rtmpServer" => Map.get(params, "rtmpServer", "")
    })

    case write_watchdog_config(merged) do
      :ok ->
        TProNVR.CommanderSync.RTMPWorker.trigger_sync()
        {:noreply, assign(socket, config: merged, saved: true, error: nil)}
      {:error, reason} ->
        {:noreply, assign(socket, error: reason, saved: false)}
    end
  end

  def handle_info({:sync_log, line}, socket) do
    logs = [line | socket.assigns.logs] |> Enum.take(50)
    {:noreply, assign(socket, logs: logs)}
  end

  defp read_watchdog_config do
    if File.exists?(@config_path) do
      content = File.read!(@config_path)
      %{
        "enable" => extract_val(content, "enable", "0"),
        "server" => extract_val(content, "server", "http://127.0.0.1:5055"),
        "deviceId" => extract_val(content, "deviceId", ""),
        "deviceType" => extract_val(content, "deviceType", "omnimedia"),
        "interval" => extract_val(content, "interval", "3600"),
        "latitude" => extract_val(content, "latitude", "0.0"),
        "longitude" => extract_val(content, "longitude", "0.0"),
        "rtmpEnable" => extract_val(content, "rtmpEnable", "0"),
        "rtmpServer" => extract_val(content, "rtmpServer", "")
      }
    else
      %{"enable" => "0", "server" => "", "deviceId" => "", "deviceType" => "omnimedia", "interval" => "3600", "latitude" => "0.0", "longitude" => "0.0", "rtmpEnable" => "0", "rtmpServer" => ""}
    end
  end

  defp extract_val(content, key, default) do
    case Regex.run(~r/^[ \t]*#{key}[ \t]*=[ \t]*(.*)$/m, content) do
      [_, val] -> String.trim(val)
      _ -> default
    end
  end

  defp write_watchdog_config(params) do
    try do
      if File.exists?(@config_path) do
        content = File.read!(@config_path)
        new_content = update_content(content, params)
        File.write!(@config_path, new_content)
        if File.exists?(@conf_dir_path) do
          File.write!(@conf_dir_path, new_content)
        end
        :ok
      else
        {:error, "File config.ini không tồn tại ở #{@config_path}"}
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp update_content(content, params) do
    Enum.reduce(params, content, fn {key, val}, acc ->
      if Regex.match?(~r/^[ \t]*#{key}[ \t]*=/m, acc) do
        Regex.replace(~r/^([ \t]*#{key}[ \t]*=)(.*)$/m, acc, "\\1#{val}")
      else
        # Key missing, inject it directly under the [watchdog] section
        if Regex.match?(~r/^\[watchdog\]/m, acc) do
          Regex.replace(~r/^(\[watchdog\]\r?\n)/m, acc, "\\1#{key}=#{val}\n")
        else
          # Fallback if somehow [watchdog] doesn't exist
          acc <> "\n[watchdog]\n#{key}=#{val}\n"
        end
      end
    end)
  end

  def render(assigns) do
    ~H"""
    <div class="p-4 md:p-6 bg-black font-mono text-green-500 h-full overflow-y-auto">
      <div class="max-w-7xl mx-auto pb-12">
        <div class="flex flex-col md:flex-row items-start md:items-center justify-between mb-8 border-b border-green-900/50 pb-4 gap-4">
          <h1 class="text-xl md:text-2xl font-bold tracking-widest uppercase flex items-center">
            <.icon name="hero-signal" class="w-8 h-8 mr-3 text-green-500 animate-pulse" />
            [ COMMANDER_TELEMETRY_SYNC ]
          </h1>
          <div class="text-[10px] md:text-xs tracking-widest uppercase text-green-700 whitespace-nowrap">
            NODE_STATUS: <span class="bg-green-500 text-black px-2 py-0.5 font-bold ml-1">OPERATIONAL</span>
          </div>
        </div>

        <!-- Navigation Tabs -->
        <div class="flex space-x-2 border-b border-green-900/50 mb-8 overflow-x-auto scrollbar-hide">
          <.link patch={~p"/commander-sync"} class={"px-6 py-3 text-[10px] md:text-xs font-bold tracking-widest uppercase transition-colors whitespace-nowrap flex items-center " <> if @live_action == :index, do: "bg-green-600 text-black border-t-2 border-green-400", else: "bg-green-900/20 text-green-500 hover:bg-green-800/40"}>
            <.icon name="hero-cog" class="w-4 h-4 mr-2" /> CẤU HÌNH (CONFIG)
          </.link>
          <.link patch={~p"/commander-sync/rtmp"} class={"px-6 py-3 text-[10px] md:text-xs font-bold tracking-widest uppercase transition-colors whitespace-nowrap flex items-center " <> if @live_action == :rtmp, do: "bg-green-600 text-black border-t-2 border-green-400", else: "bg-green-900/20 text-green-500 hover:bg-green-800/40"}>
            <.icon name="hero-video-camera" class="w-4 h-4 mr-2" /> RTMP RELAY
          </.link>
          <.link patch={~p"/commander-sync/logs"} class={"px-6 py-3 text-[10px] md:text-xs font-bold tracking-widest uppercase transition-colors whitespace-nowrap flex items-center " <> if @live_action == :logs, do: "bg-green-600 text-black border-t-2 border-green-400", else: "bg-green-900/20 text-green-500 hover:bg-green-800/40"}>
            <.icon name="hero-command-line" class="w-4 h-4 mr-2" /> NHẬT KÝ (LOGS)
          </.link>
        </div>

        <div :if={@saved && @live_action in [:index, :rtmp]} class="mb-6 p-4 border-l-4 border-green-500 bg-green-900/20 text-green-400">
          > CẤU HÌNH ĐÃ LƯU & DỊCH VỤ ĐANG KHỞI ĐỘNG LẠI.
        </div>

        <div :if={@error && @live_action in [:index, :rtmp]} class="mb-6 p-4 border-l-4 border-red-500 bg-red-900/20 text-red-500">
          > ERROR: {@error}
        </div>

        <div :if={@live_action == :index} class="bg-black border border-green-800 p-4 md:p-6 relative group shadow-[0_0_15px_rgba(34,197,94,0.1)] mb-8">
          <div class="absolute top-0 left-0 w-3 h-3 border-t-2 border-l-2 border-green-500"></div>
          <div class="absolute bottom-0 right-0 w-3 h-3 border-b-2 border-r-2 border-green-500"></div>

          <h3 class="text-base md:text-lg font-bold text-green-500 mb-6 tracking-widest uppercase border-b border-green-900/50 pb-2 flex items-center">
            <.icon name="hero-globe-alt" class="w-5 h-5 mr-3" />
            > KẾT NỐI TỚI MÁY CHỦ COMMANDER
          </h3>

          <p class="text-[10px] md:text-xs text-green-600 mb-8 border-l-2 border-green-800 pl-4 hidden sm:block">
            Đồng bộ trạng thái phần cứng (CPU, GPU, RAM, Nhiệt độ) và Network của hệ thống OmniSense NVR lên Commander Central (qua OsmAnd protocol) để giám sát tập trung.
          </p>

          <.form :let={f} for={%{"config" => @config}} as={:config} phx-submit="save" class="grid grid-cols-1 lg:grid-cols-2 gap-8">
            
            <!-- LEFT COLUMN: Input Fields -->
            <div class="space-y-6">
              <div class="flex items-center space-x-3 mb-6 bg-green-900/10 p-4 border border-green-900/30">
                <input type="checkbox" id={f[:enable].id} name={f[:enable].name} value="1" checked={@config["enable"] == "1"}
                       class="w-5 h-5 bg-black border-green-500 text-green-500 focus:ring-green-500 focus:ring-2 rounded-none" />
                <label for={f[:enable].id} class="text-[10px] md:text-sm font-bold uppercase tracking-widest text-green-400">
                  Kích hoạt Telemetry Watchdog
                </label>
              </div>

              <div class="grid grid-cols-1 xl:grid-cols-2 gap-6">
                <div>
                  <label class="block text-[10px] md:text-xs uppercase tracking-widest mb-2 text-green-600 font-bold">Commander Server URL</label>
                  <input type="text" name={f[:server].name} value={@config["server"]}
                         class="w-full bg-black border border-green-800 text-green-500 p-3 outline-none focus:border-green-400 focus:ring-1 focus:ring-green-400 tracking-wide text-xs"
                         placeholder="http://192.168.1.100:5055" />
                </div>

                <div>
                  <label class="block text-xs uppercase tracking-widest mb-2 text-green-600 font-bold">Mã Định Danh (Device ID)</label>
                  <input type="text" name={f[:deviceId].name} value={@config["deviceId"]}
                         class="w-full bg-black border border-green-800 text-green-500 p-3 outline-none focus:border-green-400 focus:ring-1 focus:ring-green-400 tracking-wide uppercase"
                         placeholder="OMNISENSE-01" />
                  <p class="text-[10px] text-green-700 mt-1">*Phải khớp chính xác với Identifier trên Commander</p>
                </div>

                <div>
                  <label class="block text-xs uppercase tracking-widest mb-2 text-green-600 font-bold">Phân Loại (Device Type)</label>
                  <input type="hidden" name={f[:deviceType].name} value="omnisense" />
                  <input type="text" value="OmniSense NVR" readonly
                         class="w-full bg-[#051005] border border-green-900 text-green-700 p-3 outline-none tracking-wide uppercase cursor-not-allowed" />
                </div>

                <div>
                  <label class="block text-xs uppercase tracking-widest mb-2 text-green-600 font-bold">Tần Xuất Báo Cáo (Giây)</label>
                  <input type="number" name={f[:interval].name} value={@config["interval"]}
                         class="w-full bg-black border border-green-800 text-green-500 p-3 outline-none focus:border-green-400 focus:ring-1 focus:ring-green-400 tracking-wide"
                         placeholder="60" />
                </div>

                <div>
                  <label class="block text-xs uppercase tracking-widest mb-2 text-green-600 font-bold">Tọa Độ: Latitude</label>
                  <input type="text" id="config_latitude" name={f[:latitude].name} value={@config["latitude"]}
                         class="w-full bg-black border border-green-800 text-green-500 p-3 outline-none focus:border-green-400 focus:ring-1 focus:ring-green-400 tracking-wide" />
                </div>

                <div>
                  <label class="block text-xs uppercase tracking-widest mb-2 text-green-600 font-bold">Tọa Độ: Longitude</label>
                  <input type="text" id="config_longitude" name={f[:longitude].name} value={@config["longitude"]}
                         class="w-full bg-black border border-green-800 text-green-500 p-3 outline-none focus:border-green-400 focus:ring-1 focus:ring-green-400 tracking-wide" />
                </div>
              </div>

            </div>

            <!-- RIGHT COLUMN: Interactive Map & Submission -->
            <div class="flex flex-col flex-1 h-full min-h-[400px]">
              <label class="block text-xs uppercase tracking-widest mb-2 text-green-600 font-bold flex items-center">
                <.icon name="hero-map-solid" class="w-4 h-4 mr-2" />
                Bản Đồ Định Vị (Click để chọn tọa độ)
              </label>
              
              <div class="p-1 border border-green-800 bg-black/50 shadow-[0_0_15px_rgba(34,197,94,0.1)] flex-1 min-h-[400px] flex flex-col relative w-full">
                <div id="commander-map" 
                     phx-hook="LocationPicker" 
                     phx-update="ignore"
                     data-lat-id="config_latitude" 
                     data-lng-id="config_longitude" 
                     class="absolute inset-0 z-0 h-full w-full"
                     style="filter: invert(100%) hue-rotate(180deg) brightness(95%) contrast(90%);">
                </div>
              </div>
              <p class="text-[10px] text-green-700 mt-2">*Kéo thả Marker hoặc click trên bản đồ để cập nhật tự động Latitude & Longitude.</p>

              <div class="mt-8 flex justify-end">
                <button type="submit" class="w-full bg-green-600 hover:bg-green-500 text-black font-bold uppercase tracking-widest py-3 px-8 transition-colors flex items-center justify-center">
                  <.icon name="hero-arrow-path" class="w-5 h-5 mr-4" />
                  LƯU & KHỞI ĐỘNG LẠI TELEMETRY TỪ NVR
                </button>
              </div>
            </div>
          </.form>
        </div>

        <!-- RTMP RELAY TAB -->
        <div :if={@live_action == :rtmp} class="bg-black border border-green-800 p-4 md:p-6 relative group shadow-[0_0_15px_rgba(34,197,94,0.1)] mb-8">
          <div class="absolute top-0 left-0 w-3 h-3 border-t-2 border-l-2 border-green-500"></div>
          <div class="absolute bottom-0 right-0 w-3 h-3 border-b-2 border-r-2 border-green-500"></div>

          <h3 class="text-base md:text-lg font-bold text-green-500 mb-6 tracking-widest uppercase border-b border-green-900/50 pb-2 flex items-center">
            <.icon name="hero-video-camera" class="w-5 h-5 mr-3" />
            > OMNIMEDIA RTMP STREAM RELAY
          </h3>

          <p class="text-[10px] md:text-xs text-green-600 mb-8 border-l-2 border-green-800 pl-4 hidden sm:block">
            Đẩy toàn bộ luồng Camera IP đang kết nối trên OmniSense lên máy chủ trung tâm OmniMedia qua giao thức RTMP. Mỗi Camera sẽ được publish theo đường dẫn: <span class="text-green-400">rtmp_server/device_id</span>.
          </p>

          <.form :let={f} for={%{"rtmp" => @config}} as={:rtmp} phx-submit="save_rtmp" class="space-y-6">
            <div class="flex items-center space-x-3 bg-green-900/10 p-4 border border-green-900/30">
              <input type="hidden" name={f[:rtmpEnable].name} value="0" />
              <input type="checkbox" id="rtmp_enable_cb" name={f[:rtmpEnable].name} value="1" checked={@config["rtmpEnable"] == "1"}
                     class="w-5 h-5 bg-black border-green-500 text-green-500 focus:ring-green-500 focus:ring-2 rounded-none" />
              <label for="rtmp_enable_cb" class="text-[10px] md:text-sm font-bold uppercase tracking-widest text-green-400">
                Kích hoạt Đẩy Luồng RTMP
              </label>
              <span :if={@config["rtmpEnable"] == "1"} class="ml-auto bg-green-500 text-black px-2 py-0.5 text-[10px] font-bold tracking-widest">ACTIVE</span>
              <span :if={@config["rtmpEnable"] != "1"} class="ml-auto bg-red-900 text-red-400 px-2 py-0.5 text-[10px] font-bold tracking-widest">INACTIVE</span>
            </div>

            <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
              <div>
                <label class="block text-xs uppercase tracking-widest mb-2 text-green-600 font-bold">ĐỊA CHỈ MÁY CHỦ RTMP (TRUNG TÂM)</label>
                <input type="text" name={f[:rtmpServer].name} value={@config["rtmpServer"]}
                       class="w-full bg-black border border-green-800 text-green-500 p-3 outline-none focus:border-green-400 focus:ring-1 focus:ring-green-400 tracking-wide text-xs"
                       placeholder="rtmp://192.168.1.127:1935/live" />
                <p class="text-[9px] text-green-700 mt-1">*Hệ thống sẽ ép luồng theo định dạng: rtmp_server/device_id</p>
              </div>

              <div>
                <label class="block text-xs uppercase tracking-widest mb-2 text-green-600 font-bold">PHƯƠNG THỨC TRUYỀN TẢI</label>
                <input type="text" value="FFmpeg (Copy Stream, Zero-Transcode)" readonly
                       class="w-full bg-[#051005] border border-green-900 text-green-700 p-3 outline-none tracking-wide uppercase cursor-not-allowed text-xs" />
              </div>
            </div>

            <div class="mt-6 flex justify-end">
              <button type="submit" class="bg-green-600 hover:bg-green-500 text-black font-bold uppercase tracking-widest py-3 px-8 transition-colors flex items-center justify-center">
                <.icon name="hero-arrow-path" class="w-5 h-5 mr-4" />
                LƯU CẤU HÌNH RTMP RELAY
              </button>
            </div>
          </.form>

          <!-- Active Camera Streams Table -->
          <div class="mt-8 pt-6 border-t border-green-900/50">
            <h4 class="text-sm font-bold text-green-500 mb-4 tracking-widest uppercase flex items-center">
              <.icon name="hero-signal" class="w-4 h-4 mr-2" />
              > DANH SÁCH CAMERA ĐANG KẾT NỐI
            </h4>
            <div class="overflow-x-auto">
              <table class="w-full text-left">
                <thead>
                  <tr class="border-b border-green-900/50 text-[10px] uppercase tracking-widest text-green-700">
                    <th class="py-2 pr-4">TÊN CAMERA</th>
                    <th class="py-2 pr-4">ID</th>
                    <th class="py-2 pr-4">TRẠNG THÁI</th>
                    <th class="py-2">RTMP TARGET</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for device <- TProNVR.Devices.list() do %>
                    <tr class="border-b border-green-900/20 text-xs">
                      <td class="py-2 pr-4 text-green-400"><%= device.name %></td>
                      <td class="py-2 pr-4 text-green-600 font-mono text-[10px]"><%= String.slice(device.id, 0, 8) %>...</td>
                      <td class="py-2 pr-4">
                        <span class={if device.state != :stopped, do: "text-green-400", else: "text-red-500"}>
                          <%= if device.state != :stopped, do: "● ONLINE", else: "○ OFFLINE" %>
                        </span>
                      </td>
                      <td class="py-2 text-green-700 font-mono text-[10px]">
                        <%= if @config["rtmpServer"] != "" do %>
                          <%= @config["rtmpServer"] %>/<%= device.id %>
                        <% else %>
                          —
                        <% end %>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <!-- OMNISENSE NATIVE TERMINAL LOGS -->
        <div :if={@live_action == :logs} class="bg-black border border-green-800 p-4 md:p-6 relative group shadow-[0_0_15px_rgba(34,197,94,0.1)]">
          <div class="absolute top-0 left-0 w-3 h-3 border-t-2 border-l-2 border-green-500"></div>
          <div class="absolute bottom-0 right-0 w-3 h-3 border-b-2 border-r-2 border-green-500"></div>

          <h3 class="text-base md:text-lg font-bold text-green-500 mb-6 tracking-widest uppercase border-b border-green-900/50 pb-2 flex items-center">
            <.icon name="hero-command-line" class="w-4 h-4 mr-2" />
            > NVR SYNC LOGS (NATIVE)
          </h3>
          
          <div class="bg-[#051005] border border-green-900/50 p-6 min-h-[600px] max-h-[800px] overflow-y-auto font-mono text-xs md:text-sm leading-relaxed relative flex flex-col">
            <%= if Enum.empty?(@logs) do %>
              <div class="text-green-800 animate-pulse">> WAITING FOR TELEMETRY BROADCAST...</div>
              <div class="text-green-900 mt-2 text-[10px]">*Ensure Telemetry Watchdog is enabled and the server is actively parsing stats matrix.</div>
            <% else %>
              <%= for log <- Enum.reverse(@logs) do %>
                <div class={"mb-2 tracking-wide " <> (if String.contains?(log, "[ERROR]") or String.contains?(log, "[FATAL]"), do: "text-red-500", else: (if String.contains?(log, "[SUCCESS]"), do: "text-green-300", else: "text-green-600"))}>
                  {log}
                </div>
              <% end %>
            <% end %>
            <div id="log-anchor" phx-hook="ScrollToBottom" data-container="command-logs"></div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
