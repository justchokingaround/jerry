![image](https://github.com/justchokingaround/jerry/assets/44473782/9f49b6e1-a07a-4610-b893-6a5ab816c40b)


# Jerry
Jerry is a command line tool for streaming anime from various providers. It can search for and play anime, continue watching from the currently watching list, and has various options for customization. The core idea of the script is that it allows users to watch anime in sync with their anilist account, automatically updating and tracking all progress (down to seconds of an episode watched).

---
## Table of Contents
- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
- [Configuration](#configuration)
- [Dependencies](#dependencies)
- [Credits](#credits)

## Features
- Search for and stream anime from various providers (currently supported: 9anime, zoro and yugen) (default: 9anime)
  (some providers, such as zoro and have support for external subtitles which allows more freedom)
- Sync watch progress on Anilist on episode completion, and locally (down to the second watched, just like YouTube and Netflix does it)
- Customize subtitle language, video quality, provider and many other things (using arguments or config file)
- Edit the configuration file using the command line
- Update the script from GitHub
- External menu support: ability to use rofi, so that opening a terminal window isn't even required to run the script !! (this can be used to setting the script to run on a keybind)
- Output episode links in JSON format


## Installation
### Linux
```sh
sudo curl -sL github.com/justchokingaround/jerry/raw/main/jerry.sh -o /usr/local/bin/jerry &&
sudo chmod +x /usr/local/bin/jerry
```
---
### Mac
```sh
curl -sL github.com/justchokingaround/jerry/raw/main/jerry.sh -o "$(brew --prefix)"/bin/jerry &&
chmod +x "$(brew --prefix)"/bin/jerry
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
    Specify the provider to watch from (default: zoro) (currently supported: zoro, gogoanime)
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

You can use the following command to edit your jerry configuration (in case a configuration file does not exist, a default one will be created, containing all the default values) :
```sh
jerry -e
```

## Dependencies
- grep
- sed
- awk
- curl
- fzf
- mpv (Video Player)
- rofi (optional)
- ueberuzgpp (image preview in fzf) (optional)
- jq (for displaying anime/manga info) (optional)

## Credits
- Anilist API: https://anilist.co/api/
