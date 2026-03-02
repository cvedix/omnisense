defmodule TProNVRWeb.FlopConfig do
  @moduledoc false

  use PhoenixHTMLHelpers

  def table_opts do
    [
      table_attrs: [
        class: "w-[40rem] mt-4 text-sm text-left sm:w-full text-white/60 dark:text-white/80 py-3"
      ],
      thead_attrs: [
        class: "text-xs text-white uppercase bg-green-900 dark:bg-black dark:text-white/80"
      ],
      thead_th_attrs: [class: "px-6 py-3 relative p-0 pb-2 text-center"],
      tbody_tr_attrs: [
        class:
          "text-white bg-green-900 border-b dark:bg-black dark:border-green-800 hover:bg-green-200 dark:text-white/80"
      ],
      tbody_td_attrs: [class: "relative w-14 p-0 p-4 text-center"],
      symbol_attrs: [class: "text-xl"],
      th_wrapper_attrs: [class: "flex items-center justify-center space-x-1"],
      no_results_content:
        content_tag(:p, "No results.",
          class: "px-6 py-3 w-[40rem] mt-4 text-xl text-left text-white/80"
        )
    ]
  end
end
