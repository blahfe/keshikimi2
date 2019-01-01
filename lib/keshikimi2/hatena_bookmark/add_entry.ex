defmodule Keshikimi2.HatenaBookmark.AddEntry do
  @moduledoc false

  use GenServer
  alias Keshikimi2.HatenaBookmark
  alias Keshikimi2Feed.Registry
  require Logger
  require IEx

  defmodule State do
    @moduledoc false
    defstruct [
      :poll_interval,
      :prefix,
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

  def start_link(opts \\ []) do
    poll_interval = Keyword.get(opts, :poll_interval, 100)
    prefix = Keyword.get(opts, :prefix, Default)
    opts = Keyword.put(opts, :name, Registry.name(prefix, "hatena_bookmark"))

    GenServer.start_link(
      __MODULE__,
      [poll_interval, prefix],
      opts
    )
  end

  def stop_polling(prefix \\ Default) do
    GenServer.cast(Registry.name(prefix, "hatena_bookmark"), {:change_polling, 0})
  end

  def change_polling(interval, prefix \\ Default) do
    GenServer.cast(Registry.name(prefix, "hatena_bookmark"), {:change_polling, interval})
  end

  #
  # Server
  #
  def init([poll_interval, prefix]) do
    state_with_poll_reference =
      schedule_poll(%State{
        poll_interval: poll_interval,
        prefix: prefix
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

  def handle_info(:poll_updating, state) do
    add_entries_to_hb()
    schedule_poll(state)
    {:noreply, state}
  end

  #
  # Helpers.AddEntry
  #
  defp add_entries_to_hb() do
    Cachex.keys!(:feed)
    |> Enum.reject(fn key ->
      key in [
        "excluded_links",
        "excluded_titles",
        "corrected_links",
        "redirected_links",
        "feed_group",
        "archived_links"
      ]
    end)
    |> Task.async_stream(
      fn item_link ->
        with {:ok, [item_title, feed_tags]} <- Cachex.get(:feed, item_link),
             :ok <- validate_all(item_link, item_title),
             corrected_link <- correct_all(item_link),
             {:ok, payload} <-
               FormData.create(
                 %{
                   url: corrected_link,
                   comment: feed_tags |> Enum.map_join(fn tag -> "[#{tag}]" end),
                   rks: System.get_env("HATENA_BOOKMARK_RKS"),
                   private: 0,
                   keep_original_url: 1,
                   with_status_op: 1,
                   from: "inplace",
                   post_twitter: 0,
                   post_evernote: 0
                 },
                 :url_encoded,
                 get: false
               ) do
          do_add_entries_to_hb(payload)
          Logger.info("add entry: #{item_link}")
        end

        archive_link(item_link)
      end,
      timeout: 15_000
    )
    |> Stream.run()
  end

  defp do_add_entries_to_hb(payload) do
    HatenaBookmark.post("/#{System.get_env("HATENA_BOOKMARK_USERNAME")}/add.edit.json", payload)
  end

  #
  # Helpers.Validate
  #
  defp validate_all(link, title) do
    with true <- validate_link(link), true <- validate_title(title), do: :ok
  end

  def validate_link(link) do
    case Cachex.get(:feed, "excluded_links") do
      {:ok, excluded_links} ->
        excluded_links
        |> Stream.map(fn excluded_link -> !Regex.match?(~r/#{excluded_link}/, link) end)
        |> Enum.to_list()
        |> Enum.all?()
        |> Kernel.&&(Regex.match?(~r/^http/, link))
        |> Kernel.&&(!(link in Cachex.get!(:feed, "archived_links")))

      _ ->
        false
    end
  end

  defp validate_title(title) do
    case Cachex.get(:feed, "excluded_titles") do
      {:ok, excluded_titles} ->
        excluded_titles
        |> Stream.map(fn excluded_title -> !Regex.match?(~r/#{excluded_title}/, title) end)
        |> Enum.to_list()
        |> Enum.all?()

      _ ->
        false
    end
  end

  #
  # Helpers.Correct
  #
  defp correct_all(link) do
    link |> correct_link() |> redirect_link()
  end

  defp correct_link(link) do
    corrected_link_rules = Cachex.get!(:feed, "corrected_links")

    corrected_link_rules
    |> Map.keys()
    |> Enum.reduce(link, fn key, corrected_link ->
      case key == "common" || Regex.match?(~r/#{key}/, corrected_link) do
        true ->
          corrected_link_rules[key]
          |> Enum.reduce(corrected_link, fn rule, acc ->
            acc |> String.replace(~r/[\?&]*?#{rule}=.*?$/, "")
          end)

        false ->
          corrected_link
      end
    end)
  end

  defp redirect_link(link) do
    redirected_link_rules = Cachex.get!(:feed, "redirected_links")

    redirected_link_rules
    |> Map.keys()
    |> Enum.reduce(link, fn key, redirected_link ->
      case key == "common" || Regex.match?(~r/#{key}/, redirected_link) do
        true ->
          redirected_link_rules[key]
          |> Enum.reduce(redirected_link, fn rule, acc ->
            with [{_, [{"href", href} | _], _} | _] <-
                   Code.eval_string(rule, fst: HTTPoison.get!(acc).body),
                 %URI{host: host, scheme: scheme} <- URI.parse(acc),
                 %URI{path: path} <- URI.parse(href) do
              "#{scheme}://#{host}#{path}"
            else
              _ -> acc
            end
          end)

        false ->
          redirected_link
      end
    end)
  end

  #
  # Helpers.Other
  #
  defp archive_link(link) do
    Cachex.transaction(:feed, ["archived_links"], fn cache ->
      archived_links = Cachex.get!(cache, "archived_links") ++ [link]
      Cachex.put(cache, "archived_links", archived_links)
      Cachex.del(cache, link)
      Cachex.dump(cache, [:code.priv_dir(:keshikimi), "tmp", "cache.dump"] |> Path.join())
    end)
  end

  defp schedule_poll(state) do
    State.poll(state, self())
  end
end
