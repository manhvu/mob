defmodule Dala.MixProject do
  use Mix.Project

  def project do
    [
      app: :dala,
      version: "0.0.4",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: "An other mobile framework for Elixir, rework from Mob framework",
      source_url: "https://github.com/manhvu/dala",
      homepage_url: "https://hexdocs.pm/dala",
      package: package(),
      docs: docs(),
      # Rustler configuration
      rustler_crates: rustler_crates()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "assets/logo/logo_full_color.png",
      source_url: "https://github.com/manhvu/dala",
      source_url_pattern: "https://github.com/manhvu/dala/blob/main/%{path}#L%{line}",
      extras: [
        "README.md": [title: "Dala"],
        "guides/getting_started.md": [title: "Getting Started"],
        "guides/architecture.md": [title: "Architecture & Prior Art"],
        "guides/screen_lifecycle.md": [title: "Screen Lifecycle"],
        "guides/components.md": [title: "Components"],
        "guides/styling.md": [title: "Styling & Native Rendering"],
        "guides/theming.md": [title: "Theming"],
        "guides/navigation.md": [title: "Navigation"],
        "guides/device_capabilities.md": [title: "Device Capabilities"],
        "guides/data.md": [title: "Data & Persistence"],
        "guides/render_engine.md": [title: "Render Engine"],
        "guides/binary_protocol.md": [title: "Binary Protocol"],
        "guides/ui_design.md": [title: "UI Design"],
        "guides/ui_render_pipeline.md": [title: "UI Render Pipeline"],
        "guides/events.md": [title: "Events"],
        "guides/event_model.md": [title: "Event Model"],
        "guides/event_audit.md": [title: "Event Audit"],
        "guides/spark_dsl.md": [title: "Spark DSL"],
        "guides/testing.md": [title: "Testing"],
        "guides/liveview.md": [title: "LiveView Integration"],
        "guides/ios_ml_support.md": [title: "iOS ML Support"],
        "guides/ios_physical_device.md": [title: "iOS Physical Device"],
        "guides/rustler_in_mob.md": [title: "Rustler in Mobile"],
        "guides/rustler_message_sending.md": [title: "Rustler Message Sending"],
        "guides/emlx_ios_summary.md": [title: "EMLX iOS Summary"],
        "guides/publishing.md": [title: "Publishing to App Store / TestFlight"],
        "guides/troubleshooting.md": [title: "Troubleshooting"],
        "guides/agentic_coding.md": [title: "Agentic Coding"],
        "guides/security.md": [title: "Security Guide"]
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*/
      ],
      groups_for_modules: [
        Core: [Dala, Dala.App, Dala.Screen, Dala.Socket, Dala.State],
        UI: [
          Dala.UI,
          Dala.Style,
          Dala.Renderer,
          Dala.Theme,
          Dala.Theme.Obsidian,
          Dala.Theme.Citrus,
          Dala.Theme.Birch
        ],
        Navigation: [Dala.Nav.Registry],
        "Device APIs": [
          Dala.Haptic,
          Dala.Clipboard,
          Dala.Share,
          Dala.Permissions,
          Dala.Biometric,
          Dala.Location,
          Dala.Camera,
          Dala.Photos,
          Dala.Files,
          Dala.Audio,
          Dala.Motion,
          Dala.Scanner,
          Dala.Notify
        ],
        "Testing & Debugging": [Dala.Test],
        Internals: [Dala.Dist, Dala.NativeLogger, Dala.List, Dala.Sigil]
      ],
      before_closing_body_tag: &before_closing_body_tag/1
    ]
  end

  defp before_closing_body_tag(:html) do
    """
    <script>
      // Ensure code blocks with language hints are highlighted
      document.querySelectorAll("pre code").forEach(el => {
        if (!el.className) el.className = "language-elixir";
      });
    </script>
    """
  end

  defp before_closing_body_tag(_), do: ""

  # Rustler crate configuration
  defp rustler_crates do
    [
      dala_nif: [
        path: "native/dala_nif",
        mode: if(Mix.env() == :prod, do: :release, else: :debug)
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/onboarding", "test/onboarding/support", "dev_tools", "dev_tools/test"]
  defp elixirc_paths(:dev), do: ["lib", "dev_tools", "dev_tools/test"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/manhvu/dala"},
      files: ~w(
        lib native priv
        android ios assets
        mix.exs mix.lock
        README.md LICENSE
      )
    ]
  end

  defp deps do
    [
      # HTML/HEEx template engine — same one Phoenix uses
      {:phoenix_live_view, "~> 1.0", only: [:dev, :test]},
      {:nimble_parsec, "~> 1.0"},
      {:spark, "~> 2.7"},
      {:rustler, "~> 0.37.3", runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:jump_credo_checks, "~> 0.1.0", only: [:dev, :test], runtime: false}
    ]
  end
end
