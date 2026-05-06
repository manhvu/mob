defmodule Mix.Tasks.Dala.SetupIosBluetooth do
  @shortdoc "Set up iOS Bluetooth/WiFi integration for Dala"

  @moduledoc """
  Automated setup for iOS Bluetooth and WiFi functionality in Dala.

  This task configures your iOS project by:
  1. Adding Bluetooth source files to the Xcode project
  2. Linking CoreBluetooth.framework
  3. Adding required Info.plist entries for Bluetooth usage

  ## Usage

      mix dala.setup_ios_bluetooth              # Use default ios/ directory
      mix dala.setup_ios_bluetooth /path/to/ios # Specify custom path

  ## Examples

      # Set up with default settings
      mix dala.setup_ios_bluetooth

      # Set up with verbose output
      mix dala.setup_ios_bluetooth --verbose

      # Check what would be done without making changes
      mix dala.setup_ios_bluetooth --dry-run

  ## Options

      --check        Verify current setup without making changes
      --dry-run      Show what would be done without making changes
      --verbose      Show detailed output
      --help         Show this help message

  ## Prerequisites

  - Xcode project must exist in the ios/ directory
  - Ruby is preferred (for pbxproj modification); sed fallback if unavailable
  - plutil or PlistBuddy must be available (for Info.plist modification)

  The required Bluetooth files should already exist in the ios/ directory:
  - DalaBluetoothManager.h
  - DalaBluetoothManager.m
  - DalaBluetoothCInterface.m
  - DalaBluetooth.swift
  """

  use Mix.Task

  @switches [
    check: :boolean,
    dry_run: :boolean,
    verbose: :boolean,
    help: :boolean
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, args, _invalid} = OptionParser.parse(argv, strict: @switches)

    if opts[:help] do
      print_help()
      exit(:normal)
    end

    ios_dir = parse_ios_dir(args)

    cond do
      opts[:check] ->
        run_check(ios_dir)

      opts[:dry_run] ->
        dry_run(ios_dir)

      true ->
        run_setup(ios_dir, opts)
    end
  end

  defp parse_ios_dir(args) do
    case args do
      [path | _] -> path
      [] -> nil
    end
  end

  defp run_setup(ios_dir, opts) do
    Mix.shell().info("""
    ╔══════════════════════════════════════════════════════╗
    ║     Dala iOS Bluetooth/WiFi Setup                     ║
    ╚══════════════════════════════════════════════════════╝
    """)

    # Check prerequisites
    unless Dala.Setup.IOS.bluetooth_files_present?(ios_dir) do
      Mix.shell().error("Bluetooth files not found in ios/ directory.")
      Mix.shell().info("Required files:")
      Mix.shell().info("  - DalaBluetoothManager.h")
      Mix.shell().info("  - DalaBluetoothManager.m")
      Mix.shell().info("  - DalaBluetoothCInterface.m")
      Mix.shell().info("  - DalaBluetooth.swift")
      Mix.raise("Missing Bluetooth files")
    end

    unless Dala.Setup.IOS.xcode_project_exists?(ios_dir) do
      Mix.shell().error("No Xcode project found in #{ios_dir || "ios/"} directory.")
      Mix.shell().info("Please create an Xcode project first.")
      Mix.raise("Xcode project not found")
    end

    Mix.shell().info("Prerequisites check passed.")

    if opts[:verbose] do
      Mix.shell().info("Running setup with verbose output...")
    end

    case Dala.Setup.IOS.setup_bluetooth(ios_dir) do
      {:ok, output} ->
        Mix.shell().info("Setup completed successfully!")

        if opts[:verbose] do
          Mix.shell().info(output)
        end

      {:error, reason} ->
        Mix.shell().error("Setup failed:")
        Mix.shell().error(reason)
        Mix.raise("iOS Bluetooth setup failed")
    end
  end

  defp run_check(ios_dir) do
    Mix.shell().info("Checking iOS Bluetooth/WiFi setup...\n")

    case Dala.Setup.IOS.check(ios_dir) do
      {:ok, output} ->
        Mix.shell().info(output)

      {:error, reason} ->
        Mix.shell().error(reason)
        Mix.raise("iOS Bluetooth setup check failed")
    end
  end

  defp dry_run(ios_dir) do
    Mix.shell().info("Dry run - no changes will be made\n")

    case Dala.Setup.IOS.find_xcode_project(ios_dir) do
      {:ok, project} ->
        Mix.shell().info("Found Xcode project: #{project}")

      {:error, reason} ->
        Mix.shell().info("Xcode project: NOT FOUND (#{reason})")
    end

    if Dala.Setup.IOS.bluetooth_files_present?(ios_dir) do
      Mix.shell().info("Bluetooth files: PRESENT")
    else
      Mix.shell().info("Bluetooth files: MISSING")
    end

    Mix.shell().info("\nDry run complete. Run without --dry-run to apply changes.")
  end

  defp print_help do
    Mix.shell().info(@moduledoc)
  end
end
