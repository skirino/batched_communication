use Croma

defmodule BatchedCommunication.Sender do
  use GenServer
  alias BatchedCommunication.{Receiver, FixedWorkersSup, Buffer, Compression}

  defmodule State do
    use Croma.Struct, fields: [
      max_wait_time:          {Croma.PosInteger, [default: 100]},
      max_messages_per_batch: {Croma.PosInteger, [default: 100]},
      compression:            Compression,
      receiver_name:          Croma.Atom,
      map:                    Croma.Map, # %{node => Buffer.t}
    ]
  end

  @n_children FixedWorkersSup.n_children()

  def start_link(i) do
    GenServer.start_link(__MODULE__, :ok, [name: name(i)])
  end

  @impl true
  def init(:ok) do
    receiver_name = Receiver.name(hash_node(Node.self()))
    {:ok, %State{compression: :gzip, receiver_name: receiver_name, map: %{}}}
  end

  @impl true
  def handle_call(:get_configurations, _from, state) do
    reply = Map.take(state, [:max_wait_time, :max_messages_per_batch, :compression])
    {:reply, reply, state}
  end

  @impl true
  def handle_cast({:max_wait_time, new_wait_time}, state) do
    {:noreply, %State{state | max_wait_time: new_wait_time}}
  end
  def handle_cast({:max_messages_per_batch, new_max}, state) do
    {:noreply, %State{state | max_messages_per_batch: new_max}}
  end
  def handle_cast({:compression, new_compression}, state) do
    {:noreply, %State{state | compression: new_compression}}
  end

  @impl true
  def handle_info({node, dest, msg},
                  %State{max_wait_time: wait_time, max_messages_per_batch: max, compression: compression, map: map1} = state) do
    new_state =
      case Map.get(map1, node) do
        nil  -> %State{state | map: Map.put(map1, node, Buffer.make(node, wait_time, dest, msg))}
        buf1 ->
          case Buffer.add(buf1, max, compression, dest, msg) do
            {:flush, bin} -> send_impl(state, node, bin)
            buf2          -> %State{state | map: Map.put(map1, node, buf2)}
          end
      end
    {:noreply, new_state}
  end
  def handle_info({:timeout, node}, %State{compression: compression, map: map} = state) do
    new_state =
      case Map.get(map, node) do
        nil -> state
        buf -> send_impl(state, node, Buffer.encode_messages(buf, compression))
      end
    {:noreply, new_state}
  end

  defp send_impl(%State{receiver_name: receiver_name, map: map} = state, node, binary) do
    # We simply drop the message if `:noconnect` is returned (when the destination node is disconnected from `Node.self()`),
    # with the assumption that
    # - retry will be done by the calling side
    # - reconnect will be done by another component (such as `RaftFleet`)
    _ = :erlang.send({receiver_name, node}, binary, [:noconnect])
    %State{state | map: Map.delete(map, node)}
  end

  defunp hash_node(node :: node) :: non_neg_integer do
    :erlang.phash2({:batch_sender, node}, @n_children)
  end

  defun name(i :: non_neg_integer) :: atom do
    :"batched_sender_#{i}"
  end

  def enqueue(n, pid_or_atom, msg) do
    send(name(hash_node(n)), {n, pid_or_atom, msg})
  end

  def get_configurations() do
    GenServer.call(name(0), :get_configurations)
  end

  defun change_property_in_all_senders(prop :: atom, value :: pos_integer | atom) :: :ok do
    Enum.each(0 .. (@n_children - 1), fn i ->
      GenServer.cast(name(i), {prop, value})
    end)
  end
end
