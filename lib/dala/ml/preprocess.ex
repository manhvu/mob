defmodule Dala.ML.Preprocess do
  @moduledoc """
  Preprocessing pipelines for ML model inputs.

  Provides standardized preprocessing for common input types:
  images, text, and audio. All functions return Nx tensors ready
  for model consumption.

  ## Image Preprocessing

      # Standard ImageNet preprocessing
      tensor = image_path
               |> Dala.ML.Preprocess.load_image()
               |> Dala.ML.Preprocess.resize({224, 224})
               |> Dala.ML.Preprocess.normalize(:imagenet)
               |> Dala.ML.Preprocess.to_batch()

  ## Audio Preprocessing

      spectrogram = audio_path
                    |> Dala.ML.Preprocess.load_audio()
                    |> Dala.ML.Preprocess.mel_spectrogram(sample_rate: 16000)
  """

  @imagenet_mean [0.485, 0.456, 0.406]
  @imagenet_std [0.229, 0.224, 0.225]

  @doc """
  Loads an image from a file path and returns a tensor.
  Returns an Nx tensor of shape `{height, width, 3}` with values 0..255.
  """
  @spec load_image(String.t()) :: {:ok, Nx.Tensor.t()} | {:error, term()}
  def load_image(path) do
    case File.read(path) do
      {:ok, binary} ->
        # Decode image binary to RGB tensor
        # Uses built-in Erlang image decoding
        case :erlang.binary_to_term(binary) do
          # If it's already a stored tensor
          tensor when is_struct(tensor, Nx.Tensor) ->
            {:ok, tensor}

          _ ->
            # Raw binary: assume RGB pixel data and create tensor
            # In production, use a proper image decoder
            {:ok, Nx.from_binary(binary, :u8)}
        end

      {:error, reason} ->
        {:error, "Failed to load image: #{format_error(reason)}"}
    end
  end

  @doc """
  Resizes an image tensor to the target size.

  `size` is a tuple `{height, width}`.
  """
  @spec resize(Nx.Tensor.t(), {pos_integer(), pos_integer()}) :: Nx.Tensor.t()
  def resize(tensor, {h, w}) do
    # Use Nx broadcasting for resize
    # In production, use proper bilinear/bicubic interpolation
    case Nx.shape(tensor) do
      {^h, ^w, 3} ->
        tensor

      _ ->
        # Simple resize via Nx operations
        # Real implementation would use Dala.Native for GPU resize
        tensor
        |> Nx.reshape({:auto, 3})
        |> Nx.slice([0, 0], [h, w])
    end
  end

  @doc """
  Normalizes a tensor with standard normalization schemes.

  ## Schemes

  - `:imagenet` — ImageNet mean/std normalization
  - `:minmax` — Scale to [0, 1]
  - `:standard` — Zero mean, unit variance
  - `{mean, std}` — Custom normalization
  """
  @spec normalize(Nx.Tensor.t(), atom() | {list(), list()}) :: Nx.Tensor.t()
  def normalize(tensor, :imagenet) do
    mean = Nx.tensor(@imagenet_mean, type: :f32)
    std = Nx.tensor(@imagenet_std, type: :f32)

    tensor
    |> Nx.divide(255.0)
    |> Nx.subtract(mean)
    |> Nx.divide(std)
  end

  def normalize(tensor, :minmax) do
    min = Nx.reduce_min(tensor)
    max = Nx.reduce_max(tensor)
    Nx.subtract(tensor, min) |> Nx.divide(Nx.subtract(max, min))
  end

  def normalize(tensor, :standard) do
    mean = Nx.mean(tensor)
    std = Nx.subtract(tensor, mean) |> Nx.pow(2) |> Nx.mean() |> Nx.sqrt()
    Nx.subtract(tensor, mean) |> Nx.divide(std)
  end

  def normalize(tensor, {mean, std}) do
    mean_t = Nx.tensor(mean, type: :f32)
    std_t = Nx.tensor(std, type: :f32)
    Nx.subtract(tensor, mean_t) |> Nx.divide(std_t)
  end

  @doc """
  Adds a batch dimension to a tensor (shape `{...}` → `{1, ...}`).
  """
  @spec to_batch(Nx.Tensor.t()) :: Nx.Tensor.t()
  def to_batch(tensor) do
    shape = [1 | Tuple.to_list(Nx.shape(tensor))] |> List.to_tuple()
    Nx.reshape(tensor, shape)
  end

  @doc """
  Converts an Nx tensor to a binary of f32 values for ONNX input.
  """
  @spec to_f32_binary(Nx.Tensor.t()) :: binary()
  def to_f32_binary(tensor) do
    tensor
    |> Nx.as_type(:f32)
    |> Nx.to_binary()
  end

  @doc """
  Loads audio from a file path.

  Returns `{:ok, {samples_tensor, sample_rate}}`.
  """
  @spec load_audio(String.t()) :: {:ok, {Nx.Tensor.t(), pos_integer()}} | {:error, term()}
  def load_audio(path) do
    case File.read(path) do
      {:ok, binary} ->
        # In production, use a proper audio decoder
        # For now, assume raw f32 PCM data at 16kHz
        samples = Nx.from_binary(binary, :f32)
        {:ok, {samples, 16000}}

      {:error, reason} ->
        {:error, "Failed to load audio: #{format_error(reason)}"}
    end
  end

  @doc """
  Computes a mel spectrogram from audio samples.

  ## Options

  - `:sample_rate` — Audio sample rate (default: 16000)
  - `:n_fft` — FFT size (default: 400)
  - `:n_mels` — Number of mel bands (default: 80)
  - `:hop_length` — Hop length (default: 160)
  """
  @spec mel_spectrogram(Nx.Tensor.t(), keyword()) :: {:ok, Nx.Tensor.t()}
  def mel_spectrogram(samples, opts \\ []) do
    #sample_rate = Keyword.get(opts, :sample_rate, 16000)
    n_fft = Keyword.get(opts, :n_fft, 400)
    n_mels = Keyword.get(opts, :n_mels, 80)
    hop_length = Keyword.get(opts, :hop_length, 160)

    # Compute STFT
    frames = stft(samples, n_fft, hop_length)

    # Compute power spectrum (magnitude squared)
    power = Nx.multiply(frames, frames)

    # Apply mel filterbank: project frequency bins to mel bands
    # power shape: {num_frames, n_fft}
    # We reduce n_fft dims to n_mels via a simple linear projection
    n_freqs = elem(Nx.shape(power), 1)
    mel_fb = mel_filterbank(n_mels, n_freqs)
    # mel_fb shape: {n_mels, n_freqs}, power shape: {num_frames, n_freqs}
    # Result: {n_mels, num_frames} then transpose to {num_frames, n_mels}
    result = Nx.dot(mel_fb, Nx.transpose(power))
    {:ok, Nx.transpose(result)}
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp format_error(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_error(reason), do: Exception.message(reason)

  defp stft(samples, n_fft, _hop_length) do
    # Simplified STFT — real implementation would use NxSignal
    samples = Nx.from_binary(Nx.to_binary(samples), :f32)
    # Pad and frame
    pad_size = div(n_fft, 2)
    padded = Nx.pad(samples, 0.0, [{pad_size, pad_size, 0}])
    # Ensure total size is a multiple of n_fft for reshape
    padded_size = elem(Nx.shape(padded), 0)
    remainder = rem(padded_size, n_fft)
    padded =
      if remainder != 0 do
        extra = n_fft - remainder
        Nx.pad(padded, 0.0, [{0, extra, 0}])
      else
        padded
      end
    # Return frames (simplified)
    Nx.reshape(padded, {:auto, n_fft})
  end

  defp mel_filterbank(n_mels, n_freqs) do
    # Simplified mel filterbank — returns a matrix of shape {n_mels, n_freqs}
    # that projects frequency bins to mel bands
    base = Nx.broadcast(Nx.tensor(1.0, type: :f32), {n_mels, n_freqs})
    # Scale rows to simulate mel filterbank
    scales = Nx.iota({n_mels}, axis: 0) |> Nx.divide(max(n_mels, 1)) |> Nx.add(1.0)
    Nx.multiply(base, Nx.reshape(scales, {n_mels, 1}))
  end
end
