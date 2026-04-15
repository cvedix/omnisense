defmodule TProNVRWeb.UserLoginLive do
  use TProNVRWeb, :live_view

  def render(assigns) do
    ~H"""
    <.flash_group flash={@flash} />
    <div class="flex flex-col items-center justify-center h-screen bg-black bg-[radial-gradient(ellipse_at_center,_var(--tw-gradient-stops))] from-green-900/20 via-black to-black font-mono">
      <.card class="w-full max-w-sm">
        <.header class="text-center mb-6">
          <span class="text-green-500 text-xl font-bold uppercase tracking-widest drop-shadow-[0_0_10px_rgba(34,197,94,0.5)]">System Access</span>
        </.header>

        <.simple_form
          for={@form}
          id="login_form"
          action={~p"/users/login"}
          phx-update="ignore"
        >
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            required
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            required
          />

          <:actions>
            <.input field={@form[:remember_me]} type="checkbox" label="Keep me logged in" />
          </:actions>
          
          <:actions>
            <.link href={~p"/users/reset-password"} class="text-xs font-semibold text-green-500 hover:text-green-400 hover:underline">
              Forgot your password?
            </.link>
          </:actions>
          
          <:actions>
            <.button phx-disable-with="Authenticating..." class="w-full relative group">
              <span class="relative z-10 flex items-center justify-center gap-2">
                Initialize Session <.icon name="hero-arrow-right-solid" class="w-4 h-4" />
              </span>
            </.button>
          </:actions>
        </.simple_form>
      </.card>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")
    {:ok, assign(socket, form: form), temporary_assigns: [form: form], layout: false}
  end
end
