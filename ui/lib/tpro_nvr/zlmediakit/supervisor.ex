defmodule TProNVR.ZLMediaKit.Supervisor do
  @moduledoc """
  Supervisor for ZLMediaKit stream push processes.
  """
  
  use Supervisor
  
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
  
  @impl true
  def init(_init_arg) do
    children = [
      # Registry for stream processes
      {Registry, keys: :unique, name: TProNVR.ZLMediaKit.StreamRegistry},
      # DynamicSupervisor for stream push processes
      {DynamicSupervisor, strategy: :one_for_one, name: TProNVR.ZLMediaKit.StreamSupervisor}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end
