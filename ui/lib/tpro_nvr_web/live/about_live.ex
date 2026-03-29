defmodule TProNVRWeb.AboutLive do
  use TProNVRWeb, :live_view

  def mount(_params, _session, socket) do
    hwinfo = TProNVR.HardwareInfo.get_info()
    {:ok, assign(socket, hwinfo: hwinfo, page_title: "About OmniSense")}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 font-mono">
      <%!-- Military Header --%>
      <div class="bg-black border-2 border-green-600 p-6 relative overflow-hidden mb-8 shadow-[0_0_15px_rgba(0,128,0,0.3)]">
        <div class="absolute inset-x-0 top-0 h-1 bg-gradient-to-r from-transparent via-green-500 to-transparent opacity-50"></div>
        <div class="absolute top-0 right-0 p-2 text-green-700 text-xs">TRẠNG_THÁI: HOẠT ĐỘNG</div>
        <div class="flex flex-col sm:flex-row items-center sm:items-start sm:space-x-8 space-y-6 sm:space-y-0">
          <div class="border border-green-500 p-6 bg-green-900/20 shadow-[0_0_15px_rgba(34,197,94,0.2)] flex-shrink-0">
            <.icon name="hero-server-stack-solid" class="w-16 h-16 text-green-500 animate-pulse" />
          </div>
          <div class="flex-1 text-center sm:text-left">
            <h1 class="text-2xl sm:text-3xl md:text-4xl font-bold text-green-500 tracking-widest uppercase mb-2">
              [ OmniSense AI NVR ]
            </h1>
            <div class="h-px bg-green-500/30 w-full mb-4 hidden sm:block"></div>
            <p class="text-green-400 text-xs sm:text-sm tracking-widest mb-4 font-bold border-b border-green-900/50 pb-2 inline-block sm:block">
              PHIÊN BẢN // {Application.spec(:tpro_nvr, :vsn)}
            </p>
            <p class="text-green-600 text-xs sm:text-sm leading-relaxed max-w-4xl sm:border-l-2 sm:border-green-800 sm:pl-4">
              ĐẦU GHI HÌNH MẠNG TÍCH HỢP TRÍ TUỆ NHÂN TẠO THỜI GIAN THỰC.
              TRIỂN KHAI TRÊN KIẾN TRÚC ELIXIR PHÂN TÁN CHO KHẢ NĂNG MỞ RỘNG TỐI ĐA.
            </p>
          </div>
        </div>
      </div>

      <!-- Navigation Tabs -->
      <div class="flex space-x-2 border-b border-green-900/50 mb-8 overflow-x-auto scrollbar-hide">
        <.link patch={~p"/about"} class={"px-6 py-3 text-[10px] md:text-xs font-bold tracking-widest uppercase transition-colors whitespace-nowrap flex items-center " <> if @live_action == :index, do: "bg-green-600 text-black border-t-2 border-green-400", else: "bg-green-900/20 text-green-500 hover:bg-green-800/40"}>
          <.icon name="hero-document-text" class="w-4 h-4 mr-2" /> GHI CHÚ CẬP NHẬT
        </.link>
        <.link patch={~p"/about/hardware"} class={"px-6 py-3 text-[10px] md:text-xs font-bold tracking-widest uppercase transition-colors whitespace-nowrap flex items-center " <> if @live_action == :hardware, do: "bg-green-600 text-black border-t-2 border-green-400", else: "bg-green-900/20 text-green-500 hover:bg-green-800/40"}>
          <.icon name="hero-cpu-chip" class="w-4 h-4 mr-2" /> THÔNG TIN PHẦN CỨNG
        </.link>
      </div>

      <%!-- Release Notes Tab --%>
      <div :if={@live_action == :index}>
      <div class="bg-black border border-green-800 p-6 relative mb-8 group hover:border-green-500 transition-colors shadow-[0_0_15px_rgba(34,197,94,0.05)]">
        <div class="absolute top-0 left-0 w-3 h-3 border-t-2 border-l-2 border-green-500"></div>
        <div class="absolute bottom-0 right-0 w-3 h-3 border-b-2 border-r-2 border-green-500"></div>
        <div class="flex items-center mb-6 border-b border-green-900/50 pb-2">
          <.icon name="hero-document-text" class="w-5 h-5 mr-3 text-green-500" />
          <h2 class="text-lg font-bold text-green-500 tracking-widest uppercase">GHI CHÚ CẬP NHẬT // V1.1.0</h2>
          <span class="ml-auto bg-green-500 text-black px-2 py-0.5 text-[10px] font-bold tracking-widest">MỚI NHẤT</span>
        </div>

        <div class="space-y-4 text-xs sm:text-sm font-mono">
          <div class="border-l-2 border-green-600 pl-4">
            <h4 class="text-green-400 font-bold tracking-widest uppercase mb-2">> COMMANDER TELEMETRY (NATIVE ELIXIR)</h4>
            <ul class="space-y-1 text-green-600">
              <li>• Chuyển đổi hoàn toàn hệ thống Telemetry từ C++ OmniMedia Watchdog sang Elixir GenServer gốc</li>
              <li>• Gửi trạng thái phần cứng (CPU, RAM, Temp, Disk) lên Commander Central qua OsmAnd protocol</li>
              <li>• Cấu trúc JSON lồng chuẩn Traccar (device_id, location.coords) — khắc phục lỗi HTTP 400</li>
              <li>• Bổ sung metric <span class="text-green-400">totalCameras</span> tự động đếm số Camera đang kết nối trên NVR</li>
              <li>• Cơ chế Reconnect tức thì khi lưu cấu hình mới (hủy timer cũ, đồng bộ ngay lập tức)</li>
            </ul>
          </div>

          <div class="border-l-2 border-green-600 pl-4">
            <h4 class="text-green-400 font-bold tracking-widest uppercase mb-2">> RTMP STREAM RELAY (OMNIMEDIA UPLINK)</h4>
            <ul class="space-y-1 text-green-600">
              <li>• Đẩy tự động luồng Camera IP lên máy chủ trung tâm qua RTMP (rtmp://server/live/device_id)</li>
              <li>• FFmpeg Zero-Transcode (-c:v copy) — tiêu thụ CPU cực thấp</li>
              <li>• Tab cấu hình RTMP RELAY riêng biệt tại <span class="text-green-400">/commander-sync/rtmp</span></li>
              <li>• Bảng liệt kê Camera với trạng thái Online/Offline và RTMP Target URL tương ứng</li>
              <li>• Tự động khôi phục kết nối khi FFmpeg bị ngắt</li>
            </ul>
          </div>

          <div class="border-l-2 border-green-600 pl-4">
            <h4 class="text-green-400 font-bold tracking-widest uppercase mb-2">> GIAO DIỆN & TRẢI NGHIỆM</h4>
            <ul class="space-y-1 text-green-600">
              <li>• Thanh điều hướng Sidebar mặc định mở rộng (expanded)</li>
              <li>• Hệ thống 3 Tab trên Commander Sync: Config / RTMP Relay / Logs</li>
              <li>• Terminal Log realtime hiển thị trạng thái đồng bộ và đẩy luồng</li>
              <li>• Phân loại thiết bị mặc định: <span class="text-green-400">OmniSense NVR</span> (không còn OmniMedia)</li>
            </ul>
          </div>
        </div>
      </div>
      </div>

      <%!-- Hardware Tab --%>
      <div :if={@live_action == :hardware}>
      <div class="flex items-center text-green-500 mb-6 border-b border-green-500/50 pb-2">
        <.icon name="hero-cpu-chip-solid" class="w-6 h-6 mr-3" />
        <h2 class="text-xl font-bold tracking-widest uppercase">CHẨN ĐOÁN PHẦN CỨNG</h2>
      </div>

      <%!-- OS & Platform --%>
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-8 mb-8">
        <div class="bg-black border border-green-800 p-6 relative group hover:border-green-500 transition-colors shadow-[0_0_15px_rgba(34,197,94,0.05)]">
          <div class="absolute top-0 left-0 w-3 h-3 border-t-2 border-l-2 border-green-500"></div>
          <div class="absolute bottom-0 right-0 w-3 h-3 border-b-2 border-r-2 border-green-500"></div>
          <h3 class="text-lg font-bold text-green-500 mb-6 tracking-widest uppercase border-b border-green-900/50 pb-2">
            > HỆ ĐIỀU HÀNH
          </h3>
          <dl class="space-y-3 text-xs sm:text-sm text-green-400 font-mono tracking-wide">
            <div class="flex justify-between items-center border-b border-green-900/30 pb-2">
              <dt class="text-green-700 font-bold">TÊN_HĐH</dt>
              <dd class="text-right uppercase truncate max-w-[60%]">{@hwinfo["os"]["name"]}</dd>
            </div>
            <div class="flex justify-between items-center border-b border-green-900/30 pb-2">
              <dt class="text-green-700 font-bold">PHIÊN BẢN</dt>
              <dd class="text-right uppercase truncate max-w-[60%]">{@hwinfo["os"]["version"]}</dd>
            </div>
            <div class="flex justify-between items-center border-b border-green-900/30 pb-2">
              <dt class="text-green-700 font-bold">KERNEL</dt>
              <dd class="text-right truncate max-w-[60%]" title={@hwinfo["os"]["kernel"]}>
                {@hwinfo["os"]["kernel"]}
              </dd>
            </div>
            <div class="flex justify-between items-center border-b border-green-900/30 pb-2">
              <dt class="text-green-700 font-bold">KIẾN TRÚC</dt>
              <dd class="text-right uppercase">{@hwinfo["os"]["architecture"]}</dd>
            </div>
          </dl>
        </div>

        <div class="bg-black border border-green-800 p-6 relative group hover:border-green-500 transition-colors shadow-[0_0_15px_rgba(34,197,94,0.05)]">
          <div class="absolute top-0 right-0 w-3 h-3 border-t-2 border-r-2 border-green-500"></div>
          <div class="absolute bottom-0 left-0 w-3 h-3 border-b-2 border-l-2 border-green-500"></div>
          <h3 class="text-lg font-bold text-green-500 mb-6 tracking-widest uppercase border-b border-green-900/50 pb-2">
            > BO MẠCH CHỦ
          </h3>
          <dl class="space-y-3 text-xs sm:text-sm text-green-400 font-mono tracking-wide">
            <div class="flex justify-between items-center border-b border-green-900/30 pb-2">
              <dt class="text-green-700 font-bold">NHÀ SẢN XUẤT</dt>
              <dd class="text-right uppercase truncate max-w-[60%]">{@hwinfo["mainboard"]["vendor"] || "KHÔNG RÕ"}</dd>
            </div>
            <div class="flex justify-between items-center border-b border-green-900/30 pb-2">
              <dt class="text-green-700 font-bold">MODEL</dt>
              <dd class="text-right uppercase truncate max-w-[60%]">{@hwinfo["mainboard"]["name"] || "KHÔNG RÕ"}</dd>
            </div>
            <div class="flex justify-between items-center border-b border-green-900/30 pb-2">
              <dt class="text-green-700 font-bold">REVISION</dt>
              <dd class="text-right uppercase truncate max-w-[60%]">{@hwinfo["mainboard"]["version"] || "KHÔNG RÕ"}</dd>
            </div>
            <div class="flex justify-between items-center border-b border-green-900/30 pb-2">
              <dt class="text-green-700 font-bold">SERIAL</dt>
              <dd class="text-right uppercase truncate max-w-[60%]">{@hwinfo["mainboard"]["serial"] || "KHÔNG RÕ"}</dd>
            </div>
          </dl>
        </div>
      </div>

      <%!-- CPU & GPU --%>
      <div class="grid grid-cols-1 xl:grid-cols-2 gap-8 mb-8">
        <%!-- CPU --%>
        <div class="bg-black border border-green-800 p-6 relative shadow-lg h-full flex flex-col group hover:border-green-500 transition-colors shadow-[0_0_15px_rgba(34,197,94,0.05)]">
          <div class="absolute top-0 left-0 w-3 h-3 border-t-2 border-l-2 border-green-500"></div>
          <h3 class="text-lg font-bold text-green-500 mb-6 tracking-widest uppercase flex items-center border-b border-green-900/50 pb-2">
            <.icon name="hero-cpu-chip" class="w-5 h-5 mr-3" /> [ BỘ XỬ LÝ ]
          </h3>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 flex-grow">
            <div
              :for={cpu <- @hwinfo["cpu"]}
              class="border border-green-900/60 p-4 bg-green-900/5 relative hover:bg-green-900/20 transition-colors"
            >
              <div class="absolute top-0 right-0 p-1 text-[10px] text-green-700 font-bold border-b border-l border-green-900/60 bg-black">CHIP_{cpu["socket_id"] || Enum.find_index(@hwinfo["cpu"], &(&1 == cpu))}</div>
              <p class="text-green-400 font-bold text-[13px] sm:text-sm truncate uppercase mb-1 pr-12" title={cpu["model"]}>{cpu["model"]}</p>
              <p class="text-[10px] text-green-600 mb-4 tracking-widest uppercase">{cpu["vendor"]}</p>
              <div class="grid grid-cols-2 gap-y-2 text-xs text-green-500 font-mono tracking-wide">
                <div class="text-green-700 font-bold">NHÂN VẬT LÝ:</div>
                <div class="text-right">{cpu["cores_physical"]}</div>
                <div class="text-green-700 font-bold">NHÂN LOGIC:</div>
                <div class="text-right">{cpu["cores_logical"]}</div>
                <div class="text-green-700 font-bold">TẦN SỐ TỐI ĐA:</div>
                <div class="text-right">{cpu["max_clock_mhz"]} MHz</div>
                <div class="text-green-700 font-bold">L3_CACHE:</div>
                <div class="text-right">{round(cpu["cache_size_bytes"] / 1_048_576)} MB</div>
              </div>
            </div>
          </div>
        </div>

        <%!-- GPU --%>
        <div
          :if={length(@hwinfo["gpu"] || []) > 0}
          class="bg-black border border-green-800 p-6 relative shadow-lg h-full flex flex-col group hover:border-green-500 transition-colors shadow-[0_0_15px_rgba(34,197,94,0.05)]"
        >
          <div class="absolute top-0 right-0 w-3 h-3 border-t-2 border-r-2 border-green-500"></div>
          <h3 class="text-lg font-bold text-green-500 mb-6 tracking-widest uppercase flex items-center border-b border-green-900/50 pb-2">
            <.icon name="hero-bolt" class="w-5 h-5 mr-3" /> [ CARD ĐỒ HỌA ]
          </h3>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 flex-grow">
            <div
              :for={gpu <- @hwinfo["gpu"]}
              class="border border-green-900/60 p-4 bg-green-900/5 relative hover:bg-green-900/20 transition-colors"
            >
              <p class="text-green-400 font-bold text-[13px] sm:text-sm truncate uppercase mb-1" title={gpu["name"]}>{gpu["name"]}</p>
              <p class="text-[10px] text-green-600 mb-4 tracking-widest uppercase">{gpu["vendor"]}</p>
              <div class="grid grid-cols-2 gap-y-2 text-xs text-green-500 font-mono tracking-wide">
                <div class="text-green-700 font-bold">VRAM:</div>
                <div class="text-right">
                  {Float.round(gpu["memory_bytes"] / 1_073_741_824, 2)} GB
                </div>
                <div class="text-green-700">DRIVER:</div>
                <div class="text-right">{gpu["driver_version"] || "N/A"}</div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- System Memory & Storage --%>
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <%!-- RAM --%>
        <div class="bg-black border border-green-800 p-5 relative h-full group hover:border-green-500 transition-colors">
          <div class="absolute bottom-0 left-0 w-2 h-2 border-b border-l border-green-500"></div>
          <h3 class="text-md font-bold text-green-500 mb-4 tracking-wider uppercase">
            > BỘ NHỚ RAM
          </h3>
          <div class="space-y-2">
            <div
              :for={ram <- @hwinfo["ram"]}
              class="border border-green-900/50 p-2 bg-green-900/5 flex justify-between items-center"
            >
              <div>
                <p class="text-green-400 text-xs font-bold uppercase">{ram["vendor"]} {ram["model"]}</p>
                <p class="text-green-700 text-[10px] mt-1">
                  TẦN SỐ: {if ram["frequency_hz"] && ram["frequency_hz"] > 0, do: "#{div(ram["frequency_hz"], 1_000_000)} MHz", else: "KHÔNG RÕ"}
                </p>
              </div>
              <div class="text-green-500 font-bold text-sm">
                [ {round(ram["total_bytes"] / 1_073_741_824)} GB ]
              </div>
            </div>
          </div>
        </div>

        <%!-- Disks --%>
        <div class="bg-black border border-green-800 p-5 relative h-full group hover:border-green-500 transition-colors">
          <div class="absolute bottom-0 right-0 w-2 h-2 border-b border-r border-green-500"></div>
          <h3 class="text-md font-bold text-green-500 mb-4 tracking-wider uppercase">
            > Ổ LƯU TRỮ
          </h3>
          <div class="space-y-2">
            <div
              :for={disk <- @hwinfo["disk"]}
              class="border border-green-900/50 p-2 bg-green-900/5 flex justify-between items-center"
            >
              <div>
                <p class="text-green-400 text-xs font-bold uppercase truncate max-w-[200px]" title={disk["model"]}>
                  {disk["model"] || "DRIVE"}
                </p>
                <p class="text-green-700 text-[10px] mt-1">{disk["vendor"] || "UNKNOWN_VNDR"}</p>
              </div>
              <div class="text-green-500 font-bold text-sm">
                [ {Float.round(disk["size_bytes"] / 1_073_741_824, 1)} GB ]
              </div>
            </div>
            <div :if={length(@hwinfo["disk"] || []) == 0} class="text-green-800 text-xs uppercase text-center mt-4">
              -- KHÔNG TÌM THẤY Ổ LƯU TRỮ --
            </div>
          </div>
        </div>
      </div>
      </div>
    </div>
    """
  end
end
