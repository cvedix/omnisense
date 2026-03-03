defmodule TProNVR.Model.Device do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Query

  alias Ecto.Changeset
  alias TProNVR.Model.Device.{SnapshotConfig, StorageConfig}
  alias TProNVR.Model.Schedule

  @states [:stopped, :streaming, :recording, :failed]
  @camera_vendors ["HIKVISION", "Milesight Technology Co.,Ltd.", "AXIS", "Dahua", "Tapo"]

  @type state :: :stopped | :recording | :streaming | :failed
  @type id :: binary()

  @type t :: %__MODULE__{}

  defmodule Credentials do
    @moduledoc false
    use Ecto.Schema

    import Ecto.Changeset

    @type t :: %__MODULE__{
            username: binary(),
            password: binary()
          }

    @primary_key false
    embedded_schema do
      field :username, :string
      field :password, :string
    end

    @spec changeset(t(), map()) :: Ecto.Changeset.t()
    def changeset(struct, params) do
      struct
      |> cast(params, __MODULE__.__schema__(:fields))
    end
  end

  defmodule StreamConfig do
    @moduledoc false
    use Ecto.Schema

    import Ecto.Changeset

    @type url :: String.t()

    @type t :: %__MODULE__{
            stream_uri: url(),
            snapshot_uri: url(),
            profile_token: String.t(),
            sub_stream_uri: url(),
            sub_snapshot_uri: url(),
            sub_profile_token: String.t(),
            third_stream_uri: url(),
            third_profile_token: url(),
            filename: String.t(),
            temporary_path: Path.t(),
            duration: Membrane.Time.t(),
            framerate: String.t(),
            resolution: String.t()
          }

    @primary_key false
    embedded_schema do
      # I guess we need better names
      field :stream_uri, :string
      field :snapshot_uri, :string
      field :profile_token, :string
      field :sub_stream_uri, :string
      field :sub_snapshot_uri, :string
      field :sub_profile_token, :string
      field :third_stream_uri, :string
      field :third_profile_token, :string
      # File settings
      field :filename, :string
      field :temporary_path, :string, virtual: true
      field :duration, :integer
      field :framerate, :float, default: 8.0
      field :resolution, :string
    end

    def changeset(struct, params, device_type) do
      struct
      |> cast(params, [
        :stream_uri,
        :snapshot_uri,
        :profile_token,
        :sub_stream_uri,
        :sub_snapshot_uri,
        :sub_profile_token,
        :filename,
        :temporary_path,
        :duration,
        :framerate,
        :resolution
      ])
      |> validate_device_config(device_type)
    end

    defp validate_device_config(changeset, :ip) do
      validate_required(changeset, [:stream_uri])
      |> Changeset.validate_change(:stream_uri, &validate_uri/2)
      |> Changeset.validate_change(:sub_stream_uri, &validate_uri/2)
      |> Changeset.validate_change(:snapshot_uri, fn :snapshot_uri, snapshot_uri ->
        validate_uri(:snapshot_uri, snapshot_uri, "http")
      end)
      |> Changeset.validate_change(:sub_snapshot_uri, fn :sub_snapshot_uri, snapshot_uri ->
        validate_uri(:sub_snapshot_uri, snapshot_uri, "http")
      end)
    end

    defp validate_device_config(changeset, :file) do
      validate_required(changeset, [:filename, :duration])
    end

    defp validate_device_config(changeset, :webcam) do
      changeset
      |> validate_required([:framerate])
      |> validate_number(:framerate, greater_than_or_equal_to: 5, less_than_or_equal_to: 30)
      |> validate_format(:resolution, ~r/^\d+x\d+$/, message: "should be in WIDTHxHEIGHT format")
    end

    defp validate_uri(field, uri, protocl \\ "rtsp") do
      parsed_uri = URI.parse(uri)

      cond do
        parsed_uri.scheme != protocl ->
          [{field, "scheme should be #{protocl}"}]

        to_string(parsed_uri.host) == "" ->
          [{field, "invalid #{protocl} uri"}]

        true ->
          []
      end
    end
  end

  defmodule Settings do
    @moduledoc false
    use Ecto.Schema

    import Ecto.Changeset

    @type t :: %__MODULE__{
            generate_bif: boolean(),
            enable_lpr: boolean(),
            enable_face_detection: boolean()
          }

    @primary_key false
    embedded_schema do
      field :generate_bif, :boolean, default: true
      field :enable_lpr, :boolean, default: false
      field :enable_face_detection, :boolean, default: false
    end

    @spec changeset(t(), map()) :: Ecto.Changeset.t()
    def changeset(struct, params) do
      cast(struct, params, __MODULE__.__schema__(:fields))
    end
  end

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "devices" do
    field :name, :string
    field :type, Ecto.Enum, values: [:ip, :file, :webcam], default: :ip
    field :timezone, :string, default: "UTC"
    field :state, Ecto.Enum, values: @states, default: :recording
    field :vendor, :string
    field :mac, :string
    field :url, :string
    field :model, :string

    # RTSP routing mode: :direct for compatible cameras, :proxy for Tapo via MediaMTX
    field :rtsp_mode, Ecto.Enum, values: [:direct, :proxy], default: :direct
    # Auto-generated stream key for MediaMTX proxy (e.g., "tapo_serial123")
    field :proxy_stream_key, :string

    embeds_one :credentials, Credentials, source: :credentials, on_replace: :update
    embeds_one :stream_config, StreamConfig, source: :config, on_replace: :update
    embeds_one :settings, Settings, on_replace: :update
    embeds_one :storage_config, StorageConfig, on_replace: :update
    embeds_one :snapshot_config, SnapshotConfig, on_replace: :update

    timestamps(type: :utc_datetime_usec)
  end

  @spec vendors :: [binary()]
  def vendors, do: @camera_vendors

  @spec vendor(t()) :: atom()
  def vendor(%__MODULE__{vendor: vendor}) do
    case vendor do
      "HIKVISION" -> :hik
      "Milesight Technology Co.,Ltd." -> :milesight
      "AXIS" -> :axis
      "Dahua" -> :dahua
      "Tapo" -> :tapo
      _other -> :unknown
    end
  end

  @doc """
  Check if the device is a Tapo/TP-Link camera that requires MediaMTX proxy.
  """
  @spec is_tapo?(t()) :: boolean()
  def is_tapo?(%__MODULE__{vendor: nil}), do: false
  def is_tapo?(%__MODULE__{vendor: vendor}) do
    vendor_lower = String.downcase(vendor)
    String.contains?(vendor_lower, "tapo") or 
      String.contains?(vendor_lower, "tp-link") or
      String.contains?(vendor_lower, "tp link")
  end

  @doc """
  Generate a stream key for MediaMTX proxy based on device serial/mac/id.
  """
  @spec generate_stream_key(t() | map()) :: String.t()
  def generate_stream_key(%{mac: mac}) when is_binary(mac) and mac != "" do
    sanitized = mac |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "")
    "tapo_#{sanitized}"
  end
  def generate_stream_key(%{id: id}) when is_binary(id) do
    sanitized = id |> String.replace("-", "") |> String.slice(0, 12)
    "tapo_#{sanitized}"
  end
  def generate_stream_key(_), do: "tapo_#{:rand.uniform(999999)}"

  @doc """
  Get the RTSP URL to use for streaming.
  """
  @spec effective_rtsp_url(t(), :main | :sub) :: String.t() | nil
  def effective_rtsp_url(%__MODULE__{} = device, stream) do
    {main_stream, sub_stream} = streams(device)
    if stream == :main, do: main_stream, else: sub_stream
  end

  @spec http_url(t()) :: binary() | nil
  def http_url(%__MODULE__{url: nil}), do: nil

  def http_url(%__MODULE__{url: url}) do
    url
    |> URI.parse()
    |> Map.put(:path, nil)
    |> URI.to_string()
  end

  @spec streams(t()) :: {binary(), binary() | nil}
  def streams(%__MODULE__{} = device), do: build_stream_uri(device)

  @spec file_location(t()) :: Path.t()
  def file_location(%__MODULE__{stream_config: %{filename: filename}} = device) do
    Path.join(base_dir(device), filename)
  end

  @spec file_duration(t()) :: Membrane.Time.t()
  def file_duration(%__MODULE__{type: :file, stream_config: %{duration: duration}}), do: duration

  @spec config_updated(t(), t()) :: boolean()
  def config_updated(%__MODULE__{} = device_1, %__MODULE__{} = device_2) do
    device_1.stream_config != device_2.stream_config or device_1.settings != device_2.settings or
      device_1.storage_config != device_2.storage_config
  end

  @spec has_sub_stream(t()) :: boolean()
  def has_sub_stream(%__MODULE__{stream_config: nil}), do: false
  def has_sub_stream(%__MODULE__{stream_config: %StreamConfig{sub_stream_uri: nil}}), do: false
  def has_sub_stream(_), do: true

  @doc """
  Check if the device main pipeline is running.
  """
  @spec recording?(t()) :: boolean()
  def recording?(%__MODULE__{state: state}), do: state != :stopped

  @doc """
  Check if the device is streaming media
  """
  @spec streaming?(t()) :: boolean()
  def streaming?(%__MODULE__{state: state}), do: state in [:recording, :streaming]

  # directories path

  @spec base_dir(t()) :: Path.t()
  def base_dir(%__MODULE__{id: id, storage_config: %{address: path}}),
    do: Path.join([path, "nvr", id])

  @spec recording_dir(t()) :: Path.t()
  @spec recording_dir(t(), :high | :low) :: Path.t()
  def recording_dir(%__MODULE__{} = device, stream \\ :high) do
    stream = if stream == :high, do: "hi_quality", else: "lo_quality"
    Path.join(base_dir(device), stream)
  end

  @spec bif_dir(t()) :: Path.t()
  def bif_dir(%__MODULE__{} = device) do
    Path.join(base_dir(device), "bif")
  end

  @spec bif_thumbnails_dir(t()) :: Path.t()
  def bif_thumbnails_dir(%__MODULE__{} = device) do
    Path.join([base_dir(device), "thumbnails", "bif"])
  end

  @spec thumbnails_dir(t()) :: Path.t()
  def thumbnails_dir(%__MODULE__{} = device) do
    Path.join([base_dir(device), "thumbnails"])
  end

  @spec lpr_thumbnails_dir(t()) :: Path.t()
  def lpr_thumbnails_dir(device) do
    Path.join(thumbnails_dir(device), "lpr")
  end

  @spec snapshot_config(t()) :: map()
  def snapshot_config(%{snapshot_config: nil}) do
    %{enabled: false}
  end

  def snapshot_config(%{snapshot_config: snapshot_config}) do
    config = Map.take(snapshot_config, [:enabled, :remote_storage, :upload_interval])

    if config.enabled do
      schedule = Schedule.parse!(snapshot_config.schedule)
      Map.put(snapshot_config, :schedule, schedule)
    else
      config
    end
  end

  def filter(query \\ __MODULE__, params) do
    Enum.reduce(params, query, fn
      {:state, value}, q when is_atom(value) -> where(q, [d], d.state == ^value)
      {:state, values}, q when is_list(values) -> where(q, [d], d.state in ^values)
      {:type, value}, q -> where(q, [d], d.type == ^value)
      {:mac, mac_addr}, q -> where(q, [d], d.mac == ^mac_addr)
      _, q -> q
    end)
  end

  @spec states :: [state()]
  def states, do: @states

  @spec onvif_device(t()) :: {:ok, Onvif.Device.t()} | {:error, any()}
  def onvif_device(%__MODULE__{type: :ip} = device) do
    case http_url(device) do
      nil ->
        {:error, :no_url}

      url ->
        ExOnvif.Device.new(url, device.credentials.username, device.credentials.password)
    end
  end

  def onvif_device(_device), do: {:error, :not_camera}

  # Changesets
  def create_changeset(device \\ %__MODULE__{}, params) do
    device
    |> Changeset.cast(params, [:name, :type, :timezone, :state, :vendor, :mac, :url, :model, :rtsp_mode, :proxy_stream_key])
    |> Changeset.cast_embed(:credentials)
    |> Changeset.cast_embed(:storage_config, required: true)
    |> maybe_set_rtsp_mode()
    |> common_config()
  end

  def update_changeset(device, params) do
    device
    |> Changeset.cast(params, [:name, :timezone, :state, :vendor, :mac, :url, :model])
    |> Changeset.cast_embed(:credentials)
    |> Changeset.cast_embed(:storage_config,
      required: true,
      with: &StorageConfig.update_changeset/2
    )
    |> common_config()
  end

  defp common_config(changeset) do
    changeset
    |> Changeset.validate_required([:name, :type])
    |> Changeset.validate_inclusion(:timezone, Tzdata.zone_list())
    |> Changeset.cast_embed(:settings)
    |> Changeset.cast_embed(:snapshot_config)
    |> validate_config()
    |> maybe_set_default_settings()
  end

  defp validate_config(%Changeset{} = changeset) do
    type = Changeset.get_field(changeset, :type)

    Changeset.cast_embed(changeset, :stream_config,
      required: true,
      with: &StreamConfig.changeset(&1, &2, type)
    )
  end

  defp maybe_set_default_settings(changeset) do
    if Changeset.get_field(changeset, :settings),
      do: changeset,
      else: Changeset.put_embed(changeset, :settings, %Settings{})
  end

  defp maybe_set_rtsp_mode(changeset) do
    vendor = Changeset.get_field(changeset, :vendor) || ""
    model = Changeset.get_field(changeset, :model) || ""
    url = Changeset.get_field(changeset, :url) || ""
    
    vendor_lower = String.downcase(vendor)
    model_lower = String.downcase(model)
    _url_lower = String.downcase(url)
    
    # Check multiple signals for Tapo detection
    is_tapo = String.contains?(vendor_lower, "tapo") or 
              String.contains?(vendor_lower, "tp-link") or
              String.contains?(vendor_lower, "tp link") or
              String.contains?(model_lower, "tapo") or
              String.contains?(model_lower, "c200") or
              String.contains?(model_lower, "c210") or
              String.contains?(model_lower, "c310") or
              String.contains?(model_lower, "c320") or
              # Check stream_config for Tapo URL patterns
              check_tapo_stream_uri(changeset)
    
    if is_tapo do
      mac = Changeset.get_field(changeset, :mac)
      id = Changeset.get_field(changeset, :id)
      
      stream_key = cond do
        mac && mac != "" ->
          sanitized = mac |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "")
          "tapo_#{sanitized}"
        id && is_binary(id) ->
          sanitized = id |> String.replace("-", "") |> String.slice(0, 12)
          "tapo_#{sanitized}"
        true ->
          "tapo_#{:rand.uniform(999999)}"
      end
      
      changeset
      |> Changeset.put_change(:rtsp_mode, :proxy)
      |> Changeset.put_change(:proxy_stream_key, stream_key)
    else
      changeset
    end
  end

  defp check_tapo_stream_uri(changeset) do
    case Changeset.get_field(changeset, :stream_config) do
      %{stream_uri: uri} when is_binary(uri) ->
        uri_lower = String.downcase(uri)
        String.contains?(uri_lower, "stream1") or String.contains?(uri_lower, "stream2")
      _ ->
        false
    end
  end

  defp build_stream_uri(%__MODULE__{stream_config: config, credentials: credentials_config}) do
    userinfo =
      if to_string(credentials_config.username) != "" and
           to_string(credentials_config.password) != "" do
        "#{credentials_config.username}:#{credentials_config.password}"
      end

    {do_build_uri(config.stream_uri, userinfo), do_build_uri(config.sub_stream_uri, userinfo)}
  end

  defp build_stream_uri(_), do: nil

  defp do_build_uri(nil, _userinfo), do: nil

  defp do_build_uri(stream_uri, userinfo) do
    stream_uri
    |> URI.parse()
    |> then(&%URI{&1 | userinfo: userinfo})
    |> URI.to_string()
  end
end
