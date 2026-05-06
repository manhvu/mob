defmodule Dala.Bluetooth do
  @moduledoc """
  Bluetooth Low Energy (BLE) support.

  Provides BLE central (client) and peripheral (server) functionality.
  Requires `:bluetooth` permission (request via `Dala.Permissions.request/2`).

  ## Events

  Bluetooth events arrive as:

      handle_info({:bluetooth, :state_changed, state}, socket)
      handle_info({:bluetooth, :device_found, %{id: id, name: name, rssi: rssi}}, socket)
      handle_info({:bluetooth, :device_connected, %{id: id, name: name}}, socket)
      handle_info({:bluetooth, :device_disconnected, %{id: id}}, socket)
      handle_info({:bluetooth, :characteristic_read, %{device: id, service: uuid, characteristic: uuid, value: data}}, socket)
      handle_info({:bluetooth, :characteristic_written, %{device: id, service: uuid, characteristic: uuid}}, socket)
      handle_info({:bluetooth, :notification_received, %{device: id, service: uuid, characteristic: uuid, value: data}}, socket)

  ## States

  - `:unknown` - State not determined
  - `:resetting` - Resetting
  - `:unsupported` - BLE not supported
  - `:unauthorized` - Permission denied
  - `:powered_off` - Bluetooth is off
  - `:powered_on` - Bluetooth is on and ready

  iOS: `CBCentralManager` / `CBPeripheralManager`.
  Android: `BluetoothAdapter` / `BluetoothLeScanner`.
  """

  @type state :: :unknown | :resetting | :unsupported | :unauthorized | :powered_off | :powered_on
  @type device_id :: String.t()
  @type uuid :: String.t()

  @doc """
  Check current Bluetooth state.
  """
  @spec state() :: state()
  def state do
    Dala.Native.bluetooth_state()
  end

  @doc """
  Start scanning for BLE devices.

  Options:
    - `services: [uuid]` - filter by service UUIDs (optional)
    - `timeout_ms: integer` - scan duration (default: 10000)

  Found devices arrive as `:bluetooth, :device_found` messages.
  """
  @spec start_scan(Dala.Socket.t(), keyword()) :: Dala.Socket.t()
  def start_scan(socket, opts \\ []) do
    services = Keyword.get(opts, :services, [])
    timeout_ms = Keyword.get(opts, :timeout_ms, 10_000)
    Dala.Native.bluetooth_start_scan(services, timeout_ms)
    socket
  end

  @doc """
  Stop scanning for devices.
  """
  @spec stop_scan(Dala.Socket.t()) :: Dala.Socket.t()
  def stop_scan(socket) do
    Dala.Native.bluetooth_stop_scan()
    socket
  end

  @doc """
  Connect to a BLE device.

  Device ID is obtained from `:device_found` event.
  """
  @spec connect(Dala.Socket.t(), device_id()) :: Dala.Socket.t()
  def connect(socket, device_id) do
    Dala.Native.bluetooth_connect(device_id)
    socket
  end

  @doc """
  Disconnect from a BLE device.
  """
  @spec disconnect(Dala.Socket.t(), device_id()) :: Dala.Socket.t()
  def disconnect(socket, device_id) do
    Dala.Native.bluetooth_disconnect(device_id)
    socket
  end

  @doc """
  Discover services for a connected device.
  """
  @spec discover_services(Dala.Socket.t(), device_id()) :: Dala.Socket.t()
  def discover_services(socket, device_id) do
    Dala.Native.bluetooth_discover_services(device_id)
    socket
  end

  @doc """
  Read a characteristic value.

  Results arrive as `:bluetooth, :characteristic_read` message.
  """
  @spec read_characteristic(Dala.Socket.t(), device_id(), uuid(), uuid()) :: Dala.Socket.t()
  def read_characteristic(socket, device_id, service_uuid, characteristic_uuid) do
    Dala.Native.bluetooth_read_characteristic(device_id, service_uuid, characteristic_uuid)
    socket
  end

  @doc """
  Write a characteristic value.

  Value should be a binary (for bytes) or integer/list for simple values.
  """
  @spec write_characteristic(Dala.Socket.t(), device_id(), uuid(), uuid(), binary()) ::
          Dala.Socket.t()
  def write_characteristic(socket, device_id, service_uuid, characteristic_uuid, value) do
    Dala.Native.bluetooth_write_characteristic(device_id, service_uuid, characteristic_uuid, value)
    socket
  end

  @doc """
  Subscribe to notifications for a characteristic.

  Notifications arrive as `:bluetooth, :notification_received` messages.
  """
  @spec subscribe(Dala.Socket.t(), device_id(), uuid(), uuid()) :: Dala.Socket.t()
  def subscribe(socket, device_id, service_uuid, characteristic_uuid) do
    Dala.Native.bluetooth_subscribe(device_id, service_uuid, characteristic_uuid)
    socket
  end

  @doc """
  Unsubscribe from notifications for a characteristic.
  """
  @spec unsubscribe(Dala.Socket.t(), device_id(), uuid(), uuid()) :: Dala.Socket.t()
  def unsubscribe(socket, device_id, service_uuid, characteristic_uuid) do
    Dala.Native.bluetooth_unsubscribe(device_id, service_uuid, characteristic_uuid)
    socket
  end
end
