defmodule Keshikimi2Feed.PublisherTrigger do
  defmodule State do
    defstruct feed_items: []
  end

  def init(_) do
    {:ok, %State{}}
  end

  def update(feed_items, %{feed_items: feed_items} = state) do
    {:ok, state}
  end

  def update(new_feed_items, state) do
    {:changed, %{state | feed_items: new_feed_items}}
  end
end
