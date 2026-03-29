defmodule TProNVRWeb.FlopConfig do
  @moduledoc false

  use PhoenixHTMLHelpers

  def table_opts do
    [
      table_attrs: [
        class: "w-full mt-4 text-xs text-left text-green-500 tracking-widest uppercase border border-green-500 shadow-[0_0_15px_rgba(0,128,0,0.15)] bg-black/90 font-mono"
      ],
      thead_attrs: [
        class: "text-[10px] text-green-400 bg-green-900/40 border-b border-green-500"
      ],
      thead_th_attrs: [class: "px-6 py-4 relative p-0 pb-2 text-left"],
      tbody_tr_attrs: [
        class:
          "bg-black border-b border-green-900/50 hover:bg-green-900/20 transition-colors group"
      ],
      tbody_td_attrs: [class: "px-6 py-4 font-bold text-green-400 group-hover:text-green-300"],
      symbol_attrs: [class: "text-lg text-green-500 font-bold ml-1 inline-block"],
      th_wrapper_attrs: [class: "flex items-center justify-start space-x-2 text-green-500"],
      no_results_content:
        content_tag(:p, "NO_RECORDS_FOUND",
          class: "px-6 py-6 w-full mt-4 text-sm font-bold tracking-widest uppercase text-center text-green-700 font-mono border border-green-900/50"
        )
    ]
  end
end
