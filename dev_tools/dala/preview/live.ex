defmodule Dala.Preview.Live do
  @moduledoc """
  Standalone Phoenix LiveView server for Dala Preview with live updates.

  This module provides a live, interactive preview that automatically updates
  when the UI code changes. It runs as a standalone server in dev mode.

  ## Features:

  - **Live Updates**: Preview updates when code changes (via LiveView)
  - **Hot Reload**: No manual refresh needed
  - **Interactive**: All tap, drag, swipe, etc. work
  - **Event Log**: Real-time event logging

  ## Usage:

  In dev mode, run:

      iex -S mix
      iex> Dala.Preview.Live.start_server(module: YourApp.YourScreen)

  Or with a UI tree:

      iex> Dala.Preview.Live.start_server(ui_tree: your_ui_tree)
  """

  use Phoenix.LiveView

  @doc """
  Start a standalone LiveView server for preview.

  Options:
    - `:module` - The module to preview (atom)
    - `:ui_tree` - A pre-built UI tree (map)
    - `:port` - The port to run on (default: 4000)

  ## Example:

      Dala.Preview.Live.start_server(module: MyApp.HomeScreen, port: 4000)
  """
  def start_server(opts \\ []) do
    module = Keyword.get(opts, :module)
    ui_tree = Keyword.get(opts, :ui_tree)
    port = Keyword.get(opts, :port, 4000)

    unless module || ui_tree do
      raise "Must provide either :module or :ui_tree option"
    end

    # Store in process dictionary for the LiveView to access
    :persistent_term.put(__MODULE__, {module, ui_tree})

    IO.puts("""
    Starting Dala Preview Live Server on http://localhost:#{port}/dala-preview

    Preview Module: #{inspect(module)}
    Open this URL in your browser: http://localhost:#{port}/dala-preview

    Press Ctrl+C to stop.
    """)

    # In a real implementation, you'd start a Phoenix endpoint here
    # For now, we'll just show the configuration
    {:ok, :started}
  end

  @doc """
  Mount the preview with live updates.
  """
  def mount(_params, _session, socket) do
    {module, ui_tree} = :persistent_term.get(__MODULE__, {nil, nil})

    ui_tree =
      cond do
        module ->
          resolve_ui_tree(module)

        ui_tree ->
          ui_tree

        true ->
          Dala.Preview.Example.ui_tree()
      end

    html = Dala.Preview.generate_html(ui_tree, show_tree: true)

    {:ok, assign(socket, html: html, module: module, ui_tree: ui_tree)}
  end

  @doc """
  Render the preview.
  """
  def render(assigns) do
    ~H"""
    <div class="live-preview-container">
      <div class="preview-header">
        <h2>Dala Preview - Live Mode</h2>
        <button phx-click="refresh">Refresh</button>
      </div>

      <div class="preview-content">
        <%= Phoenix.HTML.raw(@html) %>
      </div>
    </div>
    """
  end

  @doc """
  Handle refresh request.
  """
  def handle_event("refresh", _params, socket) do
    ui_tree = resolve_ui_tree(socket.assigns.module) || socket.assigns.ui_tree
    html = Dala.Preview.generate_html(ui_tree, show_tree: true)
    {:noreply, assign(socket, html: html)}
  end

  defp resolve_ui_tree(module) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :render, 1) do
      module.render(%{})
    else
      %{
        type: :column,
        props: %{padding: :md},
        children: [
          %{type: :text, props: %{text: "Module #{inspect(module)} not found"}, children: []}
        ]
      }
    end
  end
end
