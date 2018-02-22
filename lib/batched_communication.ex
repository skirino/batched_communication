use Croma

defmodule BatchedCommunication do
  @moduledoc File.read!(Path.join([__DIR__, "..", "README.md"])) |> String.replace_prefix("# BatchedCommunication\n\n", "")

  import Kernel, except: [send: 2]
  alias BatchedCommunication.{Compression, Sender}

  @type dest    :: pid | atom | {atom, node}
  @type message :: any
  @type reply   :: any

  @doc """
  Sends an asynchronous message to the given destination process.

  When you want to batch multiple messages to the same destination node,
  you can use this function as a replacement for `GenServer.cast/2`.
  """
  defun cast(dest :: dest, msg :: message) :: :ok do
    send(dest, {:"$gen_cast", msg})
  end

  @doc """
  Makes a synchronous request to the given destination process.

  When you want to batch multiple messages to the same destination node,
  you can use this function as a replacement for `GenServer.call/3`.
  """
  defun call(dest :: dest, msg :: message, t :: timeout | {:clean_timeout, timeout} | {:dirty_timeout, timeout} \\ 5000) :: reply do
    ref = Process.monitor(dest)
    try do
      send(dest, {:"$gen_call", {self(), ref}, msg})
    rescue
      ArgumentError -> :ok # no process found for the name
    end
    receive do
      {^ref, reply}                      -> Process.demonitor(ref, [:flush]); reply
      {:DOWN, ^ref, _, _, :noconnection} -> exit({{:nodedown, get_node(dest)}, {__MODULE__, :call, [dest, msg, t]}})
      {:DOWN, ^ref, _, _, reason}        -> exit({reason, {__MODULE__, :call, [dest, msg, t]}})
    after
      timeout(t) ->
        Process.demonitor(ref, [:flush])
        exit({:timeout, {__MODULE__, :call, [dest, msg, t]}})
    end
  end

  defp get_node({_name, node}), do: node
  defp get_node(p) when is_pid(p), do: node(p)

  defp timeout({:dirty_timeout, t}), do: t
  defp timeout({:clean_timeout, t}), do: t
  defp timeout(t                  ), do: t

  @doc """
  Sends a reply to a client that has sent a synchronous request.

  When you want to batch multiple messages to the same destination node,
  you can use this function as a replacement for `GenServer.reply/2`.
  """
  defun reply({pid, tag} :: {pid, reference}, reply :: reply) :: :ok do
    send(pid, {tag, reply})
  end

  @doc """
  Sends `message` to the destination process `dest` with a batching mechanism.
  """
  defun send(dest :: dest, message :: message) :: :ok do
    case dest do
      a when is_atom(a)       -> Kernel.send(a, message)
      {a, n} when n == node() -> Kernel.send(a, message)
      {a, n}                  -> Sender.enqueue(n, a, message)
      pid when is_pid(pid)    ->
        case node(pid) do
          n when n == node() -> Kernel.send(pid, message)
          n                  -> Sender.enqueue(n, pid, message)
        end
    end
    :ok
  end

  @type configurations :: %{
    max_wait_time:          pos_integer,
    max_messages_per_batch: pos_integer,
    compression:            Compression.t,
  }

  @doc """
  Gets the current configurations.
  """
  defun get_configurations() :: configurations do
    Sender.get_configurations()
  end

  @doc """
  Sets maximum wait time (in milliseconds) before sending messages as a batch.

  When a `BatchedCommunication.Sender` process receives a message for a particular destination node,
  it starts a timer with the maximum wait time.
  When the timer fires the accumulated messages are sent in one batch.
  Defaults to `100` milliseconds.
  """
  defun change_max_wait_time(time :: g[pos_integer]) :: :ok do
    Sender.change_property_in_all_senders(:max_wait_time, time)
  end

  @doc """
  Sets maximum number of messages to accumulate in one batch.

  When a `BatchedCommunication.Sender` process has messages more than or equal to this maximum,
  it immediately (i.e., without waiting for timer; see also `change_max_wait_time/1`) sends the messages in one batch.
  Defaults to `100` messages.
  """
  defun change_max_messages_per_batch(max :: g[pos_integer]) :: :ok do
    Sender.change_property_in_all_senders(:max_messages_per_batch, max)
  end

  @doc """
  Changes whether to compress each batch of messages or not.

  Currently supported values are `:gzip` and `:raw` (no compression).
  Defaults to `:gzip`.
  """
  defun change_compression(compression :: Compression.t) :: :ok do
    if not Compression.valid?(compression) do
      raise ArgumentError, "invalid value for compression setting: #{inspect(compression)}"
    end
    Sender.change_property_in_all_senders(:compression, compression)
  end
end
