use Croma

defmodule BatchedCommunication.Receiver do
  use GenServer

  def start_link(i) do
    GenServer.start_link(__MODULE__, :ok, [name: name(i)])
  end

  @impl true
  def init(:ok) do
    {:ok, %{}}
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
      {:raw , b} -> b
      {:gzip, b} -> :zlib.gunzip(b)
    end
    |> :erlang.binary_to_term()
    |> Enum.reverse() # `Sender` accumulates messages in the reverse order; here we have to restore the original order
  end

  defun name(i :: non_neg_integer) :: atom do
    :"batched_receiver_#{i}"
  end
end
