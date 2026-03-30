defmodule TProNVR.Accounts.Permissions do
  @moduledoc """
  Defines all available feature permissions and helpers for checking user access.
  Empty permissions list = full access (backward compatible).
  Admin role always has full access.
  """

  @features [
    %{key: "dashboard", label: "Tổng Quan", icon: "hero-tv-solid"},
    %{key: "devices", label: "Quản Lý Thiết Bị", icon: "hero-video-camera-solid"},
    %{key: "playback", label: "Xem Lại Bản Ghi", icon: "hero-play-solid"},
    %{key: "events", label: "Sự Kiện AI", icon: "hero-bell-alert-solid"},
    %{key: "emap", label: "Bản Đồ (E-Map)", icon: "hero-map-solid"},
    %{key: "storage", label: "Quản Lý Lưu Trữ", icon: "hero-circle-stack-solid"},
    %{key: "commander", label: "Đồng Bộ Commander", icon: "hero-signal"},
    %{key: "onvif", label: "ONVIF Discovery", icon: "hero-magnifying-glass-solid"},
    %{key: "users", label: "Quản Lý Users", icon: "hero-users-solid"},
    %{key: "system", label: "Hệ Thống", icon: "hero-cpu-chip-solid"},
    %{key: "analytics", label: "AI Instances", icon: "hero-sparkles-solid"},
    %{key: "about", label: "Giới Thiệu", icon: "hero-information-circle-solid"}
  ]

  @feature_keys Enum.map(@features, & &1.key)

  @doc "Returns all available features with key, label, icon."
  @spec all_features() :: [map()]
  def all_features, do: @features

  @doc "Returns all valid feature keys."
  @spec all_keys() :: [String.t()]
  def all_keys, do: @feature_keys

  @doc """
  Check if a user has permission for a given feature.
  - Admin role: always true
  - Empty permissions list: full access (backward compatible)
  - Otherwise: check if feature key is in user's permissions list
  """
  @spec has_permission?(map(), String.t()) :: boolean()
  def has_permission?(%{role: :admin}, _feature), do: true
  def has_permission?(%{permissions: []}, _feature), do: true
  def has_permission?(%{permissions: nil}, _feature), do: true
  def has_permission?(%{permissions: perms}, feature) when is_list(perms) do
    feature in perms
  end
  def has_permission?(_, _), do: false

  @doc "Returns count string like '5/12' for display."
  @spec permission_summary(map()) :: String.t()
  def permission_summary(%{role: :admin}), do: "ALL"
  def permission_summary(%{permissions: []}), do: "ALL"
  def permission_summary(%{permissions: nil}), do: "ALL"
  def permission_summary(%{permissions: perms}) when is_list(perms) do
    "#{length(perms)}/#{length(@feature_keys)}"
  end
  def permission_summary(_), do: "ALL"

  # --- Device access ---

  @doc """
  Filter a list of devices by user's allowed_device_ids.
  - Admin: all devices
  - Empty allowed_device_ids: all devices (backward compatible)
  - Otherwise: only devices in the list
  """
  @spec filter_devices([map()], map()) :: [map()]
  def filter_devices(devices, %{role: :admin}), do: devices
  def filter_devices(devices, %{allowed_device_ids: []}), do: devices
  def filter_devices(devices, %{allowed_device_ids: nil}), do: devices
  def filter_devices(devices, %{allowed_device_ids: ids}) when is_list(ids) do
    Enum.filter(devices, fn d -> d.id in ids end)
  end
  def filter_devices(devices, _), do: devices

  @doc "Returns device access summary for display."
  @spec device_summary(map(), integer()) :: String.t()
  def device_summary(%{role: :admin}, _total), do: "ALL"
  def device_summary(%{allowed_device_ids: []}, _total), do: "ALL"
  def device_summary(%{allowed_device_ids: nil}, _total), do: "ALL"
  def device_summary(%{allowed_device_ids: ids}, total) when is_list(ids) do
    "#{length(ids)}/#{total}"
  end
  def device_summary(_, _total), do: "ALL"
end
