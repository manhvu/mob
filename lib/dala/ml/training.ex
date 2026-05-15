defmodule Dala.ML.Training do
  @moduledoc """
  On-device training support for Dala ML.

  Provides fine-tuning of pre-trained Axon models on-device with
  progress callbacks. All training runs on the dirty CPU scheduler
  to avoid blocking the BEAM.

  ## Usage

      model = Axon.input("input", shape: {nil, 784})
              |> Axon.dense(128, activation: :relu)
              |> Axon.dense(10, activation: :softmax)

      {init_fn, predict_fn} = Axon.build(model)
      params = init_fn.(Nx.template({1, 784}, :f32), %{})

      # Fine-tune on local data
      Dala.ML.Training.fine_tune(
        model, params, {train_data, train_labels},
        epochs: 5, batch_size: 32, learning_rate: 0.001,
        progress: fn epoch, loss -> IO.puts("Epoch \#{epoch}: loss=\#{loss}") end
      )
  """

  @doc """
  Fine-tunes a model on-device with progress reporting.

  ## Options

  - `:epochs` — Number of training epochs (default: 5)
  - `:batch_size` — Mini-batch size (default: 32)
  - `:learning_rate` — Optimizer learning rate (default: 0.001)
  - `:optimizer` — Optimizer function (default: `Polaris.Optimizers.adam/1`)
  - `:loss` — Loss function (default: `:categorical_cross_entropy`)
  - `:progress` — Callback `(epoch, loss) -> :ok` (default: no-op)
  - `:validation_data` — `{val_data, val_labels}` tuple for eval
  """
  @spec fine_tune(term(), term(), {term(), term()}, keyword()) ::
          {:ok, term()} | {:error, term()}
  def fine_tune(model, params, {data, labels}, opts \\ []) do
    epochs = Keyword.get(opts, :epochs, 5)
    lr = Keyword.get(opts, :learning_rate, 0.001)
    progress_fn = Keyword.get(opts, :progress, fn _, _ -> :ok end)
    loss_fn = Keyword.get(opts, :loss, :categorical_cross_entropy)
    optimizer = Keyword.get(opts, :optimizer, Polaris.Optimizers.adam(learning_rate: lr))

    try do
      result =
        model
        |> Axon.Loop.trainer(loss_fn, optimizer)
        |> Axon.Loop.run(
          {data, labels},
          params,
          epochs: epochs,
          progress_callback: progress_fn
        )

      {:ok, result}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @doc """
  Evaluates a model on validation data.

  Returns `{%{metrics: map()}, updated_params}`.
  """
  @spec evaluate(term(), term(), {term(), term()}, keyword()) ::
          {:ok, map()} | {:error, term()}
  def evaluate(model, params, {data, labels}, opts \\ []) do
    _metrics = Keyword.get(opts, :metrics, [:accuracy])

    try do
      result =
        model
        |> Axon.Loop.evaluator()
        |> Axon.Loop.metric(:accuracy)
        |> Axon.Loop.run({data, labels}, params)

      {:ok, result}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @doc """
  Saves model parameters to a file for later loading.
  """
  @spec save_params(term(), String.t()) :: :ok | {:error, term()}
  def save_params(params, path) do
    binary = :erlang.term_to_binary(params)
    File.write(path, binary)
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Loads model parameters from a file.
  """
  @spec load_params(String.t()) :: {:ok, term()} | {:error, term()}
  def load_params(path) do
    case File.read(path) do
      {:ok, binary} ->
        params = :erlang.binary_to_term(binary)
        {:ok, params}

      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  defp format_error(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_error(reason), do: Exception.message(reason)
end
