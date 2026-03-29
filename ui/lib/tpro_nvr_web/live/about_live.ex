defmodule TProNVRWeb.AboutLive do
  use TProNVRWeb, :live_view

  def mount(_params, _session, socket) do
    # Fetch cached hardware info from GenServer
    hwinfo = TProNVR.HardwareInfo.get_info()

    {:ok, assign(socket, hwinfo: hwinfo, page_title: "About OmniSense")}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 font-mono">
      <%!-- Military Header --%>
      <div class="bg-black border-2 border-green-600 p-6 relative overflow-hidden mb-8 shadow-[0_0_15px_rgba(0,128,0,0.3)]">
        <div class="absolute inset-x-0 top-0 h-1 bg-gradient-to-r from-transparent via-green-500 to-transparent opacity-50"></div>
        <div class="absolute top-0 right-0 p-2 text-green-700 text-xs">SYS_STATUS: ONLINE</div>
        <div class="flex items-start space-x-6">
          <div class="border border-green-500 p-4 bg-green-900/20 shadow-[0_0_10px_rgba(34,197,94,0.2)]">
            <.icon name="hero-server-stack-solid" class="w-12 h-12 text-green-500 animate-pulse" />
          </div>
          <div class="flex-1">
            <h1 class="text-3xl font-bold text-green-500 tracking-widest uppercase mb-1">
              [ OmniSense AI NVR ]
            </h1>
            <div class="h-px bg-green-500/30 w-full mb-3 hidden sm:block"></div>
            <p class="text-green-400 text-xs tracking-wider mb-4">
              BUILD/VERSION // {Application.spec(:tpro_nvr, :vsn)}
            </p>
            <p class="text-green-600 text-sm leading-relaxed max-w-4xl border-l-2 border-green-800 pl-4">
              HARDWARE-AGNOSTIC NETWORK VIDEO RECORDER INTEGRATED WITH REAL-TIME AI COMPUTER VISION PIPELINES.
              DEPLOYED ON DISTRIBUTED ELIXIR ARCHITECTURE FOR MASSIVE SCALABILITY.
            </p>
          </div>
        </div>
      </div>

      <div class="flex items-center text-green-500 mb-6 border-b border-green-500/50 pb-2">
        <.icon name="hero-cpu-chip-solid" class="w-6 h-6 mr-3" />
        <h2 class="text-xl font-bold tracking-widest uppercase">HARDWARE_DIAGNOSTICS</h2>
      </div>

      <%!-- OS & Platform --%>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
        <div class="bg-black border border-green-800 p-5 relative group hover:border-green-500 transition-colors">
          <div class="absolute top-0 left-0 w-2 h-2 border-t border-l border-green-500"></div>
          <div class="absolute bottom-0 right-0 w-2 h-2 border-b border-r border-green-500"></div>
          <h3 class="text-md font-bold text-green-500 mb-4 tracking-wider uppercase">
            > SYS.OS.INFO
          </h3>
          <dl class="space-y-2 text-sm text-green-400">
            <div class="grid grid-cols-3 border-b border-green-900/50 pb-1">
              <dt class="text-green-700">OS_NAME</dt>
              <dd class="col-span-2 text-right uppercase">{@hwinfo["os"]["name"]}</dd>
            </div>
            <div class="grid grid-cols-3 border-b border-green-900/50 pb-1">
              <dt class="text-green-700">RELEASE</dt>
              <dd class="col-span-2 text-right uppercase">{@hwinfo["os"]["version"]}</dd>
            </div>
            <div class="grid grid-cols-3 border-b border-green-900/50 pb-1">
              <dt class="text-green-700">KERNEL</dt>
              <dd class="col-span-2 text-right truncate" title={@hwinfo["os"]["kernel"]}>
                {@hwinfo["os"]["kernel"]}
              </dd>
            </div>
            <div class="grid grid-cols-3 border-b border-green-900/50 pb-1">
              <dt class="text-green-700">ARCH</dt>
              <dd class="col-span-2 text-right uppercase">{@hwinfo["os"]["architecture"]}</dd>
            </div>
          </dl>
        </div>

        <div class="bg-black border border-green-800 p-5 relative group hover:border-green-500 transition-colors">
          <div class="absolute top-0 right-0 w-2 h-2 border-t border-r border-green-500"></div>
          <div class="absolute bottom-0 left-0 w-2 h-2 border-b border-l border-green-500"></div>
          <h3 class="text-md font-bold text-green-500 mb-4 tracking-wider uppercase">
            > SYS.MAINBOARD.INFO
          </h3>
          <dl class="space-y-2 text-sm text-green-400">
            <div class="grid grid-cols-3 border-b border-green-900/50 pb-1">
              <dt class="text-green-700">VENDOR</dt>
              <dd class="col-span-2 text-right uppercase truncate">{@hwinfo["mainboard"]["vendor"] || "UNKNOWN"}</dd>
            </div>
            <div class="grid grid-cols-3 border-b border-green-900/50 pb-1">
              <dt class="text-green-700">MODEL</dt>
              <dd class="col-span-2 text-right uppercase truncate">{@hwinfo["mainboard"]["name"] || "UNKNOWN"}</dd>
            </div>
            <div class="grid grid-cols-3 border-b border-green-900/50 pb-1">
              <dt class="text-green-700">REVISION</dt>
              <dd class="col-span-2 text-right uppercase truncate">{@hwinfo["mainboard"]["version"] || "UNKNOWN"}</dd>
            </div>
            <div class="grid grid-cols-3 border-b border-green-900/50 pb-1">
              <dt class="text-green-700">SERIAL</dt>
              <dd class="col-span-2 text-right uppercase">{@hwinfo["mainboard"]["serial"] || "UNKNOWN"}</dd>
            </div>
          </dl>
        </div>
      </div>

      <%!-- CPU & GPU --%>
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        <%!-- CPU --%>
        <div class="bg-black border border-green-800 p-5 relative shadow-lg h-full flex flex-col group hover:border-green-500 transition-colors">
          <div class="absolute top-0 left-0 w-2 h-2 border-t border-l border-green-500"></div>
          <h3 class="text-md font-bold text-green-500 mb-4 tracking-wider uppercase flex items-center">
            <.icon name="hero-cpu-chip" class="w-4 h-4 mr-2" /> [ PROCESSORS ]
          </h3>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 flex-grow">
            <div
              :for={cpu <- @hwinfo["cpu"]}
              class="border border-green-900/60 p-3 bg-green-900/5 relative"
            >
              <div class="absolute top-0 right-0 p-1 text-[10px] text-green-700">CHIP_{cpu["socket_id"] || Enum.find_index(@hwinfo["cpu"], &(&1 == cpu))}</div>
              <p class="text-green-400 font-bold text-sm truncate uppercase mb-1" title={cpu["model"]}>{cpu["model"]}</p>
              <p class="text-[10px] text-green-600 mb-3 tracking-widest">{cpu["vendor"]}</p>
              <div class="grid grid-cols-2 gap-y-1 text-xs text-green-500">
                <div class="text-green-700">PHYS_CORES:</div>
                <div class="text-right">{cpu["cores_physical"]}</div>
                <div class="text-green-700">LOGIC_CORES:</div>
                <div class="text-right">{cpu["cores_logical"]}</div>
                <div class="text-green-700">MAX_FREQ:</div>
                <div class="text-right">{cpu["max_clock_mhz"]} MHz</div>
                <div class="text-green-700">L3_CACHE:</div>
                <div class="text-right">{round(cpu["cache_size_bytes"] / 1_048_576)} MB</div>
              </div>
            </div>
          </div>
        </div>

        <%!-- GPU --%>
        <div
          :if={length(@hwinfo["gpu"] || []) > 0}
          class="bg-black border border-green-800 p-5 relative shadow-lg h-full flex flex-col group hover:border-green-500 transition-colors"
        >
          <div class="absolute top-0 right-0 w-2 h-2 border-t border-r border-green-500"></div>
          <h3 class="text-md font-bold text-green-500 mb-4 tracking-wider uppercase flex items-center">
            <.icon name="hero-bolt" class="w-4 h-4 mr-2" /> [ ACCELERATORS ]
          </h3>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 flex-grow">
            <div
              :for={gpu <- @hwinfo["gpu"]}
              class="border border-green-900/60 p-3 bg-green-900/5 relative"
            >
              <p class="text-green-400 font-bold text-sm truncate uppercase mb-1" title={gpu["name"]}>{gpu["name"]}</p>
              <p class="text-[10px] text-green-600 mb-3 tracking-widest">{gpu["vendor"]}</p>
              <div class="grid grid-cols-2 gap-y-1 text-xs text-green-500">
                <div class="text-green-700">VRAM_TOTAL:</div>
                <div class="text-right">
                  {Float.round(gpu["memory_bytes"] / 1_073_741_824, 2)} GB
                </div>
                <div class="text-green-700">DRIVER_VER:</div>
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
            > SYS.MEM.INFO
          </h3>
          <div class="space-y-2">
            <div
              :for={ram <- @hwinfo["ram"]}
              class="border border-green-900/50 p-2 bg-green-900/5 flex justify-between items-center"
            >
              <div>
                <p class="text-green-400 text-xs font-bold uppercase">{ram["vendor"]} {ram["model"]}</p>
                <p class="text-green-700 text-[10px] mt-1">
                  FREQ: {if ram["frequency_hz"] && ram["frequency_hz"] > 0, do: "#{div(ram["frequency_hz"], 1_000_000)} MHz", else: "UNKNOWN"}
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
            > SYS.STORAGE.INFO
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
              -- NO STORAGE VISIBLE --
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
