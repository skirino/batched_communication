use Croma

defmodule BatchedCommunication.Compression do
  use Croma.SubtypeOfAtom, values: [:raw, :gzip]
end

defmodule BatchedCommunication.EncodedBatch do
  use Croma.SubtypeOfTuple, elem_modules: [Croma.PosInteger, Croma.PosInteger, BatchedCommunication.Compression, Croma.Binary]
end
