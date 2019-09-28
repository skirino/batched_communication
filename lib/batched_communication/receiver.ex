use Croma

defmodule BatchedCommunication.Receiver do
  use GenServer

  @n_children BatchedCommunication.FixedWorkersSup.n_children()

  def start_link(i) do
    GenServer.start_link(__MODULE__, :ok, [name: name(i)])
  end

  @impl true
  def init(:ok) do
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:priority, new_priority}, state) do
    Process.flag(:priority, new_priority)
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    decode_to_pairs(msg)
    |> Enum.each(fn {dest, msg} ->
      case dest do
        dests when is_list(dests) -> Enum.each(dests, &send(&1, msg))
        _pid_or_name              -> send(dest, msg)
      end
    end)
    {:noreply, state}
  end

  defp decode_to_pairs(msg) do
    case msg do
      {:raw , b} when is_binary(b) -> b               |> to_terms()
      {:gzip, b} when is_binary(b) -> :zlib.gunzip(b) |> to_terms()
      _unexpected                  -> []
    end
  end

  defp to_terms(b) do
    b
    |> :erlang.binary_to_term()
    |> Enum.reverse() # `Sender` accumulates messages in the reverse order; here we have to restore the original order
  end

  defun name(i :: non_neg_integer) :: atom do
    :"batched_receiver_#{i}"
  end

  defun change_property_in_all_receivers(prop :: atom, value :: pos_integer | atom) :: :ok do
    Enum.each(0 .. (@n_children - 1), fn i ->
      GenServer.cast(name(i), {prop, value})
    end)
  end
end
