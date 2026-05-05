defmodule MLApp.HomeScreen do
  @moduledoc """
  Home screen for ML App with YOLO object detection demo.

  ## Features demonstrated:
  - Auto-configured EMLX backend (zero config!)
  - Simulated YOLO object detection
  - Camera integration ready
  """
  use Dala.Screen

  def mount(_params, _session, socket) do
    socket =
      socket
      |> Dala.Socket.assign(:detections, [])
      |> Dala.Socket.assign(:is_detecting, false)
      |> Dala.Socket.assign(:backend, detect_backend())

    {:ok, socket}
  end

  def render(assigns) do
    %{
      type: :column,
      props: %{padding: 16, spacing: 12},
      children:
        [
          %{type: :text, props: %{text: "YOLO Object Detection", text_size: :xl}},
          %{type: :text, props: %{text: "Backend: #{assigns.backend}"}},
          %{
            type: :button,
            props: %{text: "Run YOLO Detection"},
            on_tap: {self(), :detect}
          },
          %{
            type: :button,
            props: %{text: "Open Camera"},
            on_tap: {self(), :open_camera}
          },
          %{type: :separator, props: %{}},
          %{type: :text, props: %{text: "Detections:", text_size: :lg}}
        ] ++ render_detections(assigns.detections)
    }
  end

  defp render_detections([]) do
    [%{type: :text, props: %{text: "No detections yet. Tap 'Run YOLO Detection' to start."}}]
  end

  defp render_detections(detections) do
    Enum.map(detections, fn %{label: label, confidence: conf} ->
      %{
        type: :text,
        props: %{text: "#{label} (#{Float.round(conf * 100, 1)}%)"}
      }
    end)
  end

  def handle_event(:detect, _params, socket) do
    socket = Dala.Socket.assign(socket, :is_detecting, true)

    # Simulate YOLO detection (in real app, this would use camera frame)
    detections = simulate_yolo_detection()

    socket =
      socket
      |> Dala.Socket.assign(:detections, detections)
      |> Dala.Socket.assign(:is_detecting, false)

    {:noreply, socket}
  end

  def handle_event(:open_camera, _params, socket) do
    # Open camera for live detection
    # Dala.Camera.start_preview(label: "camera_preview")
    {:noreply, socket}
  end

  defp simulate_yolo_detection do
    # Simulated YOLO output - in production, use real EMLX model
    [
      %{label: "person", confidence: 0.92},
      %{label: "car", confidence: 0.87},
      %{label: "traffic light", confidence: 0.76},
      %{label: "bicycle", confidence: 0.65}
    ]
  end

  defp detect_backend do
    if Code.ensure_loaded?(EMLX) do
      "EMLX (Metal GPU)"
    else
      "Nx (CPU)"
    end
  end
end
