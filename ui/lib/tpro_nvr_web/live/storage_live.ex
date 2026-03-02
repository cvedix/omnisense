defmodule TProNVRWeb.StorageLive do
  @moduledoc """
  LiveView for managing physical storage devices.
  Displays connected disks, their status, and usage statistics.
  """

  use TProNVRWeb, :live_view

  alias TProNVR.Disk

  @refresh_interval :timer.seconds(30)

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-green-900 dark:bg-black p-6">
      <div class="max-w-7xl mx-auto">
        <!-- Header -->
        <div class="flex justify-between items-center mb-6">
          <h1 class="text-2xl font-bold text-white dark:text-white">
            <svg class="inline-block w-8 h-8 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4m0 5c0 2.21-3.582 4-8 4s-8-1.79-8-4" />
            </svg>
            Storage Management
          </h1>
          <button
            phx-click="refresh"
            class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition flex items-center"
          >
            <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
            </svg>
            Refresh
          </button>
        </div>

        <!-- Summary Cards -->
        <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
          <div class="bg-black rounded-lg shadow p-4">
            <div class="text-sm text-white/70 dark:text-white/80">Total Disks</div>
            <div class="text-2xl font-bold text-white dark:text-white"><%= length(@disks) %></div>
          </div>
          <div class="bg-black rounded-lg shadow p-4">
            <div class="text-sm text-white/70 dark:text-white/80">Total Capacity</div>
            <div class="text-2xl font-bold text-white dark:text-white"><%= format_bytes(@total_size) %></div>
          </div>
          <div class="bg-black rounded-lg shadow p-4">
            <div class="text-sm text-white/70 dark:text-white/80">Used Space</div>
            <div class="text-2xl font-bold text-white dark:text-white"><%= format_bytes(@used_space) %></div>
          </div>
          <div class="bg-black rounded-lg shadow p-4">
            <div class="text-sm text-white/70 dark:text-white/80">Free Space</div>
            <div class="text-2xl font-bold text-green-600 dark:text-green-400"><%= format_bytes(@free_space) %></div>
          </div>
        </div>

        <!-- Disk List -->
        <div class="bg-black rounded-lg shadow overflow-hidden">
          <div class="px-6 py-4 border-b border-green-700 dark:border-green-800">
            <h2 class="text-lg font-semibold text-white dark:text-white">Connected Drives</h2>
          </div>

          <div :if={@disks == []} class="p-8 text-center text-white/70 dark:text-white/80">
            No storage devices detected
          </div>

          <div :if={@disks != []} class="divide-y divide-gray-200 dark:divide-gray-700">
            <div :for={disk <- @disks} class="p-6 hover:bg-green-800 dark:hover:bg-green-800 transition">
              <div class="flex items-start justify-between">
                <div class="flex items-center">
                  <!-- Disk Icon -->
                  <div class={"w-12 h-12 rounded-lg flex items-center justify-center mr-4 #{disk_type_color(disk.type)}"}>
                    <%= disk_icon(disk.type) %>
                  </div>

                  <div>
                    <h3 class="text-lg font-medium text-white dark:text-white">
                      <%= disk.vendor %> <%= disk.model %>
                    </h3>
                    <div class="text-sm text-white/70 dark:text-white/80 space-x-4">
                      <span><%= disk.path %></span>
                      <span>•</span>
                      <span><%= format_bytes(disk.size) %></span>
                      <span :if={disk.serial}>• Serial: <%= disk.serial %></span>
                    </div>

                    <!-- Partitions -->
                    <div :if={disk.parts != []} class="mt-2">
                      <div :for={part <- disk.parts} class="text-sm text-white/60 dark:text-white ml-4">
                        └ <%= part.name %>
                        <span :if={part.fs} class="text-white/80">
                          (<%= part.fs.type %>, <%= format_bytes(part.fs.size) %>,
                          mounted: <%= part.fs.mountpoint || "not mounted" %>)
                        </span>
                      </div>
                    </div>
                  </div>
                </div>

                <div class="flex items-center space-x-2">
                  <!-- Type Badge -->
                  <span class={"px-2 py-1 text-xs font-medium rounded-full #{disk_type_badge(disk.type)}"}>
                    <%= disk_type_label(disk.type) %>
                  </span>

                  <!-- Connection Type -->
                  <span :if={disk.tran} class="px-2 py-1 text-xs font-medium rounded-full bg-green-900 dark:bg-green-700 text-white dark:text-white">
                    <%= String.upcase(to_string(disk.tran)) %>
                  </span>

                  <!-- Hot-plug indicator -->
                  <span :if={disk.hotplug} class="px-2 py-1 text-xs font-medium rounded-full bg-orange-100 text-orange-700">
                    Hot-plug
                  </span>
                </div>
              </div>

              <!-- Usage Bar (if filesystem) -->
              <div :if={disk.fs && disk.fs.size} class="mt-4">
                <div class="flex justify-between text-sm mb-1">
                  <span class="text-white/60 dark:text-white/80">Usage</span>
                  <span class="text-white dark:text-white font-medium">
                    <%= usage_percentage(disk.fs) %>%
                  </span>
                </div>
                <div class="w-full bg-green-900 dark:bg-green-700 rounded-full h-2">
                  <div
                    class={"h-2 rounded-full #{usage_color(usage_percentage(disk.fs))}"}
                    style={"width: #{usage_percentage(disk.fs)}%"}
                  ></div>
                </div>
                <div class="flex justify-between text-xs mt-1 text-white/70 dark:text-white/80">
                  <span>Used: <%= format_bytes((disk.fs.size || 0) - (disk.fs.avail || 0)) %></span>
                  <span>Free: <%= format_bytes(disk.fs.avail) %></span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Last Updated -->
        <div class="mt-4 text-center text-sm text-white/70 dark:text-white/80">
          Last updated: <%= Calendar.strftime(@last_updated, "%Y-%m-%d %H:%M:%S") %>
        </div>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Process.send_after(self(), :refresh, @refresh_interval)
    end

    socket
    |> load_disks()
    |> then(&{:ok, &1})
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, load_disks(socket)}
  end

  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, load_disks(socket)}
  end

  defp load_disks(socket) do
    disks = case Disk.list_drives(major_number: [8, 179, 259]) do
      {:ok, drives} -> drives
      {:error, _} -> []
    end

    total_size = Enum.reduce(disks, 0, fn d, acc -> acc + (d.size || 0) end)

    {used, free} = Enum.reduce(disks, {0, 0}, fn disk, {used_acc, free_acc} ->
      case disk.fs do
        %{size: size, avail: avail} when is_integer(size) and is_integer(avail) ->
          {used_acc + (size - avail), free_acc + avail}
        _ ->
          # Check partitions
          Enum.reduce(disk.parts || [], {used_acc, free_acc}, fn part, {u, f} ->
            case part.fs do
              %{size: size, avail: avail} when is_integer(size) and is_integer(avail) ->
                {u + (size - avail), f + avail}
              _ -> {u, f}
            end
          end)
      end
    end)

    assign(socket,
      disks: disks,
      total_size: total_size,
      used_space: used,
      free_space: free,
      last_updated: NaiveDateTime.local_now()
    )
  end

  # Helper functions
  defp format_bytes(nil), do: "N/A"
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes) when bytes < 1024 * 1024 * 1024, do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"
  defp format_bytes(bytes) when bytes < 1024 * 1024 * 1024 * 1024, do: "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024 * 1024 * 1024), 2)} TB"

  defp disk_type_label(:nvme), do: "NVMe"
  defp disk_type_label(:ssd), do: "SSD"
  defp disk_type_label(:hdd), do: "HDD"
  defp disk_type_label(_), do: "Unknown"

  defp disk_type_color(:nvme), do: "bg-purple-100 dark:bg-purple-900"
  defp disk_type_color(:ssd), do: "bg-blue-100 dark:bg-blue-900"
  defp disk_type_color(:hdd), do: "bg-green-900 dark:bg-green-800"
  defp disk_type_color(_), do: "bg-green-900 dark:bg-green-800"

  defp disk_type_badge(:nvme), do: "bg-purple-100 text-purple-700 dark:bg-purple-900 dark:text-purple-300"
  defp disk_type_badge(:ssd), do: "bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-300"
  defp disk_type_badge(:hdd), do: "bg-green-900 text-white dark:bg-green-800 dark:text-white"
  defp disk_type_badge(_), do: "bg-green-900 text-white"

  defp disk_icon(:nvme) do
    Phoenix.HTML.raw("""
    <svg class="w-6 h-6 text-purple-600 dark:text-purple-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
    </svg>
    """)
  end

  defp disk_icon(:ssd) do
    Phoenix.HTML.raw("""
    <svg class="w-6 h-6 text-blue-600 dark:text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z" />
    </svg>
    """)
  end

  defp disk_icon(_) do
    Phoenix.HTML.raw("""
    <svg class="w-6 h-6 text-white/60 dark:text-white/80" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4" />
    </svg>
    """)
  end

  defp usage_percentage(%{size: size, avail: avail}) when is_integer(size) and size > 0 do
    used = size - (avail || 0)
    round(used / size * 100)
  end
  defp usage_percentage(_), do: 0

  defp usage_color(percent) when percent >= 90, do: "bg-red-500"
  defp usage_color(percent) when percent >= 70, do: "bg-yellow-500"
  defp usage_color(_), do: "bg-green-500"
end
