defmodule TProNVR.Devices.Cameras.StreamProfile do
  @moduledoc false

  alias ExOnvif.Media2.Profile
  alias ExOnvif.Media.Profile, as: Media1Profile

  defmodule VideoConfig do
    @moduledoc false

    alias ExOnvif.Media2.Profile.VideoEncoder
    alias ExOnvif.Media.Profile.VideoEncoderConfiguration

    @type t :: %__MODULE__{
            codec: atom(),
            codec_profile: nil | binary(),
            width: non_neg_integer(),
            height: non_neg_integer(),
            frame_rate: number(),
            bitrate: non_neg_integer(),
            bitrate_mode: :vbr | :cbr | :abr | nil,
            gop: non_neg_integer(),
            smart_codec: boolean()
          }

    defstruct [
      :codec,
      :codec_profile,
      :width,
      :height,
      :frame_rate,
      :bitrate,
      :bitrate_mode,
      :gop,
      smart_codec: false
    ]

    def from_onvif(%VideoEncoder{} = encoder) do
      %__MODULE__{
        codec: encoder.encoding,
        codec_profile: encoder.profile,
        width: encoder.resolution.width,
        height: encoder.resolution.height,
        frame_rate: encoder.rate_control.frame_rate_limit,
        bitrate: encoder.rate_control.bitrate_limit,
        bitrate_mode: bitrate_mode(encoder.rate_control.constant_bitrate),
        gop: encoder.gov_length
      }
    end

    # Media1 VideoEncoderConfiguration support
    def from_onvif(%VideoEncoderConfiguration{} = encoder) do
      %__MODULE__{
        codec: encoder.encoding,
        codec_profile: get_codec_profile(encoder),
        width: get_resolution_field(encoder.resolution, :width),
        height: get_resolution_field(encoder.resolution, :height),
        frame_rate: get_rate_control_field(encoder.rate_control, :frame_rate_limit),
        bitrate: get_rate_control_field(encoder.rate_control, :bitrate_limit),
        bitrate_mode: nil,
        gop: get_rate_control_field(encoder.rate_control, :encoding_interval)
      }
    end

    def from_onvif(nil), do: nil

    defp get_codec_profile(%{h264_configuration: %{h264_profile: profile}}) when not is_nil(profile), do: profile
    defp get_codec_profile(_), do: nil

    defp get_resolution_field(nil, _field), do: 0
    defp get_resolution_field(resolution, :width), do: resolution.width || 0
    defp get_resolution_field(resolution, :height), do: resolution.height || 0

    defp get_rate_control_field(nil, _field), do: 0
    defp get_rate_control_field(rate_control, :frame_rate_limit), do: rate_control.frame_rate_limit || 0
    defp get_rate_control_field(rate_control, :bitrate_limit), do: rate_control.bitrate_limit || 0
    defp get_rate_control_field(rate_control, :encoding_interval), do: rate_control.encoding_interval || 0

    defp bitrate_mode(true), do: :cbr
    defp bitrate_mode(false), do: :vbr
    defp bitrate_mode(nil), do: nil
  end

  @type t :: %__MODULE__{
          id: binary() | non_neg_integer(),
          enabled: boolean(),
          name: binary(),
          video_config: nil | VideoConfig.t(),
          stream_uri: binary() | nil,
          snapshot_uri: binary() | nil
        }

  defstruct [
    :id,
    :name,
    :stream_uri,
    :snapshot_uri,
    enabled: false,
    video_config: nil
  ]

  @spec flatten(t()) :: map()
  def flatten(profile) do
    profile.video_config
    |> Map.from_struct()
    |> Map.merge(Map.take(profile, [:id, :enabled, :name]))
  end

  @spec from_onvif(Profile.t()) :: t()
  def from_onvif(%Profile{} = onvif_profile) do
    %__MODULE__{
      id: onvif_profile.reference_token,
      name: onvif_profile.name,
      enabled: true,
      video_config: VideoConfig.from_onvif(onvif_profile.video_encoder_configuration)
    }
  end

  # Media1 Profile support
  @spec from_onvif(Media1Profile.t()) :: t()
  def from_onvif(%Media1Profile{} = onvif_profile) do
    %__MODULE__{
      id: onvif_profile.reference_token,
      name: onvif_profile.name,
      enabled: true,
      video_config: VideoConfig.from_onvif(onvif_profile.video_encoder_configuration)
    }
  end
end

