use Croma

defmodule BatchedCommunication.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      Supervisor.child_spec({BatchedCommunication.FixedWorkersSup, BatchedCommunication.Sender  }, [id: :senders_sup  ]),
      Supervisor.child_spec({BatchedCommunication.FixedWorkersSup, BatchedCommunication.Receiver}, [id: :receivers_sup]),
    ]
    Supervisor.start_link(children, [strategy: :one_for_one])
  end
end

defmodule BatchedCommunication.FixedWorkersSup do
  use Supervisor
  @behaviour Supervisor

  @n_children 32
  def n_children(), do: @n_children

  def start_link(worker_module) do
    Supervisor.start_link(__MODULE__, worker_module, [])
  end

  @impl true
  def init(worker_module) do
    Supervisor.init(children(worker_module), [strategy: :one_for_one])
  end

  defp children(worker_module) do
    Enum.map(0 .. (@n_children - 1), &child(worker_module, &1))
  end

  defp child(worker_module, i) do
    Supervisor.child_spec({worker_module, i}, [id: worker_module.name(i)])
  end
end
