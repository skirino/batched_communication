# BatchedCommunication

Mostly-transparent batching of remote messages in Erlang/Elixir cluster.

- [API Documentation](http://hexdocs.pm/batched_communication/)
- [Hex package information](https://hex.pm/packages/batched_communication)

[![Hex.pm](http://img.shields.io/hexpm/v/batched_communication.svg)](https://hex.pm/packages/batched_communication)
[![Build Status](https://travis-ci.org/skirino/batched_communication.svg)](https://travis-ci.org/skirino/batched_communication)
[![Coverage Status](https://coveralls.io/repos/skirino/batched_communication/badge.png?branch=master)](https://coveralls.io/r/skirino/batched_communication?branch=master)

## Features & Design

For high throughput use cases ErlangVM's default remote messaging may not be optimal.
Messages that are not sensitive to latency can be sent in compressed batches to save network bandwidth and to reduce TCP overhead.

- `BatchedCommunication.cast/2`, `BatchedCommunication.call/3`, etc. (which behave similarly to `GenServer.cast/2`, `GenServer.call/3`, etc.) are provided.
- Remote messages sent using `BatchedCommunication` are relayed to the following processes:
    - A `BatchedCommunication.Sender` process on the sender node, which buffers messages for a while,
      (optionally) compresses it, and sends the batch to the `Receiver` process on the destination node.
    - A `BatchedCommunication.Receiver` process on the receiver node, which decodes the received batch and
      dispatches messages to each destination process.

- There are 32 `Sender`s and 32 `Receiver`s in each node (for concurrency within each node) and
  the actual `Sender` and `Receiver` processes are chosen by hash values of receiver node and sender node, respectively.
  Thus message passing using `BatchedCommunication` preserves order of messages between each pair of processes
  (just as the original Erlang message passing does),
  since messages go through the same set of `Sender` and `Receiver` processes.
- The following configuration parameters can be modified at runtime:
    - maximum wait time before sending messages as a batch
    - maximum number of accumulated messages (during wait time) in a batch
    - whether to compress batched messages or not
- Of course local messages (i.e., message sent within a single node) are delivered immediately, bypassing the batching mechanism described above.
