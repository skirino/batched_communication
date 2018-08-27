use Croma

defmodule BatchedCommunication do
  @moduledoc File.read!(Path.join([__DIR__, "..", "README.md"])) |> String.replace_prefix("# BatchedCommunication\n\n", "")

  import Kernel, except: [send: 2]
  alias BatchedCommunication.{Compression, Sender, Receiver}

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
    send(dest, {:"$gen_call", {self(), ref}, msg})
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
    {p, n} = node_pair(dest)
    case n == node() do
      true  -> send_local(p, message)
      false -> Sender.enqueue(n, p, message)
    end
    :ok
  end

  @doc """
  Sends the same `message` to multiple destination processes.
  """
  defun broadcast(dests :: [dest], message :: message) :: :ok do
    dests_per_node =
      Enum.map(dests, &node_pair/1)
      |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
    {dests_in_this_node, dests_per_remote_node} = Map.pop(dests_per_node, Node.self(), [])
    Enum.each(dests_in_this_node, fn d -> send_local(d, message) end)
    Enum.each(dests_per_remote_node, fn {n, ds} -> Sender.enqueue(n, ds, message) end)
  end

  defp node_pair(p) when is_pid(p) , do: {p, node(p)}
  defp node_pair(a) when is_atom(a), do: {a, Node.self()}
  defp node_pair({_a, _n} = pair)  , do: pair

  defp send_local(p, message) do
    try do
      Kernel.send(p, message)
    rescue
      ArgumentError -> :ok # no process found for name (in this case `p` is an atom)
    end
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

  @doc """
  Changes the process scheduling priority of senders and receivers.

  By default processes run with `:normal` priority.
  You can change the priority of all sender/receiver processes using this function.
  See also [`:erlang.process_flag/2`](http://erlang.org/doc/man/erlang.html#process_flag_priority).
  """
  defun change_process_priority(priority :: :high | :normal | :low) :: :ok do
    :high   -> change_property_in_all_senders_and_receivers(:priority, :high  )
    :normal -> change_property_in_all_senders_and_receivers(:priority, :normal)
    :low    -> change_property_in_all_senders_and_receivers(:priority, :low   )
  end

  defp change_property_in_all_senders_and_receivers(prop, value) do
    Sender.change_property_in_all_senders(prop, value)
    Receiver.change_property_in_all_receivers(prop, value)
  end

  @type batch_stats :: {n_messages :: pos_integer, raw_bytes :: pos_integer, sent_bytes :: pos_integer}

  @doc """
  Collect statistics of batches sent from this node to the specified node during the specified duration (in milliseconds).

  Each element of the returned list is a 3-tuple that consists of

  - number of messages in a batch
  - byte size of the batch before comprression
  - byte size of the batch after compression (this is equal to the previous one if `:raw` compression option is used)
  """
  defun collect_sending_stats(dest_node :: g[node], duration :: g[pos_integer]) :: [batch_stats] do
    if dest_node == Node.self(), do: raise "target node must not be the current node"
    Sender.collect_stats(dest_node, duration)
  end
end
