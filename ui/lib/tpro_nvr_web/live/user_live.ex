defmodule TProNVRWeb.UserLive do
  @moduledoc false

  use TProNVRWeb, :live_view

  alias TProNVR.Accounts
  alias TProNVR.Accounts.User
  alias TProNVR.Accounts.Permissions
  alias TProNVR.Devices

  def mount(%{"id" => "new"}, _session, socket) do
    changeset = Accounts.change_user_registration(%User{})
    all_devices = Devices.list()

    {:ok, assign(socket,
      user: %User{},
      user_form: to_form(changeset),
      all_features: Permissions.all_features(),
      selected_permissions: [],
      selected_role: "user",
      all_devices: all_devices,
      selected_device_ids: []
    )}
  end

  def mount(%{"id" => user_id}, _session, socket) do
    user = Accounts.get_user!(user_id)
    all_devices = Devices.list()

    {:ok, assign(socket,
      user: user,
      user_form: to_form(Accounts.change_user_update(user)),
      all_features: Permissions.all_features(),
      selected_permissions: user.permissions || [],
      selected_role: to_string(user.role),
      all_devices: all_devices,
      selected_device_ids: user.allowed_device_ids || []
    )}
  end

  def handle_event("toggle_permission", %{"feature" => feature}, socket) do
    perms = socket.assigns.selected_permissions

    updated =
      if feature in perms,
        do: List.delete(perms, feature),
        else: perms ++ [feature]

    {:noreply, assign(socket, selected_permissions: updated)}
  end

  def handle_event("select_all_permissions", _params, socket) do
    all_keys = Permissions.all_keys()
    {:noreply, assign(socket, selected_permissions: all_keys)}
  end

  def handle_event("deselect_all_permissions", _params, socket) do
    {:noreply, assign(socket, selected_permissions: [])}
  end

  def handle_event("toggle_device", %{"device-id" => device_id}, socket) do
    ids = socket.assigns.selected_device_ids

    updated =
      if device_id in ids,
        do: List.delete(ids, device_id),
        else: ids ++ [device_id]

    {:noreply, assign(socket, selected_device_ids: updated)}
  end

  def handle_event("select_all_devices", _params, socket) do
    all_ids = Enum.map(socket.assigns.all_devices, & &1.id)
    {:noreply, assign(socket, selected_device_ids: all_ids)}
  end

  def handle_event("deselect_all_devices", _params, socket) do
    {:noreply, assign(socket, selected_device_ids: [])}
  end

  def handle_event("role_changed", %{"user" => %{"role" => role}}, socket) do
    {:noreply, assign(socket, selected_role: role)}
  end

  def handle_event("save_user", %{"user" => user_params}, socket) do
    user = socket.assigns.user

    # Inject permissions and allowed devices from toggle state
    user_params =
      user_params
      |> Map.put("permissions", socket.assigns.selected_permissions)
      |> Map.put("allowed_device_ids", socket.assigns.selected_device_ids)

    if user.id,
      do: do_update_user(socket, user, user_params),
      else: do_save_user(socket, user_params)
  end

  defp do_save_user(socket, user_params) do
    case Accounts.register_user(user_params) do
      {:ok, _user} ->
        info = "User created successfully"

        socket
        |> put_flash(:info, info)
        |> redirect(to: ~p"/users")
        |> then(&{:noreply, &1})

      {:error, changeset} ->
        {:noreply,
         assign(
           socket,
           user_form: to_form(changeset)
         )}
    end
  end

  defp do_update_user(socket, user, user_params) do
    case Accounts.update_user(user, user_params) do
      {:ok, updated_user} ->
        info = "User updated successfully"

        socket
        |> put_flash(:info, info)
        |> assign(
          user: updated_user,
          user_form: to_form(Accounts.change_user_registration(updated_user))
        )
        |> redirect(to: ~p"/users")
        |> then(&{:noreply, &1})

      {:error, changeset} ->
        {:noreply,
         assign(socket,
           user_form: to_form(changeset)
         )}
    end
  end
end
