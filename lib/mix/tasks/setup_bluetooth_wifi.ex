defmodule Mix.Tasks.Dala.SetupBluetoothWifi do
  @shortdoc "One-command setup for Bluetooth and WiFi on iOS and Android"

  @moduledoc """
  One-command setup for Bluetooth and WiFi functionality in Dala apps.

  This task automates ALL production setup steps for Bluetooth and WiFi:

  ## iOS Setup
  1. Adds Bluetooth source files to Xcode project
  2. Links CoreBluetooth.framework
  3. Adds required Info.plist entries:
     - NSBluetoothAlwaysUsageDescription
     - NSBluetoothPeripheralUsageDescription
     - NSLocalNetworkUsageDescription
     - NSBonjourServices
  4. Patches AppDelegate to initialize Bluetooth bridge
  5. Configures background Bluetooth modes

  ## Android Setup
  1. Adds Bluetooth/WiFi permissions to AndroidManifest.xml
  2. Adds required features for BLE
  3. Copies DalaBridge.java if not present
  4. Patches MainActivity to call DalaBridge.init()

  ## Usage

      # Set up everything (recommended)
      mix dala.setup_bluetooth_wifi

      # Set up specific platform
      mix dala.setup_bluetooth_wifi --platform ios
      mix dala.setup_bluetooth_wifi --platform android

      # Check current setup without making changes
      mix dala.setup_bluetooth_wifi --check

      # Verbose output
      mix dala.setup_bluetooth_wifi --verbose

  ## Options

      --platform PLATFORM   Target platform: ios, android, or all (default: all)
      --check              Verify setup without making changes
      --verbose            Show detailed output
      --no-color           Disable colored output
      --dry-run            Alias for --check

  ## Examples

      # First time setup
      mix dala.setup_bluetooth_wifi

      # Verify everything is configured correctly
      mix dala.setup_bluetooth_wifi --check

      # Re-run after adding new permissions
      mix dala.setup_bluetooth_wifi --verbose

  ## Idempotent

  Safe to run multiple times - will not duplicate entries or cause conflicts.

  ## Prerequisites

  - iOS: Xcode project must exist in ios/ directory
  - Android: Android project must exist in android/ directory
  - Ruby (optional, for iOS Xcode project modification)
  """

  use Mix.Task

  @switches [
    platform: :string,
    check: :boolean,
    dry_run: :boolean,
    verbose: :boolean,
    no_color: :boolean
  ]

  @platforms [:ios, :android]

  @impl Mix.Task
  def run(argv) do
    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: @switches)

    platforms = parse_platforms(opts)
    check_only? = Keyword.get(opts, :check, false) or Keyword.get(opts, :dry_run, false)
    verbose? = Keyword.get(opts, :verbose, false)
    color? = not Keyword.get(opts, :no_color, false)

    banner(color?)

    if check_only? do
      check_setup(platforms, color?, verbose?)
    else
      run_setup(platforms, color?, verbose?)
    end
  end

  # ── Setup ────────────────────────────────────────────────────────────────────

  defp run_setup(platforms, color?, verbose?) do
    results =
      Enum.map(platforms, fn platform ->
        {platform, setup_platform(platform, color?, verbose?)}
      end)

    summary(results, color?)
  end

  defp setup_platform(:ios, color?, verbose?) do
    info(color?, "Setting up iOS Bluetooth/WiFi...")

    steps = [
      {"Checking prerequisites", fn -> check_ios_prerequisites(color?) end},
      {"Running iOS setup script", fn -> run_ios_setup(color?, verbose?) end},
      {"Verifying setup", fn -> verify_ios_setup(color?) end}
    ]

    run_steps(steps, color?)
  end

  defp setup_platform(:android, color?, verbose?) do
    info(color?, "Setting up Android Bluetooth/WiFi...")

    steps = [
      {"Checking prerequisites", fn -> check_android_prerequisites(color?) end},
      {"Running Android setup script", fn -> run_android_setup(color?, verbose?) end},
      {"Verifying setup", fn -> verify_android_setup(color?) end}
    ]

    run_steps(steps, color?)
  end

  defp run_steps(steps, color?) do
    Enum.reduce_while(steps, :ok, fn {name, step_fn}, _acc ->
      info(color?, "  → #{name}...")

      case step_fn.() do
        :ok ->
          success(color?, "  ✓ #{name} complete")
          {:cont, :ok}

        {:error, reason} ->
          error(color?, "  ✗ #{name} failed: #{reason}")
          {:halt, {:error, reason}}
      end
    end)
  end

  # ── iOS Setup Steps ──────────────────────────────────────────────────────────

  defp check_ios_prerequisites(color?) do
    ios_dir = "ios"

    unless File.dir?(ios_dir) do
      warning(color?, "  ⚠ No ios/ directory found")
      print_ios_manual_instructions(color?)
      {:error, "iOS directory not found"}
    else
      # Check for Xcode project
      xcode_projects =
        Path.wildcard("#{ios_dir}/**/*.xcodeproj") ++
          Path.wildcard("#{ios_dir}/**/*.xcworkspace")

      if Enum.empty?(xcode_projects) do
        warning(color?, "  ⚠ No Xcode project found in ios/")
        print_ios_manual_instructions(color?)
        {:error, "Xcode project not found"}
      else
        :ok
      end
    end
  end

  defp run_ios_setup(color?, verbose?) do
    script_path = "scripts/ios_setup.sh"

    if File.exists?(script_path) do
      args = if verbose?, do: ["--verbose"], else: []

      case System.cmd("bash", [script_path | args], stderr_to_stdout: true) do
        {output, 0} ->
          if verbose?, do: Mix.shell().info(output)
          :ok

        {output, _exit_code} ->
          error(color?, output)
          {:error, "iOS setup script failed"}
      end
    else
      warning(color?, "  ⚠ iOS setup script not found, using Elixir module")
      Dala.Setup.IOS.setup_bluetooth()
    end
  end

  defp verify_ios_setup(color?) do
    checks = [
      {"Bluetooth files", Dala.Setup.IOS.bluetooth_files_present?()},
      {"Xcode project", Dala.Setup.IOS.xcode_project_exists?()}
    ]

    failed =
      Enum.filter(checks, fn {_name, result} -> not result end)
      |> Enum.map(fn {name, _} -> name end)

    if Enum.empty?(failed) do
      :ok
    else
      {:error, "Missing: #{Enum.join(failed, ", ")}"}
    end
  end

  # ── Android Setup Steps ──────────────────────────────────────────────────────

  defp check_android_prerequisites(color?) do
    android_dir = "android"

    unless File.dir?(android_dir) do
      warning(color?, "  ⚠ No android/ directory found")
      print_android_manual_instructions(color?)
      {:error, "Android directory not found"}
    else
      # Check for AndroidManifest.xml
      manifests = Path.wildcard("#{android_dir}/**/AndroidManifest.xml")

      if Enum.empty?(manifests) do
        warning(color?, "  ⚠ No AndroidManifest.xml found in android/")
        print_android_manual_instructions(color?)
        {:error, "AndroidManifest.xml not found"}
      else
        :ok
      end
    end
  end

  defp run_android_setup(color?, verbose?) do
    script_path = "scripts/android_setup.sh"

    if File.exists?(script_path) do
      args = if verbose?, do: ["--verbose"], else: []

      case System.cmd("bash", [script_path | args], stderr_to_stdout: true) do
        {output, 0} ->
          if verbose?, do: Mix.shell().info(output)
          :ok

        {output, _exit_code} ->
          error(color?, output)
          {:error, "Android setup script failed"}
      end
    else
      warning(color?, "  ⚠ Android setup script not found, using Elixir module")
      Dala.Setup.Android.setup_bluetooth(nil)
      Dala.Setup.Android.setup_wifi(nil)
      Dala.Setup.Android.ensure_bridge_init()
    end
  end

  defp verify_android_setup(color?) do
    checks = [
      {"AndroidManifest.xml", Dala.Setup.Android.manifest_present?()},
      {"DalaBridge.java", Dala.Setup.Android.bluetooth_files_present?()}
    ]

    failed =
      Enum.filter(checks, fn {_name, result} -> not result end)
      |> Enum.map(fn {name, _} -> name end)

    if Enum.empty?(failed) do
      :ok
    else
      {:error, "Missing: #{Enum.join(failed, ", ")}"}
    end
  end

  # ── Check Mode ───────────────────────────────────────────────────────────────

  defp check_setup(platforms, color?, verbose?) do
    info(color?, "Checking Bluetooth/WiFi setup...\n")

    results =
      Enum.map(platforms, fn platform ->
        {platform, check_platform(platform, color?, verbose?)}
      end)

    check_summary(results, color?)
  end

  defp check_platform(:ios, color?, verbose?) do
    info(color?, "iOS:")

    checks = [
      {"Bluetooth files present", Dala.Setup.IOS.bluetooth_files_present?()},
      {"Xcode project exists", Dala.Setup.IOS.xcode_project_exists?()},
      {"Info.plist configured", check_ios_plist(color?)}
    ]

    Enum.each(checks, fn {name, result} ->
      if result do
        success(color?, "  ✓ #{name}")
      else
        error(color?, "  ✗ #{name}")
      end
    end)

    if verbose? do
      info(color?, "\n  Run `mix dala.setup_bluetooth_wifi --platform ios` to fix issues")
    end

    :ok
  end

  defp check_platform(:android, color?, verbose?) do
    info(color?, "Android:")

    checks = [
      {"AndroidManifest.xml present", Dala.Setup.Android.manifest_present?()},
      {"DalaBridge.java present", Dala.Setup.Android.bluetooth_files_present?()},
      {"Permissions configured", check_android_permissions(color?)}
    ]

    Enum.each(checks, fn {name, result} ->
      if result do
        success(color?, "  ✓ #{name}")
      else
        error(color?, "  ✗ #{name}")
      end
    end)

    if verbose? do
      info(color?, "\n  Run `mix dala.setup_bluetooth_wifi --platform android` to fix issues")
    end

    :ok
  end

  defp check_ios_plist(_color?) do
    case Path.wildcard("ios/**/Info.plist") do
      [] -> false
      paths -> Enum.any?(paths, &plist_has_bluetooth_keys?/1)
    end
  end

  defp plist_has_bluetooth_keys?(path) do
    content = File.read!(path)
    String.contains?(content, "NSBluetoothAlwaysUsageDescription")
  end

  defp check_android_permissions(_color?) do
    case Dala.Setup.Android.find_manifest() do
      nil -> false
      manifest_path -> manifest_has_bluetooth_permissions?(manifest_path)
    end
  end

  defp manifest_has_bluetooth_permissions?(path) do
    content = File.read!(path)
    String.contains?(content, "BLUETOOTH_SCAN") and String.contains?(content, "BLUETOOTH_CONNECT")
  end

  # ── Manual Instructions ──────────────────────────────────────────────────────

  defp print_ios_manual_instructions(color?) do
    info(color?, "")

    info(color?, """
    Manual iOS Setup Required
    =========================

    1. Create an iOS project in the ios/ directory
    2. Add these keys to your Info.plist:

       <key>NSBluetoothAlwaysUsageDescription</key>
       <string>Need Bluetooth for device communication</string>
       <key>NSBluetoothPeripheralUsageDescription</key>
       <string>Need Bluetooth for device communication</string>
       <key>NSLocalNetworkUsageDescription</key>
       <string>Need local network access for WiFi discovery</string>

    3. Link CoreBluetooth.framework in Xcode
    4. Add Bluetooth source files to your Xcode project
    5. Initialize in AppDelegate:

       // Swift
       DalaBluetoothBridge.ensureLinked()

       // Objective-C
       [DalaBluetoothBridge ensureLinked];
    """)
  end

  defp print_android_manual_instructions(color?) do
    info(color?, "")

    info(color?, """
    Manual Android Setup Required
    =============================

    1. Create an Android project in the android/ directory
    2. Add these permissions to AndroidManifest.xml:

       <uses-permission android:name="android.permission.BLUETOOTH" />
       <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
       <uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
       <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
       <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
       <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
       <uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />

    3. Add uses-feature:

       <uses-feature android:name="android.hardware.bluetooth_le"
                     android:required="false" />

    4. Initialize DalaBridge in MainActivity.onCreate():

       // Java
       DalaBridge.init(getApplicationContext());

       // Kotlin
       DalaBridge.init(applicationContext)
    """)
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp parse_platforms(opts) do
    case Keyword.get(opts, :platform, "all") do
      "all" -> @platforms
      "ios" -> [:ios]
      "android" -> [:android]
      other -> Mix.raise("Unknown platform: #{other}. Use ios, android, or all.")
    end
  end

  # ── Output ───────────────────────────────────────────────────────────────────

  defp banner(color?) do
    Mix.shell().info("""
    #{color(color?, :cyan, "╔══════════════════════════════════════════════════════╗", color?)}
    #{color(color?, :cyan, "║     Dala Bluetooth/WiFi Setup                       ║", color?)}
    #{color(color?, :cyan, "╚══════════════════════════════════════════════════════╝", color?)}
    """)
  end

  defp summary(results, color?) do
    Mix.shell().info("")

    Enum.each(results, fn
      {:ios, :ok} -> success(color?, "✓ iOS setup complete")
      {:ios, {:error, reason}} -> error(color?, "✗ iOS setup failed: #{reason}")
      {:android, :ok} -> success(color?, "✓ Android setup complete")
      {:android, {:error, reason}} -> error(color?, "✗ Android setup failed: #{reason}")
    end)

    Mix.shell().info("")

    if Enum.all?(results, fn {_, result} -> result == :ok end) do
      success(color?, "All platforms configured successfully!")
      Mix.shell().info("")

      Mix.shell().info("""
      Next steps:
        1. Open your Xcode project and verify the Bluetooth files are added
        2. Open your Android project and verify DalaBridge.init() is called
        3. Test with: Dala.Bluetooth.state()
        4. Run diagnostics: Dala.Setup.print_diagnostic()
      """)
    else
      warning(color?, "Some platforms had errors. Check the output above for details.")
    end
  end

  defp check_summary(results, color?) do
    Mix.shell().info("")

    all_ok =
      Enum.all?(results, fn
        {_, :ok} -> true
        _ -> false
      end)

    if all_ok do
      success(color?, "✓ All checks passed!")
    else
      error(color?, "✗ Some checks failed. Run without --check to fix issues.")
    end
  end

  defp info(color?, msg), do: Mix.shell().info(color(color?, :default, msg, color?))
  defp success(color?, msg), do: Mix.shell().info(color(color?, :green, msg, color?))
  defp warning(color?, msg), do: Mix.shell().info(color(color?, :yellow, msg, color?))
  defp error(color?, msg), do: Mix.shell().error(color(color?, :red, msg, color?))

  defp color(true, :cyan, text, _), do: IO.ANSI.cyan() <> text <> IO.ANSI.reset()
  defp color(true, :green, text, _), do: IO.ANSI.green() <> text <> IO.ANSI.reset()
  defp color(true, :yellow, text, _), do: IO.ANSI.yellow() <> text <> IO.ANSI.reset()
  defp color(true, :red, text, _), do: IO.ANSI.red() <> text <> IO.ANSI.reset()
  defp color(true, :default, text, _), do: text
  defp color(false, _, text, _), do: text
end

# Alias for easier discovery
defmodule Mix.Tasks.Dala.BtSetup do
  @shortdoc "Alias for dala.setup_bluetooth_wifi"
  @moduledoc "Alias for `mix dala.setup_bluetooth_wifi`"

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    Mix.Tasks.Dala.SetupBluetoothWifi.run(argv)
  end
end
