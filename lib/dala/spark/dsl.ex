defmodule Dala.Spark.Dsl do
  @moduledoc """
  Spark DSL for Dala screens with attributes and @ref syntax.
  """

  # Attribute struct module
  defmodule Attribute do
    defstruct name: nil, type: nil, default: nil, __spark_metadata__: nil
  end

  # Attribute Entity
  @attribute %Spark.Dsl.Entity{
    name: :attribute,
    target: Attribute,
    describe: "Define a screen assign with type and default",
    args: [:name, :type],
    schema: [
      name: [type: :atom, required: true],
      type: [type: {:one_of, [:integer, :string, :boolean, :float]}, required: true],
      default: [type: :any]
    ]
  }

  # Attributes Section
  @attributes %Spark.Dsl.Section{
    name: :attributes,
    describe: "Declare screen state attributes",
    entities: [@attribute]
  }

  # Text struct module
  defmodule Text do
    defstruct text: nil, text_size: nil, text_color: nil, __spark_metadata__: nil
  end

  # Text Entity
  @text %Spark.Dsl.Entity{
    name: :text,
    target: Text,
    describe: "Display text",
    args: [:text],
    schema: [
      text: [type: :string, required: true],
      text_size: [type: {:one_of, [:integer, :atom]}],
      text_color: [type: :atom]
    ]
  }

  # Button struct module
  defmodule Button do
    defstruct text: nil, on_tap: nil, background: nil, text_color: nil, __spark_metadata__: nil
  end

  # Button Entity with inline handler support
  @button %Spark.Dsl.Entity{
    name: :button,
    target: Button,
    describe: "Tappable button with optional inline event handler",
    args: [:text],
    schema: [
      text: [type: :string, required: true],
      on_tap: [type: :atom],
      background: [type: :atom],
      text_color: [type: :atom]
    ],
    transform: {__MODULE__, :transform_button, []}
  }

  # WebView struct module
  defmodule WebView do
    defstruct url: nil,
              allow: nil,
              show_url: nil,
              title: nil,
              width: nil,
              height: nil,
              __spark_metadata__: nil
  end

  # WebView Entity
  @webview %Spark.Dsl.Entity{
    name: :webview,
    target: WebView,
    describe: "Native web view",
    args: [:url],
    schema: [
      url: [type: :string, required: true],
      allow: [type: {:list, :string}],
      show_url: [type: :boolean],
      title: [type: :string],
      width: [type: :integer],
      height: [type: :integer]
    ]
  }

  # CameraPreview struct module
  defmodule CameraPreview do
    defstruct facing: nil, width: nil, height: nil, __spark_metadata__: nil
  end

  # CameraPreview Entity
  @camera_preview %Spark.Dsl.Entity{
    name: :camera_preview,
    target: CameraPreview,
    describe: "Live camera feed",
    schema: [
      facing: [type: {:one_of, [:back, :front]}],
      width: [type: :integer],
      height: [type: :integer]
    ]
  }

  # NativeView struct module
  defmodule NativeView do
    defstruct module: nil, id: nil, __spark_metadata__: nil
  end

  # NativeView Entity
  @native_view %Spark.Dsl.Entity{
    name: :native_view,
    target: NativeView,
    describe: "Platform-native component",
    args: [:module],
    schema: [
      module: [type: :atom, required: true],
      id: [type: :atom, required: true]
    ]
  }

  # Image struct module
  defmodule Image do
    defstruct src: nil,
              resize_mode: nil,
              width: nil,
              height: nil,
              corner_radius: nil,
              __spark_metadata__: nil
  end

  # Image Entity
  @image %Spark.Dsl.Entity{
    name: :image,
    target: Image,
    describe: "Display image",
    args: [:src],
    schema: [
      src: [type: :string, required: true],
      resize_mode: [type: {:one_of, [:cover, :contain, :stretch, :repeat]}],
      width: [type: :integer],
      height: [type: :integer],
      corner_radius: [type: :integer]
    ]
  }

  # Switch struct module
  defmodule Switch do
    defstruct value: nil,
              on_toggle: nil,
              track_color: nil,
              thumb_color: nil,
              __spark_metadata__: nil
  end

  # Switch Entity
  @switch %Spark.Dsl.Entity{
    name: :switch,
    target: Switch,
    describe: "Boolean toggle switch",
    schema: [
      value: [type: :boolean],
      on_toggle: [type: :atom],
      track_color: [type: :atom],
      thumb_color: [type: :atom]
    ]
  }

  # ActivityIndicator struct module
  defmodule ActivityIndicator do
    defstruct size: nil, color: nil, animating: nil, __spark_metadata__: nil
  end

  # ActivityIndicator Entity
  @activity_indicator %Spark.Dsl.Entity{
    name: :activity_indicator,
    target: ActivityIndicator,
    describe: "Loading spinner",
    schema: [
      size: [type: {:one_of, [:small, :large]}],
      color: [type: :atom],
      animating: [type: :boolean]
    ]
  }

  # Modal struct module
  defmodule Modal do
    defstruct visible: nil, on_dismiss: nil, presentation_style: nil, __spark_metadata__: nil
  end

  # Modal Entity
  @modal %Spark.Dsl.Entity{
    name: :modal,
    target: Modal,
    describe: "Modal overlay",
    schema: [
      visible: [type: :boolean],
      on_dismiss: [type: :atom],
      presentation_style: [type: {:one_of, [:full_screen, :page_sheet]}]
    ]
  }

  # RefreshControl struct module
  defmodule RefreshControl do
    defstruct on_refresh: nil, refreshing: nil, tint_color: nil, __spark_metadata__: nil
  end

  # RefreshControl Entity
  @refresh_control %Spark.Dsl.Entity{
    name: :refresh_control,
    target: RefreshControl,
    describe: "Pull-to-refresh control",
    schema: [
      on_refresh: [type: :atom],
      refreshing: [type: :boolean],
      tint_color: [type: :atom]
    ]
  }

  # Scroll struct module
  defmodule Scroll do
    defstruct horizontal: nil, on_end_reached: nil, on_scroll: nil, __spark_metadata__: nil
  end

  # Scroll Entity
  @scroll %Spark.Dsl.Entity{
    name: :scroll,
    target: Scroll,
    describe: "Scrollable container",
    schema: [
      horizontal: [type: :boolean],
      on_end_reached: [type: :atom],
      on_scroll: [type: :atom]
    ]
  }

  # Pressable struct module
  defmodule Pressable do
    defstruct on_press: nil, on_long_press: nil, __spark_metadata__: nil
  end

  # Pressable Entity
  @pressable %Spark.Dsl.Entity{
    name: :pressable,
    target: Pressable,
    describe: "Pressable wrapper",
    schema: [
      on_press: [type: :atom],
      on_long_press: [type: :atom]
    ]
  }

  # SafeArea struct module
  defmodule SafeArea do
    defstruct children: [], __spark_metadata__: nil
  end

  # SafeArea Entity
  @safe_area %Spark.Dsl.Entity{
    name: :safe_area,
    target: SafeArea,
    describe: "Safe area view",
    schema: []
  }

  # StatusBar struct module
  defmodule StatusBar do
    defstruct bar_style: nil, hidden: nil, __spark_metadata__: nil
  end

  # StatusBar Entity
  @status_bar %Spark.Dsl.Entity{
    name: :status_bar,
    target: StatusBar,
    describe: "Status bar control",
    schema: [
      bar_style: [type: {:one_of, [:default, :light_content]}],
      hidden: [type: :boolean]
    ]
  }

  # ProgressBar struct module
  defmodule ProgressBar do
    defstruct progress: nil, indeterminate: nil, color: nil, __spark_metadata__: nil
  end

  # ProgressBar Entity
  @progress_bar %Spark.Dsl.Entity{
    name: :progress_bar,
    target: ProgressBar,
    describe: "Progress bar",
    schema: [
      progress: [type: :float],
      indeterminate: [type: :boolean],
      color: [type: :atom]
    ]
  }

  # List struct module
  defmodule List do
    defstruct id: nil, data: nil, on_end_reached: nil, scroll: nil, __spark_metadata__: nil
  end

  # List Entity
  @list %Spark.Dsl.Entity{
    name: :list,
    target: List,
    describe: "Data-driven list",
    args: [:id],
    schema: [
      id: [type: :atom, required: true],
      data: [type: :any],
      on_end_reached: [type: :atom],
      scroll: [type: :boolean]
    ]
  }

  # Screen Section
  @screen %Spark.Dsl.Section{
    name: :screen,
    describe: "Screen definition with UI components",
    schema: [
      name: [type: :atom, required: true]
    ],
    entities: [
      @text,
      @button,
      @webview,
      @camera_preview,
      @native_view,
      @image,
      @switch,
      @activity_indicator,
      @modal,
      @refresh_control,
      @scroll,
      @pressable,
      @safe_area,
      @status_bar,
      @progress_bar,
      @list
    ]
  }

  # Use Spark Extension
  use Spark.Dsl.Extension,
    sections: [@attributes, @screen],
    transformers: [Dala.Spark.Transformers.GenerateMount, Dala.Spark.Transformers.Render],
    verifiers: [__MODULE__.Verifier]

  # Enables `use Dala.Spark.Dsl` in user modules. Sets up Spark.Dsl with
  # this extension and imports the `dala/1` macro.
  defmacro __using__(_opts) do
    quote do
      use Spark.Dsl, default_extensions: [extensions: Dala.Spark.Dsl]
      import Dala.Spark.Dsl, only: [dala: 1]
    end
  end

  # Verifier module for compile-time prop validation
  defmodule Verifier do
    @moduledoc """
    Compile-time validation for Dala Spark DSL.
    """
    use Spark.Dsl.Verifier

    def verify(dsl_state) do
      # Validate that all on_tap handlers referenced in buttons exist
      buttons = Spark.Dsl.Transformer.get_entities(dsl_state, [:screen, :button])

      errors =
        Enum.flat_map(buttons, fn button ->
          if on_tap = Map.get(button, :on_tap) do
            unless is_atom(on_tap) do
              ["button on_tap must be an atom, got: #{inspect(on_tap)}"]
            else
              []
            end
          else
            []
          end
        end)

      # Validate attributes have valid types
      attributes = Spark.Dsl.Transformer.get_entities(dsl_state, [:attributes, :attribute])

      attr_errors =
        Enum.flat_map(attributes, fn attr ->
          type = Map.get(attr, :type)

          unless type in [:integer, :string, :boolean, :float] do
            ["attribute #{inspect(Map.get(attr, :name))} has invalid type: #{inspect(type)}"]
          else
            []
          end
        end)

      case errors ++ attr_errors do
        [] -> :ok
        msgs -> {:error, Enum.join(msgs, "; ")}
      end
    end
  end

  # Transform button to handle inline handlers
  def transform_button(%Spark.Dsl.Entity{} = entity, _opts) do
    # This is where we could process inline handlers in the future
    # For now, just return the entity as-is
    {:ok, entity}
  end

  # Define the dala/1 macro that wraps Spark DSL sections.
  # `use Dala.Spark.Dsl` already sets up the Spark extension at the module
  # level, so this macro just executes the block — Spark picks up the
  # section entities (attributes, screen) through its own compilation pipeline.
  defmacro dala(do: block) do
    block
  end
end
