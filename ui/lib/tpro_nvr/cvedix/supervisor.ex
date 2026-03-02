defmodule TProNVR.CVEDIX.Supervisor do
  @moduledoc """
  Supervisor for CVEDIX-RT integration components.
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Registry for polling event consumers
      {Registry, keys: :unique, name: TProNVR.CVEDIX.Registry},

      # Dynamic supervisor for polling event consumers
      {DynamicSupervisor, strategy: :one_for_one, name: TProNVR.CVEDIX.EventSupervisor},

      # Registry for SSE consumers
      {Registry, keys: :unique, name: TProNVR.CVEDIX.SSERegistry},

      # Dynamic supervisor for SSE consumers
      {DynamicSupervisor, strategy: :one_for_one, name: TProNVR.CVEDIX.SSESupervisor},

      # Auto-start SSE consumers for running instances
      TProNVR.CVEDIX.SSEAutoStarter
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
