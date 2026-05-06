defmodule Dala.Settings do
  @compile {:nowarn_undefined, [:dala_nif]}

  @moduledoc """
  Persistent app settings (UserDefaults on iOS, SharedPreferences on Android).

  ## Examples

      # Get a setting value
      Dala.Settings.get("theme")

      # Set a setting value
      socket = Dala.Settings.set(socket, "theme", "dark")

      # Watch a key for changes (messages arrive via handle_info)
      socket = Dala.Settings.watch(socket, "theme")

  Incoming change messages are delivered to screens via `handle_info/2`:

      def handle_info({:settings, :changed, {key, value}}, socket) do
        # React to setting change
        {:noreply, socket}
      end
  """

  @spec get(String.t()) :: any() | nil
  def get(key) when is_binary(key) do
    :dala_nif.settings_get(key)
  end

  @spec set(Dala.Socket.t(), String.t(), any()) :: Dala.Socket.t()
  def set(socket, key, value) when is_binary(key) do
    :dala_nif.settings_set(key, value)
    socket
  end

  @spec watch(Dala.Socket.t(), String.t()) :: Dala.Socket.t()
  def watch(socket, key) when is_binary(key) do
    :dala_nif.settings_watch(key)
    socket
  end
end
