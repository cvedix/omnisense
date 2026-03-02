defmodule TProNVR.MediaUtils do
  @moduledoc false

  alias TProNVR.AV.Decoder
  alias Membrane.Buffer

  @default_video_timescale 90_000

  @spec decode_last(Enumerable.t(Buffer.t() | ExMP4.Sample.t()), Decoder.t()) :: Buffer.t()
  def decode_last(buffers, decoder) do
    buffers
    |> Stream.transform(
      fn -> decoder end,
      &{Decoder.decode(&2, &1.payload, pts: &1.pts), &2},
      &{Decoder.flush(&1), &1},
      &Function.identity/1
    )
    |> Enum.reverse()
    |> hd()
  end

  @spec track_from_stream_format(module()) :: ExMP4.Track.t()
  def track_from_stream_format(stream_format) do
    media =
      case stream_format do
        %Membrane.H264{} -> :h264
        %Membrane.H265{} -> :h265
      end

    %ExMP4.Track{
      type: :video,
      media: media,
      # Fallback to common resolutions when stream_format doesn't provide dimensions
      # These will be overwritten with actual values from SPS in write_data
      width: stream_format.width || 1920,
      height: stream_format.height || 1080,
      timescale: @default_video_timescale
    }
  end

  @spec to_annexb(binary() | [binary()]) :: binary()
  def to_annexb(au) when is_list(au), do: Enum.map_join(au, &<<1::32, &1::binary>>)
  def to_annexb(au), do: au
end
