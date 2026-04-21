defmodule TProNVRWeb.Components.Sidebar do
  @moduledoc false

  use TProNVRWeb, :live_component

  attr :current_user, :map, required: false
  attr :current_path, :string, default: nil

  def sidebar(assigns) do
    user = assigns.current_user

    assigns =
      groups()
      |> Enum.map(&filter_group_by_access(&1, user))
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
        <%!-- Logo Section (click to toggle sidebar) --%>
        <button type="button" onclick="window.toggleSidebar()" class="flex flex-col items-center justify-center py-4 border-b border-green-900/50 flex-shrink-0 group relative w-full cursor-pointer" title="Thu gọn / Mở rộng">
          <div class="absolute top-0 right-0 w-2 h-2 border-t border-r border-green-500"></div>
          <div class="absolute bottom-0 left-0 w-2 h-2 border-b border-l border-green-500"></div>
          <div class="flex items-center justify-center w-10 h-10 bg-green-900/10 border border-green-500/50 group-hover:bg-green-500 group-hover:text-black transition-all shadow-[0_0_10px_rgba(34,197,94,0.1)] group-hover:shadow-[0_0_15px_rgba(34,197,94,0.4)]">
            <.icon name="hero-eye-solid" class="w-6 h-6 text-green-500 group-hover:text-black transition-colors" />
          </div>
          <span class="sidebar-label text-lg font-bold tracking-widest uppercase mt-1">
            <span class="text-white">OMNI</span><span class="text-green-500">SENSE</span>
          </span>
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
      // Sidebar toggle with localStorage persistence
      window.toggleSidebar = function() {
        const sidebar = document.getElementById('logo-sidebar');
        if (!sidebar) return;
        const isCollapsed = sidebar.classList.toggle('sidebar-collapsed');
        sidebar.classList.toggle('sidebar-expanded', !isCollapsed);
        localStorage.setItem('sidebar-collapsed', isCollapsed ? 'true' : 'false');
        document.querySelectorAll('.main-content-offset').forEach(el => {
          el.style.marginLeft = isCollapsed ? '64px' : '256px';
        });
        window.dispatchEvent(new Event('resize'));
      };

      // Sidebar menu dropdown toggle with localStorage persistence
      window.toggleSidebarMenu = function(menuId) {
        const menu = document.getElementById(menuId);
        if (!menu) return;
        const isHidden = menu.classList.contains('hidden');
        if (isHidden) {
          menu.classList.remove('hidden');
          menu.classList.add('block');
        } else {
          menu.classList.add('hidden');
          menu.classList.remove('block');
        }
        // Persist open menus
        const openMenus = JSON.parse(localStorage.getItem('sidebar-open-menus') || '[]');
        if (isHidden) {
          if (!openMenus.includes(menuId)) openMenus.push(menuId);
        } else {
          const idx = openMenus.indexOf(menuId);
          if (idx > -1) openMenus.splice(idx, 1);
        }
        localStorage.setItem('sidebar-open-menus', JSON.stringify(openMenus));
      };

      // Apply sidebar state from localStorage
      window._applySidebarState = function() {
        const sidebar = document.getElementById('logo-sidebar');
        if (!sidebar) return;
        const isCollapsed = localStorage.getItem('sidebar-collapsed') === 'true';
        if (isCollapsed) {
          sidebar.classList.add('sidebar-collapsed');
          sidebar.classList.remove('sidebar-expanded');
        } else {
          sidebar.classList.remove('sidebar-collapsed');
          sidebar.classList.add('sidebar-expanded');
        }
        document.querySelectorAll('.main-content-offset').forEach(el => {
          el.style.marginLeft = isCollapsed ? '64px' : '256px';
        });

        // Restore open menu states
        const openMenus = JSON.parse(localStorage.getItem('sidebar-open-menus') || '[]');
        document.querySelectorAll('[id^="dropdown-"]').forEach(menu => {
          if (openMenus.includes(menu.id)) {
            menu.classList.remove('hidden');
            menu.classList.add('block');
          }
        });
      };

      // Apply on initial load
      window._applySidebarState();

      // Re-apply after LiveView navigations
      window.addEventListener('phx:page-loading-stop', () => {
        window._applySidebarState();
      });
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
        onclick={"window.toggleSidebarMenu('dropdown-#{@label}')"}
        aria-expanded={@has_active_child}
      >
        <div class="flex items-center">
          <.icon name={@icon} class={["w-5 h-5", if(@has_active_child, do: "text-black", else: "text-green-500")]} />
          <span class="flex-1 ml-3 whitespace-nowrap">{@label}</span>
        </div>
        <.icon name="hero-chevron-down-solid" class={["w-5 h-5", if(@has_active_child, do: "text-black", else: "text-green-500")]} />
      </button>
      <ul id={"dropdown-#{@label}"} phx-update="ignore" class={[@menu_classes, "border-l border-green-900/50 pl-2 ml-4"]}>
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
          %{label: "Tổng Quan", icon: "hero-tv-solid", href: ~p"/dashboard", feature: "dashboard"},
          %{
            label: "Xem Trực Tiếp",
            icon: "hero-video-camera-solid",
            feature: "devices",
            children: [
              %{label: "Lưới Camera", icon: "hero-squares-2x2-solid", href: ~p"/live-view"},
              %{label: "Bản Đồ E-Map", icon: "hero-map-solid", href: ~p"/emap"}
            ]
          },
          %{label: "Phát Lại", icon: "hero-clock-solid", href: ~p"/playback", feature: "playback"},
          %{label: "Bản Ghi", icon: "hero-film-solid", href: ~p"/recordings", feature: "playback"},
          %{
            label: "Sự Kiện",
            icon: "hero-camera-solid",
            feature: "events",
            children: [
              %{label: "Sự Kiện Chung", icon: "hero-code-bracket", href: ~p"/events/generic", feature: "events.generic"},
              %{label: "Biển Số Xe", icon: "hero-truck-solid", href: ~p"/events/lpr", feature: "events.lpr"},
              %{label: "Nhận Diện Khuôn Mặt", icon: "hero-user-circle-solid", href: ~p"/events/face", feature: "events.face"},
              %{label: "Sự Kiện AI", icon: "hero-bolt-solid", href: ~p"/events/ai-events", feature: "events.ai"},
              %{label: "Bản Đồ Nhiệt AI", icon: "hero-fire-solid", href: ~p"/events/ai-heatmap", feature: "events.heatmap"},
              %{
                label: "Biểu Đồ Vượt Tuyến",
                icon: "hero-chart-bar-solid",
                href: ~p"/events/ai-tripwire-chart",
                feature: "events.tripwire"
              },
              %{
                label: "Báo Cáo Lảng Vảng",
                icon: "hero-clock-solid",
                href: ~p"/events/ai-loitering-report",
                feature: "events.loitering"
              },
              %{
                label: "Báo Cáo Thuộc Tính",
                icon: "hero-tag-solid",
                href: ~p"/events/attribute",
                feature: "events.attribute"
              }
            ]
          },
          %{label: "Phân Tích AI", icon: "hero-sparkles-solid", href: ~p"/analytics/instances", feature: "analytics"}
        ],
        [
          %{label: "Thiết Bị", icon: "hero-video-camera-solid", href: ~p"/devices", feature: "devices"},
          %{label: "Người Dùng", icon: "hero-users-solid", href: ~p"/users", role: :admin, feature: "users"},
          %{
            label: "Khám Phá ONVIF",
            icon: "hero-magnifying-glass-circle",
            href: ~p"/onvif-discovery",
            role: :admin,
            feature: "onvif"
          }
        ],
        [
          %{
            label: "Quản Lý Lưu Trữ",
            icon: "hero-circle-stack-solid",
            role: :admin,
            feature: "storage",
            children: [
              %{label: "Bộ Nhớ Vật Lý", icon: "hero-server-stack-solid", href: ~p"/local-storages"},
              %{label: "Lưu Trữ Từ Xa", icon: "hero-cloud-solid", href: ~p"/remote-storages"}
            ]
          }
        ],
        [
          %{
            label: "Cài Đặt Hệ Thống",
            icon: "hero-cog-6-tooth-solid",
            href: ~p"/nerves/system-settings",
            role: :admin,
            feature: "system"
          }
        ],
        [
          %{
            label: "Bảng Điều Khiển",
            icon: "hero-chart-bar-solid",
            href: ~p"/live-dashboard",
            target: "_blank",
            feature: "system"
          },
          %{
            label: "Tài Liệu API",
            icon: "hero-document-solid",
            href: "/swagger.html",
            target: "_blank",
            feature: "system"
          },
          %{
            label: "Giới Thiệu",
            icon: "hero-information-circle-solid",
            href: ~p"/about",
            feature: "about"
          }
        ]
      ]
    end
  else
    defp groups do
      [
        [
          %{label: "Tổng Quan", icon: "hero-tv-solid", href: ~p"/dashboard", feature: "dashboard"},
          %{
            label: "Xem Trực Tiếp",
            icon: "hero-video-camera-solid",
            feature: "devices",
            children: [
              %{label: "Lưới Camera", icon: "hero-squares-2x2-solid", href: ~p"/live-view"},
              %{label: "Bản Đồ E-Map", icon: "hero-map-solid", href: ~p"/emap"}
            ]
          },
          %{label: "Phát Lại", icon: "hero-clock-solid", href: ~p"/playback", feature: "playback"},
          %{label: "Bản Ghi", icon: "hero-film-solid", href: ~p"/recordings", feature: "playback"},
          %{
            label: "Sự Kiện",
            icon: "hero-camera-solid",
            feature: "events",
            children: [
              %{label: "Sự Kiện Chung", icon: "hero-code-bracket", href: ~p"/events/generic", feature: "events.generic"},
              %{label: "Biển Số Xe", icon: "hero-truck-solid", href: ~p"/events/lpr", feature: "events.lpr"},
              %{label: "Nhận Diện Khuôn Mặt", icon: "hero-user-circle-solid", href: ~p"/events/face", feature: "events.face"},
              %{label: "Sự Kiện AI", icon: "hero-bolt-solid", href: ~p"/events/ai-events", feature: "events.ai"},
              %{label: "Bản Đồ Nhiệt AI", icon: "hero-fire-solid", href: ~p"/events/ai-heatmap", feature: "events.heatmap"},
              %{
                label: "Biểu Đồ Vượt Tuyến",
                icon: "hero-chart-bar-solid",
                href: ~p"/events/ai-tripwire-chart",
                feature: "events.tripwire"
              },
              %{
                label: "Báo Cáo Lảng Vảng",
                icon: "hero-clock-solid",
                href: ~p"/events/ai-loitering-report",
                feature: "events.loitering"
              },
              %{
                label: "Báo Cáo Thuộc Tính",
                icon: "hero-tag-solid",
                href: ~p"/events/attribute",
                feature: "events.attribute"
              }
            ]
          },
          %{label: "Phân Tích AI", icon: "hero-sparkles-solid", href: ~p"/analytics/instances", feature: "analytics"}
        ],
        [
          %{label: "Thiết Bị", icon: "hero-video-camera-solid", href: ~p"/devices", feature: "devices"},
          %{label: "Người Dùng", icon: "hero-users-solid", href: ~p"/users", role: :admin, feature: "users"},
          %{
            label: "Tìm Kiếm Thiết Bị",
            icon: "hero-magnifying-glass-circle",
            href: ~p"/onvif-discovery",
            role: :admin,
            feature: "onvif"
          },
          %{
            label: "Đồng Bộ Commander",
            icon: "hero-signal",
            href: ~p"/commander-sync",
            feature: "commander"
          }
        ],
        [
          %{
            label: "Quản Lý Lưu Trữ",
            icon: "hero-circle-stack-solid",
            role: :admin,
            feature: "storage",
            children: [
              %{label: "Bộ Nhớ Vật Lý", icon: "hero-server-stack-solid", href: ~p"/local-storages"},
              %{label: "Lưu Trữ Từ Xa", icon: "hero-cloud-solid", href: ~p"/remote-storages"}
            ]
          }
        ],
        [
          %{
            label: "Bảng Điều Khiển",
            icon: "hero-chart-bar-solid",
            href: ~p"/live-dashboard",
            target: "_blank",
            feature: "system"
          },
          %{
            label: "Tài Liệu API",
            icon: "hero-document-solid",
            href: "/swagger.html",
            target: "_blank",
            feature: "system"
          },
          %{
            label: "Giới Thiệu",
            icon: "hero-information-circle-solid",
            href: ~p"/about",
            feature: "about"
          }
        ]
      ]
    end
  end

  alias TProNVR.Accounts.Permissions

  defp filter_group_by_access(group, user) do
    Enum.flat_map(group, fn
      %{children: children} = item ->
        role_blocked = not is_nil(item[:role]) and (is_nil(user) or item[:role] != user.role)
        perm_blocked = not is_nil(item[:feature]) and not Permissions.has_permission?(user, item[:feature])
        if role_blocked or perm_blocked do
          []
        else
          # Filter children individually by their own feature permission
          filtered_children = filter_children_by_access(children, user)
          if filtered_children == [], do: [], else: [%{item | children: filtered_children}]
        end
      item ->
        role_blocked = not is_nil(item[:role]) and (is_nil(user) or item[:role] != user.role)
        perm_blocked = not is_nil(item[:feature]) and not Permissions.has_permission?(user, item[:feature])
        if role_blocked or perm_blocked, do: [], else: [item]
    end)
  end

  defp filter_children_by_access(children, user) do
    Enum.reject(children, fn child ->
      if child[:feature] do
        not Permissions.has_permission?(user, child[:feature])
      else
        false
      end
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
