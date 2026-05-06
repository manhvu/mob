defmodule Dala.Setup.IOS do
  @moduledoc """
  iOS Bluetooth/WiFi setup automation for Dala.

  This module provides automated setup for iOS Bluetooth and WiFi functionality
  by configuring the Xcode project with required files, frameworks, and
  Info.plist entries.

  ## Usage

  From the command line (via Mix task):

      mix dala.setup_ios_bluetooth
      mix dala.setup_ios_bluetooth --check

  From Elixir code:

      Dala.Setup.IOS.setup_bluetooth()
      Dala.Setup.IOS.setup_bluetooth("/path/to/ios/directory")
      Dala.Setup.IOS.check("/path/to/ios/directory")

  ## What it does

  1. Finds the Xcode project or workspace in the ios/ directory
  2. Adds Bluetooth files to the Xcode project:
     - DalaBluetoothManager.h
     - DalaBluetoothManager.m
     - DalaBluetoothCInterface.m
     - DalaBluetooth.swift
  3. Links CoreBluetooth.framework
  4. Adds required keys to Info.plist:
     - NSBluetoothAlwaysUsageDescription
     - NSBluetoothPeripheralUsageDescription
     - NSLocalNetworkUsageDescription
     - NSBonjourServices
     - UIBackgroundModes (bluetooth-central)
  5. Patches AppDelegate to call DalaBluetoothBridge.ensureLinked()
  6. Verifies the setup

  ## Prerequisites

  - Xcode project must exist in the ios/ directory
  - Ruby is preferred (for pbxproj modification); sed fallback if unavailable
  - plutil or PlistBuddy must be available (for Info.plist modification)
  """

  @type result :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Run the iOS Bluetooth/WiFi setup.

  Returns `{:ok, message}` on success, `{:error, reason}` on failure.
  """
  @spec setup_bluetooth(String.t() | nil) :: result()
  def setup_bluetooth(ios_dir \\ nil) do
    run_script(ios_dir, [])
  end

  @doc """
  Verify the current iOS Bluetooth/WiFi setup without making changes.

  Returns `{:ok, message}` if all checks pass, `{:error, reason}` otherwise.
  """
  @spec check(String.t() | nil) :: result()
  def check(ios_dir \\ nil) do
    run_script(ios_dir, ["--check"])
  end

  defp run_script(ios_dir, extra_args) do
    ios_dir = ios_dir || default_ios_dir()
    script_path = script_path()

    if !File.exists?(script_path) do
      {:error, "Setup script not found at #{script_path}"}
    else
      args = [script_path] ++ extra_args ++ [ios_dir]

      case System.cmd("bash", args, stderr_to_stdout: true) do
        {output, 0} ->
          {:ok, output}

        {output, _exit_code} ->
          {:error, output}
      end
    end
  end

  @doc """
  Check if Bluetooth files are present in the ios/ directory.
  """
  @spec bluetooth_files_present?(String.t() | nil) :: boolean()
  def bluetooth_files_present?(ios_dir \\ nil) do
    ios_dir = ios_dir || default_ios_dir()

    required_files = [
      "DalaBluetoothManager.h",
      "DalaBluetoothManager.m",
      "DalaBluetoothCInterface.m",
      "DalaBluetooth.swift"
    ]

    Enum.all?(required_files, fn file ->
      File.exists?(Path.join(ios_dir, file))
    end)
  end

  @doc """
  Check if an Xcode project exists in the given directory.
  """
  @spec xcode_project_exists?(String.t() | nil) :: boolean()
  def xcode_project_exists?(ios_dir \\ nil) do
    ios_dir = ios_dir || default_ios_dir()

    case find_xcode_project(ios_dir) do
      {:ok, _path} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Find the Xcode project or workspace in the given directory.
  """
  @spec find_xcode_project(String.t() | nil) :: {:ok, String.t()} | {:error, String.t()}
  def find_xcode_project(ios_dir \\ nil) do
    ios_dir = ios_dir || default_ios_dir()

    # Look for .xcworkspace first (preferred for CocoaPods)
    case Path.wildcard(Path.join(ios_dir, "**/*.xcworkspace")) do
      [workspace | _] ->
        {:ok, workspace}

      [] ->
        # Look for .xcodeproj
        case Path.wildcard(Path.join(ios_dir, "**/*.xcodeproj")) do
          [project | _] -> {:ok, project}
          [] -> {:error, "No Xcode project or workspace found in #{ios_dir}"}
        end
    end
  end

  @doc """
  Print setup instructions without running the script.
  """
  @spec print_instructions() :: :ok
  def print_instructions do
    instructions = """
    iOS Bluetooth/WiFi Setup Instructions
    =====================================

    1. Ensure you have an Xcode project in your ios/ directory
    2. Run the setup script:

       mix dala.setup_ios_bluetooth

    3. Or manually run the script:

       bash scripts/ios_setup.sh

    4. After setup, open your Xcode project and verify:
       - Bluetooth files are added to the project
       - CoreBluetooth.framework is linked
       - Info.plist contains Bluetooth usage descriptions

    5. Initialize the Bluetooth manager in your AppDelegate:

       import CoreBluetooth

       // In your AppDelegate or early in app lifecycle:
       DalaBluetoothBridge.ensureLinked()

    6. Request Bluetooth permissions in your Elixir code:

       # Check Bluetooth state
       bluetooth_state = Dala.Bluetooth.state()

       case bluetooth_state do
         :powered_on ->
           Dala.Bluetooth.start_scan(socket)
         :unauthorized ->
           # Request permission via Dala.Permissions
           Dala.Permissions.request(socket, :bluetooth)
         other_state ->
           IO.puts("Bluetooth state: " <> to_string(other_state))
       end

    Required Info.plist keys (added automatically by script):
    - NSBluetoothAlwaysUsageDescription
    - NSBluetoothPeripheralUsageDescription
    - NSLocalNetworkUsageDescription
    - NSBonjourServices
    - UIBackgroundModes (bluetooth-central)

    AppDelegate initialization (added automatically by script):
    - DalaBluetoothBridge.ensureLinked() in didFinishLaunchingWithOptions
    - For SwiftUI apps: DalaAppDelegate.swift with UIApplicationDelegateAdaptor
    """

    IO.puts(instructions)
  end

  # Private functions

  defp default_ios_dir do
    Path.join([:code.priv_dir(:dala), "..", "ios"])
    |> Path.expand()
  end

  defp script_path do
    Path.join([:code.priv_dir(:dala), "..", "scripts", "ios_setup.sh"])
    |> Path.expand()
  end
end
