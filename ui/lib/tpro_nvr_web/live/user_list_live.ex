defmodule TProNVRWeb.UserListLive do
  @moduledoc false

  use TProNVRWeb, :live_view

  alias TProNVR.Accounts

  def render(assigns) do
    ~H"""
    <div class="grow e-m-8">
      <div :if={@current_user.role == :admin} class="ml-4 sm:ml-0">
        <.link href={~p"/users/new"}>
          <.button>Add User</.button>
        </.link>
      </div>

      <.table id="users" rows={@users}>
        <:col :let={user} label="Id">{user.id}</:col>
        <:col :let={user} label="First Name">{user.first_name}</:col>
        <:col :let={user} label="Last Name">{user.last_name}</:col>
        <:col :let={user} label="Username">{user.username}</:col>
        <:col :let={user} label="Email">{user.email}</:col>
        <:col :let={user} label="Role">
          <div class="flex items-center">
            {String.upcase(to_string(user.role))}
          </div>
        </:col>
        <:col :let={user} label="Language">
          <div class="flex items-center">
            {String.upcase(to_string(user.language))}
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
                  Update
                </.link>
              </li>
              <li>
                <.link
                  id={"delete_user-#{user.id}"}
                  href="#"
                  class="block px-4 py-2 hover:bg-green-900 dark:hover:bg-green-800 dark:hover:text-red"
                  phx-click={show_modal("delete-modal-#{user.id}")}
                >
                  Delete
                </.link>
              </li>
            </ul>
          </div>
          <.modal id={"delete-modal-#{user.id}"}>
            <div class="bg-green-300 p-4 rounded-lg text-center dark:bg-black dark:border-green-800">
              <p class="text-l text-white font-bold mb-4">
                {"Are you sure you want to delete the User: '#{user.email}'"}
              </p>
              <.button
                phx-disable-with="Deleting..."
                phx-click={JS.push("delete", value: %{id: user.id})}
                class="text-white bg-red-500 hover:bg-red-400 px-4 py-2 mx-2 rounded hover:bg-red-600 dark:text-white"
              >
                Yes
              </.button>
              <.button
                phx-click={hide_modal("delete-modal-#{user.id}")}
                class="text-white bg-green-800 hover:bg-green-900 px-4 py-2 mx-2 rounded hover:bg-red-600 dark:text-white"
              >
                Cancel
              </.button>
            </div>
          </.modal>
        </:action>
      </.table>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, users: Accounts.list())}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)
    email = user.email

    case Accounts.delete_user(user) do
      {:ok, _deleted_user} ->
        info = "User: '#{email}' has been deleted"

        socket
        |> assign(users: Accounts.list())
        |> put_flash(:info, info)
        |> then(&{:noreply, &1})

      {:error, _} ->
        error = "An error has occured!"

        socket
        |> put_flash(:error, error)
        |> then(&{:noreply, &1})
    end
  end
end
