defmodule TProNVRWeb.Components.Sidebar do
  @moduledoc false

  use TProNVRWeb, :live_component

  attr :current_user, :map, required: false
  attr :current_path, :string, default: nil

  def sidebar(assigns) do
    role = assigns.current_user && assigns.current_user.role

    assigns =
      groups()
      |> Enum.map(&filter_group_by_role(&1, role))
      |> Enum.reject(&(&1 == []))
      |> Enum.with_index()
      |> then(&Map.put(assigns, :groups, &1))

    ~H"""
    <aside
      id="logo-sidebar"
      class="fixed top-0 left-0 z-40 h-screen bg-black border-r border-green-900/50 sm:translate-x-0 font-mono text-sm tracking-widest uppercase sidebar-expanded transition-all duration-300"
      aria-label="Sidebar"
    >
      <div class="flex flex-col h-full bg-black">
        <%!-- Logo Section --%>
        <a href="/" class="flex flex-col items-center justify-center py-4 border-b border-green-900/50 flex-shrink-0 group relative">
          <div class="absolute top-0 right-0 w-2 h-2 border-t border-r border-green-500"></div>
          <div class="absolute bottom-0 left-0 w-2 h-2 border-b border-l border-green-500"></div>
          <div class="flex items-center justify-center w-10 h-10 bg-green-900/10 border border-green-500/50 group-hover:bg-green-500 group-hover:text-black transition-all shadow-[0_0_10px_rgba(34,197,94,0.1)] group-hover:shadow-[0_0_15px_rgba(34,197,94,0.4)]">
            <.icon name="hero-eye-solid" class="w-6 h-6 text-green-500 group-hover:text-black transition-colors" />
          </div>
          <span class="sidebar-label text-lg font-bold tracking-widest uppercase mt-1">
            <span class="text-white">OMNI</span><span class="text-green-500">SENSE</span>
          </span>
        </a>

        <%!-- Toggle Button --%>
        <button
          id="sidebar-toggle-btn"
          type="button"
          onclick="window.toggleSidebar()"
          class="flex items-center justify-center w-full py-2 text-green-500 hover:bg-green-900/20 hover:text-green-400 transition-all border-b border-green-900/50"
          title="Toggle sidebar"
        >
          <.icon name="hero-chevron-double-left-solid" class="w-4 h-4 text-green-500 group-hover:text-green-400 sidebar-toggle-icon transition-transform duration-300" />
        </button>

        <%!-- Navigation links --%>
        <div class="flex-1 overflow-y-auto px-2 py-3 space-y-1">
          <.sidebar_group
            :for={{group, index} <- @groups}
            items={group}
            current_path={@current_path}
            border={index > 0}
          />
        </div>

        <%!-- Account & Notifications --%>
        <div class="px-5 py-4 border-t border-green-900/50 flex-shrink-0 bg-black relative sidebar-account-panel">
          <div class="absolute top-0 right-0 w-2 h-2 border-t border-r border-green-500"></div>
          
          <div class="flex items-center justify-between mb-4 sidebar-account-flex">
            <%!-- User Dropdown Trigger --%>
            <div class="flex items-center gap-3 relative cursor-pointer group" data-dropdown-toggle="dropdown-user-sidebar">
              <div class="p-0.5 border border-green-500/50 bg-black group-hover:border-green-500 transition-colors shadow-inner">
                <img class="w-10 h-10 object-cover grayscale opacity-80 group-hover:grayscale-0 group-hover:opacity-100 transition-all" src="https://media.npr.org/assets/img/2021/08/11/gettyimages-1279899488_wide-f3860ceb0ef19643c335cb34df3fa1de166e2761-s1100-c50.jpg" alt="user photo" />
              </div>
              <div class="sidebar-user-info flex flex-col">
                <span class="text-xs font-bold text-green-500 leading-tight tracking-wider uppercase">{if @current_user, do: @current_user.last_name, else: "GUEST_OP"}</span>
                <span class="text-[10px] text-green-700 truncate max-w-[100px] tracking-widest uppercase">{if @current_user, do: @current_user.email, else: "UNAUTHORIZED_LVL1"}</span>
              </div>
              
              <%!-- User Dropdown Menu --%>
              <div class="z-50 hidden absolute bottom-full left-0 mb-3 w-48 text-base list-none bg-black border border-green-500 rounded-none shadow-[0_0_15px_rgba(0,128,0,0.15)]" id="dropdown-user-sidebar">
                <ul class="py-1 font-mono tracking-widest text-xs uppercase" role="none">
                  <li><.link href={~p"/users/settings"} class="block px-4 py-2 text-green-500 hover:bg-green-900/40 hover:text-green-400 border-l-2 border-transparent hover:border-green-500 transition-all">CÀI ĐẶT</.link></li>
                  <li><.link href={~p"/users/logout"} method="delete" class="block px-4 py-2 text-green-500 hover:bg-green-900/40 hover:text-green-400 border-l-2 border-transparent hover:border-green-500 transition-all">ĐĂNG XUẤT</.link></li>
                </ul>
              </div>
            </div>

            <%!-- Notification Bell --%>
            <div class="relative" id="sidebar-notification-wrapper">
              <button type="button" class="relative p-2 text-green-500 bg-black border border-green-900/40 hover:border-green-500 hover:bg-green-900/20 transition-all focus:outline-none shadow-inner" onclick="document.getElementById('sidebar-notification-panel').classList.toggle('hidden')">
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9" /></svg>
                <span id="notification-badge" class="hidden absolute top-0 -right-1 bg-green-500 text-black text-[9px] font-bold rounded-none w-4 h-4 flex items-center justify-center tracking-tighter">0</span>
              </button>
              
              <%!-- Notification Panel --%>
              <div id="sidebar-notification-panel" class="hidden absolute bottom-0 left-full ml-2 w-72 max-h-[75vh] bg-black border border-green-500 shadow-[0_0_15px_rgba(34,197,94,0.15)] overflow-hidden z-[9999]" style="transform: translateY(1rem);">
                <div class="flex items-center justify-between px-4 py-2 border-b border-green-500 bg-green-900/20">
                  <span class="text-[10px] font-bold tracking-widest text-green-500 uppercase">THÔNG BÁO</span>
                  <button class="text-[10px] text-green-700 hover:text-green-400 uppercase tracking-widest font-bold" onclick="window._clearNotificationLog && window._clearNotificationLog()">XÓA TẤT CẢ</button>
                </div>
                <div id="notification-log-list" class="overflow-y-auto max-h-[calc(70vh-40px)]">
                  <div class="px-4 py-6 text-center text-green-700 text-xs font-mono uppercase tracking-widest" id="notification-log-empty">KHÔNG CÓ THÔNG BÁO</div>
                </div>
              </div>
            </div>
          </div>

          <%!-- Version Info --%>
          <ul class="sidebar-version-info pt-3 border-t border-green-900/50 space-y-1 text-center font-mono">
            <li class="font-bold text-green-700 text-[10px] tracking-widest uppercase">
              VERSION.{Application.spec(:tpro_nvr, :vsn)}
            </li>
            <li class="text-[9px] text-green-900 tracking-widest uppercase">
              PRODUCT OF CVEDIX
            </li>
          </ul>
        </div>
      </div>
    </aside>

    <script>
      // Sidebar toggle with localStorage persistence (default: collapsed)
      window.toggleSidebar = function() {
        const sidebar = document.getElementById('logo-sidebar');
        const isCollapsed = sidebar.classList.toggle('sidebar-collapsed');
        sidebar.classList.toggle('sidebar-expanded', !isCollapsed);
        localStorage.setItem('sidebar-collapsed', isCollapsed ? 'true' : 'false');
        // Update main content margin
        document.querySelectorAll('.main-content-offset').forEach(el => {
          el.style.marginLeft = isCollapsed ? '64px' : '256px';
        });
        window.dispatchEvent(new Event('resize'));
      };
      // Initialize sidebar state on load
      (function() {
        const sidebar = document.getElementById('logo-sidebar');
        if (!sidebar) return;
        const stored = localStorage.getItem('sidebar-collapsed');
        // Default to expanded if no stored preference
        const isCollapsed = stored === null ? false : stored === 'true';
        if (isCollapsed) {
          sidebar.classList.add('sidebar-collapsed');
          sidebar.classList.remove('sidebar-expanded');
        } else {
          sidebar.classList.remove('sidebar-collapsed');
          sidebar.classList.add('sidebar-expanded');
        }
      })();
    </script>
    """
  end

  attr :items, :list, required: true
  attr :current_path, :string, default: nil
  attr :border, :boolean, default: false

  defp sidebar_group(assigns) do
    class =
      case assigns[:border] do
        true -> "pt-3 mt-3 border-t border-green-900/50"
        _ -> ""
      end

    assigns = assign(assigns, :class, class)

    ~H"""
    <ul class={"space-y-1 font-mono tracking-widest text-xs uppercase #{@class}"}>
      <.sidebar_item
        :for={item <- @items}
        label={item.label}
        icon={item.icon}
        href={item[:href]}
        target={item[:target]}
        children={item[:children] || []}
        role={item[:role]}
        current_path={@current_path}
      />
    </ul>
    """
  end

  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :href, :string, default: nil
  attr :target, :string, default: nil
  attr :children, :list, default: []
  attr :current_path, :string, default: nil
  attr :is_active, :boolean, default: false
  attr :role, :atom, default: nil

  defp sidebar_item(assigns) do
    active? = active?(assigns.href, assigns.current_path)
    has_active_child = has_active_child?(assigns.children, assigns.current_path)

    assigns =
      assigns
      |> assign(:is_active, active?)
      |> assign(:has_active_child, has_active_child)
      |> assign(:link_classes, link_classes(active?))
      |> assign(:icon_classes, icon_classes(active?))
      |> assign(:menu_classes, menu_classes(has_active_child))

    ~H"""
    <li>
      <button
        :if={@children != []}
        type="button"
        class={["flex items-center justify-between w-full p-2 rounded-none transition-all font-bold tracking-widest text-xs uppercase",
                if(@has_active_child, do: "bg-green-500 text-black border border-green-500 shadow-[0_0_10px_rgba(34,197,94,0.3)]", else: "text-green-500 border border-transparent hover:border-green-500/50 hover:bg-green-900/20")]}
        aria-controls={"dropdown-#{@label}"}
        data-collapse-toggle={"dropdown-#{@label}"}
        aria-expanded={@has_active_child}
      >
        <div class="flex items-center">
          <.icon name={@icon} class={["w-5 h-5", if(@has_active_child, do: "text-black", else: "text-green-500")]} />
          <span class="flex-1 ml-3 whitespace-nowrap">{@label}</span>
        </div>
        <.icon name="hero-chevron-down-solid" class={["w-5 h-5", if(@has_active_child, do: "text-black", else: "text-green-500")]} />
      </button>
      <ul id={"dropdown-#{@label}"} class={[@menu_classes, "border-l border-green-900/50 pl-2 ml-4"]}>
        <.sidebar_item
          :for={child <- @children}
          label={child[:label]}
          icon={child[:icon]}
          href={child[:href]}
          target={child[:target]}
          children={child[:children] || []}
          current_path={@current_path}
          role={child[:role]}
        />
      </ul>
      <.link :if={@children == []} href={@href} target={@target} class={@link_classes}>
        <.icon name={@icon} class={@icon_classes} />
        <span class="ml-3 truncate">{@label}</span>
      </.link>
    </li>
    """
  end

  if Application.compile_env(:tpro_nvr, :nerves_routes) do
    defp groups do
      [
        [
          %{label: "Tổng Quan", icon: "hero-tv-solid", href: ~p"/dashboard"},
          %{
            label: "Xem Trực Tiếp",
            icon: "hero-video-camera-solid",
            children: [
              %{label: "Lưới Camera", icon: "hero-squares-2x2-solid", href: ~p"/live-view"},
              %{label: "Bản Đồ E-Map", icon: "hero-map-solid", href: ~p"/emap"}
            ]
          },
          %{label: "Phát Lại", icon: "hero-clock-solid", href: ~p"/playback"},
          %{label: "Bản Ghi", icon: "hero-film-solid", href: ~p"/recordings"},
          %{
            label: "Sự Kiện",
            icon: "hero-camera-solid",
            children: [
              %{label: "Sự Kiện Chung", icon: "hero-code-bracket", href: ~p"/events/generic"},
              %{label: "Biển Số Xe", icon: "hero-truck-solid", href: ~p"/events/lpr"},
              %{label: "Nhận Diện Khuôn Mặt", icon: "hero-user-circle-solid", href: ~p"/events/face"},
              %{label: "Sự Kiện AI", icon: "hero-bolt-solid", href: ~p"/events/ai-events"},
              %{label: "Bản Đồ Nhiệt AI", icon: "hero-fire-solid", href: ~p"/events/ai-heatmap"},
              %{
                label: "Biểu Đồ Vượt Tuyến",
                icon: "hero-chart-bar-solid",
                href: ~p"/events/ai-tripwire-chart"
              },
              %{
                label: "Báo Cáo Lảng Vảng",
                icon: "hero-clock-solid",
                href: ~p"/events/ai-loitering-report"
              }
            ]
          },
          %{label: "Phân Tích AI", icon: "hero-sparkles-solid", href: ~p"/analytics/instances"}
        ],
        [
          %{label: "Thiết Bị", icon: "hero-video-camera-solid", href: ~p"/devices"},
          %{label: "Người Dùng", icon: "hero-users-solid", href: ~p"/users", role: :admin},
          %{
            label: "Khám Phá ONVIF",
            icon: "hero-magnifying-glass-circle",
            href: ~p"/onvif-discovery",
            role: :admin
          }
        ],
        [
          %{
            label: "Lưu Trữ Từ Xa",
            icon: "hero-circle-stack-solid",
            href: ~p"/remote-storages",
            role: :admin
          }
        ],
        [
          %{
            label: "Cài Đặt Hệ Thống",
            icon: "hero-cog-6-tooth-solid",
            href: ~p"/nerves/system-settings",
            role: :admin
          }
        ],
        [
          %{
            label: "Bảng Điều Khiển",
            icon: "hero-chart-bar-solid",
            href: ~p"/live-dashboard",
            target: "_blank"
          },
          %{
            label: "Tài Liệu API",
            icon: "hero-document-solid",
            href: "/swagger.html",
            target: "_blank"
          },
          %{
            label: "Giới Thiệu",
            icon: "hero-information-circle-solid",
            href: ~p"/about"
          }
        ]
      ]
    end
  else
    defp groups do
      [
        [
          %{label: "Tổng Quan", icon: "hero-tv-solid", href: ~p"/dashboard"},
          %{
            label: "Xem Trực Tiếp",
            icon: "hero-video-camera-solid",
            children: [
              %{label: "Lưới Camera", icon: "hero-squares-2x2-solid", href: ~p"/live-view"},
              %{label: "Bản Đồ E-Map", icon: "hero-map-solid", href: ~p"/emap"}
            ]
          },
          %{label: "Phát Lại", icon: "hero-clock-solid", href: ~p"/playback"},
          %{label: "Bản Ghi", icon: "hero-film-solid", href: ~p"/recordings"},
          %{
            label: "Sự Kiện",
            icon: "hero-camera-solid",
            children: [
              %{label: "Sự Kiện Chung", icon: "hero-code-bracket", href: ~p"/events/generic"},
              %{label: "Biển Số Xe", icon: "hero-truck-solid", href: ~p"/events/lpr"},
              %{label: "Nhận Diện Khuôn Mặt", icon: "hero-user-circle-solid", href: ~p"/events/face"},
              %{label: "Sự Kiện AI", icon: "hero-bolt-solid", href: ~p"/events/ai-events"},
              %{label: "Bản Đồ Nhiệt AI", icon: "hero-fire-solid", href: ~p"/events/ai-heatmap"},
              %{
                label: "Biểu Đồ Vượt Tuyến",
                icon: "hero-chart-bar-solid",
                href: ~p"/events/ai-tripwire-chart"
              },
              %{
                label: "Báo Cáo Lảng Vảng",
                icon: "hero-clock-solid",
                href: ~p"/events/ai-loitering-report"
              }
            ]
          },
          %{label: "Phân Tích AI", icon: "hero-sparkles-solid", href: ~p"/analytics/instances"}
        ],
        [
          %{label: "Thiết Bị", icon: "hero-video-camera-solid", href: ~p"/devices"},
          %{label: "Người Dùng", icon: "hero-users-solid", href: ~p"/users", role: :admin},
          %{
            label: "Tìm Kiếm Thiết Bị",
            icon: "hero-magnifying-glass-circle",
            href: ~p"/onvif-discovery",
            role: :admin
          },
          %{
            label: "Đồng Bộ Commander",
            icon: "hero-signal",
            href: ~p"/commander-sync"
          }
        ],
        [
          %{
            label: "Lưu Trữ Từ Xa",
            icon: "hero-circle-stack-solid",
            href: ~p"/remote-storages",
            role: :admin
          }
        ],
        [
          %{
            label: "Bảng Điều Khiển",
            icon: "hero-chart-bar-solid",
            href: ~p"/live-dashboard",
            target: "_blank"
          },
          %{
            label: "Tài Liệu API",
            icon: "hero-document-solid",
            href: "/swagger.html",
            target: "_blank"
          },
          %{
            label: "Giới Thiệu",
            icon: "hero-information-circle-solid",
            href: ~p"/about"
          }
        ]
      ]
    end
  end

  defp filter_group_by_role(group, role) do
    Enum.reject(group, fn
      %{children: children} -> filter_group_by_role(children, role) == []
      item -> not is_nil(item[:role]) and item[:role] != role
    end)
  end

  defp active?(nil, _), do: false
  defp active?(_, nil), do: false
  defp active?(href, current_path), do: String.starts_with?(current_path, href)

  defp has_active_child?(children, current_path) do
    Enum.any?(children, fn child ->
      active?(child[:href], current_path)
    end)
  end

  defp link_classes(true = _active),
    do: "flex w-full items-center p-2 rounded-none border border-green-500 bg-green-500 text-black font-bold tracking-widest text-xs uppercase shadow-[0_0_10px_rgba(34,197,94,0.3)] transition-all"

  defp link_classes(false = _active),
    do: "flex w-full items-center p-2 text-green-500 rounded-none border border-transparent hover:border-green-500/50 hover:bg-green-900/20 font-bold tracking-widest text-xs uppercase transition-all"

  defp icon_classes(true = _active), do: "w-5 h-5 text-black"
  defp icon_classes(false = _active), do: "w-5 h-5 text-green-500"

  defp menu_classes(true = _active), do: "py-1 space-y-1 px-2 block mt-1"
  defp menu_classes(false = _active), do: "py-1 space-y-1 px-2 hidden mt-1"
end
