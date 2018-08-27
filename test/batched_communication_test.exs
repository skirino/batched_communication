defmodule BatchedCommunicationTest do
  use ExUnit.Case
  alias BatchedCommunication, as: BC
  alias BatchedCommunication.{Sender, Receiver, FixedWorkersSup}

  defmacro at(call, nodename) do
    {{:., _, [mod, fun]}, _, args} = call
    quote bind_quoted: [nodename: nodename, mod: mod, fun: fun, args: args] do
      if nodename == Node.self() do
        apply(mod, fun, args)
      else
        :rpc.call(nodename, mod, fun, args)
      end
    end
  end

  defp start_slave() do
    {:ok, hostname} = :inet.gethostname()
    {:ok, longname} = :slave.start_link(hostname, :slave)
    true            = :code.set_path(:code.get_path()) |> at(longname)
    {:ok, _}        = Application.ensure_all_started(:batched_communication) |> at(longname)
    longname
  end

  test "public functions in BatchedCommunication should behave (basically) in the same way as GenServer functions" do
    {:ok, pid_local} = TestServer.start(self())
    name_local = TestServer

    slave = start_slave()
    {:ok, pid_remote} = TestServer.start(self()) |> at(slave)
    name_remote = {TestServer, slave}

    # cast
    assert BC.cast(pid_local, :foo) == :ok
    assert_receive({^pid_local, :cast, :foo})
    assert BC.cast(name_local, :foo) == :ok
    assert_receive({^pid_local, :cast, :foo})

    assert BC.cast(pid_remote, :foo) == :ok
    assert_receive({^pid_remote, :cast, :foo}, 250)
    assert BC.cast(name_remote, :foo) == :ok
    assert_receive({^pid_remote, :cast, :foo}, 250)

    # send
    assert BC.send(pid_local, :foo) == :ok
    assert_receive({^pid_local, :info, :foo})
    assert BC.send(name_local, :foo) == :ok
    assert_receive({^pid_local, :info, :foo})

    assert BC.send(pid_remote, :foo) == :ok
    assert_receive({^pid_remote, :info, :foo}, 250)
    assert BC.send(name_remote, :foo) == :ok
    assert_receive({^pid_remote, :info, :foo}, 250)

    # broadcast
    assert BC.broadcast([pid_local, name_local, pid_remote, name_remote], :foo) == :ok
    assert_receive({^pid_local, :info, :foo})
    assert_receive({^pid_local, :info, :foo})
    assert_receive({^pid_remote, :info, :foo}, 250)
    assert_receive({^pid_remote, :info, :foo}, 250)

    # call
    assert BC.call(pid_local, {:echo, :foo}) == :foo
    assert_receive({^pid_local, :call, {:echo, :foo}})
    assert BC.call(name_local, {:echo, :foo}) == :foo
    assert_receive({^pid_local, :call, {:echo, :foo}})

    assert BC.call(pid_remote, {:echo, :foo}) == :foo
    assert_receive({^pid_remote, :call, {:echo, :foo}}, 250)
    assert BC.call(name_remote, {:echo, :foo}) == :foo
    assert_receive({^pid_remote, :call, {:echo, :foo}}, 250)

    # timeout in call
    assert catch_exit(GenServer.call(pid_local , {:sleep, 500}, 200)) == {:timeout, {GenServer, :call, [pid_local , {:sleep, 500}, 200]}}
    assert catch_exit(GenServer.call(name_local, {:sleep, 500}, 200)) == {:timeout, {GenServer, :call, [name_local, {:sleep, 500}, 200]}}
    assert catch_exit(BC       .call(pid_local , {:sleep, 500}, 200)) == {:timeout, {BC       , :call, [pid_local , {:sleep, 500}, 200]}}
    assert catch_exit(BC       .call(name_local, {:sleep, 500}, 200)) == {:timeout, {BC       , :call, [name_local, {:sleep, 500}, 200]}}
    Enum.each(1..4, fn _ ->
      assert_receive({^pid_local, :call, {:sleep, 500}})
      assert_receive({_ref, :ok}, 2000) # consume late replies
    end)

    assert catch_exit(GenServer.call(pid_remote , {:sleep, 500}, 200)) == {:timeout, {GenServer, :call, [pid_remote , {:sleep, 500}, 200]}}
    assert catch_exit(GenServer.call(name_remote, {:sleep, 500}, 200)) == {:timeout, {GenServer, :call, [name_remote, {:sleep, 500}, 200]}}
    assert catch_exit(BC       .call(pid_remote , {:sleep, 500}, 200)) == {:timeout, {BC       , :call, [pid_remote , {:sleep, 500}, 200]}}
    assert catch_exit(BC       .call(name_remote, {:sleep, 500}, 200)) == {:timeout, {BC       , :call, [name_remote, {:sleep, 500}, 200]}}
    Enum.each(1..4, fn _ ->
      assert_receive({^pid_remote, :call, {:sleep, 500}})
      assert_receive({_ref, :ok}, 2000) # consume late replies
    end)

    # call to dead pid
    assert GenServer.stop(pid_local ) == :ok
    assert GenServer.stop(pid_remote) == :ok

    assert catch_exit(GenServer.call(pid_local , {:sleep, 500}, 200)) == {:noproc, {GenServer, :call, [pid_local , {:sleep, 500}, 200]}}
    assert catch_exit(GenServer.call(name_local, {:sleep, 500}, 200)) == {:noproc, {GenServer, :call, [name_local, {:sleep, 500}, 200]}}
    assert catch_exit(BC       .call(pid_local , {:sleep, 500}, 200)) == {:noproc, {BC       , :call, [pid_local , {:sleep, 500}, 200]}}
    assert catch_exit(BC       .call(name_local, {:sleep, 500}, 200)) == {:noproc, {BC       , :call, [name_local, {:sleep, 500}, 200]}}

    assert catch_exit(GenServer.call(pid_remote , {:sleep, 500}, 200)) == {:noproc, {GenServer, :call, [pid_remote , {:sleep, 500}, 200]}}
    assert catch_exit(GenServer.call(name_remote, {:sleep, 500}, 200)) == {:noproc, {GenServer, :call, [name_remote, {:sleep, 500}, 200]}}
    assert catch_exit(BC       .call(pid_remote , {:sleep, 500}, 200)) == {:noproc, {BC       , :call, [pid_remote , {:sleep, 500}, 200]}}
    assert catch_exit(BC       .call(name_remote, {:sleep, 500}, 200)) == {:noproc, {BC       , :call, [name_remote, {:sleep, 500}, 200]}}

    # call to pid in disconnected node
    :ok = :slave.stop(slave)

    assert catch_exit(GenServer.call(pid_remote , {:sleep, 500}, 200)) == {{:nodedown, slave}, {GenServer, :call, [pid_remote , {:sleep, 500}, 200]}}
    assert catch_exit(GenServer.call(name_remote, {:sleep, 500}, 200)) == {{:nodedown, slave}, {GenServer, :call, [name_remote, {:sleep, 500}, 200]}}
    assert catch_exit(BC       .call(pid_remote , {:sleep, 500}, 200)) == {{:nodedown, slave}, {BC       , :call, [pid_remote , {:sleep, 500}, 200]}}
    assert catch_exit(BC       .call(name_remote, {:sleep, 500}, 200)) == {{:nodedown, slave}, {BC       , :call, [name_remote, {:sleep, 500}, 200]}}

    # check that there's no extra message
    refute_receive(_)
  end

  defp assert_props_in_all_senders(max_messages, max_wait_time, compression) do
    s = BC.get_configurations()
    assert s.max_messages_per_batch == max_messages
    assert s.max_wait_time          == max_wait_time
    assert s.compression            == compression

    Enum.each(0 .. (FixedWorkersSup.n_children() - 1), fn i ->
      s = :sys.get_state(Sender.name(i))
      assert s.max_messages_per_batch == max_messages
      assert s.max_wait_time          == max_wait_time
      assert s.compression            == compression
    end)
  end

  test "Properties in all Sender processes should be updated" do
    assert_props_in_all_senders(100, 100, :gzip)
    assert BC.change_max_messages_per_batch(200) == :ok
    assert_props_in_all_senders(200, 100, :gzip)
    assert BC.change_max_messages_per_batch(100) == :ok
    assert_props_in_all_senders(100, 100, :gzip)
    assert BC.change_max_wait_time(50) == :ok
    assert_props_in_all_senders(100, 50, :gzip)
    assert BC.change_max_wait_time(100) == :ok
    assert_props_in_all_senders(100, 100, :gzip)
    assert BC.change_compression(:raw) == :ok
    assert_props_in_all_senders(100, 100, :raw)
    assert BC.change_compression(:gzip) == :ok
    assert_props_in_all_senders(100, 100, :gzip)
  end

  test "priorities of all senders/receivers should be updated" do
    sender_names   = Enum.map(0 .. (FixedWorkersSup.n_children() - 1), &Sender.name/1)
    receiver_names = Enum.map(0 .. (FixedWorkersSup.n_children() - 1), &Receiver.name/1)
    pids = Enum.map(sender_names ++ receiver_names, &Process.whereis/1)
    Enum.each(pids, fn pid ->
      assert Process.alive?(pid)
      assert Process.info(pid, :priority) == {:priority, :normal}
    end)

    assert BC.change_process_priority(:high) == :ok
    Enum.each(pids, fn pid ->
      _ = :sys.get_state(pid) # confirm that the cast message has been processed
      assert Process.alive?(pid)
      assert Process.info(pid, :priority) == {:priority, :high}
    end)

    assert BC.change_process_priority(:normal) == :ok
    Enum.each(pids, fn pid ->
      _ = :sys.get_state(pid) # confirm that the cast message has been processed
      assert Process.alive?(pid)
      assert Process.info(pid, :priority) == {:priority, :normal}
    end)
  end

  defp client_loop(target) do
    BC.send(target, :foo)
    receive do
      :finish -> :ok
    after
      10 -> client_loop(target)
    end
  end

  test "should collect sending stats for a specified node" do
    slave = start_slave()
    {:ok, pid_remote} = TestServer.start(self()) |> at(slave)
    assert BC.collect_sending_stats(slave, 500) == []

    {client, ref} = spawn_monitor(fn -> client_loop(pid_remote) end)
    assert length(BC.collect_sending_stats(slave, 500)) in [4, 5]

    send(client, :finish)
    receive do
      {:DOWN, ^ref, :process, ^client, :normal} -> :ok
    end
  end
end
