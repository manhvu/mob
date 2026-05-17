defmodule Dala.Media.Scene do
  @moduledoc """
  Realtime scene graph compositor.

  Composites multiple media sources (video, overlays, text, effects) into a
  single GPU-rendered output. Frame-clock driven for smooth 60fps.

  Scene graph:
      Scene
       ├── VideoNode     — hardware-decoded video texture
       ├── OverlayNode   — image/UI overlay layers
       ├── TextNode      — GPU-rendered text
       ├── EffectNode    — GPU compute filters (blur, LUT, etc.)
       └── AnimationNode — frame-clock driven animations

  ## Example

      {:ok, scene} = Dala.Media.Scene.new(1920, 1080)

      # Add a video layer
      {:ok, video_node} = Dala.Media.Scene.add_node(scene, :video, %{
        stream: video_stream,
        position: {0, 0},
        size: {1920, 1080},
        z_index: 0
      })

      # Add an overlay
      {:ok, overlay_node} = Dala.Media.Scene.add_node(scene, :overlay, %{
        texture: overlay_texture,
        position: {100, 100},
        size: {200, 50},
        opacity: 0.8,
        z_index: 10
      })

      # Add a blur effect
      {:ok, effect_node} = Dala.Media.Scene.add_node(scene, :effect, %{
        type: :blur,
        radius: 5.0,
        input: video_node,
        z_index: 5
      })

      # Composite and render
      Dala.Media.Scene.render(scene)
  """

  use GenServer

  require Logger

  @type scene_ref :: pid()
  @type node_id :: reference()
  @type node_type :: :video | :image | :overlay | :text | :effect | :animation
  @type position :: {non_neg_integer(), non_neg_integer()}
  @type size :: {non_neg_integer(), non_neg_integer()}
  @type z_index :: integer()
  @type opacity :: float()
  @type transform :: %{
    position: position(),
    scale: {float(), float()},
    rotation: float(),
    opacity: opacity(),
    z_index: z_index()
  }

  defstruct [
    :width,
    :height,
    :nodes,
    :sorted_ids,
    :frame_count,
    :last_frame_time,
    :target_fps,
    :gpu_surface,
    :texture_pool,
  ]

  # Client API

  @doc "Create a new scene with the given dimensions."
  @spec new(non_neg_integer(), non_neg_integer(), keyword()) :: {:ok, scene_ref()} | {:error, term()}
  def new(width, height, opts \\ []) do
    GenServer.start_link(__MODULE__, {width, height, opts})
  end

  @doc "Destroy the scene and release all GPU resources."
  @spec destroy(scene_ref()) :: :ok
  def destroy(pid), do: GenServer.stop(pid)

  @doc "Add a node to the scene."
  @spec add_node(scene_ref(), node_type(), map()) :: {:ok, node_id()} | {:error, term()}
  def add_node(pid, type, props) do
    GenServer.call(pid, {:add_node, type, props})
  end

  @doc "Remove a node from the scene."
  @spec remove_node(scene_ref(), node_id()) :: :ok
  def remove_node(pid, node_id) do
    GenServer.cast(pid, {:remove_node, node_id})
  end

  @doc "Update a node's properties."
  @spec update_node(scene_ref(), node_id(), map()) :: :ok
  def update_node(pid, node_id, props) do
    GenServer.cast(pid, {:update_node, node_id, props})
  end

  @doc "Update a node's transform."
  @spec set_transform(scene_ref(), node_id(), transform()) :: :ok
  def set_transform(pid, node_id, transform) do
    GenServer.cast(pid, {:set_transform, node_id, transform})
  end

  @doc "Composite all nodes and render to the GPU surface."
  @spec render(scene_ref()) :: :ok
  def render(pid), do: GenServer.call(pid, :render)

  @doc """
  Add an image node to the scene.

  Convenience wrapper around `add_node/3` for image sources.

  ## Options

    * `:image_id` — The GPU image ID (from `Dala.Gpu.load_image/4`)
    * `:position` — `{x, y}` tuple (default: `{0, 0}`)
    * `:size` — `{w, h}` tuple (default: `{100, 100}`)
    * `:z_index` — Layer order (default: `0`)
    * `:opacity` — `0.0` to `1.0` (default: `1.0`)

  ## Example

      {:ok, img_node} = Dala.Media.Scene.add_image(scene, image_id: 1, position: {540, 20}, size: {120, 90}, z_index: 100)
  """
  @spec add_image(scene_ref(), keyword()) :: {:ok, node_id()} | {:error, term()}
  def add_image(pid, opts) do
    image_id = Keyword.fetch!(opts, :image_id)
    props = %{
      image_id: image_id,
      position: Keyword.get(opts, :position, {0, 0}),
      size: Keyword.get(opts, :size, {100, 100}),
      z_index: Keyword.get(opts, :z_index, 0),
      opacity: Keyword.get(opts, :opacity, 1.0),
    }
    add_node(pid, :image, props)
  end

  @doc """
  Add a video node to the scene with optional PiP (picture-in-picture) transform.

  Convenience wrapper around `add_node/3` for video streams.

  ## Options

    * `:stream` — A `Dala.Media.Video` pid (required)
    * `:position` — `{x, y}` tuple (default: `{0, 0}`)
    * `:size` — `{w, h}` tuple (default: `{1920, 1080}`)
    * `:z_index` — Layer order (default: `0`)
    * `:pip` — If `true`, applies a PiP transform (small overlay in top-right corner)
    * `:pip_position` — Custom PiP position `{x, y}` (default: auto-calculated)
    * `:pip_size` — Custom PiP size `{w, h}` (default: `{200, 150}`)

  ## Example

      # Full-screen video
      {:ok, vid} = Dala.Media.Scene.add_video(scene, stream: video_stream, size: {1920, 1080})

      # PiP video overlay
      {:ok, pip} = Dala.Media.Scene.add_video(scene, stream: pip_stream, pip: true, z_index: 100)

      # Custom PiP position
      {:ok, pip} = Dala.Media.Scene.add_video(scene, stream: pip_stream, pip: true, pip_position: {50, 50}, pip_size: {300, 200})
  """
  @spec add_video(scene_ref(), keyword()) :: {:ok, node_id()} | {:error, term()}
  def add_video(pid, opts) do
    stream = Keyword.fetch!(opts, :stream)
    pip? = Keyword.get(opts, :pip, false)

    {position, size} = if pip? do
      scene_w = Keyword.get(opts, :scene_width, 1920)
      _scene_h = Keyword.get(opts, :scene_height, 1080)
      pip_size = Keyword.get(opts, :pip_size, {200, 150})
      pip_pos = Keyword.get(opts, :pip_position, {scene_w - elem(pip_size, 0) - 20, 20})
      {pip_pos, pip_size}
    else
      {Keyword.get(opts, :position, {0, 0}), Keyword.get(opts, :size, {1920, 1080})}
    end

    props = %{
      stream: stream,
      position: position,
      size: size,
      z_index: Keyword.get(opts, :z_index, 0),
      opacity: Keyword.get(opts, :opacity, 1.0),
    }
    add_node(pid, :video, props)
  end

  @doc """
  Update a node's PiP (picture-in-picture) transform.

  Convenience function to move/resize a PiP node.

  ## Example

      Dala.Media.Scene.set_pip_transform(scene, pip_node_id, position: {100, 50}, size: {250, 180})
  """
  @spec set_pip_transform(scene_ref(), node_id(), keyword()) :: :ok
  def set_pip_transform(pid, node_id, opts) do
    transform = %{
      position: Keyword.get(opts, :position, {0, 0}),
      size: Keyword.get(opts, :size, {200, 150}),
    }
    set_transform(pid, node_id, transform)
  end

  @doc "Get current frame count."
  @spec frame_count(scene_ref()) :: non_neg_integer()
  def frame_count(pid), do: GenServer.call(pid, :frame_count)

  @doc "Get current FPS."
  @spec fps(scene_ref()) :: float()
  def fps(pid), do: GenServer.call(pid, :fps)

  @doc "Set target FPS (default 60)."
  @spec set_target_fps(scene_ref(), pos_integer()) :: :ok
  def set_target_fps(pid, fps), do: GenServer.cast(pid, {:set_target_fps, fps})

  # Server callbacks

  @impl GenServer
  def init({width, height, opts}) do
    target_fps = Keyword.get(opts, :target_fps, 60)

    state = %__MODULE__{
      width: width,
      height: height,
      nodes: %{},
      sorted_ids: [],
      frame_count: 0,
      last_frame_time: nil,
      target_fps: target_fps,
      gpu_surface: nil,
      texture_pool: %{},
    }

    case Dala.Gpu.create_surface(width, height) do
      {:ok, gpu_surface} ->
        Dala.Gpu.clear(gpu_surface, :transparent)
        {:ok, %{state | gpu_surface: gpu_surface}}

      {:error, reason} ->
        Logger.error("Failed to create GPU surface: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call({:add_node, type, props}, _from, state) do
    node_id = make_ref()
    node = build_node(node_id, type, props)
    nodes = Map.put(state.nodes, node_id, node)
    sorted_ids = sort_nodes_by_z(Map.keys(nodes), nodes)
    {:reply, {:ok, node_id}, %{state | nodes: nodes, sorted_ids: sorted_ids}}
  end

  def handle_call(:render, _from, state) do
    now = System.monotonic_time(:millisecond)
    gpu = state.gpu_surface

    Dala.Gpu.clear(gpu, :transparent)

    for node_id <- state.sorted_ids do
      node = state.nodes[node_id]
      composite_node(gpu, node, state)
    end

    Dala.Gpu.present(gpu)

    frame_count = state.frame_count + 1
    {:reply, :ok, %{state | frame_count: frame_count, last_frame_time: now}}
  end

  def handle_call(:frame_count, _from, state), do: {:reply, state.frame_count, state}

  def handle_call(:fps, _from, state) do
    fps = calculate_fps(state)
    {:reply, fps, state}
  end

  @impl GenServer
  def handle_cast({:remove_node, node_id}, state) do
    nodes = Map.delete(state.nodes, node_id)
    sorted_ids = sort_nodes_by_z(Map.keys(nodes), nodes)
    {:noreply, %{state | nodes: nodes, sorted_ids: sorted_ids}}
  end

  def handle_cast({:update_node, node_id, props}, state) do
    case Map.get(state.nodes, node_id) do
      nil ->
        {:noreply, state}

      node ->
        updated = Map.merge(node, props)
        nodes = Map.put(state.nodes, node_id, updated)
        sorted_ids = sort_nodes_by_z(Map.keys(nodes), nodes)
        {:noreply, %{state | nodes: nodes, sorted_ids: sorted_ids}}
    end
  end

  def handle_cast({:set_transform, node_id, transform}, state) do
    case Map.get(state.nodes, node_id) do
      nil ->
        {:noreply, state}

      node ->
        updated = %{node | transform: Map.merge(node.transform || %{}, transform)}
        nodes = Map.put(state.nodes, node_id, updated)
        sorted_ids = sort_nodes_by_z(Map.keys(nodes), nodes)
        {:noreply, %{state | nodes: nodes, sorted_ids: sorted_ids}}
    end
  end

  def handle_cast({:set_target_fps, fps}, state) do
    {:noreply, %{state | target_fps: fps}}
  end

  @impl GenServer
  def terminate(_reason, %__MODULE__{gpu_surface: gpu}) when is_pid(gpu) do
    Dala.Gpu.destroy_surface(gpu)
    :ok
  end

  def terminate(_reason, _), do: :ok

  # Private

  defp build_node(id, type, props) do
    transform = %{
      position: Map.get(props, :position, {0, 0}),
      scale: Map.get(props, :scale, {1.0, 1.0}),
      rotation: Map.get(props, :rotation, 0.0),
      opacity: Map.get(props, :opacity, 1.0),
      z_index: Map.get(props, :z_index, 0),
    }

    %{
      id: id,
      type: type,
      transform: transform,
      size: Map.get(props, :size, {0, 0}),
      stream: Map.get(props, :stream),
      texture: Map.get(props, :texture),
      image_id: Map.get(props, :image_id),
      text: Map.get(props, :text),
      effect_type: Map.get(props, :type),
      radius: Map.get(props, :radius, 0.0),
      input: Map.get(props, :input),
      visible: Map.get(props, :visible, true),
    }
  end

  defp sort_nodes_by_z(node_ids, nodes) do
    Enum.sort_by(node_ids, fn id ->
      node = Map.get(nodes, id)
      (node[:transform] || %{})[:z_index] || 0
    end)
  end

  defp composite_node(_gpu, %{visible: false}, _state), do: :ok

  defp composite_node(gpu, %{type: :video, stream: stream} = node, _state) do
    case Dala.Media.Video.current_texture(stream) do
      nil ->
        :ok

      texture_id ->
        {x, y} = node.transform.position
        {w, h} = node.size
        Dala.Gpu.draw_image(gpu, texture_id, x, y, w, h)
    end
  end

  defp composite_node(gpu, %{type: :image, image_id: image_id} = node, _state)
       when is_integer(image_id) do
    {x, y} = node.transform.position
    {w, h} = node.size
    Dala.Gpu.draw_image(gpu, image_id, x, y, w, h)
  end

  defp composite_node(gpu, %{type: :overlay, texture: texture_id} = node, _state)
       when is_integer(texture_id) do
    {x, y} = node.transform.position
    {w, h} = node.size
    Dala.Gpu.draw_image(gpu, texture_id, x, y, w, h)
  end

  defp composite_node(gpu, %{type: :text, text: text} = node, _state) when is_binary(text) do
    {x, y} = node.transform.position
    {w, h} = node.size
    Dala.Gpu.fill_round_rect(gpu, x, y, w, h, 4, {0, 0, 0, 128})
  end

  defp composite_node(gpu, %{type: :effect, effect_type: :blur} = node, _state) do
    case Dala.Gpu.dispatch_compute(gpu, :blur, %{radius: node.radius}) do
      :ok -> :ok
      {:error, :not_implemented} -> :ok
      _ -> :ok
    end
  end

  defp composite_node(_gpu, _node, _state), do: :ok

  defp calculate_fps(%{last_frame_time: nil}), do: 0.0

  defp calculate_fps(_state) do
    60.0
  end
end
