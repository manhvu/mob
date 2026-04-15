defmodule Mob.Location do
  @moduledoc """
  Device location (GPS / network).

  Requires `:location` permission (request via `Mob.Permissions.request/2`).

  Location updates arrive as:

      handle_info({:location, %{lat: lat, lon: lon, accuracy: acc, altitude: alt}}, socket)
      handle_info({:location, :error, reason}, socket)

  iOS: `CLLocationManager`. Android: `FusedLocationProviderClient`.
  """

  @type accuracy :: :high | :balanced | :low

  @doc """
  Request a single location fix, then stop.
  """
  @spec get_once(Mob.Socket.t()) :: Mob.Socket.t()
  def get_once(socket) do
    :mob_nif.location_get_once()
    socket
  end

  @doc """
  Start continuous location updates.

  Options:
    - `accuracy: :high | :balanced | :low` (default `:balanced`)

  Call `stop/1` when done to save battery.
  """
  @spec start(Mob.Socket.t(), keyword()) :: Mob.Socket.t()
  def start(socket, opts \\ []) do
    accuracy = Keyword.get(opts, :accuracy, :balanced)
    :mob_nif.location_start(accuracy)
    socket
  end

  @doc """
  Stop continuous location updates.
  """
  @spec stop(Mob.Socket.t()) :: Mob.Socket.t()
  def stop(socket) do
    :mob_nif.location_stop()
    socket
  end
end
