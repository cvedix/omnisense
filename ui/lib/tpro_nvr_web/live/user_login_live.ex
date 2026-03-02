defmodule TProNVRWeb.UserLoginLive do
  use TProNVRWeb, :live_view

  def render(assigns) do
    ~H"""
    <.flash_group flash={@flash} />
    <div class="flex flex-col items-center justify-center h-screen bg-black">
      <.header class="text-center">
        <span class="text-white text-xl font-bold">Sign in to account</span>
      </.header>

      <.simple_form
        class="bg-black mt-6 w-80"
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
          l_class="text-white"
        />
        <.input
          field={@form[:password]}
          type="password"
          label="Password"
          required
          l_class="text-white"
        />

        <:actions>
          <.input field={@form[:remember_me]} type="checkbox" label="Keep me logged in" />
          <.link href={~p"/users/reset-password"} class="text-sm font-semibold text-white hover:text-blue-400">
            Forgot your password?
          </.link>
        </:actions>
        <:actions>
          <.button phx-disable-with="Signing in..." class="w-full bg-blue-600 hover:bg-blue-700 text-white">
            Sign in <span aria-hidden="true">→</span>
          </.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")
    {:ok, assign(socket, form: form), temporary_assigns: [form: form], layout: false}
  end
end
