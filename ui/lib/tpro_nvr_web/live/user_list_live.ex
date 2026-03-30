defmodule TProNVRWeb.UserListLive do
  @moduledoc false

  use TProNVRWeb, :live_view

  alias TProNVR.Accounts
  alias TProNVR.Accounts.Permissions

  def render(assigns) do
    ~H"""
    <div class="grow e-m-8">
      <div :if={@current_user.role == :admin} class="ml-4 sm:ml-0">
        <.link href={~p"/users/new"}>
          <.button>Thêm Người Dùng</.button>
        </.link>
      </div>

      <.table id="users" rows={@users}>
        <:col :let={user} label="Họ">{user.first_name}</:col>
        <:col :let={user} label="Tên">{user.last_name}</:col>
        <:col :let={user} label="Username">{user.username}</:col>
        <:col :let={user} label="Email">{user.email}</:col>
        <:col :let={user} label="Vị Trí">
          <span class="text-xs font-mono text-gray-400">{user.position || "—"}</span>
        </:col>
        <:col :let={user} label="Vai Trò">
          <div class="flex items-center">
            <span class={[
              "px-2 py-0.5 text-xs font-bold tracking-widest uppercase font-mono border",
              if(user.role == :admin,
                do: "text-black bg-green-500 border-green-500",
                else: "text-green-400 bg-green-900/20 border-green-500/50"
              )
            ]}>
              {String.upcase(to_string(user.role))}
            </span>
          </div>
        </:col>
        <:col :let={user} label="Quyền Hạn">
          <div class="flex items-center">
            <span class={[
              "px-2 py-0.5 text-xs font-bold tracking-widest uppercase font-mono",
              if(Permissions.permission_summary(user) == "ALL",
                do: "text-green-500",
                else: "text-yellow-400"
              )
            ]}>
              {Permissions.permission_summary(user)}
            </span>
          </div>
        </:col>
        <:col :let={user} label="Camera">
          <div class="flex items-center">
            <span class={[
              "px-2 py-0.5 text-xs font-bold tracking-widest uppercase font-mono",
              if(Permissions.device_summary(user, @total_devices) == "ALL",
                do: "text-green-500",
                else: "text-cyan-400"
              )
            ]}>
              {Permissions.device_summary(user, @total_devices)}
            </span>
          </div>
        </:col>
        <:action :let={user}>
          <.three_dot
            :if={@current_user.role == :admin}
            id={"dropdownMenuIconButton-#{user.id}"}
            dropdown_id={"dropdownDots-#{user.id}"}
          />
          <div
            id={"dropdownDots-#{user.id}"}
            class="z-10 hidden text-left bg-black divide-y divide-green-800 rounded-lg shadow w-44 dark:bg-black dark:divide-green-700"
          >
            <ul
              class="py-2 text-sm text-white dark:text-white"
              aria-labelledby={"dropdownMenuIconButton-#{user.id}"}
            >
              <li>
                <.link
                  href={~p"/users/#{user.id}"}
                  class="block px-4 py-2 hover:bg-green-900 dark:hover:bg-green-800 dark:hover:text-white"
                >
                  Chỉnh Sửa
                </.link>
              </li>
              <li>
                <.link
                  id={"delete_user-#{user.id}"}
                  href="#"
                  class="block px-4 py-2 hover:bg-green-900 dark:hover:bg-green-800 dark:hover:text-red"
                  phx-click={show_modal("delete-modal-#{user.id}")}
                >
                  Xóa
                </.link>
              </li>
            </ul>
          </div>
          <.modal id={"delete-modal-#{user.id}"}>
            <div class="bg-green-300 p-4 rounded-lg text-center dark:bg-black dark:border-green-800">
              <p class="text-l text-white font-bold mb-4">
                {"Bạn có chắc muốn xóa người dùng: '#{user.email}'?"}
              </p>
              <.button
                phx-disable-with="Đang xóa..."
                phx-click={JS.push("delete", value: %{id: user.id})}
                class="text-white bg-red-500 hover:bg-red-400 px-4 py-2 mx-2 rounded hover:bg-red-600 dark:text-white"
              >
                Xóa
              </.button>
              <.button
                phx-click={hide_modal("delete-modal-#{user.id}")}
                class="text-white bg-green-800 hover:bg-green-900 px-4 py-2 mx-2 rounded hover:bg-red-600 dark:text-white"
              >
                Hủy
              </.button>
            </div>
          </.modal>
        </:action>
      </.table>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    total_devices = TProNVR.Devices.list() |> length()
    {:ok, assign(socket, users: Accounts.list(), total_devices: total_devices)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)
    email = user.email

    case Accounts.delete_user(user) do
      {:ok, _deleted_user} ->
        info = "Đã xóa người dùng: '#{email}'"

        socket
        |> assign(users: Accounts.list())
        |> put_flash(:info, info)
        |> then(&{:noreply, &1})

      {:error, _} ->
        error = "Đã xảy ra lỗi!"

        socket
        |> put_flash(:error, error)
        |> then(&{:noreply, &1})
    end
  end
end
