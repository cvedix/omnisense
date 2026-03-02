defmodule TProNVRWeb.LiveDashboard.CVEDIXPage do
  @moduledoc """
  Custom Phoenix LiveDashboard page for CVEDIX-RT instances management.
  """

  use Phoenix.LiveDashboard.PageBuilder

  alias TProNVR.CVEDIX
  alias TProNVR.CVEDIX.Instance

  @impl true
  def menu_link(_, _) do
    {:ok, "AI Video Analytics"}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load_data(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component module={__MODULE__.Component} id="cvedix-page" {assigns} />
    """
  end

  defp load_data(socket) do
    # Get CVEDIX version and status
    {cvedix_status, cvedix_version} = case CVEDIX.health_check() do
      {:ok, version} when is_map(version) -> {:connected, version}
      {:ok, version} -> {:connected, %{"engine" => version}}
      _ -> {:disconnected, nil}
    end
    
    # Load remote instances from CVEDIX-RT
    remote_instances = case Instance.list() do
      {:ok, instances} -> instances
      _ -> []
    end
    
    # Load NVR database instances
    nvr_instances = CVEDIX.list_instances()

    assign(socket,
      cvedix_status: cvedix_status,
      cvedix_version: cvedix_version,
      remote_instances: remote_instances,
      nvr_instances: nvr_instances
    )
  end

  defmodule Component do
    use Phoenix.LiveComponent

    alias TProNVR.CVEDIX.Instance

    @impl true
    def render(assigns) do
      ~H"""
      <div>
        <!-- Header with Status -->
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px;">
          <div>
            <h2 style="margin: 0; color: #1a1a2e;">AI Video Analytics</h2>
            <p style="color: #666; margin: 5px 0 0 0;">Manage video analytics instances</p>
          </div>
          <div style="display: flex; gap: 10px; align-items: center;">
            <%= if @cvedix_status == :connected do %>
              <span style="background: #d4edda; color: #155724; padding: 5px 15px; border-radius: 20px; font-size: 14px;">
                ✓ Connected
              </span>
            <% else %>
              <span style="background: #f8d7da; color: #721c24; padding: 5px 15px; border-radius: 20px; font-size: 14px;">
                ✗ Disconnected
              </span>
            <% end %>
            <button phx-click="refresh" phx-target={@myself} 
              style="background: #6c757d; color: white; border: none; padding: 8px 16px; border-radius: 5px; cursor: pointer;">
              ↻ Refresh
            </button>
          </div>
        </div>

        <!-- Version Info -->
        <%= if @cvedix_version do %>
          <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); border-radius: 8px; padding: 15px 20px; margin-bottom: 20px; color: white;">
            <div style="display: flex; justify-content: space-between; align-items: center;">
              <div>
                <strong style="font-size: 16px;">Omnimind Runtime Engine</strong>
                <p style="margin: 5px 0 0 0; opacity: 0.9; font-size: 13px;">Real-time Video Analytics Platform</p>
              </div>
              <div style="text-align: right;">
                <div style="font-size: 18px; font-family: monospace;"><%= @cvedix_version["engine"] || "Unknown" %></div>
                <div style="font-size: 11px; opacity: 0.8;">
                  API: <%= @cvedix_version["api"] || "-" %> | Build: <%= @cvedix_version["build"] || "-" %>
                </div>
              </div>
            </div>
          </div>
        <% end %>

        <!-- Stats Cards -->
        <div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 15px; margin-bottom: 20px;">
          <div style="background: #f8f9fa; border-radius: 8px; padding: 15px; text-align: center;">
            <div style="color: #666; font-size: 12px;">Remote Instances</div>
            <div style="font-size: 28px; font-weight: bold; color: #007bff;"><%= length(@remote_instances) %></div>
          </div>
          <div style="background: #f8f9fa; border-radius: 8px; padding: 15px; text-align: center;">
            <div style="color: #666; font-size: 12px;">Running</div>
            <div style="font-size: 28px; font-weight: bold; color: #28a745;"><%= count_running(@remote_instances) %></div>
          </div>
          <div style="background: #f8f9fa; border-radius: 8px; padding: 15px; text-align: center;">
            <div style="color: #666; font-size: 12px;">Loaded</div>
            <div style="font-size: 28px; font-weight: bold; color: #ffc107;"><%= count_loaded(@remote_instances) %></div>
          </div>
          <div style="background: #f8f9fa; border-radius: 8px; padding: 15px; text-align: center;">
            <div style="color: #666; font-size: 12px;">NVR Linked</div>
            <div style="font-size: 28px; font-weight: bold; color: #6c757d;"><%= length(@nvr_instances) %></div>
          </div>
        </div>

        <!-- Remote Instances Table -->
        <div style="background: white; border-radius: 8px; border: 1px solid #dee2e6; overflow: hidden; margin-bottom: 20px;">
          <div style="background: #f8f9fa; padding: 12px 15px; border-bottom: 1px solid #dee2e6;">
            <strong>Omnimind Remote Instances</strong>
            <span style="color: #666; font-size: 12px; margin-left: 10px;">from /v1/core/instances</span>
          </div>
          <table style="width: 100%; border-collapse: collapse;">
            <thead>
              <tr style="background: #f8f9fa;">
                <th style="padding: 10px 15px; text-align: left; border-bottom: 1px solid #dee2e6; font-size: 13px;">Instance ID</th>
                <th style="padding: 10px 15px; text-align: left; border-bottom: 1px solid #dee2e6; font-size: 13px;">Name</th>
                <th style="padding: 10px 15px; text-align: left; border-bottom: 1px solid #dee2e6; font-size: 13px;">Status</th>
                <th style="padding: 10px 15px; text-align: left; border-bottom: 1px solid #dee2e6; font-size: 13px;">Solution</th>
                <th style="padding: 10px 15px; text-align: left; border-bottom: 1px solid #dee2e6; font-size: 13px;">NVR</th>
                <th style="padding: 10px 15px; text-align: left; border-bottom: 1px solid #dee2e6; font-size: 13px;">Actions</th>
              </tr>
            </thead>
            <tbody>
              <%= if @remote_instances == [] do %>
                <tr>
                  <td colspan="6" style="padding: 30px; text-align: center; color: #666;">
                    No instances found in Omnimind
                  </td>
                </tr>
              <% else %>
                <%= for instance <- @remote_instances do %>
                  <tr style="border-bottom: 1px solid #dee2e6;">
                    <td style="padding: 10px 15px;">
                      <code style="background: #e9ecef; padding: 2px 6px; border-radius: 3px; font-size: 11px;">
                        <%= String.slice(instance["instanceId"] || "", 0, 12) %>...
                      </code>
                    </td>
                    <td style="padding: 10px 15px; font-weight: 500;"><%= instance["name"] || "Unnamed" %></td>
                    <td style="padding: 10px 15px;">
                      <span style={"background: #{status_bg(instance)}; color: #{status_color(instance)}; padding: 3px 10px; border-radius: 12px; font-size: 11px;"}>
                        <%= status_text(instance) %>
                      </span>
                    </td>
                    <td style="padding: 10px 15px; color: #666;"><%= instance["solution"] || "-" %></td>
                    <td style="padding: 10px 15px;">
                      <%= if is_linked?(@nvr_instances, instance["instanceId"]) do %>
                        <span style="color: #28a745;">✓ Linked</span>
                      <% else %>
                        <span style="color: #aaa;">-</span>
                      <% end %>
                    </td>
                    <td style="padding: 10px 15px;">
                      <div style="display: flex; gap: 5px;">
                        <%= if instance["running"] do %>
                          <button phx-click="stop_instance" phx-value-id={instance["instanceId"]} phx-target={@myself}
                            style="background: #dc3545; color: white; border: none; padding: 4px 10px; border-radius: 3px; font-size: 11px; cursor: pointer;">
                            Stop
                          </button>
                        <% else %>
                          <%= if instance["loaded"] do %>
                            <button phx-click="start_instance" phx-value-id={instance["instanceId"]} phx-target={@myself}
                              style="background: #28a745; color: white; border: none; padding: 4px 10px; border-radius: 3px; font-size: 11px; cursor: pointer;">
                              Start
                            </button>
                          <% else %>
                            <button phx-click="load_instance" phx-value-id={instance["instanceId"]} phx-target={@myself}
                              style="background: #007bff; color: white; border: none; padding: 4px 10px; border-radius: 3px; font-size: 11px; cursor: pointer;">
                              Load
                            </button>
                          <% end %>
                        <% end %>
                      </div>
                    </td>
                  </tr>
                <% end %>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
      """
    end

    @impl true
    def handle_event("refresh", _, socket) do
      {:noreply, load_component_data(socket)}
    end

    @impl true
    def handle_event("load_instance", %{"id" => id}, socket) do
      Instance.load(id)
      {:noreply, load_component_data(socket)}
    end

    @impl true
    def handle_event("start_instance", %{"id" => id}, socket) do
      Instance.start(id)
      {:noreply, load_component_data(socket)}
    end

    @impl true
    def handle_event("stop_instance", %{"id" => id}, socket) do
      Instance.stop(id)
      {:noreply, load_component_data(socket)}
    end

    defp load_component_data(socket) do
      remote_instances = case Instance.list() do
        {:ok, instances} -> instances
        _ -> []
      end
      
      assign(socket, remote_instances: remote_instances)
    end

    defp count_running(instances), do: Enum.count(instances, & &1["running"])
    defp count_loaded(instances), do: Enum.count(instances, &(&1["loaded"] && !&1["running"]))
    
    defp is_linked?(nvr_instances, instance_id) do
      Enum.any?(nvr_instances, & &1.instance_id == instance_id)
    end

    defp status_text(instance) do
      cond do
        instance["running"] -> "RUNNING"
        instance["loaded"] -> "LOADED"
        true -> "STOPPED"
      end
    end

    defp status_bg(instance) do
      cond do
        instance["running"] -> "#d4edda"
        instance["loaded"] -> "#fff3cd"
        true -> "#e9ecef"
      end
    end

    defp status_color(instance) do
      cond do
        instance["running"] -> "#155724"
        instance["loaded"] -> "#856404"
        true -> "#495057"
      end
    end
  end
end
