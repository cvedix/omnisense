defmodule TProNVR.Events do
  @moduledoc false

  import Ecto.Query

  alias TProNVR.Events.{Event, LPR}
  alias TProNVR.CVEDIX.AnalyticsEvent
  alias TProNVR.Model.Device
  alias TProNVR.Repo

  @type flop_result :: {:ok, {[map()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}

  @spec create_event(map()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def create_event(params) do
    do_create_event(nil, params)
  end

  @spec create_event(Device.t(), map()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def create_event(device, params) do
    do_create_event(device.id, params)
  end

  @spec create_lpr_event(Device.t(), map(), binary() | nil) ::
          {:ok, LPR.t()} | {:error, Ecto.Changeset.t()}
  def create_lpr_event(device, params, plate_picture) do
    insertion_result =
      params
      |> Map.put(:device_id, device.id)
      |> LPR.changeset()
      |> Repo.insert(on_conflict: :nothing)

    with {:ok, %{id: id} = event} when not is_nil(id) <- insertion_result do
      if plate_picture do
        device
        |> Device.lpr_thumbnails_dir()
        |> tap(&File.mkdir/1)
        |> Path.join(LPR.plate_name(event))
        |> File.write(plate_picture)
      end

      {:ok, event}
    end
  end

  @spec list_events(map()) :: flop_result()
  def list_events(%Flop{} = flop) do
    Event |> preload([:device]) |> TProNVR.Flop.validate_and_run(flop)
  end

  @spec list_events(map()) :: flop_result()
  def list_events(params) do
    Event
    |> preload([:device])
    |> Event.filter(params)
    |> TProNVR.Flop.validate_and_run(params, for: Event)
  end

  @spec list_lpr_events(map(), Keyword.t()) :: flop_result()
  def list_lpr_events(params, opts \\ []) do
    LPR
    |> preload([:device])
    |> TProNVR.Flop.validate_and_run(params, for: LPR)
    |> case do
      {:ok, {data, meta}} ->
        {:ok, {maybe_include_lpr_thumbnails(opts[:include_plate_image], data), meta}}

      other ->
        other
    end
  end

  @spec get_event(integer()) :: Event.t() | nil
  def get_event(id) do
    Repo.get(Event, id)
    |> Repo.preload(:device)
  end

  @spec last_lpr_event_timestamp(Device.t()) :: DateTime.t() | nil
  def last_lpr_event_timestamp(device) do
    LPR
    |> select([e], e.capture_time)
    |> where([e], e.device_id == ^device.id)
    |> order_by(desc: :capture_time)
    |> limit(1)
    |> Repo.one()
  end

  @spec lpr_event_thumbnail(LPR.t()) :: binary() | nil
  def lpr_event_thumbnail(lpr_event) do
    Device.lpr_thumbnails_dir(lpr_event.device)
    |> Path.join(LPR.plate_name(lpr_event))
    |> File.read()
    |> case do
      {:ok, image} -> Base.encode64(image)
      _other -> nil
    end
  end

  defp do_create_event(device_id, params) do
    %Event{device_id: device_id}
    |> Event.changeset(params)
    |> Repo.insert()
  end

  defp maybe_include_lpr_thumbnails(true, entries) do
    Enum.map(entries, fn entry ->
      plate_image = lpr_event_thumbnail(entry)
      Map.put(entry, :plate_image, plate_image)
    end)
  end

  defp maybe_include_lpr_thumbnails(_other, entries), do: entries

  # ============================================================================
  # Analytics Events Functions
  # ============================================================================

  @doc """
  Create an analytics event from CVEDIX-RT.
  """
  @spec create_analytics_event(map()) :: {:ok, AnalyticsEvent.t()} | {:error, Ecto.Changeset.t()}
  def create_analytics_event(params) do
    %AnalyticsEvent{}
    |> AnalyticsEvent.changeset(params)
    |> Repo.insert()
  end

  @doc """
  List analytics events with filtering and pagination.
  """
  @spec list_analytics_events(map()) :: flop_result()
  def list_analytics_events(params) do
    AnalyticsEvent
    |> preload([:device])
    |> AnalyticsEvent.filter(params)
    |> TProNVR.Flop.validate_and_run(params, for: AnalyticsEvent)
  end

  @doc """
  Get an analytics event by ID.
  """
  @spec get_analytics_event(binary()) :: AnalyticsEvent.t() | nil
  def get_analytics_event(id) do
    Repo.get(AnalyticsEvent, id)
    |> Repo.preload(:device)
  end

  @doc """
  Delete analytics events older than given datetime.
  """
  @spec delete_analytics_events_older_than(DateTime.t()) :: {integer(), nil}
  def delete_analytics_events_older_than(datetime) do
    AnalyticsEvent
    |> where([e], e.event_time < ^datetime)
    |> Repo.delete_all()
  end

  @doc """
  Get analytics event statistics grouped by event type.
  """
  @spec analytics_event_stats_by_type(map()) :: list()
  def analytics_event_stats_by_type(params \\ %{}) do
    AnalyticsEvent
    |> AnalyticsEvent.filter(params)
    |> AnalyticsEvent.count_by_type()
    |> Repo.all()
  end

  @doc """
  Get analytics event statistics grouped by object class.
  """
  @spec analytics_event_stats_by_class(map()) :: list()
  def analytics_event_stats_by_class(params \\ %{}) do
    AnalyticsEvent
    |> AnalyticsEvent.filter(params)
    |> AnalyticsEvent.count_by_object_class()
    |> Repo.all()
  end
end

