defmodule Dala.Notify do
  @moduledoc """
  Local and push notifications.

  Requires `:notifications` permission (request via `Dala.Permissions.request/2`).

  All notifications arrive via `handle_info` regardless of app state (foreground,
  background, or relaunched after being killed). No special `mount/3` handling needed.

  ## Local notifications

      Dala.Notify.schedule(socket,
        id:    "reminder_1",
        title: "Time to check in",
        body:  "Open the app to see today's updates",
        at:    ~U[2026-04-16 09:00:00Z],   # or delay_seconds: 60
        data:  %{screen: "reminders"}
      )

      # Cancel a pending notification
      Dala.Notify.cancel(socket, "reminder_1")

      def handle_info({:notification, %{id: id, data: data, source: :local}}, socket), do: ...

  ## Push notifications (requires `dala_push` package on your server)

      # Call once after :notifications permission granted
      Dala.Notify.register_push(socket)

      def handle_info({:push_token, :ios,     token}, socket), do: ...
      def handle_info({:push_token, :android, token}, socket), do: ...

      def handle_info({:notification, %{title: t, body: b, data: d, source: :push}}, socket), do: ...

  iOS: `UNUserNotificationCenter`. Android: `NotificationManager` + `AlarmManager` + FCM.
  """

  @doc """
  Schedule a local notification.

  Options:
    - `id:` (required) — string identifier, used to cancel the notification
    - `title:` (required) — notification title
    - `body:` (required) — notification body text
    - `at: %DateTime{}` — absolute trigger time (UTC)
    - `delay_seconds: integer` — trigger after N seconds (alternative to `at:`)
    - `data: %{}` — arbitrary map passed back in the `handle_info` payload
  """
  @spec schedule(Dala.Socket.t(), keyword()) :: Dala.Socket.t()
  def schedule(socket, opts) do
    id = Keyword.fetch!(opts, :id)
    title = Keyword.fetch!(opts, :title)
    body = Keyword.fetch!(opts, :body)
    data = Keyword.get(opts, :data, %{})

    trigger_at =
      case opts[:at] do
        %DateTime{} = dt -> DateTime.to_unix(dt)
        nil -> DateTime.to_unix(DateTime.utc_now()) + (opts[:delay_seconds] || 0)
      end

    # Convert data map keys to strings for JSON serialisation
    data_str = Map.new(data, fn {k, v} -> {to_string(k), v} end)

    opts_json =
      :json.encode(%{
        "id" => id,
        "title" => title,
        "body" => body,
        "trigger_at" => trigger_at,
        "data" => data_str
      })

    :dala_nif.notify_schedule(opts_json)
    socket
  end

  @doc """
  Cancel a pending local notification by its id.
  Has no effect if the notification has already been delivered.
  """
  @spec cancel(Dala.Socket.t(), String.t()) :: Dala.Socket.t()
  def cancel(socket, id) do
    :dala_nif.notify_cancel(id)
    socket
  end

  @doc """
  Register this device for push notifications.

  The device token arrives as `{:push_token, platform, token_string}` where
  `platform` is `:ios` or `:android`.

  Send this token to your server and use the `dala_push` library to send
  notifications to it.
  """
  @spec register_push(Dala.Socket.t()) :: Dala.Socket.t()
  def register_push(socket) do
    :dala_nif.notify_register_push()
    socket
  end
end
