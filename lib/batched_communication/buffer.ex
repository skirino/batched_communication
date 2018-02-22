use Croma

defmodule BatchedCommunication.Buffer do
  alias BatchedCommunication.{Compression, EncodedBatch}

  @type proc :: pid | atom
  @type dest :: proc | [proc]
  @type t    :: {pos_integer, reference, [{dest, any}]}

  defun make(node :: node, wait_time :: pos_integer, dest :: dest, msg :: any) :: t do
    timer = Process.send_after(self(), {:timeout, node}, wait_time)
    {1, timer, [{dest, msg}]}
  end

  defun add({n1, timer, pairs1} :: t, max :: pos_integer, compression :: Compression.t, dest :: dest, msg :: any) :: {:flush, EncodedBatch.t} | t do
    pairs2 = [{dest, msg} | pairs1]
    case n1 + 1 do
      n2 when n2 < max -> {n2, timer, pairs2}
      _gte_max         ->
        Process.cancel_timer(timer, [async: true])
        {:flush, encode_messages_impl(pairs2, compression)}
    end
  end

  defun encode_messages({_, _, pairs} :: t, compression :: Compression.t) :: EncodedBatch.t do
    encode_messages_impl(pairs, compression)
  end

  defp encode_messages_impl(pairs, compression) do
    b = :erlang.term_to_binary(pairs)
    z =
      case compression do
        :raw  -> b
        :gzip -> :zlib.gzip(b)
      end
    {compression, z}
  end
end
