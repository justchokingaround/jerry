### Linux

```sh
sudo curl -sL github.com/justchokingaround/jerry/raw/main/jerry.sh -o /usr/local/bin/jerry &&
sudo chmod +x /usr/local/bin/jerry
```

Example usage:

```sh
jerry -i blue lock -n 3
```

Just use

```sh
jerry -h
```

to see features lol

Example config (found at `$HOME/.config/jerry/jerry.conf`)

```sh
use_external_menu=1
discord_presence="true"
preferred_provider="crunchyroll"
opt_fzf_args="--cycle --reverse"
subs_language="english"

external_menu() {
 tofi --require-match false --fuzzy-match true --prompt-text "$1"
}
```
