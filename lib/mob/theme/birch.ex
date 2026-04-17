defmodule Mob.Theme.Birch do
  @moduledoc """
  Birch theme for Mob — warm parchment surfaces with a chestnut-brown accent.

  A light warm theme. Calm and readable — works well for content-heavy apps,
  reading interfaces, and anywhere you want a natural, unhurried feel.

  ## Usage

      defmodule MyApp do
        use Mob.App, theme: Mob.Theme.Birch
      end

  ## Overrides

      use Mob.App, theme: {Mob.Theme.Birch, primary: :brown_400}

  ## Publishing your own theme

  Any module that exports `theme/0 :: Mob.Theme.t()` works as a Mob theme.
  You can publish yours as a standalone Hex package and users import it the
  same way:

      use Mob.App, theme: AcmeCorp.Theme.Light
  """

  @doc "Returns the compiled Birch theme struct."
  @spec theme() :: Mob.Theme.t()
  def theme do
    Mob.Theme.build(
      # ── Brand ──────────────────────────────────────────────────────────────
      primary:      :brown_600,      # 0xFF7C4A1E — warm chestnut
      on_primary:   0xFFFFF4E8,      # warm cream — readable on chestnut
      secondary:    0xFF5C7A52,      # muted sage green — complements chestnut
      on_secondary: 0xFFFFF4E8,      # warm cream

      # ── Surfaces ───────────────────────────────────────────────────────────
      background:    0xFFF5EFE0,     # warm parchment
      on_background: 0xFF2C1A08,     # dark coffee — high contrast on parchment
      surface:       0xFFEDE6D5,     # slightly darker warm card
      surface_raised: 0xFFE0D7C3,    # elevated card
      on_surface:    0xFF2C1A08,     # dark coffee
      muted:         0xFF8A7A6A,     # warm gray-brown — placeholders / captions

      # ── Utility ────────────────────────────────────────────────────────────
      error:    :red_500,
      on_error: :white,
      border:   0xFFCCBCA8          # warm beige divider
    )
  end
end
