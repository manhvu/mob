defmodule Mob.Event.Component do
  @moduledoc """
  Behaviour for **stateful** event-owning components.

  See `guides/event_model.md` for the model. In short:

  - **Stateless** components are plain functions: `(assigns) -> render_tree`.
    They have no event horizon — events fired inside their subtree resolve to
    the nearest stateful ancestor.
  - **Stateful** components implement `Mob.Event.Component`. They own events
    fired in their subtree and may escalate semantic events to their parent.

  This is the Mob equivalent of `Phoenix.LiveComponent`.

  ## Status

  This is the **interface declaration**. The runtime that hosts these
  components — registering them in render trees, routing events to them,
  managing their lifecycle — is implemented incrementally:

  1. Existing `Mob.Component` (a sibling concept for native_view widgets)
     remains the runtime for components that pair with custom native views.
  2. `Mob.Event.Component` (this module) is the *event-routing* abstraction:
     a stateful owner of events for a subtree of standard widgets.
  3. The two will likely merge once the new event model is plumbed end-to-end.

  Until then, the Bridge module handles the legacy event shapes and the
  existing `Mob.Component` is the canonical stateful component.

  ## Callbacks

      defmodule MyApp.CheckoutForm do
        use Mob.Event.Component

        def mount(props, state), do: {:ok, Map.put(state, :email, "")}

        def render(state) do
          # return a render tree (uses Mob.UI helpers)
          %{type: :column, ...}
        end

        def handle_event(%Address{id: :email}, :change, value, state) do
          {:noreply, %{state | email: value}}
        end

        def handle_event(%Address{id: :submit}, :tap, _, state) do
          # Escalate to parent — this is the "semantic" event.
          send(state.parent_pid, {:form_submitted, state.email})
          {:noreply, state}
        end
      end
  """

  alias Mob.Event.Address

  @callback mount(props :: map(), state :: map()) ::
              {:ok, map()} | {:error, term()}

  @callback update(props :: map(), state :: map()) ::
              {:ok, map()}

  @callback render(state :: map()) :: map()

  @callback handle_event(
              addr :: Address.t(),
              event :: atom(),
              payload :: term(),
              state :: map()
            ) :: {:noreply, map()}

  @callback handle_info(message :: term(), state :: map()) ::
              {:noreply, map()}

  @callback terminate(reason :: term(), state :: map()) :: term()

  @optional_callbacks [update: 2, handle_info: 2, terminate: 2]

  defmacro __using__(_opts) do
    quote do
      @behaviour Mob.Event.Component

      alias Mob.Event.Address

      def mount(_props, state), do: {:ok, state}

      def update(props, state), do: mount(props, state)

      def handle_event(_addr, _event, _payload, state), do: {:noreply, state}

      def handle_info(_message, state), do: {:noreply, state}

      def terminate(_reason, _state), do: :ok

      defoverridable mount: 2,
                     update: 2,
                     handle_event: 4,
                     handle_info: 2,
                     terminate: 2
    end
  end
end
