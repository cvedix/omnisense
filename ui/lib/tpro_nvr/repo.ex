defmodule TProNVR.Repo do
  use Ecto.Repo,
    otp_app: :tpro_nvr,
    adapter: Ecto.Adapters.SQLite3
end
