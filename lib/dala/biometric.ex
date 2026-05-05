defmodule Dala.Biometric do
  @moduledoc """
  Biometric authentication (Face ID / Touch ID / fingerprint).

  No permission dialog is shown — uses the device's existing biometric enrollment.

      Dala.Biometric.authenticate(socket, reason: "Confirm payment")

  Result arrives as:

      handle_info({:biometric, :success},       socket)
      handle_info({:biometric, :failure},        socket)
      handle_info({:biometric, :not_available},  socket)

  `:not_available` is returned if the device has no biometric hardware or the
  user has not enrolled any biometrics.

  iOS: `LAContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, ...)`
  Android: `BiometricPrompt`
  """

  @spec authenticate(Dala.Socket.t(), keyword()) :: Dala.Socket.t()
  def authenticate(socket, opts \\ []) do
    reason = Keyword.get(opts, :reason, "Authenticate")
    :dala_nif.biometric_authenticate(reason)
    socket
  end
end
