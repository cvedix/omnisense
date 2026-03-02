defmodule TProNVRWeb.CVEDIXInstancesLive do
  @moduledoc """
  LiveView for listing all NVR CVEDIX instances.
  """

  use TProNVRWeb, :live_view

  alias TProNVR.CVEDIX
  alias TProNVR.CVEDIX.Instance

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(10_000, self(), :refresh)
    end

    {:ok, load_instances(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 w-full min-h-full">
      <div class="flex justify-between items-center mb-6">
        <div>
          <h1 class="text-2xl font-bold text-white">NVR Analytics Instances</h1>
          <p class="text-white/80 text-sm mt-1">Manage instances linked to devices</p>
        </div>
        <button phx-click="refresh" class="px-4 py-2 bg-black hover:bg-green-800 text-white rounded-lg text-sm">
          ↻ Refresh
        </button>
      </div>

      <!-- Stats Cards -->
      <div class="grid grid-cols-4 gap-4 mb-6">
        <div class="bg-black rounded-lg p-4">
          <div class="text-white/80 text-sm">Total Instances</div>
          <div class="text-2xl font-bold text-white"><%= length(@instances) %></div>
        </div>
        <div class="bg-black rounded-lg p-4">
          <div class="text-white/80 text-sm">Running</div>
          <div class="text-2xl font-bold text-green-400"><%= Enum.count(@instances, &(&1.status == "running")) %></div>
        </div>
        <div class="bg-black rounded-lg p-4">
          <div class="text-white/80 text-sm">Stopped</div>
          <div class="text-2xl font-bold text-yellow-400"><%= Enum.count(@instances, &(&1.status == "stopped")) %></div>
        </div>
        <div class="bg-black rounded-lg p-4">
          <div class="text-white/80 text-sm">Errors</div>
          <div class="text-2xl font-bold text-red-400"><%= Enum.count(@instances, &(&1.status == "error")) %></div>
        </div>
      </div>

      <!-- Instances Table -->
      <div class="bg-black rounded-lg overflow-hidden">
        <table class="w-full">
          <thead class="bg-black">
            <tr>
              <th class="px-4 py-3 text-left text-sm font-medium text-white">Device</th>
              <th class="px-4 py-3 text-left text-sm font-medium text-white">Instance ID</th>
              <th class="px-4 py-3 text-left text-sm font-medium text-white">Status</th>
              <th class="px-4 py-3 text-left text-sm font-medium text-white">Detector Mode</th>
              <th class="px-4 py-3 text-left text-sm font-medium text-white">FPS Limit</th>
              <th class="px-4 py-3 text-left text-sm font-medium text-white">Zones</th>
              <th class="px-4 py-3 text-left text-sm font-medium text-white">Actions</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-green-800">
              <%= for instance <- @instances do %>
                <tr class="hover:bg-black/50">
                  <td class="px-4 py-3">
                    <.link navigate={"/devices/#{instance.device_id}/details"} 
                      class="text-green-400 hover:text-green-300 font-medium">
                      <%= instance.name %>
                    </.link>
                  </td>
                  <td class="px-4 py-3">
                    <code class="text-xs text-white/80 bg-black px-2 py-1 rounded">
                      <%= String.slice(instance.instance_id || "", 0, 8) %>...
                    </code>
                  </td>
                  <td class="px-4 py-3">
                    <span class={[
                      "inline-flex items-center px-2 py-1 rounded-full text-xs font-medium",
                      status_badge_class(instance.status)
                    ]}>
                      <span class={["w-1.5 h-1.5 rounded-full mr-1.5", status_dot_class(instance.status)]}></span>
                      <%= String.upcase(instance.status || "unknown") %>
                    </span>
                  </td>
                  <td class="px-4 py-3 text-sm text-white"><%= instance.detector_mode %></td>
                  <td class="px-4 py-3 text-sm text-white"><%= instance.frame_rate_limit %> FPS</td>
                  <td class="px-4 py-3 text-sm text-white"><%= length(instance.intrusion_areas || []) %></td>
                  <td class="px-4 py-3">
                    <div class="flex gap-2">
                      <%= if instance.status == "running" do %>
                        <button phx-click="stop" phx-value-id={instance.device_id}
                          class="px-3 py-1 bg-red-600 hover:bg-red-700 text-white rounded text-xs">
                          Stop
                        </button>
                      <% else %>
                        <button phx-click="start" phx-value-id={instance.device_id}
                          class="px-3 py-1 bg-green-600 hover:bg-green-700 text-white rounded text-xs">
                          Start
                        </button>
                      <% end %>
                      <button phx-click="sync" phx-value-id={instance.device_id}
                        class="px-3 py-1 bg-green-800 hover:bg-green-700 text-white rounded text-xs">
                        Sync
                      </button>
                      <button phx-click="delete" phx-value-id={instance.device_id}
                        data-confirm="Delete this instance?"
                        class="px-3 py-1 bg-black hover:bg-red-600 text-white hover:text-white rounded text-xs">
                        Delete
                      </button>
                    </div>
                  </td>
                </tr>
              <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, load_instances(socket)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_instances(socket)}
  end

  @impl true
  def handle_event("start", %{"id" => device_id}, socket) do
    case CVEDIX.get_instance(device_id) do
      {:ok, instance} ->
        with :ok <- Instance.load(instance.instance_id),
             :ok <- Instance.start(instance.instance_id) do
          {:noreply, socket |> put_flash(:info, "Instance started") |> load_instances()}
        else
          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to start: #{inspect(reason)}")}
        end
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Instance not found")}
    end
  end

  @impl true
  def handle_event("stop", %{"id" => device_id}, socket) do
    case CVEDIX.get_instance(device_id) do
      {:ok, instance} ->
        case Instance.stop(instance.instance_id) do
          :ok -> {:noreply, socket |> put_flash(:info, "Instance stopped") |> load_instances()}
          {:error, reason} -> {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
        end
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Instance not found")}
    end
  end

  @impl true
  def handle_event("sync", %{"id" => device_id}, socket) do
    case CVEDIX.sync_instance_status(device_id) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Status synced") |> load_instances()}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => device_id}, socket) do
    case CVEDIX.stop_intrusion_detection(device_id) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Instance deleted") |> load_instances()}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  defp load_instances(socket) do
    assign(socket, instances: CVEDIX.list_instances())
  end

  defp status_badge_class("running"), do: "bg-green-900/50 text-green-400"
  defp status_badge_class("stopped"), do: "bg-yellow-900/50 text-yellow-400"
  defp status_badge_class("error"), do: "bg-red-900/50 text-red-400"
  defp status_badge_class("loading"), do: "bg-green-900/50 text-green-400"
  defp status_badge_class(_), do: "bg-black text-white/80"

  defp status_dot_class("running"), do: "bg-green-400"
  defp status_dot_class("stopped"), do: "bg-yellow-400"
  defp status_dot_class("error"), do: "bg-red-400"
  defp status_dot_class("loading"), do: "bg-green-400"
  defp status_dot_class(_), do: "bg-green-700"
end
