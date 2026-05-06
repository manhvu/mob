defmodule Dala.Setup.Android do
  @moduledoc """
  Android Bluetooth/WiFi setup automation for Dala.

  This module provides automated setup for Android Bluetooth and WiFi functionality
  by configuring the AndroidManifest.xml with required permissions and features,
  and ensuring DalaBridge.init() is called in the MainActivity.

  ## Usage

  From the command line (via Mix task):

      mix dala.setup_bluetooth_wifi --platform android

  From Elixir code:

      Dala.Setup.Android.setup_bluetooth()
      Dala.Setup.Android.setup_bluetooth("/path/to/android/directory")

  ## What it does

  1. Finds AndroidManifest.xml in the android/ directory
  2. Adds required Bluetooth permissions:
     - BLUETOOTH
     - BLUETOOTH_ADMIN
     - BLUETOOTH_SCAN
     - BLUETOOTH_CONNECT
     - ACCESS_FINE_LOCATION
  3. Adds required WiFi permissions:
     - ACCESS_WIFI_STATE
     - CHANGE_WIFI_STATE
  4. Adds uses-feature for bluetooth_le with required=false
  5. Ensures DalaBridge.init() is called in MainActivity

  ## Prerequisites

  - Android project must exist with an AndroidManifest.xml
  - DalaBridge.java should be present in the project
  """

  @type result :: {:ok, String.t()} | {:error, String.t()}

  @bluetooth_permissions [
    "android.permission.BLUETOOTH",
    "android.permission.BLUETOOTH_ADMIN",
    "android.permission.BLUETOOTH_SCAN",
    "android.permission.BLUETOOTH_CONNECT",
    "android.permission.ACCESS_FINE_LOCATION"
  ]

  @wifi_permissions [
    "android.permission.ACCESS_WIFI_STATE",
    "android.permission.CHANGE_WIFI_STATE"
  ]

  @bluetooth_features [
    {"android.hardware.bluetooth_le", "false"}
  ]

  # ── Public API ───────────────────────────────────────────────────────────────

  @doc """
  Run the Android Bluetooth setup.

  Adds Bluetooth permissions and features to AndroidManifest.xml.
  Idempotent — will not duplicate entries.

  Returns `{:ok, message}` on success, `{:error, reason}` on failure.
  """
  @spec setup_bluetooth(String.t() | nil) :: result()
  def setup_bluetooth(android_dir \\ nil) do
    android_dir = android_dir || default_android_dir()

    case find_manifest_in_dir(android_dir) do
      nil ->
        {:error, "No AndroidManifest.xml found in #{android_dir}"}

      manifest_path ->
        case add_permissions_to_manifest(manifest_path, @bluetooth_permissions) do
          {:ok, perm_result} ->
            case add_features_to_manifest(manifest_path, @bluetooth_features) do
              {:ok, feature_result} ->
                messages = [perm_result, feature_result] |> Enum.reject(&(&1 == ""))
                {:ok, Enum.join(messages, "\n")}

              {:error, reason} ->
                {:error, reason}
            end

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Run the Android WiFi setup.

  Adds WiFi permissions to AndroidManifest.xml.
  Idempotent — will not duplicate entries.

  Returns `{:ok, message}` on success, `{:error, reason}` on failure.
  """
  @spec setup_wifi(String.t() | nil) :: result()
  def setup_wifi(android_dir \\ nil) do
    android_dir = android_dir || default_android_dir()

    case find_manifest_in_dir(android_dir) do
      nil ->
        {:error, "No AndroidManifest.xml found in #{android_dir}"}

      manifest_path ->
        add_permissions_to_manifest(manifest_path, @wifi_permissions)
    end
  end

  @doc """
  Check if DalaBridge.init() is called in the project.

  Looks for the init call in MainActivity or Application class files.
  If not found, prints instructions for adding it.
  Optionally tries to add it automatically if the file is found.
  """
  @spec ensure_bridge_init() :: :ok | {:error, String.t()}
  def ensure_bridge_init do
    java_files = find_java_files()

    main_activity =
      Enum.find(java_files, fn path ->
        basename = Path.basename(path)
        String.contains?(basename, "MainActivity")
      end)

    application_class =
      Enum.find(java_files, fn path ->
        basename = Path.basename(path)

        String.contains?(basename, "Application") and
          (String.ends_with?(basename, ".java") or String.ends_with?(basename, ".kt"))
      end)

    target_file = main_activity || application_class

    cond do
      target_file == nil ->
        Mix.shell().info("""
        No MainActivity or Application class found.

        Add DalaBridge.init() to your MainActivity's onCreate method:

            // In MainActivity.java:
            @Override
            protected void onCreate(Bundle savedInstanceState) {
                super.onCreate(savedInstanceState);
                DalaBridge.init();  // Add this line
            }

        Or in MainActivity.kt:

            override fun onCreate(savedInstanceState: Bundle?) {
                super.onCreate(savedInstanceState)
                DalaBridge.init()  // Add this line
            }
        """)

        {:error, "No MainActivity or Application class found"}

      bridge_init_present?(target_file) ->
        Mix.shell().info("✓ DalaBridge.init() already present in #{Path.basename(target_file)}")
        :ok

      true ->
        add_dala_bridge_init(target_file)
    end
  end

  @doc """
  Check if DalaBridge.java exists in the project.
  """
  @spec bluetooth_files_present?() :: boolean()
  def bluetooth_files_present? do
    find_java_files()
    |> Enum.any?(fn path ->
      Path.basename(path) == "DalaBridge.java"
    end)
  end

  @doc """
  Check if AndroidManifest.xml exists in the project.
  """
  @spec manifest_present?() :: boolean()
  def manifest_present? do
    find_manifest() != nil
  end

  @doc """
  Find the AndroidManifest.xml path.

  Searches both common Android project layouts:
  - `android/src/main/AndroidManifest.xml`
  - `android/app/src/main/AndroidManifest.xml`

  Returns the path if found, nil otherwise.
  """
  @spec find_manifest() :: String.t() | nil
  def find_manifest do
    find_manifest_in_dir(default_android_dir())
  end

  @doc """
  Find Java/Kotlin source files in the Android project.

  Searches both common Android project layouts for .java and .kt files.
  """
  @spec find_java_files() :: [String.t()]
  def find_java_files do
    android_dir = default_android_dir()

    search_dirs =
      [
        Path.join(android_dir, "src/main/java"),
        Path.join(android_dir, "app/src/main/java"),
        Path.join(android_dir, "src/main/kotlin"),
        Path.join(android_dir, "app/src/main/kotlin")
      ]
      |> Enum.filter(&File.dir?/1)

    Enum.flat_map(search_dirs, fn dir ->
      Path.wildcard(Path.join(dir, "**/*.{java,kt}"))
    end)
  end

  @doc """
  Add DalaBridge.init() call to the given Java/Kotlin file.

  Inserts the init call into the onCreate method. If no onCreate method
  exists, prints instructions for manual addition.

  Returns `:ok` on success, `{:error, reason}` on failure.
  """
  @spec add_dala_bridge_init(String.t()) :: :ok | {:error, String.t()}
  def add_dala_bridge_init(file_path) do
    content = File.read!(file_path)
    basename = Path.basename(file_path)
    is_kotlin = String.ends_with?(basename, ".kt")

    if bridge_init_present?(content) do
      Mix.shell().info("✓ DalaBridge.init() already present in #{basename}")
      :ok
    else
      cond do
        is_kotlin and String.contains?(content, "fun onCreate") ->
          insert_bridge_init_kotlin(file_path, content)

        not is_kotlin and String.contains?(content, "void onCreate") ->
          insert_bridge_init_java(file_path, content)

        true ->
          Mix.shell().info("""
          Could not find onCreate method in #{basename}.

          Add DalaBridge.init() to your MainActivity's onCreate method:

          #{if is_kotlin do
            """
                override fun onCreate(savedInstanceState: Bundle?) {
                    super.onCreate(savedInstanceState)
                    DalaBridge.init()  // Add this line
                }
            """
          else
            """
                @Override
                protected void onCreate(Bundle savedInstanceState) {
                    super.onCreate(savedInstanceState);
                    DalaBridge.init();  // Add this line
                }
            """
          end}
          """)

          {:error, "No onCreate method found in #{basename}"}
      end
    end
  end

  @doc """
  Print setup instructions without making changes.
  """
  @spec print_instructions() :: :ok
  def print_instructions do
    Mix.shell().info("""
    Android Bluetooth/WiFi Setup Instructions
    ==========================================

    1. Ensure you have an Android project with AndroidManifest.xml
    2. Run the setup task:

       mix dala.setup_bluetooth_wifi --platform android

    3. Or manually add permissions to your AndroidManifest.xml:

       <uses-permission android:name="android.permission.BLUETOOTH" />
       <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
       <uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
       <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
       <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
       <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
       <uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
       <uses-feature android:name="android.hardware.bluetooth_le" android:required="false" />

    4. Add DalaBridge.init() to your MainActivity:

       // Java:
       @Override
       protected void onCreate(Bundle savedInstanceState) {
           super.onCreate(savedInstanceState);
           DalaBridge.init();
       }

       // Kotlin:
       override fun onCreate(savedInstanceState: Bundle?) {
           super.onCreate(savedInstanceState)
           DalaBridge.init()
       }

    5. Request Bluetooth permissions at runtime (Android 12+):

       # In your Elixir code:
       Dala.Permissions.request(socket, :bluetooth)

    Required permissions (added automatically by setup):
    - BLUETOOTH / BLUETOOTH_ADMIN (legacy, Android 11 and below)
    - BLUETOOTH_SCAN / BLUETOOTH_CONNECT (Android 12+)
    - ACCESS_FINE_LOCATION (needed for BLE scanning)
    - ACCESS_WIFI_STATE / CHANGE_WIFI_STATE (WiFi functionality)
    """)
  end

  # ── Manifest manipulation ────────────────────────────────────────────────────

  defp add_permissions_to_manifest(manifest_path, permissions) do
    content = File.read!(manifest_path)

    {updated, added} =
      Enum.reduce(permissions, {content, []}, fn perm, {acc, added} ->
        pattern = "android:name=\"#{perm}\""

        if String.contains?(acc, pattern) do
          {acc, added}
        else
          new_entry = "    <uses-permission android:name=\"#{perm}\" />\n</manifest>"
          updated = String.replace(acc, "</manifest>", new_entry)
          {updated, [perm | added]}
        end
      end)

    if added != [] do
      File.write!(manifest_path, updated)
      added_names = Enum.map(added, &String.replace(&1, "android.permission.", ""))
      {:ok, "Added permissions: #{Enum.join(added_names, ", ")}"}
    else
      {:ok, ""}
    end
  rescue
    e -> {:error, "Failed to modify #{manifest_path}: #{inspect(e)}"}
  end

  defp add_features_to_manifest(manifest_path, features) do
    content = File.read!(manifest_path)

    {updated, added} =
      Enum.reduce(features, {content, []}, fn {feature, required}, {acc, added} ->
        pattern = "android:name=\"#{feature}\""

        if String.contains?(acc, pattern) do
          {acc, added}
        else
          new_entry =
            "    <uses-feature android:name=\"#{feature}\" android:required=\"#{required}\" />\n</manifest>"

          updated = String.replace(acc, "</manifest>", new_entry)
          {updated, [feature | added]}
        end
      end)

    if added != [] do
      File.write!(manifest_path, updated)
      added_names = Enum.map(added, &String.replace(&1, "android.hardware.", ""))
      {:ok, "Added features: #{Enum.join(added_names, ", ")}"}
    else
      {:ok, ""}
    end
  rescue
    e -> {:error, "Failed to modify #{manifest_path}: #{inspect(e)}"}
  end

  # ── Bridge init insertion ────────────────────────────────────────────────────

  defp insert_bridge_init_java(file_path, content) do
    # Insert DalaBridge.init() after super.onCreate() in Java
    updated =
      String.replace(
        content,
        "super.onCreate(savedInstanceState);",
        "super.onCreate(savedInstanceState);\n        DalaBridge.init();"
      )

    File.write!(file_path, updated)
    Mix.shell().info("✓ Added DalaBridge.init() to #{Path.basename(file_path)}")
    :ok
  rescue
    e -> {:error, "Failed to modify #{file_path}: #{inspect(e)}"}
  end

  defp insert_bridge_init_kotlin(file_path, content) do
    # Insert DalaBridge.init() after super.onCreate() in Kotlin
    updated =
      String.replace(
        content,
        "super.onCreate(savedInstanceState)",
        "super.onCreate(savedInstanceState)\n        DalaBridge.init()"
      )

    File.write!(file_path, updated)
    Mix.shell().info("✓ Added DalaBridge.init() to #{Path.basename(file_path)}")
    :ok
  rescue
    e -> {:error, "Failed to modify #{file_path}: #{inspect(e)}"}
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp bridge_init_present?(file_path) when is_binary(file_path) do
    case File.read(file_path) do
      {:ok, content} -> bridge_init_present?(content)
      _ -> false
    end
  end

  defp bridge_init_present?(content) when is_binary(content) do
    String.contains?(content, "DalaBridge.init()")
  end

  defp find_manifest_in_dir(dir) do
    search_patterns = [
      Path.join(dir, "src/main/AndroidManifest.xml"),
      Path.join(dir, "app/src/main/AndroidManifest.xml")
    ]

    # Check exact paths first
    # Fall back to wildcard search
    Enum.find(search_patterns, &File.exists?/1) ||
      Path.wildcard(Path.join(dir, "**/AndroidManifest.xml"))
      |> List.first()
  end

  defp default_android_dir do
    Path.join([:code.priv_dir(:dala), "..", "android"])
    |> Path.expand()
  end
end
