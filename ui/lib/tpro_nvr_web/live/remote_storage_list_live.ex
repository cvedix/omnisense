defmodule TProNVRWeb.RemoteStorageListLive do
  @moduledoc false

  use TProNVRWeb, :live_view

  alias TProNVR.RemoteStorages

  def render(assigns) do
    ~H"""
    <div class="grow e-m-8">
      <div class="ml-4 sm:ml-0">
        <.link href={~p"/remote-storages/new"}>
          <.button><.icon name="hero-plus-solid" class="h-4 w-4" />Add Remote Storage</.button>
        </.link>
      </div>

      <.table id="remote-storages" rows={@remote_storages}>
        <:col :let={remote_storage} label="Id">{remote_storage.id}</:col>
        <:col :let={remote_storage} label="Name">{remote_storage.name}</:col>
        <:col :let={remote_storage} label="Type">{remote_storage.type}</:col>
        <:col :let={remote_storage} label="Url">{remote_storage.url}</:col>
        <:action :let={remote_storage}>
          <.three_dot
            id={"dropdownMenuIconButton_#{remote_storage.id}"}
            dropdown_id={"dropdownDots_#{remote_storage.id}"}
          />

          <div
            id={"dropdownDots_#{remote_storage.id}"}
            class="z-10 hidden text-left bg-black divide-y divide-green-800 rounded-lg shadow w-44 dark:bg-black dark:divide-green-700"
          >
            <ul
              class="py-2 text-sm text-white dark:text-white"
              aria-labelledby={"dropdownMenuIconButton_#{remote_storage.id}"}
            >
              <li>
                <.link
                  href={~p"/remote-storages/#{remote_storage.id}"}
                  class="block px-4 py-2 hover:bg-green-900 dark:hover:bg-green-800 dark:hover:text-white"
                >
                  Update
                </.link>
              </li>
              <li>
                <.link
                  phx-click={show_modal("delete-remote-storage-modal-#{remote_storage.id}")}
                  class="block px-4 py-2 hover:bg-green-900 dark:hover:bg-green-800 dark:hover:text-white"
                >
                  Delete
                </.link>
              </li>
            </ul>
          </div>
        </:action>
        <:action :let={remote_storage}>
          <.modal id={"delete-remote-storage-modal-#{remote_storage.id}"}>
            <div class="bg-black m-8 rounded">
              <h2 class="text-xl text-white font-bold mb-4">
                Are you sure you want to delete this remote storage ?
              </h2>
              <div class="mt-4">
                <button
                  phx-click="delete-remote-storage"
                  phx-value-remote_storage_id={remote_storage.id}
                  class="bg-red-500 hover:bg-red-600 text-white py-2 px-4 rounded mr-4"
                >
                  Confirm
                </button>
                <button
                  phx-click={hide_modal("delete-remote-storage-modal-#{remote_storage.id}")}
                  class="bg-green-800 hover:bg-green-700 text-white py-2 px-4 rounded"
                >
                  Cancel
                </button>
              </div>
            </div>
          </.modal>
        </:action>
      </.table>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, remote_storages: RemoteStorages.list())}
  end

  def handle_event("delete-remote-storage", %{"remote_storage_id" => remote_storage_id}, socket) do
    remote_storage = RemoteStorages.get!(remote_storage_id)

    case RemoteStorages.delete(remote_storage) do
      :ok ->
        socket
        |> assign(remote_storages: RemoteStorages.list())
        |> put_flash(:info, "Remote storage #{remote_storage.name} deleted")
        |> then(&{:noreply, &1})

      _other ->
        socket
        |> put_flash(:error, "could not delete remote_storage")
        |> redirect(to: ~p"/remote-storages")
        |> then(&{:noreply, &1})
    end
  end
end
