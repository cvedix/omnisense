defmodule TProNVRWeb.AboutLive do
  use TProNVRWeb, :live_view

  def mount(_params, _session, socket) do
    # Fetch cached hardware info from GenServer
    hwinfo = TProNVR.HardwareInfo.get_info()

    {:ok, assign(socket, hwinfo: hwinfo, page_title: "About OmniSense")}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8">
      <%!-- Header Section --%>
      <div class="bg-black border border-green-700 rounded-lg p-6 shadow-xl relative overflow-hidden">
        <div class="absolute top-0 right-0 -mt-4 -mr-4 w-24 h-24 bg-green-500 rounded-full blur-2xl opacity-20">
        </div>
        <div class="flex items-center space-x-4">
          <div class="bg-green-900/50 p-3 rounded-xl border border-green-700/50">
            <.icon name="hero-server-stack-solid" class="w-10 h-10 text-green-400" />
          </div>
          <div>
            <h1 class="text-2xl font-bold text-white tracking-tight">OmniSense AI NVR</h1>
            <p class="text-green-400 font-mono text-sm mt-1">
              Version {Application.spec(:tpro_nvr, :vsn)}
            </p>
          </div>
        </div>
        <div class="mt-6 pt-6 border-t border-green-800/50">
          <p class="text-gray-300 leading-relaxed max-w-3xl">
            OmniSense is an advanced, hardware-agnostic Network Video Recorder (NVR) integrated with real-time AI computer vision pipelines.
            Built on top of the Membrane Framework and distributed Elixir architecture, it provides massive scalability from low-power Edge devices
            to high-performance unified VMS datacenters.
          </p>
        </div>
      </div>

      <h2 class="text-xl font-bold text-white mb-4 flex items-center">
        <.icon name="hero-cpu-chip-solid" class="w-6 h-6 mr-2 text-green-500" /> Hardware Information
      </h2>

      <%!-- OS & Platform --%>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div class="bg-black border border-green-700/50 rounded-lg p-5 shadow-lg">
          <h3 class="text-lg font-semibold text-green-400 mb-4 border-b border-green-800 pb-2">
            Operating System
          </h3>
          <dl class="space-y-3 text-sm">
            <div class="flex justify-between">
              <dt class="text-gray-400">Name</dt>
              <dd class="text-white font-medium">{@hwinfo["os"]["name"]}</dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-gray-400">Version</dt>
              <dd class="text-white font-medium">{@hwinfo["os"]["version"]}</dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-gray-400">Kernel</dt>
              <dd
                class="text-white font-medium truncate max-w-[200px]"
                title={@hwinfo["os"]["kernel"]}
              >
                {@hwinfo["os"]["kernel"]}
              </dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-gray-400">Architecture</dt>
              <dd class="text-white font-medium">{@hwinfo["os"]["architecture"]}</dd>
            </div>
          </dl>
        </div>

        <div class="bg-black border border-green-700/50 rounded-lg p-5 shadow-lg">
          <h3 class="text-lg font-semibold text-green-400 mb-4 border-b border-green-800 pb-2">
            Mainboard
          </h3>
          <dl class="space-y-3 text-sm">
            <div class="flex justify-between">
              <dt class="text-gray-400">Vendor</dt>
              <dd class="text-white font-medium truncate max-w-[180px]">
                {@hwinfo["mainboard"]["vendor"] || "Unknown"}
              </dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-gray-400">Model</dt>
              <dd class="text-white font-medium truncate max-w-[180px]">
                {@hwinfo["mainboard"]["name"] || "Unknown"}
              </dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-gray-400">Version</dt>
              <dd class="text-white font-medium truncate">
                {@hwinfo["mainboard"]["version"] || "Unknown"}
              </dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-gray-400">Serial</dt>
              <dd class="text-white font-mono text-xs mt-1">
                {@hwinfo["mainboard"]["serial"] || "Unknown"}
              </dd>
            </div>
          </dl>
        </div>
      </div>

      <%!-- CPU & GPU --%>
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <%!-- CPU --%>
        <div class="bg-black border border-green-700/50 rounded-lg p-5 shadow-lg h-full flex flex-col">
          <h3 class="text-lg font-semibold text-green-400 mb-4 border-b border-green-800 pb-2 flex items-center">
            <.icon name="hero-cpu-chip" class="w-5 h-5 mr-2" /> Processors
          </h3>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 flex-grow">
            <div
              :for={cpu <- @hwinfo["cpu"]}
              class="bg-green-900/20 rounded p-4 border border-green-800/30"
            >
              <p class="text-white font-semibold truncate mb-1" title={cpu["model"]}>{cpu["model"]}</p>
              <p class="text-xs text-green-500 mb-3">{cpu["vendor"]}</p>
              <div class="grid grid-cols-2 gap-2 text-xs">
                <div class="text-gray-400">Physical Cores:</div>
                <div class="text-white text-right">{cpu["cores_physical"]}</div>
                <div class="text-gray-400">Logical Cores:</div>
                <div class="text-white text-right">{cpu["cores_logical"]}</div>
                <div class="text-gray-400">Max Clock:</div>
                <div class="text-white text-right">{cpu["max_clock_mhz"]} MHz</div>
                <div class="text-gray-400">L3 Cache:</div>
                <div class="text-white text-right">{round(cpu["cache_size_bytes"] / 1_048_576)} MB</div>
              </div>
            </div>
          </div>
        </div>

        <%!-- GPU --%>
        <div
          :if={length(@hwinfo["gpu"] || []) > 0}
          class="bg-black border border-green-700/50 rounded-lg p-5 shadow-lg h-full flex flex-col"
        >
          <h3 class="text-lg font-semibold text-green-400 mb-4 border-b border-green-800 pb-2 flex items-center">
            <.icon name="hero-bolt" class="w-5 h-5 mr-2" /> Graphics & Accelerators
          </h3>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 flex-grow">
            <div
              :for={gpu <- @hwinfo["gpu"]}
              class="bg-green-900/20 rounded p-4 border border-green-800/30"
            >
              <p class="text-white font-semibold truncate mb-1" title={gpu["name"]}>{gpu["name"]}</p>
              <p class="text-xs text-green-500 mb-3">{gpu["vendor"]}</p>
              <div class="grid grid-cols-2 gap-2 text-xs">
                <div class="text-gray-400">VRAM:</div>
                <div class="text-white text-right">
                  {Float.round(gpu["memory_bytes"] / 1_073_741_824, 2)} GB
                </div>
                <div class="text-gray-400">Driver:</div>
                <div class="text-white text-right">{gpu["driver_version"] || "N/A"}</div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- System Memory & Storage --%>
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <%!-- RAM --%>
        <div class="bg-black border border-green-700/50 rounded-lg p-5 shadow-lg h-full">
          <h3 class="text-lg font-semibold text-green-400 mb-4 border-b border-green-800 pb-2">
            System Memory (RAM)
          </h3>
          <div class="space-y-3">
            <div
              :for={ram <- @hwinfo["ram"]}
              class="bg-green-900/20 rounded p-3 border border-green-800/30 flex justify-between items-center"
            >
              <div>
                <p class="text-white text-sm font-medium">{ram["vendor"]} {ram["model"]}</p>
                <p class="text-gray-400 text-xs mt-1">
                  {ram["frequency_hz"] && div(ram["frequency_hz"], 1_000_000)} MHz
                </p>
              </div>
              <div class="text-green-400 font-mono">
                {round(ram["total_bytes"] / 1_073_741_824)} GB
              </div>
            </div>
          </div>
        </div>

        <%!-- Disks --%>
        <div class="bg-black border border-green-700/50 rounded-lg p-5 shadow-lg h-full">
          <h3 class="text-lg font-semibold text-green-400 mb-4 border-b border-green-800 pb-2">
            Storage Devices
          </h3>
          <div class="space-y-3">
            <div
              :for={disk <- @hwinfo["disk"]}
              class="bg-green-900/20 rounded p-3 border border-green-800/30 flex justify-between items-center"
            >
              <div>
                <p class="text-white text-sm font-medium truncate max-w-[200px]" title={disk["model"]}>
                  {disk["model"] || "Disk Drive"}
                </p>
                <p class="text-gray-400 text-xs mt-1">{disk["vendor"] || "Unknown vendor"}</p>
              </div>
              <div class="text-green-400 font-mono">
                {Float.round(disk["size_bytes"] / 1_073_741_824, 1)} GB
              </div>
            </div>
            <div :if={length(@hwinfo["disk"] || []) == 0} class="text-gray-500 text-sm italic">
              No disk details available.
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
