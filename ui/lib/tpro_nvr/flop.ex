defmodule TProNVR.Flop do
  @moduledoc """
  Flop global configuration module for filtering and pagination.
  """
  use Flop, repo: TProNVR.Repo, default_limit: 100
end
