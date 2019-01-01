# Keshikimi2 --- Feed aggregator for adding Hatena Bookmark
Keshikimi2 is a Feed aggregator that provides a clear syntax for adding Hatena Bookmark entries configurations.

![diagram](https://raw.githubusercontent.com/nabinno/keshikimi2/master/priv/img/diagram.png)

## Installation

```sh
$ git clone https://github.com/nabinno/keshikimi2
```

## Getting started
You setup your own with `.bashrc` or `.zshrc`.

```sh
export HATENA_BOOKMARK_RKS=your_rks
export HATENA_BOOKMARK_COOKIE=your_cookie
export HATENA_BOOKMARK_USERNAME=your_name
```

Then, type the following commands.

```sh
cd keshikimi2
mix deps.get
MIX_ENV=prod mix
MIX_ENV=prod nohup elixir --name app@hostname --cookie "Keshikimi2Cookie" -S mix run --no-compile --no-halt &
disown %1
```

## YAML files
| item                        | description                                            |
|-----------------------------|--------------------------------------------------------|
| `feed.yaml`                 | Maps for aggregating feeds with both of links and tags |
| `feed_excluded_link.yaml`   | List for excluding feed links                          |
| `feed_excluded_title.yaml`  | List for excluding feed title                          |
| `feed_corrected_link.yaml`  | Maps for correcting feed links with trimming params    |
| `feed_redirected_link.yaml` | Maps for redirecting feed links with destinations      |

```yaml
# feed.yaml
nabinno/sports/feed_group_name:
  tags:
    - ski
  links:
    - http://rss.example.com/ski_feed.rss
    - http://rss.example.com/snowboard_feed.rss
    - http://ski-status.example.com/rss

# feed_excluded_link.yaml
- anti-ski.example.com
- awesome-snowboard.example.com

# feed_excluded_title.yaml
- queer
- two-planker
- beaver-tail

# feed_corrected_link.yaml
amazon.com:
  - ref
  - ie

# feed_redirected_link.yaml
ski-status.example.com:
  - Floki.find(fst, ".post__body a")
```

---

## EPILOGUE
>     A whale!
>     Down it goes, and more, and more
>     Up goes its tail!
>
>     -Buson Yosa
