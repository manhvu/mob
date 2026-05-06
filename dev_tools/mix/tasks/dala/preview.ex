defmodule Mix.Tasks.Dala.Preview do
  @moduledoc """
  Preview Dala UI designs in a browser without a simulator/emulator.

  This task generates an HTML preview of a Dala screen module or UI tree
  and opens it in the default browser. This is a dev-only tool and will
  not be included in production builds.

  ## Usage

      # Preview a screen module
      mix dala.preview MyApp.HomeScreen

      # Preview with custom output file
      mix dala.preview MyApp.HomeScreen --output preview.html

      # Don't open in browser (just generate the file)
      mix dala.preview MyApp.HomeScreen --no-open

      # Hide the component tree in the preview
      mix dala.preview MyApp.HomeScreen --no-tree

  ## Options

    * `--output` / `-o` - Output file path (default: dala_preview.html)
    * `--no-open` - Don't open in browser after generating
    * `--no-tree` - Don't show the component tree in the preview
    * `--title` - Custom title for the preview page

  ## Examples

      mix dala.preview MyApp.CounterScreen
      mix dala.preview MyApp.LoginScreen --output login_preview.html
      mix dala.preview MyApp.HomeScreen --title "Home Screen Preview" --no-open
  """

  use Mix.Task

  @shortdoc "Preview Dala UI designs in browser"

  @impl Mix.Task
  def run(args) do
    {opts, rest, _} = OptionParser.parse(args,
      switches: [output: :string, open: :boolean, tree: :boolean, title: :string],
      aliases: [o: :output]
    )

    output = Keyword.get(opts, :output, "dala_preview.html")
    open? = Keyword.get(opts, :open, true)
    show_tree? = Keyword.get(opts, :tree, true)
    title = Keyword.get(opts, :title)

    case rest do
      [] ->
        Mix.shell().error("Please provide a module name to preview.")
        Mix.shell().info("Usage: mix dala.preview ModuleName [options]")
        exit({:shutdown, 1})

      [module_name | _] ->
        module = Module.concat([module_name])

        unless Code.ensure_loaded?(module) do
          Mix.shell().error("Module #{module_name} not found or not compiled.")
          Mix.shell().info("Make sure the module is defined and the code is compiled.")
          exit({:shutdown, 1})
        end

        preview_opts = []
        preview_opts = if show_tree?, do: preview_opts, else: [{:show_tree, false} | preview_opts]
        preview_opts = if title, do: [{:title, title} | preview_opts], else: preview_opts

        Mix.shell().info("Generating preview for #{module_name}...")

        path = Dala.Preview.preview_to_file(module, output, preview_opts)

        if open? do
          Mix.shell().info("Opening preview in browser...")
          Dala.Preview.open_in_browser(path)
        else
          Mix.shell().info("Preview saved to: #{path}")
          Mix.shell().info("Open this file in your browser to view the preview.")
        end
    end
  end
end
