defmodule Keshikimi2Feed.Publisher do
  use GenServer
  alias Keshikimi2Feed.Registry
  alias Keshikimi2Feed.Subscriber
  require IEx

  defmodule State do
    @moduledoc false
    defstruct [
      :feed_group,
      :feed_group_index,
      :trigger_state,
      :poll_interval,
      :prefix,
      :trigger,
      :poll_reference
    ]

    def poll(%State{poll_interval: 0} = state, _pid) do
      state
    end

    def poll(%State{poll_interval: poll_interval} = state, pid) do
      reference = Process.send_after(pid, :poll_updating, poll_interval)
      %{state | poll_reference: reference}
    end

    def cancel_polling(%State{poll_reference: reference} = state) do
      Process.cancel_timer(reference)
      %{state | poll_reference: nil}
    end

    def change_interval(state, interval) do
      %{state | poll_interval: interval}
    end
  end

  @doc """
  Starts a process linked to the current process. This is often used to start the process as part of a supervision tree.

  ## Options
  - `:poll_interval` - The time in ms between polling for state.i If set to 0 polling will be turned off. Default: `100`
  - `:trigger` - This is used to pass in a trigger to use for triggering events. See specific poller for defaults
  - `:trigger_opts` - This is used to pass options to a trigger `init\1`. The default is `[]`
  """
  @spec start_link() :: Supervisor.on_start()
  def start_link(opts \\ []) do
    poll_interval = Keyword.get(opts, :poll_interval, 100)
    trigger = Keyword.get(opts, :trigger, Keshikimi2Feed.PublisherTrigger)
    trigger_opts = Keyword.get(opts, :trigger_opts, [])
    prefix = Keyword.get(opts, :prefix, Default)
    opts = Keyword.put(opts, :name, Registry.name(prefix, "feed_group"))

    GenServer.start_link(
      __MODULE__,
      [poll_interval, prefix, trigger, trigger_opts],
      opts
    )
  end

  @doc "Stops polling immediately"
  @spec stop_polling(atom) :: :ok
  def stop_polling(prefix \\ Default) do
    GenServer.cast(Registry.name(prefix, "feed_group"), {:change_polling, 0})
  end

  @doc "Stops the current scheduled polling event and starts a new one with the new interval"
  @spec change_polling(integer, atom) :: :ok
  def change_polling(interval, prefix \\ Default) do
    GenServer.cast(Registry.name(prefix, "feed_group"), {:change_polling, interval})
  end

  @doc "Fetch the feed items from the specified feed_group"
  @spec fetch(atom) :: 0 | 1
  def fetch(prefix \\ Default) do
    GenServer.call(Registry.name(prefix, "feed_group"), :read)
  end

  #
  # Server
  #
  def init([poll_interval, prefix, trigger, trigger_opts]) do
    {:ok, trigger_state} = trigger.init(trigger_opts)

    state_with_poll_reference =
      schedule_poll(%State{
        feed_group: nil,
        feed_group_index: 0,
        poll_interval: poll_interval,
        prefix: prefix,
        trigger: trigger,
        trigger_state: trigger_state
      })

    {:ok, state_with_poll_reference}
  end

  def handle_cast({:change_polling, interval}, state) do
    new_state =
      state
      |> State.cancel_polling()
      |> State.change_interval(interval)
      |> State.poll(self())

    {:noreply, new_state}
  end

  def handle_call(:read, _from, state) do
    {feed_items, new_state} = update_feed_items(state)
    {:reply, feed_items, new_state}
  end

  def handle_info(:poll_updating, state) do
    {_, new_state} = update_feed_items(state)
    new_state = schedule_poll(new_state)
    {:noreply, new_state}
  end

  #
  # Helpers
  #
  @spec update_feed_items(State) :: State
  defp update_feed_items(state) do
    with {:ok, feed_items} <- fetch_feed_items(state.feed_group),
         trigger = {_, trigger_state} <- state.trigger.update(feed_items, state.trigger_state),
         :ok <- dispatch(trigger, state.prefix, state.feed_group),
         feed_group_count <- Cachex.get!(:feed, "feed_group")[:count],
         feed_group_index <-
           if(state.feed_group_index + 1 > feed_group_count,
             do: state.feed_group_index + 1 - feed_group_count,
             else: state.feed_group_index + 1
           ) do
      {feed_items, %{state | trigger_state: trigger_state, feed_group_index: feed_group_index}}
    else
      _ -> {[], state}
    end
  end

  defp dispatch({:ok, _}, _, _) do
    :ok
  end

  defp dispatch({event, trigger_state}, prefix, feed_group) do
    Subscriber.dispatch_change(prefix, {feed_group, event, trigger_state})
  end

  defp schedule_poll(%State{} = state) do
    feed_group =
      Cachex.get!(:feed, "feed_group")[:maps]
      |> Map.keys()
      |> Enum.at(state.feed_group_index)

    State.poll(%State{state | feed_group: feed_group}, self())
  end

  def fetch_feed_items(feed_group) do
    with %{"tags" => feed_tags, "links" => feed_links} <-
           Cachex.get!(:feed, "feed_group")[:maps][feed_group] do
      {:ok,
       feed_links
       |> Enum.flat_map(fn feed_link ->
         case HTTPoison.get(feed_link) do
           {:ok, response} ->
             response
             |> Map.fetch!(:body)
             |> Floki.find("item")
             |> Enum.map(fn item ->
               case item do
                 {_, _, item_elems} ->
                   with [{"title", _, [item_title]}, {"link", _, [item_link]}] <-
                          item_elems |> Enum.filter(fn ie -> elem(ie, 0) in ["title", "link"] end) do
                     {item_link, item_title, feed_tags}
                   else
                     [{"title", _, [_item_title]}, {"link", _, [item_link]}] ->
                       {item_link, "", feed_tags}

                     _ ->
                       nil
                   end

                 _ ->
                   nil
               end
             end)

           {:error, _} ->
             [nil]
         end
       end)
       |> Enum.reject(&is_nil/1)}
    end
  end
end
