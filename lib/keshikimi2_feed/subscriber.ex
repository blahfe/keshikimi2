defmodule Keshikimi2Feed.Subscriber do
  @moduledoc false

  @type event :: atom
  @type package :: any
  @type registration :: {Keshikimi2.feed_group(), event}
  @type message :: {Keshikimi2.feed_group(), event, package}

  @spec start_link(Registry.registry()) :: Supervisor.on_start()
  def start_link(prefix, opts \\ []) do
    opts
    |> Keyword.put(:id, :subscriber_registry)
    |> Keyword.put(:keys, :duplicate)
    |> Keyword.put(:name, registry(prefix))
    |> Registry.start_link()
  end

  @spec dispatch_change(atom, message) :: :ok
  def dispatch_change(prefix, {feed_group, event, _} = message) do
    Registry.dispatch(registry(prefix), {feed_group, event}, fn listeners ->
      for {pid, :ok} <- listeners, do: send(pid, message)
    end)
  end

  @spec subscribe(atom, registration) :: :ok | {:error, {:already_registered, pid}}
  def subscribe(prefix, msg) do
    Registry.register(registry(prefix), msg, :ok)
  end

  defp registry(prefix) do
    String.to_atom("#{prefix}.#{__MODULE__}")
  end
end
