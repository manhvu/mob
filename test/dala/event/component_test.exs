defmodule Dala.Event.ComponentTest do
  @moduledoc """
  Tests for the `Dala.Event.Component` behaviour. These exercise the callback
  contract and default implementations — the runtime that hosts these
  components is implemented incrementally elsewhere; these tests verify the
  interface itself.
  """

  use ExUnit.Case, async: true

  alias Dala.Event.Address

  defmodule MinimalComponent do
    use Dala.Event.Component

    def render(state), do: %{type: :column, props: %{}, children: [], debug: state}
  end

  defmodule FormComponent do
    use Dala.Event.Component

    def mount(props, state) do
      {:ok, Map.merge(state, %{email: props[:email] || "", parent_pid: props[:parent_pid]})}
    end

    def render(state) do
      %{
        type: :column,
        props: %{},
        children: [
          %{
            type: :text_field,
            props: %{value: state.email, id: :email}
          },
          %{
            type: :button,
            props: %{text: "Submit", id: :submit}
          }
        ]
      }
    end

    def handle_event(%Address{id: :email}, :change, value, state) do
      {:noreply, %{state | email: value}}
    end

    def handle_event(%Address{id: :submit}, :tap, _, state) do
      if state.parent_pid, do: send(state.parent_pid, {:form_submitted, state.email})
      {:noreply, state}
    end

    def handle_event(_addr, _event, _payload, state), do: {:noreply, state}
  end

  describe "default callbacks (use Dala.Event.Component without override)" do
    test "mount/2 returns the state unchanged" do
      assert {:ok, %{x: 1}} = MinimalComponent.mount(%{}, %{x: 1})
    end

    test "update/2 delegates to mount/2 by default" do
      assert {:ok, %{x: 1}} = MinimalComponent.update(%{}, %{x: 1})
    end

    test "handle_event/4 returns state unchanged" do
      addr = Address.new(screen: S, widget: :button, id: :foo)
      assert {:noreply, %{x: 1}} = MinimalComponent.handle_event(addr, :tap, nil, %{x: 1})
    end

    test "handle_info/2 returns state unchanged" do
      assert {:noreply, %{x: 1}} = MinimalComponent.handle_info(:any_msg, %{x: 1})
    end

    test "terminate/2 returns :ok" do
      assert :ok = MinimalComponent.terminate(:normal, %{})
    end

    test "render/1 produces a render tree" do
      tree = MinimalComponent.render(%{x: 1})
      assert tree.type == :column
    end
  end

  describe "FormComponent — overridden callbacks" do
    test "mount initialises state from props" do
      assert {:ok, %{email: "default@test.com", parent_pid: nil}} =
               FormComponent.mount(%{email: "default@test.com"}, %{})
    end

    test "mount with parent_pid" do
      {:ok, state} = FormComponent.mount(%{email: "x", parent_pid: self()}, %{})
      assert state.parent_pid == self()
    end

    test "handle_event :change updates email" do
      {:ok, state} = FormComponent.mount(%{email: ""}, %{})
      addr = Address.new(screen: S, widget: :text_field, id: :email)

      {:noreply, new_state} = FormComponent.handle_event(addr, :change, "user@x.com", state)

      assert new_state.email == "user@x.com"
    end

    test "handle_event :submit escalates to parent_pid" do
      {:ok, state} = FormComponent.mount(%{email: "user@x.com", parent_pid: self()}, %{})
      addr = Address.new(screen: S, widget: :button, id: :submit)

      {:noreply, _state} = FormComponent.handle_event(addr, :tap, nil, state)

      assert_receive {:form_submitted, "user@x.com"}
    end

    test "handle_event :submit without parent_pid does nothing" do
      {:ok, state} = FormComponent.mount(%{email: "x"}, %{})
      addr = Address.new(screen: S, widget: :button, id: :submit)

      assert {:noreply, _} = FormComponent.handle_event(addr, :tap, nil, state)
      refute_receive {:form_submitted, _}, 50
    end

    test "render produces tree with current state" do
      {:ok, state} = FormComponent.mount(%{email: "test@x.com"}, %{})
      tree = FormComponent.render(state)

      [text_field, _button] = tree.children
      assert text_field.props.value == "test@x.com"
      assert text_field.props.id == :email
    end

    test "unknown events fall through to default (no-op)" do
      {:ok, state} = FormComponent.mount(%{email: "x"}, %{})
      addr = Address.new(screen: S, widget: :button, id: :unknown)

      assert {:noreply, ^state} = FormComponent.handle_event(addr, :tap, nil, state)
    end
  end

  describe "the 1000-row pattern" do
    # A list-style component that owns row events and emits semantic events
    # upward. Demonstrates the encapsulation rule from event_model.md.
    defmodule ContactList do
      use Dala.Event.Component

      def mount(props, state) do
        {:ok,
         Map.merge(state, %{
           items: props[:items] || [],
           selected: nil,
           parent_pid: props[:parent_pid]
         })}
      end

      def render(state) do
        %{
          type: :list,
          props: %{id: :contacts},
          children: state.items
        }
      end

      def handle_event(%Address{widget: :list, instance: index}, :select, _, state) do
        # Internal selection state.
        new_state = %{state | selected: index}

        # Escalate semantic event to parent.
        if state.parent_pid do
          contact = Enum.at(state.items, index)
          send(state.parent_pid, {:contact_selected, contact})
        end

        {:noreply, new_state}
      end
    end

    test "row select updates internal state and escalates semantic event" do
      contacts = [%{name: "Alice"}, %{name: "Bob"}, %{name: "Carol"}]
      {:ok, state} = ContactList.mount(%{items: contacts, parent_pid: self()}, %{})

      addr = Address.new(screen: S, widget: :list, id: :contacts, instance: 1)

      {:noreply, new_state} = ContactList.handle_event(addr, :select, nil, state)

      # Internal state updated.
      assert new_state.selected == 1

      # Semantic event escalated.
      assert_receive {:contact_selected, %{name: "Bob"}}
    end

    test "selecting different rows updates state each time" do
      contacts = Enum.map(0..999, &%{id: &1})
      {:ok, state} = ContactList.mount(%{items: contacts, parent_pid: self()}, %{})

      # Select row 47, then 800 — only the latest should be in state.
      addr1 = Address.new(screen: S, widget: :list, id: :contacts, instance: 47)
      addr2 = Address.new(screen: S, widget: :list, id: :contacts, instance: 800)

      {:noreply, state1} = ContactList.handle_event(addr1, :select, nil, state)
      assert state1.selected == 47

      {:noreply, state2} = ContactList.handle_event(addr2, :select, nil, state1)
      assert state2.selected == 800

      # Both semantic events received in order.
      assert_receive {:contact_selected, %{id: 47}}
      assert_receive {:contact_selected, %{id: 800}}
    end
  end
end
