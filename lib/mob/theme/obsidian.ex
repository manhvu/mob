defmodule Mob.Theme.Obsidian do
  @moduledoc """
  Obsidian theme for Mob — deep blacks with a violet accent.

  ## Usage

      defmodule MyApp do
        use Mob.App, theme: Mob.Theme.Obsidian
      end

  ## Overrides

  Pass a keyword list as the second element of a tuple to override
  individual tokens while keeping the rest of the Obsidian palette:

      use Mob.App, theme: {Mob.Theme.Obsidian, primary: :rose_500}

  ## Publishing your own theme

  Any module that exports `theme/0 :: Mob.Theme.t()` works as a Mob theme.
  You can publish yours as a standalone Hex package and users import it the
  same way:

      use Mob.App, theme: AcmeCorp.Theme.Dark
  """

  @doc "Returns the compiled Obsidian theme struct."
  @spec theme() :: Mob.Theme.t()
  def theme do
    Mob.Theme.build(
      # ── Brand ──────────────────────────────────────────────────────────────
      primary:      :violet_600,   # 0xFF7C3AED
      on_primary:   :white,
      secondary:    :violet_400,   # 0xFFA78BFA — lighter for accents/tags
      on_secondary: :white,

      # ── Surfaces ───────────────────────────────────────────────────────────
      background:    0xFF0D0D1A,   # near-black, blue-tinted
      on_background: 0xFFE8E6FF,   # lavender-tinted white
      surface:       0xFF16162A,   # dark card background
      surface_raised: 0xFF1E1E38,  # slightly elevated card
      on_surface:    0xFFE8E6FF,
      muted:         0xFF6B6B8E,   # muted text / placeholders

      # ── Utility ────────────────────────────────────────────────────────────
      error:    :red_400,
      on_error: :white,
      border:   0xFF2D2D4A         # subtle purple-tinted divider
    )
  end
end
