defmodule SimpleApp do
  @moduledoc """
  Simple Dala application demonstrating basic navigation and state management.

  ## How to run:

      cd examples/simple_app
      mix deps.get
      mix dala.deploy --native --ios-sim   # or --android-emu
  """
  use Dala.App

  def navigation(_platform) do
    stack(:home, root: SimpleApp.HomeScreen, title: "Home")
  end

  def on_start do
    # Pattern-match start_root so failures crash loudly (AGENTS.md Rule #2)
    {:ok, _pid} = Dala.Screen.start_root(SimpleApp.HomeScreen)
    :ok
  end
end
