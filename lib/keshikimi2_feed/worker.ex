defmodule Keshikimi2Feed.Worker do
  @moduledoc false

  use GenServer
  alias Keshikimi2Feed.Subscriber
  require Logger
  require IEx

  def start_link(prefix) do
    warm_caches([:code.priv_dir(:keshikimi2), "yaml"] |> Path.join())
    GenServer.start_link(__MODULE__, [prefix])
  end

  def init([prefix]) do
    Cachex.get!(:feed, "feed_group")[:maps]
    |> Map.keys()
    |> Enum.each(fn feed_group ->
      Subscriber.subscribe(prefix, {feed_group, :changed})
    end)

    {:ok, %{}}
  end

  def handle_info({feed_group, :changed, %{feed_items: feed_items}}, state) do
    feed_items
    |> Enum.each(fn {item_link, item_title, feed_tags} ->
      Cachex.put(:feed, item_link, [item_title, feed_tags])
    end)

    {:noreply, state}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  #
  # Helpers
  #
  defp warm_caches(yaml_path) do
    feed_group_maps = YamlElixir.read_from_file!("#{yaml_path}/feed.yaml")
    Cachex.load(:feed, [:code.priv_dir(:keshikimi2), "tmp", "cache.dump"] |> Path.join())

    Cachex.put_many(:feed, [
      {"excluded_titles", YamlElixir.read_from_file!("#{yaml_path}/feed_excluded_title.yaml")},
      {"excluded_links", YamlElixir.read_from_file!("#{yaml_path}/feed_excluded_link.yaml")},
      {"corrected_links", YamlElixir.read_from_file!("#{yaml_path}/feed_corrected_link.yaml")},
      {"redirected_links", YamlElixir.read_from_file!("#{yaml_path}/feed_redirected_link.yaml")},
      {"feed_group", %{maps: feed_group_maps, count: Enum.count(feed_group_maps)}}
    ])

    case Cachex.get(:feed, "archived_links") do
      {:ok, []} -> nil
      {:ok, [_ | _]} -> nil
      _ -> Cachex.put!(:feed, "archived_links", [])
    end
  end
end
