defmodule TProNVR.Accounts.Permissions do
  @moduledoc """
  Defines all available feature permissions and helpers for checking user access.
  Empty permissions list = full access (backward compatible).
  Admin role always has full access.
  Supports parent-child feature hierarchy (e.g., "events" -> "events.generic", "events.lpr").
  """

  @features [
    %{key: "dashboard", label: "Tổng Quan", icon: "hero-tv-solid"},
    %{key: "devices", label: "Quản Lý Thiết Bị", icon: "hero-video-camera-solid"},
    %{key: "playback", label: "Xem Lại Bản Ghi", icon: "hero-play-solid"},
    %{key: "events", label: "Sự Kiện", icon: "hero-bell-alert-solid", children: [
      %{key: "events.generic", label: "Sự Kiện Chung", icon: "hero-code-bracket"},
      %{key: "events.lpr", label: "Biển Số Xe", icon: "hero-truck-solid"},
      %{key: "events.face", label: "Nhận Diện Khuôn Mặt", icon: "hero-user-circle-solid"},
      %{key: "events.ai", label: "Sự Kiện AI", icon: "hero-bolt-solid"},
      %{key: "events.heatmap", label: "Bản Đồ Nhiệt AI", icon: "hero-fire-solid"},
      %{key: "events.tripwire", label: "Biểu Đồ Vượt Tuyến", icon: "hero-chart-bar-solid"},
      %{key: "events.loitering", label: "Báo Cáo Lảng Vảng", icon: "hero-clock-solid"},
      %{key: "events.attribute", label: "Báo Cáo Thuộc Tính", icon: "hero-tag-solid"}
    ]},
    %{key: "emap", label: "Bản Đồ (E-Map)", icon: "hero-map-solid"},
    %{key: "storage", label: "Quản Lý Lưu Trữ", icon: "hero-circle-stack-solid"},
    %{key: "commander", label: "Đồng Bộ Commander", icon: "hero-signal"},
    %{key: "onvif", label: "ONVIF Discovery", icon: "hero-magnifying-glass-solid"},
    %{key: "users", label: "Quản Lý Users", icon: "hero-users-solid"},
    %{key: "system", label: "Hệ Thống", icon: "hero-cpu-chip-solid"},
    %{key: "analytics", label: "AI Instances", icon: "hero-sparkles-solid"},
    %{key: "about", label: "Giới Thiệu", icon: "hero-information-circle-solid"}
  ]

  @feature_keys Enum.flat_map(@features, fn f ->
    case f[:children] do
      nil -> [f.key]
      children -> [f.key | Enum.map(children, & &1.key)]
    end
  end)

  @doc "Returns all available features with key, label, icon (includes children)."
  @spec all_features() :: [map()]
  def all_features, do: @features

  @doc "Returns all valid feature keys (flat list including sub-features)."
  @spec all_keys() :: [String.t()]
  def all_keys, do: @feature_keys

  @doc "Returns only top-level feature keys."
  @spec top_level_keys() :: [String.t()]
  def top_level_keys, do: Enum.map(@features, & &1.key)

  @doc """
  Check if a user has permission for a given feature.
  - Admin role: always true
  - Empty permissions list: full access (backward compatible)
  - For sub-features (e.g. "events.lpr"): requires parent ("events") AND sub-feature permission
  - If parent is granted but no sub-features are specified: all sub-features are accessible
  """
  @spec has_permission?(map(), String.t()) :: boolean()
  def has_permission?(%{role: :admin}, _feature), do: true
  def has_permission?(%{permissions: []}, _feature), do: true
  def has_permission?(%{permissions: nil}, _feature), do: true
  def has_permission?(%{permissions: perms}, feature) when is_list(perms) do
    cond do
      # Direct match
      feature in perms -> true

      # Sub-feature check (e.g. "events.lpr")
      String.contains?(feature, ".") ->
        [parent | _] = String.split(feature, ".", parts: 2)
        if parent in perms do
          # Parent is granted. Check if any sub-features are explicitly set
          children = children_keys(parent)
          has_any_sub = Enum.any?(children, fn c -> c in perms end)
          # If no sub-features are set: backward compat = allow all
          # If some sub-features are set: only allow those that are set
          not has_any_sub or feature in perms
        else
          false
        end

      # Not a sub-feature and not directly matched
      true -> false
    end
  end
  def has_permission?(_, _), do: false

  @doc """
  Returns children keys for a parent feature.
  """
  @spec children_keys(String.t()) :: [String.t()]
  def children_keys(parent_key) do
    case Enum.find(@features, fn f -> f.key == parent_key end) do
      %{children: children} when is_list(children) -> Enum.map(children, & &1.key)
      _ -> []
    end
  end

  @doc "Returns count string like '5/12' for display."
  @spec permission_summary(map()) :: String.t()
  def permission_summary(%{role: :admin}), do: "ALL"
  def permission_summary(%{permissions: []}), do: "ALL"
  def permission_summary(%{permissions: nil}), do: "ALL"
  def permission_summary(%{permissions: perms}) when is_list(perms) do
    # Count only top-level features for display
    top_count = perms |> Enum.count(fn p -> not String.contains?(p, ".") end)
    "#{top_count}/#{length(top_level_keys())}"
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

  @doc """
  Returns the list of allowed device IDs for a user, or nil if all devices are allowed.
  Useful for query-level filtering.
  """
  @spec allowed_device_ids(map()) :: [String.t()] | nil
  def allowed_device_ids(%{role: :admin}), do: nil
  def allowed_device_ids(%{allowed_device_ids: []}), do: nil
  def allowed_device_ids(%{allowed_device_ids: nil}), do: nil
  def allowed_device_ids(%{allowed_device_ids: ids}) when is_list(ids) and ids != [], do: ids
  def allowed_device_ids(_), do: nil
end
