defmodule Mob.Event.IntegrationTest do
  @moduledoc """
  End-to-end tests that exercise the event flow:

  1. A "screen" process subscribes / has handle_info
  2. Legacy event arrives (the shape the NIF currently sends)
  3. Bridge converts it
  4. Handler receives canonical envelope and reacts

  These tests don't touch the NIF — they synthesize legacy messages directly,
  which is exactly what the iOS/Android native code does via `enif_send`.
  """

  use ExUnit.Case, async: true

  alias Mob.Event
  alias Mob.Event.{Address, Bridge}

  # A simple "screen" GenServer that uses the bridge in handle_info.
  defmodule TestScreen do
    use GenServer

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts, opts)

    def get_log(pid), do: GenServer.call(pid, :get_log)

    def init(opts) do
      {:ok, %{log: [], reply_to: opts[:reply_to]}}
    end

    def handle_info(msg, state) do
      case Bridge.legacy_to_canonical(msg, __MODULE__) do
        {:ok, {:mob_event, addr, event, payload} = envelope} ->
          # User-level handler that reacts to canonical events.
          if state.reply_to, do: send(state.reply_to, {:handled, envelope})

          new_log = [{addr.widget, addr.id, event, payload} | state.log]
          {:noreply, %{state | log: new_log}}

        :passthrough ->
          # Not a recognised legacy shape — just ignore for this test.
          {:noreply, state}
      end
    end

    def handle_call(:get_log, _from, state) do
      {:reply, Enum.reverse(state.log), state}
    end
  end

  describe "full bridge flow — tap" do
    test "atom-tagged tap arrives as canonical event" do
      {:ok, screen} = TestScreen.start_link(reply_to: self())

      # This is what `mob_nif` sends on iOS/Android via enif_send.
      send(screen, {:tap, :save})

      assert_receive {:handled, envelope}, 200
      assert {:mob_event, %Address{widget: :button, id: :save}, :tap, nil} = envelope
    end

    test "binary-tagged tap arrives as canonical event" do
      {:ok, screen} = TestScreen.start_link(reply_to: self())

      send(screen, {:tap, "contact:42"})

      assert_receive {:handled, {:mob_event, %Address{id: "contact:42"}, :tap, nil}}, 200
    end
  end

  describe "full bridge flow — list row select" do
    test "structured list-row tap converts to :select event with instance" do
      {:ok, screen} = TestScreen.start_link(reply_to: self())

      send(screen, {:tap, {:list, :contacts, :select, 47}})

      assert_receive {:handled, envelope}, 200

      assert {:mob_event,
              %Address{
                widget: :list,
                id: :contacts,
                instance: 47
              }, :select, nil} = envelope
    end
  end

  describe "full bridge flow — change" do
    test "text_field change with binary value" do
      {:ok, screen} = TestScreen.start_link(reply_to: self())

      send(screen, {:change, :email, "user@example.com"})

      assert_receive {:handled, envelope}, 200

      assert {:mob_event,
              %Address{widget: :text_field, id: :email},
              :change,
              "user@example.com"} = envelope
    end

    test "toggle change with boolean" do
      {:ok, screen} = TestScreen.start_link(reply_to: self())

      send(screen, {:change, :notifications, true})

      assert_receive {:handled, {:mob_event, %Address{id: :notifications}, :change, true}}, 200
    end

    test "slider change with float" do
      {:ok, screen} = TestScreen.start_link(reply_to: self())

      send(screen, {:change, :volume, 0.75})

      assert_receive {:handled, {:mob_event, %Address{id: :volume}, :change, 0.75}}, 200
    end
  end

  describe "full bridge flow — multiple events accumulate in screen state" do
    test "log captures every event in order" do
      {:ok, screen} = TestScreen.start_link([])

      send(screen, {:tap, :start})
      send(screen, {:change, :email, "a@b"})
      send(screen, {:tap, {:list, :items, :select, 0}})
      send(screen, {:tap, :stop})

      Process.sleep(20)
      log = TestScreen.get_log(screen)

      assert log == [
               {:button, :start, :tap, nil},
               {:text_field, :email, :change, "a@b"},
               {:list, :items, :select, nil},
               {:button, :stop, :tap, nil}
             ]
    end

    test "passthrough events don't pollute the log" do
      {:ok, screen} = TestScreen.start_link([])

      send(screen, {:tap, :a})
      send(screen, {:not_an_event, :ignored})
      send(screen, {:tap, :b})

      Process.sleep(20)
      log = TestScreen.get_log(screen)

      # Only the two recognised taps:
      assert log == [
               {:button, :a, :tap, nil},
               {:button, :b, :tap, nil}
             ]
    end
  end

  describe "Mob.Event direct dispatch (no bridge)" do
    test "synthesised event delivered to the test process" do
      addr = Address.new(screen: TestScreen, widget: :button, id: :save)
      :ok = Event.dispatch(self(), addr, :tap, nil)
      assert_receive {:mob_event, ^addr, :tap, nil}
    end

    test "match_address? filters correctly" do
      addr = Address.new(screen: TestScreen, widget: :button, id: :save)
      assert Event.match_address?(addr, widget: :button)
      refute Event.match_address?(addr, widget: :text_field)
    end
  end
end
