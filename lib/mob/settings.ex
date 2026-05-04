defmodule Mob.Settings do
  @moduledoc """
  Persistent app settings (UserDefaults on iOS, SharedPreferences on Android).

  ## Examples

      # Get a setting value
      Mob.Settings.get("theme") #=> nil (stub)

      # Set a setting value
      socket = Mob.Settings.set(socket, "theme", "dark")

      # Watch a key for changes (messages arrive via handle_info)
      socket = Mob.Settings.watch(socket, "theme")

  Incoming change messages are delivered to screens via `handle_info/2`:

      def handle_info({:settings, :changed, {key, value}}, socket) do
        # React to setting change
        {:noreply, socket}
      end
  """

  @spec get(String.t()) :: any() | nil
  def get(key) when is_binary(key) do
    nil
  end

  @spec set(Mob.Socket.t(), String.t(), any()) :: Mob.Socket.t()
  def set(socket, key, value) when is_binary(key) do
    socket
  end

  @spec watch(Mob.Socket.t(), String.t()) :: Mob.Socket.t()
  def watch(socket, key) when is_binary(key) do
    socket
  end
end
