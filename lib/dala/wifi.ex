defmodule Dala.WiFi do
  @compile {:nowarn_undefined, [:dala_nif]}
  @moduledoc """
  WiFi network information and configuration.

  Provides access to WiFi network state, connected network info,
  and (where supported) the ability to scan for nearby networks.

  Requires `:wifi` permission on Android (iOS does not expose WiFi scanning to apps).

  ## Events

  WiFi events arrive as:

      handle_info({:wifi, :state_changed, %{connected: boolean, ssid: ssid, bssid: bssid, ip: ip}}, socket)
      handle_info({:wifi, :scan_result, [%{ssid: ssid, bssid: bssid, rssi: rssi, security: security}]}, socket)

  iOS: `NEHotspotConfigurationManager` (limited), `CNCopyCurrentNetworkInfo` (deprecated but works).
  Android: `WifiManager`, `ConnectivityManager`.
  """

  @type security_type :: :open | :wep | :wpa | :wpa2 | :wpa3 | :unknown

  @doc """
  Get currently connected WiFi network info.

  Returns:
      %{
        connected: boolean,
        ssid: String.t() | nil,
        bssid: String.t() | nil,
        ip: String.t() | nil,
        rssi: integer | nil
      }
  """
  @spec current_network() :: map()
  def current_network do
    :dala_nif.wifi_current_network()
  end

  @doc """
  Check if device is connected to WiFi.
  """
  @spec connected?() :: boolean()
  def connected? do
    case current_network() do
      %{connected: true} -> true
      _ -> false
    end
  end

  @doc """
  Scan for nearby WiFi networks (Android only).

  Results arrive as `:wifi, :scan_result` message.

  iOS: Not supported by public APIs (will return `{:error, :not_supported}`).
  """
  @spec scan(Dala.Socket.t()) :: Dala.Socket.t()
  def scan(socket) do
    :dala_nif.wifi_scan()
    socket
  end

  @doc """
  Get WiFi IP address (convenience wrapper).
  """
  @spec ip_address() :: String.t() | nil
  def ip_address do
    case current_network() do
      %{ip: ip} when is_binary(ip) -> ip
      _ -> nil
    end
  end

  @doc """
  Enable WiFi (Android only, requires special permissions).

  iOS: Not supported.
  """
  @spec enable() :: :ok | {:error, term()}
  def enable do
    :dala_nif.wifi_enable()
  end

  @doc """
  Disable WiFi (Android only, requires special permissions).

  iOS: Not supported.
  """
  @spec disable() :: :ok | {:error, term()}
  def disable do
    :dala_nif.wifi_disable()
  end
end
