defmodule Dala.Haptic do
  @moduledoc """
  Haptic feedback. No permission required on either platform.

  ## Usage

      # In a handle_event or handle_info:
      def handle_event("purchase", _params, socket) do
        Dala.Haptic.trigger(socket, :success)
        {:noreply, socket}
      end

  ## Feedback types

  | Type       | Feel                              |
  |------------|-----------------------------------|
  | `:light`   | Brief, light tap                  |
  | `:medium`  | Standard tap                      |
  | `:heavy`   | Strong tap                        |
  | `:success` | Success pattern (double tap)      |
  | `:error`   | Error pattern (triple tap)        |
  | `:warning` | Warning pattern (irregular taps)  |

  iOS uses `UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator`.
  Android uses `View.performHapticFeedback` with `HapticFeedbackConstants`.
  """

  @types [:light, :medium, :heavy, :success, :error, :warning]

  @doc """
  Fire a haptic feedback pulse. Returns the socket unchanged so it can be
  used inline without disrupting the handle_event return value.

      Dala.Haptic.trigger(socket, :light)
  """
  @spec trigger(Dala.Socket.t(), atom()) :: Dala.Socket.t()
  def trigger(socket, type) when type in @types do
    :dala_nif.haptic(type)
    socket
  end
end
