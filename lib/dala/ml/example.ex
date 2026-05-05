defmodule Dala.ML.Example do
  @moduledoc """
  Simple example of using EMLX in a Dala iOS app.

  This module demonstrates basic ML operations using EMLX on iOS.
  """

  @doc """
  Simple tensor operations with EMLX backend.

  Run this in an iOS Dala app after setting up EMLX.
  """
  def basic_operations do
    # Ensure EMLX is set up
    Dala.ML.Nx.init_for_ios()

    # Create tensors
    a = Nx.tensor([[1.0, 2.0], [3.0, 4.0]], backend: EMLX.Backend)
    b = Nx.tensor([[5.0], [6.0]], backend: EMLX.Backend)

    # Matrix multiplication
    result = Nx.dot(a, b)

    %{
      input_a: Nx.to_flat_list(a),
      input_b: Nx.to_flat_list(b),
      result: Nx.to_flat_list(result),
      backend: "EMLX"
    }
  end

  @doc """
  Image classification using a quantized dalaileNet model.
  """
  def image_classify(image_tensor, _model_path \\ "dalailenet_v2_quantized") do
    input =
      image_tensor
      |> Nx.reshape({224, 224, 3})
      |> Nx.divide(255.0)
      |> Nx.subtract(0.5)
      |> Nx.multiply(2.0)
      |> Nx.reshape({1, 224, 224, 3})

    # Simulate inference with EMLX
    output = Nx.random_uniform({1, 1000}, backend: EMLX.Backend)

    %{
      predicted_class: Nx.argmax(output) |> Nx.to_number(),
      confidence: Nx.max(output) |> Nx.to_number(),
      backend: "EMLX",
      note: "Load actual quantized model for production"
    }
  end

  @doc """
  Simplified YOLO-like object detection.
  """
  def yolo_detect(image_tensor, _model_path \\ "yolo_nano_quantized") do
    input =
      image_tensor
      |> Nx.reshape({416, 416, 3})
      |> Nx.divide(255.0)
      |> Nx.reshape({1, 416, 416, 3})

    # Simulate YOLO output: [batch, grid, grid, 3 * (5 + classes)]
    detection_output =
      Nx.random_uniform({1, 13, 13, 18}, backend: EMLX.Backend)

    %{
      output_shape: Nx.shape(detection_output),
      backend: "EMLX",
      note: "Use real YOLO model for production detection"
    }
  end

  @doc """
  Load a pre-trained quantized model for iOS.
  """
  def load_quantized_model(model_name) when is_binary(model_name) do
    %{
      model_name: model_name,
      status: :placeholder,
      suggested_models: [
        "dalailenet_v2_quantized",
        "yolo_nano_quantized",
        "efficientnet_lite_quantized"
      ]
    }
  end

  @doc """
  Verify EMLX is working on iOS.
  """
  def verify_setup do
    case Dala.ML.EMLX.available?() do
      true ->
        result = basic_operations()
        {:ok, result}

      false ->
        {:error, "EMLX not available. Check that :emlx is in your deps."}
    end
  end
end
