defmodule Keshikimi2.HatenaBookmark do
  @moduledoc false
  use HTTPoison.Base
  require IEx

  @expected_fields ~w(
    login id avatar_url gravatar_id url html_url followers_url
    following_url gists_url starred_url subscriptions_url
    organizations_url repos_url events_url received_events_url type
    site_admin name company blog location email hireable bio
    public_repos public_gists followers following created_at updated_at
  )

  def process_request_headers(headers) when is_map(headers), do: Enum.into(headers, [])

  def process_request_headers(headers) do
    [
      {"Pragma", "no-cache"},
      {"Origin", "http://b.hatena.ne.jp"},
      {"Accept-Encoding", "gzip, deflate"},
      {"Accept-Language", "en-US,en;q=0.9,ja;q=0.8"},
      {"User-Agent",
       "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/71.0.3578.98 Safari/537.36"},
      {"content-type", "application/x-www-form-urlencoded"},
      {"Accept", "*/*"},
      {"Cache-Control", "no-cache"},
      {"x-requested-with", "XMLHttpRequest"},
      {"Cookie", System.get_env("HATENA_BOOKMARK_COOKIE")},
      {"Connection", "keep-alive"},
      {"Referer", "http://b.hatena.ne.jp/"}
    ]
    |> Kernel.++(headers)
  end

  def process_request_options(options) do
    [hackney: [pool: :hatena_bookmark_pool]]
    |> Kernel.++(options)
  end

  def process_request_url(url), do: "http://b.hatena.ne.jp" <> url

  # def process_response_body(body) do
  #   body
  #   |> Poison.decode!()
  #   |> Map.take(@expected_fields)
  #   |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
  # end
  def process_response_body(body), do: body

  def process_response_chunk(chunk), do: chunk

  def process_response_headers(headers), do: headers

  def process_response_status_code(status_code), do: status_code
end
