# Jerry
Jerry is a command line tool for streaming anime from various providers. It can search for and play anime, continue watching from the currently watching list, and has various options for customization. The core idea of the script is that it allows users to watch anime in sync with their anilist account, automatically updating and tracking all progress (down to minutes of an episode watched).

---
## Table of Contents
- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
- [Configuration](#configuration)
- [Dependencies](#dependencies)
- [Credits](#credits)

## Features
- Search for and stream anime from various providers (currently supported: zoro, crunchyroll, gogoanime) (default: zoro)
  (some providers, such as zoro and crunchyroll, have support for external subtitles which allows more freedom)
- Continue watching anime from different lists from Anilist (current, completed, on hold, dropped, plan to watch)
- Customize subtitle language, video quality, and provider (using arguments or config file)
- Edit the configuration file using the command line
- Update the script from GitHub
- Incognito mode: watch anime without pushing progress to Anilist or saving progress locally (no Anilist account required for this)
- Discord Rich Presence: display currently watched anime in Discord (requires the installation of the helper python script: jerrydiscordpresence.py)
- External menu support: use an external menu (e.g. rofi, tofi, dmenu...) to select anime
- Output episode links in JSON format (no Anilist account required for this)


## Installation
### Linux
```sh
sudo curl -sL github.com/justchokingaround/jerry/raw/main/jerry.sh -o /usr/local/bin/jerry &&
sudo chmod +x /usr/local/bin/jerry
```
#### Optional: Discord Rich Presence (requires python3 and the python packages: pypresence and httpx)
```sh
sudo curl -sL github.com/justchokingaround/jerry/raw/main/jerrydiscordpresence.py -o /usr/local/bin/jerrydiscordpresence.py &&
sudo chmod +x /usr/local/bin/jerrydiscordpresence.py
```
---
### Mac
```sh
curl -sL github.com/justchokingaround/jerry/raw/main/jerry.sh -o "$(brew --prefix)"/bin/jerry &"
chmod +x "$(brew --prefix)"/bin/jerry
```
#### Optional: Discord Rich Presence (requires python3 and the python packages: pypresence and httpx)
```sh
curl -sL github.com/justchokingaround/jerry/raw/main/jerrydiscordpresence.py -o "$(brew --prefix)"/bin/jerrydiscordpresence.py
chmod +x "$(brew --prefix)"/bin/jerrydiscordpresence.py
```

## Usage
```
Usage: jerry [options] [query]
If a query is provided, it will be used to search for an anime, and will default to the 'Watch New' option.

Options:
  -c, --continue
    Continue watching from currently watching list (using the user's anilist account)
  -d, --discord
    Display currently watching anime in Discord Rich Presence (jerrydiscordpresence.py is required for this)
  -D, --dmenu
    Use an external menu (instead of the default fzf) to select an anime (default one is rofi, 
    but this can be specified in the config file, you can check the example config below)
  -e, --edit
    Edit config file using an editor defined with jerry_editor in the config ($EDITOR by default)
  -h, --help
    Show this help message and exit
  -i, --incognito
    Watch in incognito mode (nothing is pushed to anilist, and no progress is locally saved)
  -j, --json
    Outputs the json containing video links, subtitle links, referrers etc. to stdout
  -l, --language
    Specify the subtitle language
  -n, --number
    Specify the episode number for an anime
  -p, --provider
    Specify the provider to watch from (default: zoro) (currently supported: zoro, crunchyroll, gogoanime)
  -q, --quality
    Specify the video quality
  -u, --update
    Update the script
  -v, --version
    Show the version of the script

  Note: 
    All arguments can be specified in the config file as well.
    If an argument is specified in both the config file and the command line, the command line argument will be used.

  Some example usages:
   jerry -q 720p banana fish
   jerry -l spanish cyberpunk edgerunners -i -n 2
   jerry -l spanish cyberpunk edgerunners --number 2 --json
```
## Configuration
Jerry can be customized through the configuration file `$HOME/.config/jerry/jerry.conf` or by using command line arguments.

The configuration file has the following format, (example of the default configuration):
```sh
discord_presence=false
preferred_provider=zoro
subs_language=English
use_external_menu=0
video_quality=best
history_file=$HOME/.cache/anime_history
```

Here is an example of a more advanced configuration:
```sh
use_external_menu=1
discord_presence="true"
preferred_provider="crunchyroll"
opt_fzf_args="--cycle --reverse"
subs_language="russian"

external_menu() {
 tofi --require-match false --fuzzy-match true --prompt-text "$1"
}
```

## Dependencies
- grep
- sed
- awk
- curl
- fzf
- mpv (Video Player)
- external menus (rofi, tofi, dmenu, etc.) (optional)

## Credits
- Anilist API: https://anilist.co/api/
- Consumet API: https://docs.consumet.org/
