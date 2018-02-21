if Mix.env() == :test do
  defmodule TestServer do
    use GenServer

    def start(pid) do
      GenServer.start(__MODULE__, pid, [name: __MODULE__])
    end

    @impl true
    def init(pid) do
      {:ok, %{pid: pid}}
    end

    @impl true
    def handle_call(msg, from, %{pid: pid} = state) do
      send(pid, {self(), :call, msg})
      BatchedCommunication.reply(from, make_reply(msg))
      {:noreply, state}
    end

    defp make_reply({:sleep, duration}) do
      :timer.sleep(duration)
      :ok
    end
    defp make_reply({:echo, any}) do
      any
    end

    @impl true
    def handle_cast(msg, %{pid: pid} = state) do
      send(pid, {self(), :cast, msg})
      {:noreply, state}
    end

    @impl true
    def handle_info(msg, %{pid: pid} = state) do
      send(pid, {self(), :info, msg})
      {:noreply, state}
    end
  end
end
