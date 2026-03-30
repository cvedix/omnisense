defmodule TProNVRWeb.LocalStorageLive do
  @moduledoc """
  LiveView for managing local/physical storage devices attached to the system.
  Provides disk listing, partition details, usage stats, and format capability.
  """
  use TProNVRWeb, :live_view

  require Logger

  @refresh_interval 10_000

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Process.send_after(self(), :refresh, @refresh_interval)
    end

    disks = list_block_devices()

    {:ok,
     assign(socket,
       disks: disks,
       active_tab: "disks",
       format_target: nil,
       format_confirm: false,
       format_status: nil,
       format_error: nil,
       formatting: false
     )}
  end

  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, assign(socket, disks: list_block_devices())}
  end

  def handle_info({:format_result, :ok, device_name}, socket) do
    {:noreply,
     socket
     |> assign(
       formatting: false,
       format_status: "Format thành công thiết bị #{device_name}!",
       format_error: nil,
       format_target: nil,
       format_confirm: false,
       disks: list_block_devices()
     )}
  end

  def handle_info({:format_result, :error, reason}, socket) do
    {:noreply,
     assign(socket,
       formatting: false,
       format_error: reason,
       format_status: nil
     )}
  end

  def handle_event("show_format", %{"device" => device}, socket) do
    {:noreply, assign(socket, format_target: device, format_confirm: false, format_status: nil, format_error: nil)}
  end

  def handle_event("cancel_format", _params, socket) do
    {:noreply, assign(socket, format_target: nil, format_confirm: false)}
  end

  def handle_event("confirm_format", _params, socket) do
    {:noreply, assign(socket, format_confirm: true)}
  end

  def handle_event("execute_format", %{"device" => device}, socket) do
    pid = self()

    Task.start(fn ->
      result = do_format(device)

      case result do
        :ok -> send(pid, {:format_result, :ok, device})
        {:error, reason} -> send(pid, {:format_result, :error, reason})
      end
    end)

    {:noreply, assign(socket, formatting: true, format_status: nil, format_error: nil)}
  end

  def handle_event("dismiss_status", _params, socket) do
    {:noreply, assign(socket, format_status: nil, format_error: nil)}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: tab)}
  end

  # --- Storage detection ---

  defp list_block_devices do
    all_devices = TProNVR.Devices.list()

    case System.cmd("lsblk", ["-J", "-b", "-o", "NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,MODEL,SERIAL,TRAN,RM,RO,HOTPLUG,STATE,VENDOR,REV"], stderr_to_stdout: true) do
      {json, 0} ->
        case Jason.decode(json) do
          {:ok, %{"blockdevices" => devices}} ->
            disks = Enum.filter(devices, fn d -> d["type"] == "disk" end)

            # Collect all mountpoints across all partitions
            all_mountpoints =
              disks
              |> Enum.flat_map(fn d -> d["children"] || [] end)
              |> Enum.map(fn p -> p["mountpoint"] end)
              |> Enum.filter(& &1)
              |> Enum.reject(& &1 == "")

            # For each device, find the best (longest) matching mountpoint
            device_to_mount =
              all_devices
              |> Enum.reduce(%{}, fn dev, acc ->
                addr = get_in(dev, [Access.key(:storage_config), Access.key(:address)])
                if addr do
                  best = Enum.filter(all_mountpoints, fn mp -> String.starts_with?(addr, mp) end)
                         |> Enum.max_by(&String.length/1, fn -> nil end)
                  if best, do: Map.put(acc, dev.id, best), else: acc
                else
                  acc
                end
              end)

            Enum.map(disks, &enrich_disk(&1, all_devices, device_to_mount))

          _ ->
            []
        end

      _ ->
        []
    end
  end

  defp enrich_disk(disk, all_devices, device_to_mount) do
    children = disk["children"] || []

    partitions =
      Enum.map(children, fn part ->
        usage = get_usage("/dev/#{part["name"]}", part["mountpoint"])
        mountpoint = part["mountpoint"]

        # Only include devices whose best matching mount == this partition's mount
        linked_devices =
          if mountpoint && mountpoint != "" do
            all_devices
            |> Enum.filter(fn dev -> Map.get(device_to_mount, dev.id) == mountpoint end)
            |> Enum.map(fn dev ->
              %{
                id: dev.id,
                name: dev.name,
                state: dev.state,
                storage_address: dev.storage_config.address
              }
            end)
          else
            []
          end

        %{
          name: part["name"],
          size: format_bytes(part["size"]),
          size_raw: part["size"] || 0,
          fstype: part["fstype"] || "—",
          mountpoint: mountpoint || "—",
          used: usage[:used] || "—",
          available: usage[:available] || "—",
          percent: usage[:percent] || 0,
          type: part["type"] || "part",
          linked_devices: linked_devices
        }
      end)

    total_size = disk["size"] || 0
    total_linked = partitions |> Enum.flat_map(& &1.linked_devices) |> length()

    %{
      name: disk["name"],
      model: (disk["model"] || "Unknown") |> String.trim(),
      serial: disk["serial"] || "—",
      vendor: (disk["vendor"] || "") |> String.trim(),
      transport: disk["tran"] || "—",
      removable: disk["rm"] == true or disk["rm"] == 1,
      readonly: disk["ro"] == true or disk["ro"] == 1,
      size: format_bytes(total_size),
      size_raw: total_size,
      state: disk["state"] || "—",
      partitions: partitions,
      partition_count: length(partitions),
      linked_device_count: total_linked
    }
  end

  defp get_usage(device, mountpoint) do
    if mountpoint && mountpoint != "" do
      case System.cmd("df", ["-B1", mountpoint], stderr_to_stdout: true) do
        {output, 0} ->
          lines = String.split(output, "\n", trim: true)

          case lines do
            [_header | [data_line | _]] ->
              parts = String.split(data_line, ~r/\s+/, trim: true)

              case parts do
                [_fs, _total, used, avail, percent | _] ->
                  pct =
                    percent
                    |> String.replace("%", "")
                    |> String.to_integer()
                    |> min(100)

                  %{
                    used: format_bytes(String.to_integer(used)),
                    available: format_bytes(String.to_integer(avail)),
                    percent: pct
                  }

                _ ->
                  %{}
              end

            _ ->
              %{}
          end

        _ ->
          %{}
      end
    else
      # Try to get size from blockdev for unmounted partitions
      case System.cmd("blockdev", ["--getsize64", device], stderr_to_stdout: true) do
        {size_str, 0} ->
          size = size_str |> String.trim() |> String.to_integer()
          %{used: "—", available: format_bytes(size), percent: 0}

        _ ->
          %{}
      end
    end
  end

  defp do_format(device) do
    dev_path = "/dev/#{device}"

    Logger.warning("LocalStorage: Formatting #{dev_path} with ext4...")

    # Unmount first if mounted
    System.cmd("umount", [dev_path], stderr_to_stdout: true)

    case System.cmd("mkfs.ext4", ["-F", dev_path], stderr_to_stdout: true) do
      {_output, 0} ->
        Logger.info("LocalStorage: Format #{dev_path} completed successfully.")
        :ok

      {output, code} ->
        Logger.error("LocalStorage: Format #{dev_path} failed (exit #{code}): #{output}")
        {:error, "mkfs.ext4 failed (code #{code}): #{String.slice(output, 0, 200)}"}
    end
  end

  defp format_bytes(nil), do: "—"

  defp format_bytes(bytes) when is_binary(bytes) do
    case Integer.parse(bytes) do
      {n, _} -> format_bytes(n)
      :error -> bytes
    end
  end

  defp format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_000_000_000_000 -> "#{Float.round(bytes / 1_000_000_000_000, 1)} TB"
      bytes >= 1_000_000_000 -> "#{Float.round(bytes / 1_000_000_000, 1)} GB"
      bytes >= 1_000_000 -> "#{Float.round(bytes / 1_000_000, 1)} MB"
      bytes >= 1_000 -> "#{Float.round(bytes / 1_000, 1)} KB"
      true -> "#{bytes} B"
    end
  end

  # --- Render ---

  defp all_linked_devices(disks) do
    disks
    |> Enum.flat_map(fn disk ->
      disk.partitions
      |> Enum.flat_map(fn part ->
        Enum.map(part.linked_devices, fn dev ->
          Map.merge(dev, %{
            disk_name: disk.name,
            disk_model: disk.model,
            partition_name: part.name,
            partition_mountpoint: part.mountpoint,
            partition_size: part.size,
            partition_used: part.used,
            partition_percent: part.percent
          })
        end)
      end)
    end)
  end

  # --- Render ---

  def render(assigns) do
    assigns = assign(assigns, :device_mappings, all_linked_devices(assigns.disks))

    ~H"""
    <div class="p-4 md:p-6 bg-black font-mono text-green-500 h-full overflow-y-auto">
      <div class="max-w-7xl mx-auto pb-12">
        <!-- Header -->
        <div class="flex flex-col md:flex-row items-start md:items-center justify-between mb-4 border-b border-green-900/50 pb-4 gap-4">
          <h1 class="text-xl md:text-2xl font-bold tracking-widest uppercase flex items-center">
            <.icon name="hero-server-stack-solid" class="w-8 h-8 mr-3 text-green-500" />
            [ BỘ NHỚ VẬT LÝ ]
          </h1>
          <div class="text-[10px] md:text-xs tracking-widest uppercase text-green-700 whitespace-nowrap">
            STORAGE_SCAN: <span class="bg-green-500 text-black px-2 py-0.5 font-bold ml-1">{length(@disks)} THIẾT BỊ</span>
          </div>
        </div>

        <!-- Sub-Tabs -->
        <div class="flex border-b border-green-900/50 mb-8">
          <button phx-click="switch_tab" phx-value-tab="disks"
                  class={"px-5 py-2.5 text-[10px] md:text-xs font-bold tracking-widest uppercase transition-all flex items-center gap-2 border-b-2 " <> if(@active_tab == "disks", do: "border-green-400 text-green-400 bg-green-900/20", else: "border-transparent text-green-700 hover:text-green-500 hover:bg-green-900/10")}>
            <.icon name="hero-server-stack-solid" class="w-3.5 h-3.5" />
            Ổ ĐĨA & PHÂN VÙNG
          </button>
          <button phx-click="switch_tab" phx-value-tab="mapping"
                  class={"px-5 py-2.5 text-[10px] md:text-xs font-bold tracking-widest uppercase transition-all flex items-center gap-2 border-b-2 " <> if(@active_tab == "mapping", do: "border-green-400 text-green-400 bg-green-900/20", else: "border-transparent text-green-700 hover:text-green-500 hover:bg-green-900/10")}>
            <.icon name="hero-link-solid" class="w-3.5 h-3.5" />
            LIÊN KẾT THIẾT BỊ
            <span class={"ml-1 px-1.5 py-0.5 text-[9px] font-mono rounded-sm " <> if(@active_tab == "mapping", do: "bg-green-500 text-black", else: "bg-green-900/50 text-green-700")}>
              {length(@device_mappings)}
            </span>
          </button>
        </div>

        <!-- Success / Error Banners -->
        <div :if={@format_status} class="mb-6 p-4 border-l-4 border-green-500 bg-green-900/20 text-green-400 flex items-center justify-between">
          <span>> {@format_status}</span>
          <button phx-click="dismiss_status" class="text-green-700 hover:text-green-400 text-xs uppercase tracking-widest">ĐÓNG</button>
        </div>
        <div :if={@format_error} class="mb-6 p-4 border-l-4 border-red-500 bg-red-900/20 text-red-500 flex items-center justify-between">
          <span>> LỖI: {@format_error}</span>
          <button phx-click="dismiss_status" class="text-red-700 hover:text-red-400 text-xs uppercase tracking-widest">ĐÓNG</button>
        </div>

        <!-- ==================== TAB 1: Ổ ĐĨA & PHÂN VÙNG ==================== -->
        <div :if={@active_tab == "disks"}>
          <p class="text-[10px] md:text-xs text-green-600 mb-8 border-l-2 border-green-800 pl-4 hidden sm:block">
            Quản lý thiết bị lưu trữ vật lý (HDD, SSD, USB) được gắn trên hệ thống OmniSense NVR. Hỗ trợ xem thông tin chi tiết, dung lượng sử dụng, và format (xóa toàn bộ dữ liệu) từng phân vùng.
          </p>

          <div :if={Enum.empty?(@disks)} class="bg-black border border-green-800 p-8 text-center">
            <.icon name="hero-exclamation-triangle" class="w-12 h-12 mx-auto text-green-700 mb-4" />
            <p class="text-green-700 text-sm uppercase tracking-widest">Không phát hiện thiết bị lưu trữ nào trên hệ thống.</p>
            <p class="text-green-900 text-[10px] mt-2">Hãy kiểm tra kết nối phần cứng hoặc quyền truy cập hệ thống.</p>
          </div>

          <div :for={disk <- @disks} class="bg-black border border-green-800 p-4 md:p-6 relative group shadow-[0_0_15px_rgba(34,197,94,0.1)] mb-6">
            <div class="absolute top-0 left-0 w-3 h-3 border-t-2 border-l-2 border-green-500"></div>
            <div class="absolute bottom-0 right-0 w-3 h-3 border-b-2 border-r-2 border-green-500"></div>

            <!-- Disk Header -->
            <div class="flex flex-col md:flex-row md:items-center justify-between mb-6 border-b border-green-900/50 pb-4 gap-3">
              <div class="flex items-center gap-3">
                <div class={"p-2 border " <> if(disk.removable, do: "border-yellow-500/50 bg-yellow-900/10", else: "border-green-500/50 bg-green-900/10")}>
                  <.icon name={if disk.removable, do: "hero-arrow-top-right-on-square", else: "hero-server-stack-solid"} class={"w-6 h-6 " <> if(disk.removable, do: "text-yellow-500", else: "text-green-500")} />
                </div>
                <div>
                  <h3 class="text-base md:text-lg font-bold text-green-500 tracking-widest uppercase">
                    /dev/{disk.name}
                    <span :if={disk.removable} class="ml-2 bg-yellow-500 text-black px-1.5 py-0.5 text-[9px] font-bold tracking-widest">REMOVABLE</span>
                    <span :if={disk.readonly} class="ml-2 bg-red-500 text-black px-1.5 py-0.5 text-[9px] font-bold tracking-widest">READ-ONLY</span>
                  </h3>
                  <p class="text-[10px] text-green-700 tracking-widest uppercase mt-0.5">
                    {disk.vendor} {disk.model}
                    <span :if={disk.serial != "—"} class="ml-2 text-green-900">SN: {disk.serial}</span>
                  </p>
                </div>
              </div>
              <div class="flex items-center gap-4 text-[10px] md:text-xs tracking-widest uppercase">
                <span class="text-green-700">
                  TỔNG: <span class="text-green-500 font-bold">{disk.size}</span>
                </span>
                <span class="text-green-700">
                  BUS: <span class="text-green-500 font-bold uppercase">{disk.transport}</span>
                </span>
                <span class="text-green-700">
                  PHÂN VÙNG: <span class="text-green-500 font-bold">{disk.partition_count}</span>
                </span>
              </div>
            </div>

            <!-- Partition Table -->
            <div :if={disk.partition_count > 0} class="overflow-x-auto">
              <table class="w-full text-left">
                <thead>
                  <tr class="border-b border-green-900/50 text-[10px] uppercase tracking-widest text-green-700">
                    <th class="py-2 pr-4">PHÂN VÙNG</th>
                    <th class="py-2 pr-4">DUNG LƯỢNG</th>
                    <th class="py-2 pr-4">ĐỊNH DẠNG</th>
                    <th class="py-2 pr-4">MOUNT</th>
                    <th class="py-2 pr-4">ĐÃ DÙNG</th>
                    <th class="py-2 pr-4">CÒN TRỐNG</th>
                    <th class="py-2 pr-4 min-w-[160px]">SỬ DỤNG</th>
                    <th class="py-2 text-right">THAO TÁC</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={part <- disk.partitions} class="border-b border-green-900/20 text-xs">
                    <td class="py-3 pr-4 text-green-400 font-bold">/dev/{part.name}</td>
                    <td class="py-3 pr-4 text-green-500">{part.size}</td>
                    <td class="py-3 pr-4">
                      <span class={"px-1.5 py-0.5 text-[9px] font-bold tracking-widest " <> cond do
                        part.fstype in ["ext4", "xfs", "btrfs"] -> "bg-green-900/50 text-green-400 border border-green-800"
                        part.fstype in ["ntfs", "vfat", "fat32", "exfat"] -> "bg-blue-900/50 text-blue-400 border border-blue-800"
                        part.fstype == "swap" -> "bg-purple-900/50 text-purple-400 border border-purple-800"
                        true -> "bg-green-900/30 text-green-700 border border-green-900"
                      end}>
                        {part.fstype}
                      </span>
                    </td>
                    <td class="py-3 pr-4 text-green-600 text-[10px] font-mono">{part.mountpoint}</td>
                    <td class="py-3 pr-4 text-green-500">{part.used}</td>
                    <td class="py-3 pr-4 text-green-500">{part.available}</td>
                    <td class="py-3 pr-4">
                      <div :if={part.percent > 0} class="flex items-center gap-2">
                        <div class="flex-1 h-2 bg-green-900/30 border border-green-900/50 overflow-hidden">
                          <div
                            class={"h-full transition-all duration-500 " <> cond do
                              part.percent >= 90 -> "bg-red-500"
                              part.percent >= 70 -> "bg-yellow-500"
                              true -> "bg-green-500"
                            end}
                            style={"width: #{part.percent}%"}
                          ></div>
                        </div>
                        <span class={"text-[10px] font-bold tracking-widest min-w-[36px] text-right " <> cond do
                          part.percent >= 90 -> "text-red-500"
                          part.percent >= 70 -> "text-yellow-500"
                          true -> "text-green-500"
                        end}>
                          {part.percent}%
                        </span>
                      </div>
                      <span :if={part.percent == 0} class="text-green-900 text-[10px]">—</span>
                    </td>
                    <td class="py-3 text-right">
                      <button
                        :if={part.mountpoint == "—" or (part.mountpoint != "/" and not String.starts_with?(part.mountpoint, "/boot"))}
                        phx-click="show_format"
                        phx-value-device={part.name}
                        class="bg-red-900/30 border border-red-800 text-red-400 hover:bg-red-800 hover:text-red-200 px-3 py-1.5 text-[10px] font-bold tracking-widest uppercase transition-all"
                        disabled={@formatting}
                      >
                        <.icon name="hero-trash" class="w-3 h-3 inline mr-1" /> FORMAT
                      </button>
                      <span :if={part.mountpoint == "/" or String.starts_with?(part.mountpoint || "", "/boot")} class="text-green-900 text-[10px] uppercase tracking-widest">
                        HỆ THỐNG
                      </span>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <!-- No partitions -->
            <div :if={disk.partition_count == 0} class="text-center py-6 text-green-700 text-xs uppercase tracking-widest">
              Thiết bị không có phân vùng — có thể cần khởi tạo bảng phân vùng.
            </div>
          </div>
        </div>

        <!-- ==================== TAB 2: LIÊN KẾT THIẾT BỊ ==================== -->
        <div :if={@active_tab == "mapping"}>
          <p class="text-[10px] md:text-xs text-green-600 mb-8 border-l-2 border-green-800 pl-4 hidden sm:block">
            Danh sách Camera IP đang ghi hình trên hệ thống, liên kết với phân vùng ổ đĩa vật lý tương ứng dựa trên cấu hình đường dẫn lưu trữ (storage_config.address) của từng thiết bị.
          </p>

          <div :if={Enum.empty?(@device_mappings)} class="bg-black border border-green-800 p-8 text-center">
            <.icon name="hero-link" class="w-12 h-12 mx-auto text-green-700 mb-4" />
            <p class="text-green-700 text-sm uppercase tracking-widest">Chưa có Camera nào được liên kết với ổ đĩa vật lý.</p>
            <p class="text-green-900 text-[10px] mt-2">Hãy kiểm tra cấu hình lưu trữ (Storage Address) của các thiết bị trong mục Quản lý Thiết bị.</p>
          </div>

          <div :if={length(@device_mappings) > 0} class="bg-black border border-green-800 p-4 md:p-6 relative shadow-[0_0_15px_rgba(34,197,94,0.1)]">
            <div class="absolute top-0 left-0 w-3 h-3 border-t-2 border-l-2 border-green-500"></div>
            <div class="absolute bottom-0 right-0 w-3 h-3 border-b-2 border-r-2 border-green-500"></div>

            <h3 class="text-sm font-bold text-green-500 mb-4 tracking-widest uppercase flex items-center border-b border-green-900/50 pb-3">
              <.icon name="hero-link-solid" class="w-4 h-4 mr-2" />
              > CAMERA → Ổ ĐĨA VẬT LÝ
            </h3>

            <div class="overflow-x-auto">
              <table class="w-full text-left">
                <thead>
                  <tr class="border-b border-green-900/50 text-[10px] uppercase tracking-widest text-green-700">
                    <th class="py-2 pr-4">TRẠNG THÁI</th>
                    <th class="py-2 pr-4">TÊN CAMERA</th>
                    <th class="py-2 pr-4">ĐƯỜNG DẪN LƯU TRỮ</th>
                    <th class="py-2 pr-4">Ổ ĐĨA</th>
                    <th class="py-2 pr-4">PHÂN VÙNG</th>
                    <th class="py-2 pr-4">MOUNT</th>
                    <th class="py-2 pr-4">DUNG LƯỢNG</th>
                    <th class="py-2 pr-4 min-w-[140px]">ĐÃ DÙNG</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={m <- @device_mappings} class="border-b border-green-900/20 text-xs">
                    <td class="py-3 pr-4">
                      <span class={"flex items-center gap-1.5 text-[10px] font-bold tracking-widest " <> if(m.state != :stopped, do: "text-green-400", else: "text-red-500")}>
                        <span class={"w-2 h-2 rounded-full " <> if(m.state != :stopped, do: "bg-green-400 animate-pulse", else: "bg-red-500")}></span>
                        {if m.state != :stopped, do: "ONLINE", else: "OFFLINE"}
                      </span>
                    </td>
                    <td class="py-3 pr-4">
                      <.link href={~p"/devices/#{m.id}/details"} class="text-cyan-400 hover:text-cyan-300 font-bold tracking-wider">
                        {m.name}
                      </.link>
                    </td>
                    <td class="py-3 pr-4 text-green-600 text-[10px] font-mono">{m.storage_address}</td>
                    <td class="py-3 pr-4">
                      <span class="text-green-400 font-bold">/dev/{m.disk_name}</span>
                      <span class="text-green-800 text-[9px] ml-1">({m.disk_model})</span>
                    </td>
                    <td class="py-3 pr-4 text-green-500 font-mono text-[10px]">/dev/{m.partition_name}</td>
                    <td class="py-3 pr-4 text-green-600 text-[10px] font-mono">{m.partition_mountpoint}</td>
                    <td class="py-3 pr-4 text-green-500">{m.partition_size}</td>
                    <td class="py-3 pr-4">
                      <div :if={m.partition_percent > 0} class="flex items-center gap-2">
                        <div class="flex-1 h-2 bg-green-900/30 border border-green-900/50 overflow-hidden">
                          <div
                            class={"h-full transition-all duration-500 " <> cond do
                              m.partition_percent >= 90 -> "bg-red-500"
                              m.partition_percent >= 70 -> "bg-yellow-500"
                              true -> "bg-green-500"
                            end}
                            style={"width: #{m.partition_percent}%"}
                          ></div>
                        </div>
                        <span class={"text-[10px] font-bold tracking-widest min-w-[36px] text-right " <> cond do
                          m.partition_percent >= 90 -> "text-red-500"
                          m.partition_percent >= 70 -> "text-yellow-500"
                          true -> "text-green-500"
                        end}>
                          {m.partition_percent}%
                        </span>
                      </div>
                      <span :if={m.partition_percent == 0} class="text-green-900 text-[10px]">—</span>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <!-- FORMAT CONFIRMATION MODAL -->
        <div :if={@format_target} class="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-sm">
          <div class="bg-black border-2 border-green-500 p-6 md:p-8 max-w-lg w-full mx-4 shadow-[0_0_30px_rgba(34,197,94,0.2)] relative">
            <div class="absolute top-0 left-0 w-4 h-4 border-t-2 border-l-2 border-green-500"></div>
            <div class="absolute top-0 right-0 w-4 h-4 border-t-2 border-r-2 border-green-500"></div>
            <div class="absolute bottom-0 left-0 w-4 h-4 border-b-2 border-l-2 border-green-500"></div>
            <div class="absolute bottom-0 right-0 w-4 h-4 border-b-2 border-r-2 border-green-500"></div>

            <div :if={!@formatting} class="text-center">
              <.icon name="hero-exclamation-triangle" class="w-12 h-12 mx-auto text-red-500 mb-4" />
              <h3 class="text-lg font-bold text-red-500 tracking-widest uppercase mb-4">
                ⚠ CẢNH BÁO: XÓA DỮ LIỆU
              </h3>
              <p class="text-green-400 text-sm mb-2">
                Bạn đang chuẩn bị format thiết bị:
              </p>
              <p class="text-green-500 text-lg font-bold mb-4 bg-green-900/20 py-2 border border-green-800">
                /dev/{@format_target}
              </p>

              <div :if={!@format_confirm} class="space-y-4">
                <p class="text-red-400 text-xs tracking-widest uppercase">
                  TOÀN BỘ DỮ LIỆU TRÊN PHÂN VÙNG NÀY SẼ BỊ XÓA VĨNH VIỄN!
                </p>
                <div class="flex gap-3 justify-center mt-6">
                  <button phx-click="cancel_format" class="bg-green-900/30 border border-green-800 text-green-500 hover:bg-green-800/50 px-6 py-2.5 text-xs font-bold tracking-widest uppercase transition-all">
                    HỦY BỎ
                  </button>
                  <button phx-click="confirm_format" class="bg-red-900/50 border border-red-500 text-red-400 hover:bg-red-700 hover:text-white px-6 py-2.5 text-xs font-bold tracking-widest uppercase transition-all">
                    TIẾP TỤC
                  </button>
                </div>
              </div>

              <div :if={@format_confirm} class="space-y-4 mt-4">
                <p class="text-yellow-400 text-xs tracking-widest uppercase animate-pulse">
                  XÁC NHẬN LẦN CUỐI: HÀNH ĐỘNG NÀY KHÔNG THỂ HOÀN TÁC!
                </p>
                <div class="flex gap-3 justify-center mt-6">
                  <button phx-click="cancel_format" class="bg-green-900/30 border border-green-800 text-green-500 hover:bg-green-800/50 px-6 py-2.5 text-xs font-bold tracking-widest uppercase transition-all">
                    HỦY BỎ
                  </button>
                  <button phx-click="execute_format" phx-value-device={@format_target} class="bg-red-600 hover:bg-red-500 text-white px-6 py-2.5 text-xs font-bold tracking-widest uppercase transition-all animate-pulse">
                    <.icon name="hero-trash" class="w-4 h-4 inline mr-1" /> XÁC NHẬN FORMAT
                  </button>
                </div>
              </div>
            </div>

            <div :if={@formatting} class="text-center py-8">
              <div class="w-12 h-12 mx-auto border-4 border-green-500 border-t-transparent rounded-full animate-spin mb-6"></div>
              <p class="text-green-400 text-sm tracking-widest uppercase animate-pulse">
                ĐANG FORMAT /dev/{@format_target}...
              </p>
              <p class="text-green-700 text-[10px] mt-2 tracking-widest">
                VUI LÒNG KHÔNG TẮT HỆ THỐNG HOẶC RÚT THIẾT BỊ.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
