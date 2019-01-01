defmodule Keshikimi2.Application do
  @moduledoc false

  use Application
  import Supervisor.Spec
  require IEx

  def start(_type, [prefix]) do
    Supervisor.start_link(
      [
        :hackney_pool.child_spec(:hatena_bookmark_pool, timeout: 15_000, max_connections: 100),
        supervisor(Cachex, [:feed, []]),
        supervisor(Keshikimi2Feed.Registry, [prefix]),
        supervisor(Keshikimi2Feed.Subscriber, [prefix]),
        worker(Keshikimi2Feed.Worker, [prefix]),
        worker(Keshikimi2Feed.Publisher, [[prefix: prefix, poll_interval: 3_000]]),
        worker(Keshikimi2.HatenaBookmark.AddEntry, [
          [prefix: prefix, poll_interval: 3_000]
        ])
      ],
      strategy: :one_for_all,
      name: name(prefix)
    )
  end

  #
  # Helpers
  #
  defp name(prefix) do
    String.to_atom("#{prefix}.#{__MODULE__}")
  end
end
