defmodule Mob.Event.Bridge do
  @moduledoc """
  Translates legacy event shapes (`{:tap, tag}`, `{:change, tag, value}`,
  `{:tap, {:list, id, :select, index}}`) into the canonical
  `{:mob_event, %Address{}, event, payload}` envelope.

  This is a transitional helper: as long as the native NIF emits the legacy
  `register_tap`-style messages, this module bridges them into the new model.
  When the native side is migrated to emit the canonical envelope directly,
  this module can be removed.

  ## Usage from a screen

      def handle_info(msg, socket) do
        case Mob.Event.Bridge.legacy_to_canonical(msg, screen_module) do
          {:ok, {:mob_event, addr, event, payload}} ->
            # Handle via the new model
            handle_event(addr, event, payload, socket)

          :passthrough ->
            # Not a recognised legacy shape — handle normally
            ...
        end
      end

  ## Bridge rules

  | Legacy shape | Canonical envelope |
  |---|---|
  | `{:tap, tag}` (atom or arbitrary tag) | `{:mob_event, addr(:button, tag), :tap, nil}` |
  | `{:tap, {:list, id, :select, index}}` | `{:mob_event, addr(:list, id, instance: index), :select, nil}` |
  | `{:change, tag, value}` | `{:mob_event, addr(:text_field, tag), :change, value}` |
  | other | `:passthrough` |

  Widget kind defaults to `:button` for `:tap`, `:text_field` for `:change`,
  and `:list` for the structured list-row tag. Callers that need a more
  specific widget kind can extend the rule table.
  """

  alias Mob.Event.Address

  @typedoc "Result of attempting to bridge a legacy message."
  @type result ::
          {:ok, {:mob_event, Address.t(), atom(), term()}}
          | :passthrough

  @doc """
  Convert a legacy event shape to the canonical envelope.

  `screen_id` is used as the `screen` field on the address; it can be the
  screen module atom, the screen pid, or any term. `render_id`, if known,
  bumps the address's render generation; defaults to 1 if omitted.

  ## Examples

      iex> Mob.Event.Bridge.legacy_to_canonical({:tap, :save}, MyScreen)
      {:ok, {:mob_event, %Mob.Event.Address{screen: MyScreen, widget: :button, id: :save, render_id: 1, component_path: [], instance: nil}, :tap, nil}}

      iex> Mob.Event.Bridge.legacy_to_canonical({:tap, {:list, :contacts, :select, 47}}, MyScreen)
      {:ok, {:mob_event, %Mob.Event.Address{screen: MyScreen, widget: :list, id: :contacts, instance: 47, render_id: 1, component_path: []}, :select, nil}}

      iex> Mob.Event.Bridge.legacy_to_canonical({:change, :email, "user@example.com"}, MyScreen)
      {:ok, {:mob_event, %Mob.Event.Address{screen: MyScreen, widget: :text_field, id: :email, render_id: 1, component_path: [], instance: nil}, :change, "user@example.com"}}

      iex> Mob.Event.Bridge.legacy_to_canonical({:not_an_event, :something}, MyScreen)
      :passthrough
  """
  @spec legacy_to_canonical(term(), term(), keyword()) :: result()
  def legacy_to_canonical(msg, screen_id, opts \\ [])

  # Structured list-row tap: `{:tap, {:list, id, :select, index}}`
  def legacy_to_canonical({:tap, {:list, id, :select, index}}, screen_id, opts) do
    addr =
      Address.new(
        screen: screen_id,
        widget: :list,
        id: id,
        instance: index,
        render_id: Keyword.get(opts, :render_id, 1)
      )

    {:ok, {:mob_event, addr, :select, nil}}
  end

  # Plain tap with a tag.
  def legacy_to_canonical({:tap, tag}, screen_id, opts) when not is_nil(tag) do
    case Address.validate_id(tag) do
      :ok ->
        addr =
          Address.new(
            screen: screen_id,
            widget: Keyword.get(opts, :widget, :button),
            id: tag,
            render_id: Keyword.get(opts, :render_id, 1)
          )

        {:ok, {:mob_event, addr, :tap, nil}}

      {:error, _} ->
        :passthrough
    end
  end

  # Change with tag + value.
  def legacy_to_canonical({:change, tag, value}, screen_id, opts) when not is_nil(tag) do
    case Address.validate_id(tag) do
      :ok ->
        addr =
          Address.new(
            screen: screen_id,
            widget: Keyword.get(opts, :widget, :text_field),
            id: tag,
            render_id: Keyword.get(opts, :render_id, 1)
          )

        {:ok, {:mob_event, addr, :change, value}}

      {:error, _} ->
        :passthrough
    end
  end

  def legacy_to_canonical(_msg, _screen_id, _opts), do: :passthrough

  @doc """
  Same as `legacy_to_canonical/3` but raises if the message is not a
  recognised legacy event. Useful in tests.
  """
  @spec legacy_to_canonical!(term(), term(), keyword()) ::
          {:mob_event, Address.t(), atom(), term()}
  def legacy_to_canonical!(msg, screen_id, opts \\ []) do
    case legacy_to_canonical(msg, screen_id, opts) do
      {:ok, envelope} -> envelope
      :passthrough -> raise ArgumentError, "Not a recognized legacy event: #{inspect(msg)}"
    end
  end
end
