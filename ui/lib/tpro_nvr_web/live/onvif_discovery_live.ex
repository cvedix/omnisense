defmodule TProNVRWeb.OnvifDiscoveryLive do
  @moduledoc false

  use TProNVRWeb, :live_view

  require Logger

  alias TProNVR.Devices
  alias TProNVR.Devices.Cameras.{NetworkInterface, NTP, StreamProfile}

  defmodule DiscoverSettings do
    @moduledoc false

    use Ecto.Schema

    alias Ecto.Changeset

    embedded_schema do
      field :ip_address, :string
      field :timeout, :integer
    end

    def to_struct(params) do
      params |> changeset() |> Changeset.apply_action(:validate)
    end

    def create_changeset(struct), do: changeset(struct, %{})

    def changeset(changeset \\ %__MODULE__{}, params) do
      changeset
      |> Changeset.cast(params, [:ip_address, :timeout])
      |> Changeset.validate_required([:timeout])
      |> Changeset.validate_number(:timeout, greater_than: 0, less_than_or_equal_to: 60)
    end
  end

  defmodule CameraDetails do
    @moduledoc false

    defstruct [
      :id,
      :name,
      :probe,
      :device,
      :network_interface,
      :ntp,
      :stream_profiles,
      :auth_form,
      :streams_form,
      :selected_profiles,
      tab: "system"
    ]
  end

  def render(assigns) do
    ~H"""
    <div class="w-full flex items-center flex-col space-y-6 px-2 md:px-0 font-mono mb-10">
      <div class="w-full lg:w-3/4 max-w-5xl bg-black border border-green-800 p-6 relative group hover:border-green-500 transition-colors shadow-[0_0_15px_rgba(0,128,0,0.1)] rounded-none px-4 md:px-6 mx-4 md:mx-0 mb-10">
        <!-- Corner Accents Master -->
        <div class="absolute top-0 right-0 w-2 h-2 border-t border-r border-green-500"></div>
        <div class="absolute bottom-0 left-0 w-2 h-2 border-b border-l border-green-500"></div>
        <div class="absolute top-0 left-0 w-2 h-2 border-t border-l border-green-500"></div>
        <div class="absolute bottom-0 right-0 w-2 h-2 border-b border-r border-green-500"></div>
        <div class="absolute top-0 left-0 p-2 text-green-700 text-[10px] tracking-widest uppercase ml-1 opacity-70">MODULE: NETWORK DISCOVERY</div>

        <div class="flex flex-col md:flex-row justify-between items-start md:items-center mt-6 gap-6">
          <div class="flex items-center space-x-4">
            <div class="border border-green-500/50 bg-green-900/10 p-3 shadow-[0_0_10px_rgba(34,197,94,0.1)]">
              <.icon name="network" class="h-6 w-6 text-green-500 animate-pulse" />
            </div>
            <div class="flex flex-col text-left">
              <span class="text-md font-bold text-green-500 tracking-widest uppercase">
                > DEVICE_DISCOVERY
              </span>
              <span class="text-xs text-green-700 tracking-widest uppercase mt-1">
                AUTOMATED NETWORK SCANNER
              </span>
            </div>
          </div>
          
          <div class="flex flex-col items-start md:items-end space-y-3 w-full md:w-auto">
            <span class="text-green-700 text-[10px] uppercase tracking-wider font-bold hidden md:block border-b border-green-900/50 pb-1">TARGET: ALL INTERFACES / 2 SEC TIMEOUT</span>
            <.button class="w-full md:w-auto py-3 px-8 bg-green-900/20 border border-green-500 text-green-500 hover:bg-green-500 hover:text-black uppercase tracking-widest text-sm font-bold transition-all shadow-[0_0_10px_rgba(34,197,94,0.1)] rounded-none" phx-click="discover" phx-disable-with="SCANNING...">
              <.icon name="hero-magnifying-glass-solid" class="w-5 h-5 mr-2" /> EXECUTE SCAN
            </.button>
          </div>
        </div>
      </div>
      
    <!-- Device List Section -->
      <div class="w-full lg:w-3/4 max-w-5xl flex flex-col space-y-4 bg-black p-6 border border-green-800 rounded-none relative group hover:border-green-500 transition-colors shadow-[0_0_15px_rgba(0,128,0,0.1)] mx-4 md:mx-0">
        <div class="absolute top-0 right-0 w-2 h-2 border-t border-r border-green-500"></div>
        <div class="absolute bottom-0 left-0 w-2 h-2 border-b border-l border-green-500"></div>
        <div class="absolute top-0 left-0 p-2 text-green-700 text-[10px] tracking-widest uppercase ml-1 opacity-70">DATA_LINK: RESULTS</div>

        <span class="text-md font-bold text-green-500 tracking-wider uppercase flex items-center border-b border-green-900/50 pb-3 mt-2">
          <.icon name="hero-wifi" class="w-5 h-5 mr-3" /> FOUND {length(@devices)} ASSET(S)
        </span>
        <div :for={device <- @devices} id={device.id} class="flex flex-col space-y-2 mt-4">
          <div class="flex flex-col md:flex-row justify-between border border-green-900/60 bg-green-900/10 p-4 space-y-4 md:space-y-0 items-start md:items-center relative group/item hover:border-green-500/80 hover:bg-green-900/20 transition-colors shadow-inner">
            <div class="flex items-center w-full min-w-0">
              <div class="border border-green-500/30 bg-black p-3 mr-4 shadow-[0_0_10px_rgba(34,197,94,0.1)]">
                <.icon name="hero-video-camera" class="w-6 h-6 text-green-400" />
              </div>
              <div class="flex flex-col justify-center text-left flex-1 min-w-0">
                <div class="flex items-center flex-wrap gap-2 mb-1.5">
                  <span class="text-sm font-bold text-green-500 tracking-widest uppercase truncate max-w-[150px] sm:max-w-[300px]">{device.name}</span>
                  <span :if={hw = scope_value(device.probe.scopes, "hardware")} class={"text-[10px] text-black bg-green-500 px-2 py-0.5 font-bold uppercase tracking-widest rounded-none whitespace-nowrap #{if hw == device.name, do: "hidden"}"}>
                    {hw}
                  </span>
                  <span class="text-[10px] text-green-400 border border-green-500/50 px-2 py-0.5 font-bold uppercase tracking-widest rounded-none whitespace-nowrap bg-green-900/30">
                    ONVIF_PROFILE_S
                  </span>
                </div>
                <div class="text-xs text-green-700 uppercase tracking-widest flex items-center">
                  <span class="inline-block w-2.5 h-2.5 bg-green-500 rounded-full mr-2 shadow-[0_0_8px_rgba(34,197,94,0.8)] animate-pulse"></span>
                  TCP/IP: <span class="text-green-400 ml-1 font-mono">{device.probe.device_ip}</span>
                </div>
              </div>
            </div>
            <div class="flex w-full md:w-auto mt-4 md:mt-0 justify-end md:ml-4 border-t border-green-900/50 md:border-t-0 pt-4 md:pt-0">
              <.button
                :if={is_nil(device.device)}
                class="w-full md:w-auto bg-black border border-green-700 text-green-500 hover:bg-green-900/40 uppercase text-xs tracking-widest font-bold rounded-none px-6 py-2.5"
                phx-click={
                  show_modal2(
                    JS.set_attribute({"phx-value-id", device.probe.device_ip}, to: "#auth-form"),
                    "camera-authentication"
                  )
                }
              >
                <.icon name="hero-lock-closed" class="w-4 h-4 mr-2" /> AUTH_REQUIRED
              </.button>
              <.button :if={not is_nil(device.device)} class="w-full md:w-auto bg-green-900/20 border border-green-500 text-green-400 hover:bg-green-500 hover:text-black uppercase text-xs tracking-widest font-bold rounded-none px-6 py-2.5 transition-all shadow-[0_0_10px_rgba(34,197,94,0.1)]" phx-click="show-details" phx-value-id={device.id}>
                <.icon name="hero-check-circle" class="w-4 h-4 mr-2" /> INSPECT_ASSET
              </.button>
            </div>
          </div>
        </div>
      </div>

      <.separator :if={@selected_device} class="w-full lg:w-3/4 max-w-5xl my-4 opacity-50 border-green-700" />
      
      <!-- Device Details Section -->
      <div :if={@selected_device} class="w-full lg:w-3/4 max-w-5xl flex flex-col space-y-5 mx-4 md:mx-0 mb-8 overflow-hidden font-mono mt-2">
        <div class="border border-green-800 bg-black p-6 relative group hover:border-green-500 transition-colors shadow-[0_0_15px_rgba(0,128,0,0.1)] rounded-none text-left w-full">
          <div class="absolute top-0 right-0 w-2 h-2 border-t border-r border-green-500"></div>
          <div class="absolute bottom-0 left-0 w-2 h-2 border-b border-l border-green-500"></div>
          <div class="absolute top-0 left-0 p-2 text-green-700 text-[10px] tracking-widest uppercase opacity-80">SYS_ACT_DEVICE</div>

          <div class="flex items-center mt-4 mb-5">
            <div class="border border-green-500/30 bg-black p-3 mr-4 shadow-inner flex-shrink-0">
              <.icon name="hero-camera" class="w-8 h-8 text-green-500" />
            </div>
            <div class="flex flex-col text-left min-w-0">
              <span class="text-lg font-bold text-green-500 tracking-widest uppercase mb-1 truncate">{@selected_device.name}</span>
              <div class="text-[10px] text-green-700 flex flex-wrap uppercase tracking-widest gap-x-4 gap-y-1">
                <span class="flex items-center">
                  <span class="inline-block w-2.5 h-2.5 bg-green-500 rounded-full mr-2 shadow-[0_0_5px_rgba(34,197,94,0.6)] animate-pulse"></span>
                  IP: <span class="text-green-400 ml-1 font-mono">{@selected_device.probe.device_ip}</span>
                </span>
                <span class="border-l border-green-800 pl-4">MFR: <span class="text-green-400">{@selected_device.device.manufacturer}</span></span>
              </div>
            </div>
          </div>
          <div class="flex flex-col sm:flex-row space-y-3 sm:space-y-0 sm:space-x-4 w-full border-t border-green-900/50 pt-5">
            <.button
              class="w-full sm:w-auto bg-black border border-green-700 text-green-500 hover:bg-green-900/40 uppercase text-xs tracking-widest font-bold rounded-none px-6 py-2.5"
              phx-click="auto-configure"
              phx-disable-with="AUTO_CONFIG..."
            >
              <.icon name="hero-wrench" class="w-4 h-4 mr-2 inline" /> AUTO_CFG
            </.button>
            <.button class="w-full sm:w-auto bg-green-900/20 border border-green-500 text-green-400 hover:bg-green-500 hover:text-black uppercase text-xs tracking-widest font-bold rounded-none px-6 py-2.5 transition-all shadow-[0_0_10px_rgba(34,197,94,0.1)]" phx-click="add-device">
              <.icon name="hero-plus" class="w-4 h-4 mr-2 inline" /> ADD_TO_NVR
            </.button>
          </div>
        </div>

        <div class="grid grid-cols-2 md:grid-cols-4 content-center gap-0 bg-black border border-green-800 relative group hover:border-green-500 transition-colors rounded-none">
          <div class={["flex justify-center uppercase tracking-widest border border-black hover:border-green-500/50 transition-colors p-3 cursor-pointer", selected_tab("system", @selected_device.tab)]} phx-click="switch-tab" phx-value-tab="system">
            <span class="text-xs font-bold flex items-center justify-center">
              <.icon name="hero-information-circle" class="w-4 h-4 mr-2" />SYSTEM
            </span>
          </div>
          <div class={["flex justify-center uppercase tracking-widest border border-black hover:border-green-500/50 transition-colors p-3 cursor-pointer", selected_tab("network", @selected_device.tab)]} phx-click="switch-tab" phx-value-tab="network">
            <span class="text-xs font-bold flex items-center justify-center">
              <.icon name="network" class="w-4 h-4 mr-2" />NETWORK
            </span>
          </div>
          <div class={["flex justify-center uppercase tracking-widest border border-black hover:border-green-500/50 transition-colors p-3 cursor-pointer", selected_tab("datetime", @selected_device.tab)]} phx-click="switch-tab" phx-value-tab="datetime">
            <span class="text-xs font-bold flex items-center justify-center">
              <.icon name="hero-clock" class="w-4 h-4 mr-2" />DATE/TIME
            </span>
          </div>
          <div class={["flex justify-center uppercase tracking-widest border border-black hover:border-green-500/50 transition-colors p-3 cursor-pointer", selected_tab("streams", @selected_device.tab)]} phx-click="switch-tab" phx-value-tab="streams">
            <span class="text-xs font-bold flex items-center justify-center">
              <.icon name="hero-tv" class="w-4 h-4 mr-2" />STREAMS
            </span>
          </div>
        </div>

        <div
          :if={@selected_device.tab == "system"}
          class="w-full lg:w-1/2 flex flex-col border border-green-800 rounded-none bg-black p-6 relative group hover:border-green-500 transition-colors shadow-[0_0_15px_rgba(0,128,0,0.1)]"
        >
          <div class="absolute top-0 right-0 w-2 h-2 border-t border-r border-green-500"></div>
          <div class="absolute bottom-0 left-0 w-2 h-2 border-b border-l border-green-500"></div>
          <h3 class="text-md font-bold text-green-500 mb-4 tracking-wider uppercase flex items-center border-b border-green-900/50 pb-2">
            > SYS.HARDWARE.INFO
          </h3>
          <dl class="space-y-3 text-sm text-green-400 mt-2">
            <div class="flex justify-between border-b border-green-900/50 pb-2 items-center">
              <dt class="text-green-700 uppercase tracking-widest text-[10px]">MFR</dt>
              <dd class="text-right uppercase font-mono text-sm max-w-[60%] truncate">{@selected_device.device.manufacturer}</dd>
            </div>
            <div class="flex justify-between border-b border-green-900/50 pb-2 items-center">
              <dt class="text-green-700 uppercase tracking-widest text-[10px]">MODEL</dt>
              <dd class="text-right uppercase font-mono text-sm max-w-[60%] truncate">{@selected_device.device.model}</dd>
            </div>
            <div class="flex justify-between border-b border-green-900/50 pb-2 items-center">
              <dt class="text-green-700 uppercase tracking-widest text-[10px]">FIRMWARE</dt>
              <dd class="text-right uppercase font-mono text-sm max-w-[60%] truncate">{@selected_device.device.firmware_version}</dd>
            </div>
            <div class="flex justify-between border-b border-green-900/50 pb-2 items-center">
              <dt class="text-green-700 uppercase tracking-widest text-[10px]">HW_ID</dt>
              <dd class="text-right uppercase font-mono text-sm max-w-[60%] truncate">{@selected_device.device.hardware_id}</dd>
            </div>
          </dl>
        </div>

        <div
          :if={@selected_device.tab == "network"}
          class="flex flex-col border border-green-800 rounded-none bg-black p-6 relative group hover:border-green-500 transition-colors shadow-[0_0_15px_rgba(0,128,0,0.1)] w-full"
        >
          <div class="absolute top-0 left-0 w-2 h-2 border-t border-l border-green-500"></div>
          <div class="absolute bottom-0 right-0 w-2 h-2 border-b border-r border-green-500"></div>
          <h3 class="text-md font-bold text-green-500 mb-4 tracking-wider uppercase flex items-center border-b border-green-900/50 pb-2">
            > SYS.NETWORK.CFG
          </h3>
          <div class="space-y-3 mt-2">
            <div class="flex justify-between border-b border-green-900/50 pb-2 items-center">
              <span class="text-green-700 uppercase tracking-widest text-[10px] flex-shrink-0">ADAPTER</span>
              <span class="text-right uppercase font-mono text-sm text-green-400 truncate ml-6">{@selected_device.network_interface.name}</span>
            </div>
            <div class="flex justify-between border-b border-green-900/50 pb-2 items-center">
              <span class="text-green-700 uppercase tracking-widest text-[10px] flex-shrink-0">IPV4</span>
              <span class="text-right uppercase font-mono text-sm text-green-400 truncate ml-6">{@selected_device.network_interface.ipv4.address}</span>
            </div>
            <div class="flex justify-between border-b border-green-900/50 pb-2 items-center">
              <span class="text-green-700 uppercase tracking-widest text-[10px] flex-shrink-0">MAC</span>
              <span class="text-right uppercase font-mono text-sm text-green-400 truncate ml-6">{@selected_device.network_interface.hw_address}</span>
            </div>
            <div class="flex justify-between border-b border-green-900/50 pb-2 items-center">
              <span class="text-green-700 uppercase tracking-widest text-[10px] flex-shrink-0">DHCP</span>
              <span class="text-right uppercase font-mono text-sm text-green-400 ml-6">
                <span class={["px-2 py-0.5 border text-[10px] uppercase font-bold tracking-widest", @selected_device.network_interface.ipv4.dhcp && "bg-green-900/40 border-green-500 text-green-400 shadow-[0_0_5px_rgba(34,197,94,0.3)]" || "bg-yellow-900/40 border-yellow-500 text-yellow-500"]}>
                  {format_dhcp(@selected_device.network_interface.ipv4.dhcp)}
                </span>
              </span>
            </div>
          </div>
        </div>

        <div
          :if={@selected_device.tab == "datetime"}
          class="flex flex-col border border-green-800 rounded-none bg-black p-6 relative group hover:border-green-500 transition-colors shadow-[0_0_15px_rgba(0,128,0,0.1)] w-full"
        >
          <div class="absolute top-0 right-0 w-2 h-2 border-t border-r border-green-500"></div>
          <div class="absolute bottom-0 left-0 w-2 h-2 border-b border-l border-green-500"></div>
          <h3 class="text-md font-bold text-green-500 mb-4 tracking-wider uppercase flex items-center border-b border-green-900/50 pb-2">
            > SYS.CLOCK.CFG
          </h3>
          <div class="space-y-3 mt-2">
            <div class="flex justify-between border-b border-green-900/50 pb-2 items-center">
              <span class="text-green-700 uppercase tracking-widest text-[10px] flex-shrink-0">TIMEZONE</span>
              <span class="text-right uppercase font-mono text-[10px] text-green-400 truncate ml-6">{@selected_device.device.system_date_time.time_zone.tz}</span>
            </div>
            <div class="flex justify-between border-b border-green-900/50 pb-2 items-center">
              <span class="text-green-700 uppercase tracking-widest text-[10px] flex-shrink-0">NTP</span>
              <span class="text-right uppercase font-mono text-sm text-green-400 ml-6">
                <span class={["px-2 py-0.5 border text-[10px] uppercase font-bold tracking-widest", @selected_device.ntp && "bg-green-900/40 border-green-500 text-green-400 shadow-[0_0_5px_rgba(34,197,94,0.3)]" || "bg-yellow-900/40 border-yellow-500 text-yellow-500"]}>
                  {yes_no(@selected_device.ntp)}
                </span>
              </span>
            </div>
            <div class="flex justify-between border-b border-green-900/50 pb-2 items-center">
              <span class="text-green-700 uppercase tracking-widest text-[10px] flex-shrink-0">DST_ACTIVE</span>
              <span class="text-right uppercase font-mono text-sm text-green-400 ml-6">
                <span class={["px-2 py-0.5 border text-[10px] uppercase font-bold tracking-widest", @selected_device.device.system_date_time.daylight_savings && "bg-green-900/40 border-green-500 text-green-400 shadow-[0_0_5px_rgba(34,197,94,0.3)]" || "bg-yellow-900/40 border-yellow-500 text-yellow-500"]}>
                  {yes_no(@selected_device.device.system_date_time.daylight_savings)}
                </span>
              </span>
            </div>
            <div class="flex justify-between border-b border-green-900/50 pb-2 items-center">
              <span class="text-green-700 uppercase tracking-widest text-[10px] flex-shrink-0">NTP_SERVER</span>
              <span class="text-right uppercase font-mono text-xs text-green-400 truncate ml-6">
                  {@selected_device.ntp && @selected_device.ntp.server || "N/A"}
              </span>
            </div>
          </div>
        </div>

        <div
          :if={@selected_device.tab == "streams"}
          class="flex flex-col border border-green-800 rounded-none bg-black p-6 relative group hover:border-green-500 transition-colors shadow-[0_0_15px_rgba(0,128,0,0.1)] w-full mb-6"
        >
          <div class="absolute top-0 left-0 w-2 h-2 border-t border-l border-green-500"></div>
          <div class="absolute bottom-0 right-0 w-2 h-2 border-b border-r border-green-500"></div>
          <h3 class="text-md font-bold text-green-500 mb-4 tracking-wider uppercase flex items-center border-b border-green-900/50 pb-2">
            > SYS.MEDIA.PROFILES
          </h3>
          <div class="mt-2">
            <.simple_form
              id="stream_selection_form"
              for={@selected_device.streams_form}
              phx-change="update-selected-stream"
            >
              <div class="grid grid-cols-1 md:grid-cols-2 gap-x-12 gap-y-6">
                <div class="border border-green-900/40 p-4 bg-green-900/5">
                  <div class="text-green-700 text-[10px] mb-2 tracking-widest uppercase font-bold">STREAM_0 (MAIN)</div>
                  <.input
                    field={@selected_device.streams_form[:main_stream]}
                    type="select"
                    name="main_stream"
                    options={stream_options(@selected_device.stream_profiles)}
                    class="bg-black border border-green-700 text-green-500 focus:ring-green-500 focus:border-green-500 font-mono text-sm uppercase rounded-none w-full"
                  />
                </div>

                <div class="border border-green-900/40 p-4 bg-green-900/5">
                  <div class="text-green-700 text-[10px] mb-2 tracking-widest uppercase font-bold">STREAM_1 (SUB)</div>
                  <.input
                    field={@selected_device.streams_form[:sub_stream]}
                    type="select"
                    name="sub_stream"
                    options={stream_options(@selected_device.stream_profiles)}
                    prompt="NONE"
                    class="bg-black border border-green-700 text-green-500 focus:ring-green-500 focus:border-green-500 font-mono text-sm uppercase rounded-none w-full"
                  />
                </div>
              </div>
            </.simple_form>
          </div>
        </div>
        <div :if={@selected_device.tab == "streams"} class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-8 mt-4">
          <TProNVRWeb.Onvif.StreamProfile.profile
            :for={{profile, idx} <- Enum.with_index(@selected_device.selected_profiles)}
            id={"#{profile.id}-#{idx}"}
            profile={profile}
          />
        </div>
      </div>
    </div>

    <.modal2 id="camera-authentication">
      <:header>Sign in</:header>
      <.simple_form id="auth-form" phx-submit="authenticate-device" for={@auth_form} class="space-y-4">
        <.input
          field={@auth_form[:username]}
          name="username"
          id="username"
          placeholder="admin"
          label="Your username"
          required
        />
        <.input
          field={@auth_form[:password]}
          type="password"
          name="password"
          id="password"
          placeholder="••••••••"
          label="Your password"
          class="bg-black border border-green-700 text-white text-sm rounded-lg focus:ring-green-500 focus:border-green-500 block w-full p-2.5 dark:bg-green-800 dark:border-green-600 dark:placeholder-white/50 dark:text-white"
          required
        />
        <div class="flex items-center space-x-5">
          <.button
            type="button"
            class="w-full bg-black border dark:border-green-700"
            phx-click={hide_modal2("camera-authentication")}
          >
            Cancel
          </.button>
          <.button class="w-full" type="submit" phx-disable-with="Authenticating...">Connect</.button>
        </div>
      </.simple_form>
    </.modal2>
    """
  end

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign_discover_settings(%DiscoverSettings{timeout: 2})
      |> assign(devices: [], auth_form: to_form(%{"username" => nil, "password" => nil}))
      |> assign(selected_device: nil)

    {:ok, socket}
  end

  def handle_event("discover-settings", params, socket) do
    case DiscoverSettings.to_struct(params) do
      {:ok, settings} ->
        {:noreply, assign_discover_settings(socket, settings)}

      {:error, changeset} ->
        {:noreply, assign(socket, discover_form: to_form(changeset))}
    end
  end

  def handle_event("discover", _params, socket) do
    settings = socket.assigns.discover_settings

    devices =
      TProNVR.Devices.Onvif.discover(
        ip_address: settings.ip_address,
        timeout: :timer.seconds(settings.timeout)
      )
      |> Enum.map(
        &%CameraDetails{id: &1.device_ip, probe: &1, name: scope_value(&1.scopes, "name")}
      )

    {:noreply, assign(socket, devices: devices, selected_device: nil)}
  end

  def handle_event("authenticate-device", params, socket) do
    devices = socket.assigns.devices
    idx = Enum.find_index(devices, &(&1.id == params["id"]))

    if idx != nil do
      camera_details = Enum.at(devices, idx)

      case ExOnvif.Device.init(camera_details.probe, params["username"], params["password"]) do
        {:ok, onvif_device} ->
          camera_details =
            %CameraDetails{camera_details | device: onvif_device}
            |> get_network_interface()
            |> get_ntp()
            |> get_stream_profiles()
            |> set_streams_form()

          socket =
            socket
            |> push_event("js-exec", %{to: "#camera-authentication", attr: "data-cancel"})
            |> assign(devices: List.replace_at(devices, idx, camera_details))

          {:noreply, socket}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Invalid credentials")}
      end
    else
      {:noreply, put_flash(socket, :error, "could not find device with id: #{params["id"]}")}
    end
  end

  def handle_event("show-details", params, socket) do
    devices = socket.assigns.devices

    case Enum.find(devices, &(&1.id == params["id"])) do
      nil -> {:noreply, socket}
      device -> {:noreply, assign(socket, selected_device: device)}
    end
  end

  def handle_event("switch-tab", %{"tab" => tab}, socket) do
    device = %{socket.assigns.selected_device | tab: tab}
    {:noreply, assign(socket, selected_device: device)}
  end

  def handle_event("update-selected-stream", params, socket) do
    selected_device = socket.assigns.selected_device
    stream_profiles = selected_device.stream_profiles || []

    main_stream = Enum.find(stream_profiles, &(&1.id == params["main_stream"]))
    sub_stream = Enum.find(stream_profiles, &(&1.id == params["sub_stream"]))

    selected_device = %{
      selected_device
      | selected_profiles: Enum.reject([main_stream, sub_stream], &is_nil/1)
    }

    {:noreply, assign(socket, selected_device: selected_device)}
  end

  def handle_event("add-device", _params, socket) do
    selected_device = socket.assigns.selected_device
    %{username: username, password: password} = selected_device.device
    manufacturer = selected_device.device.manufacturer || ""
    
    # Get MAC address for device identification
    mac = selected_device.network_interface && selected_device.network_interface.hw_address
    
    # Use direct RTSP mode - native Membrane pipelines handle streams
    # Credentials are stored separately and Device.streams/1 injects them into URIs
    rtsp_mode = :direct

    stream_config =
      case selected_device.selected_profiles do
        [main_stream, sub_stream] ->
          # Store raw RTSP URIs (without credentials) - Device.streams/1 adds credentials
          %{
            stream_uri: main_stream.stream_uri,
            snapshot_uri: main_stream.snapshot_uri,
            profile_token: main_stream.id,
            sub_stream_uri: sub_stream.stream_uri,
            sub_snapshot_uri: sub_stream.snapshot_uri,
            sub_profile_token: sub_stream.id
          }

        [main_stream] ->
          %{
            stream_uri: main_stream.stream_uri,
            snapshot_uri: main_stream.snapshot_uri,
            profile_token: main_stream.id
          }

        _other ->
          %{}
      end

    socket
    |> put_flash(:device_params, %{
      name: selected_device.name,
      type: :ip,
      vendor: manufacturer,
      model: selected_device.device.model,
      mac: mac,
      url: selected_device.device.address,
      rtsp_mode: rtsp_mode,
      stream_config: stream_config,
      credentials: %{username: username, password: password}
    })
    |> redirect(to: ~p"/devices/new")
    |> then(&{:noreply, &1})
  end

  def handle_event("auto-configure", _params, socket) do
    camera_details = socket.assigns.selected_device
    devices = socket.assigns.devices

    _auto_config_result = Devices.Onvif.auto_configure(camera_details.device)
    camera_details = camera_details |> get_stream_profiles() |> set_streams_form()

    idx = Enum.find_index(devices, &(&1.id == camera_details.id))
    devices = List.replace_at(devices, idx, camera_details)

    socket
    |> assign(selected_device: camera_details, devices: devices)
    |> put_flash(:info, "Camera configured successfully")
    |> then(&{:noreply, &1})
  end

  defp assign_discover_settings(socket, settings) do
    discover_form = to_form(DiscoverSettings.create_changeset(settings))
    assign(socket, discover_settings: settings, discover_form: discover_form)
  end

  defp get_network_interface(camera_details) do
    case ExOnvif.Devices.get_network_interfaces(camera_details.device) do
      {:ok, interfaces} ->
        %{camera_details | network_interface: NetworkInterface.from_onvif(List.first(interfaces))}

      {:error, reason} ->
        Logger.error("Failed to get network interfaces for camera #{inspect(reason)}")
        camera_details
    end
  end

  defp get_ntp(%{device: %{system_date_time: %{date_time_type: :ntp}}} = camera_details) do
    case ExOnvif.Devices.get_ntp(camera_details.device) do
      {:ok, ntp} ->
        %{camera_details | ntp: NTP.from_onvif(ntp)}

      {:error, reason} ->
        Logger.error("Failed to get ntp settings for camera #{inspect(reason)}")
        camera_details
    end
  end

  defp get_ntp(camera_details), do: camera_details

  defp get_stream_profiles(%{device: %{media_ver20_service_path: nil}} = camera_details) do
    Logger.info("[OnvifDiscovery] Camera does not support Media2, falling back to Media v1.0")
    get_stream_profiles_media1(camera_details)
  end

  defp get_stream_profiles(camera_details) do
    case ExOnvif.Media2.get_profiles(camera_details.device) do
      {:ok, profiles} ->
        profiles =
          profiles
          |> Enum.map(&StreamProfile.from_onvif/1)
          |> Enum.sort_by(& &1.name, fn name1, name2 ->
            main? = name1 == "cvr_main"
            sub? = name1 == "cvr_sub"
            main? or (sub? and not main?) or name2 not in ["cvr_main", "cvr_sub"]
          end)

        %{camera_details | stream_profiles: profiles}
        |> get_stream_uris()

      {:error, reason} ->
        Logger.error("Failed to get stream profiles for camera #{inspect(reason)}")
        camera_details
    end
  end

  defp get_stream_uris(%{device: device} = camera_details) do
    profiles =
      Enum.map(camera_details.stream_profiles, fn profile ->
        with {:ok, stream_uri} <- ExOnvif.Media2.get_stream_uri(device, profile.id),
             {:ok, snapshot_uri} <- ExOnvif.Media2.get_snapshot_uri(device, profile.id) do
          %{profile | stream_uri: stream_uri, snapshot_uri: snapshot_uri}
        else
          _error ->
            profile
        end
      end)

    %{camera_details | stream_profiles: profiles}
  end

  # Media v1.0 fallback for cameras that don't support Media2 (e.g., Tapo)
  defp get_stream_profiles_media1(%{device: %{media_ver10_service_path: nil}} = camera_details) do
    Logger.warning("[OnvifDiscovery] Camera does not support Media v1.0 either")
    camera_details
  end

  defp get_stream_profiles_media1(camera_details) do
    case ExOnvif.Media.get_profiles(camera_details.device) do
      {:ok, profiles} ->
        profiles =
          profiles
          |> Enum.map(&StreamProfile.from_onvif/1)
          |> Enum.sort_by(& &1.name, fn name1, name2 ->
            main? = name1 == "cvr_main"
            sub? = name1 == "cvr_sub"
            main? or (sub? and not main?) or name2 not in ["cvr_main", "cvr_sub"]
          end)

        %{camera_details | stream_profiles: profiles}
        |> get_stream_uris_media1()

      {:error, reason} ->
        Logger.error("[OnvifDiscovery] Failed to get Media1 stream profiles: #{inspect(reason)}")
        camera_details
    end
  end

  defp get_stream_uris_media1(%{device: _device, stream_profiles: nil} = camera_details) do
    camera_details
  end

  defp get_stream_uris_media1(%{device: device} = camera_details) do
    profiles =
      Enum.map(camera_details.stream_profiles, fn profile ->
        Logger.info("[OnvifDiscovery] Fetching stream URI for profile: #{profile.id}")
        
        stream_uri_result = ExOnvif.Media.get_stream_uri(device, profile.id)
        snapshot_uri_result = ExOnvif.Media.get_snapshot_uri(device, profile.id)
        
        Logger.info("[OnvifDiscovery] Stream URI result: #{inspect(stream_uri_result)}")
        Logger.info("[OnvifDiscovery] Snapshot URI result: #{inspect(snapshot_uri_result)}")
        
        # Get stream URI (required)
        profile = case stream_uri_result do
          {:ok, stream_uri} -> %{profile | stream_uri: stream_uri}
          _ -> 
            Logger.warning("[OnvifDiscovery] Failed to get stream URI for #{profile.id}")
            profile
        end
        
        # Get snapshot URI (optional - Tapo cameras don't support this)
        case snapshot_uri_result do
          {:ok, snapshot_uri} -> %{profile | snapshot_uri: snapshot_uri}
          _ -> profile
        end
      end)

    %{camera_details | stream_profiles: profiles}
  end

  # Handle nil stream_profiles (camera doesn't support Media2)
  defp set_streams_form(%{stream_profiles: nil} = camera_details) do
    # For cameras without Media2 support (like Tapo), we'll need manual RTSP URLs
    streams_form = to_form(%{"main_stream" => nil, "sub_stream" => nil})
    %{camera_details | streams_form: streams_form, selected_profiles: []}
  end

  defp set_streams_form(%{stream_profiles: profiles} = camera_details) do
    main_stream = Enum.at(profiles, 0)
    sub_stream = Enum.at(profiles, 1)

    streams_form =
      to_form(%{
        "main_stream" => main_stream && main_stream.id,
        "sub_stream" => sub_stream && sub_stream.id
      })

    selected_profiles = Enum.reject([main_stream, sub_stream], &is_nil/1)

    %{camera_details | streams_form: streams_form, selected_profiles: selected_profiles}
  end

  # view functions


  defp scope_value(scopes, scope_key) do
    regex = ~r[^onvif://www.onvif.org/(name|hardware)/(.*)]

    scopes
    |> Enum.flat_map(&Regex.scan(regex, &1, capture: :all_but_first))
    |> Enum.find(fn [key, _value] -> key == scope_key end)
    |> case do
      [_key, value] -> URI.decode(value)
      _other -> nil
    end
  end

  defp selected_tab(tab, tab), do: ["bg-green-900/40", "border-green-500", "text-green-400", "shadow-inner"]
  defp selected_tab(_, _), do: ["border-transparent", "text-green-700"]

  defp format_dhcp(true), do: "Enabled"
  defp format_dhcp(false), do: "Disabled"

  defp yes_no(nil), do: "No"
  defp yes_no(false), do: "No"
  defp yes_no(_other), do: "Yes"

  defp stream_options(nil), do: []

  defp stream_options(stream_profiles) do
    Enum.map(stream_profiles, &{&1.name, &1.id})
  end
end
