#!/bin/sh

JERRY_VERSION=1.9.9

anilist_base="https://graphql.anilist.co"
config_file="$HOME/.config/jerry/jerry.conf"
jerry_editor=${VISUAL:-${EDITOR}}
tmp_dir="/tmp/jerry"
tmp_position="/tmp/jerry_position"

cleanup() {
    # tput clear
    rm -rf "$tmp_dir" 2>/dev/null
    if [ "$image_preview" = "1" ] && [ "$use_external_menu" = "0" ]; then
        killall ueberzugpp 2>/dev/null
        rm /tmp/ueberzugpp-* 2>/dev/null
    fi
}
trap cleanup EXIT INT TERM

applications="$HOME/.local/share/applications/jerry"
images_cache_dir="/tmp/jerry/jerry-images"

command -v bat >/dev/null 2>&1 && display="bat" || display="less"
case "$(uname -s)" in
    MINGW* | *Msys) separator=';' && path_thing='' && sed="sed" ;;
    *arwin) sed="gsed" ;;
    *) separator=':' && path_thing="\\" && sed="sed" ;;
esac
command -v notify-send >/dev/null 2>&1 && notify="true" || notify="false"
send_notification() {
    [ "$json_output" = 1 ] && return
    if [ "$use_external_menu" = "0" ] || [ "$use_external_menu" = "" ]; then
        [ -z "$4" ] && printf "\33[2K\r\033[1;34m%s\n\033[0m" "$1" && return
        [ -n "$4" ] && printf "\33[2K\r\033[1;34m%s - %s\n\033[0m" "$1" "$4" && return
    fi
    [ -z "$2" ] && timeout=3000 || timeout="$2"
    if [ "$notify" = "true" ]; then
        [ -z "$3" ] && notify-send "$1" "$4" -t "$timeout"
        [ -n "$3" ] && notify-send "$1" "$4" -t "$timeout" -i "$3" -h string:x-dunst-stack-tag:tes
    fi
}
dep_ch() {
    for dep; do
        command -v "$dep" >/dev/null || send_notification "Program \"$dep\" not found. Please install it."
    done
}
dep_ch "grep" "$sed" "curl" "fzf" "mpv" || true

if [ "$use_external_menu" = "1" ]; then
    dep_ch "rofi" || true
fi

usage() {
    printf "
  Usage: %s [options] [query]
  If a query is provided, it will be used to search for an anime, and will default to the 'Watch New Anime' option.

  Options:
    -c, --continue
      Continue watching from currently watching list (using the user's anilist account)
    --dub
      Allows user to watch anime in dub
    -e, --edit
      Edit config file using an editor defined with jerry_editor in the config (\$EDITOR by default). If a config file does not exist, creates one with a default configuration
		-d, --discord
      Display currently watching anime in Discord Rich Presence (jerrydiscordpresence.py is required for this, check the readme for instructions on how to install it)
    -h, --help
      Show this help message and exit
    -i, --image-preview
      Allows image preveiw in fzf and rofi (Note: for image preview using fzf, ueberzugpp must be installed)
    -j, --json
      Outputs the json containing video links, subtitle links, referrers etc. to stdout
    -l, --language
      Specify the subtitle language
    -n, --number
      Specify the episode number for an anime
    --rofi, --dmenu, --external-menu
      Use an external menu (instead of the default fzf) to select an anime (default one is rofi, but this can be specified in the config file)
    -q, --quality
      Specify the video quality
    -s, --syncplay
      Watch anime together with friends, using Syncplay (only tested using mpv)
    -u, --update
      Update the script
    -v, --version
      Show the script version
    -w, --website
      Choose which website to get video links from (default: 9anime) (currently supported: 9anime, aniwatch, yugen and hdrezka)

    Note: 
      All arguments can be specified in the config file as well.
      If an argument is specified in both the config file and the command line, the command line argument will be used.

    Some example usages:
     ${0##*/} -q 720 banana fish
     ${0##*/} --rofi -l russian cyberpunk edgerunners -i -n 2
     ${0##*/} -l spanish cyberpunk edgerunners --number 2 --json

" "${0##*/}"
}

configuration() {
    [ -n "$XDG_CONFIG_HOME" ] && config_dir="$XDG_CONFIG_HOME/jerry" || config_dir="$HOME/.config/jerry"
    [ -n "$XDG_DATA_HOME" ] && data_dir="$XDG_DATA_HOME/jerry" || data_dir="$HOME/.local/share/jerry"
    [ ! -d "$data_dir" ] && mkdir -p "$data_dir"
    #shellcheck disable=1090
    [ -f "$config_file" ] && . "${config_file}"
    [ -z "$player" ] && player="mpv"
    [ -z "$provider" ] && provider="9anime"
    [ -z "$video_provider" ] && video_provider="Vidstream"
    [ -z "$base_helper_url" ] && base_helper_url="https://9anime.eltik.net"
    [ -z "$download_dir" ] && download_dir="$PWD"
    [ -z "$manga_dir" ] && manga_dir="$data_dir/jerry-manga"
    [ -z "$manga_format" ] && manga_format="image"
    [ -z "$manga_opener" ] && manga_opener="nsxiv"
    [ -z "$history_file" ] && history_file="$data_dir/jerry_history.txt"
    [ -z "$subs_language" ] && subs_language="english"
    subs_language="$(printf "%s" "$subs_language" | cut -c2-)"
    [ -z "$use_external_menu" ] && use_external_menu=0
    [ -z "$image_preview" ] && image_preview=0
    [ -z "$preview_window_size" ] && preview_window_size=up:60%:wrap
    [ -z "$ueberzug_x" ] && ueberzug_x=10
    [ -z "$ueberzug_y" ] && ueberzug_y=3
    [ -z "$ueberzug_max_width" ] && ueberzug_max_width=$(($(tput lines) / 2))
    [ -z "$ueberzug_max_height" ] && ueberzug_max_height=$(($(tput lines) / 2))
    [ -z "$json_output" ] && json_output=0
    [ -z "$dub" ] && dub="false"
    [ -z "$score_on_completion" ] && score_on_completion="false"
    if [ "$no_anilist" = 0 ] || [ "$no_anilist" = "false" ]; then
        no_anilist=""
    fi
    [ -z "$discord_presence" ] && discord_presence="false"
    [ -z "$presence_script_path" ] && presence_script_path="jerrydiscordpresence.py"
}

check_credentials() {
    [ -f "$data_dir/anilist_token.txt" ] && access_token=$(cat "$data_dir/anilist_token.txt")
    [ -z "$access_token" ] && printf "Paste your access token from this page:
https://anilist.co/api/v2/oauth/authorize?client_id=9857&response_type=token : " && read -r access_token &&
        echo "$access_token" >"$data_dir/anilist_token.txt"
    [ -f "$data_dir/anilist_user_id.txt" ] && user_id=$(cat "$data_dir/anilist_user_id.txt")
    [ -z "$access_token" ] && exit 1
    [ -z "$user_id" ] &&
        user_id=$(curl -s -X POST "$anilist_base" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -H "Authorization: Bearer $access_token" \
            -d "{\"query\":\"query { Viewer { id } }\"}" | $sed -nE "s@.*\"id\":([0-9]*).*@\1@p") &&
        echo "$user_id" >"$data_dir/anilist_user_id.txt"
}

#### HELPER FUNCTIONS ####

edit_configuration() {
    if [ -f "$config_file" ]; then
        #shellcheck disable=1090
        . "${config_file}"
        [ -z "$jerry_editor" ] && jerry_editor="vim"
        "$jerry_editor" "$config_file"
    else
        printf "No configuration file found. Would you like to generate a default one? [Y/n] " && read -r generate
        case "$generate" in
            "No" | "no" | "n" | "N") exit 0 ;;
            *)
                [ ! -d "$config_dir" ] && mkdir -p "$config_dir"
                send_notification "Jerry" "" "" "Getting the latest example config from github..."
                curl -s "https://raw.githubusercontent.com/justchokingaround/jerry/main/examples/jerry.conf" -o "$config_dir/jerry.conf"
                send_notification "Jerry" "" "" "New config generated!"
                #shellcheck disable=1090
                . "${config_file}"
                [ -z "$jerry_editor" ] && jerry_editor="vim"
                "$jerry_editor" "$config_file"
                ;;
        esac
    fi
    exit 0

}

update_script() {
    which_jerry="$(command -v jerry)"
    [ -z "$which_jerry" ] && send_notification "Can't find jerry in PATH"
    [ -z "$which_jerry" ] && exit 1
    update=$(curl -s "https://raw.githubusercontent.com/justchokingaround/jerry/main/jerry.sh" || exit 1)
    update="$(printf '%s\n' "$update" | diff -u "$which_jerry" -)"
    if [ -z "$update" ]; then
        send_notification "Script is up to date :)"
    else
        if printf '%s\n' "$update" | patch "$which_jerry" -; then
            send_notification "Script has been updated!"
        else
            send_notification "Can't update for some reason!"
        fi
    fi
    exit 0
}

check_update() {
    update=$(curl -s "https://raw.githubusercontent.com/justchokingaround/jerry/main/jerry.sh")
    update="$(printf '%s\n' "$update" | diff -u "$(command -v jerry)" -)"
    if [ -n "$update" ]; then
        if [ "$use_external_menu" = 0 ] || [ "$use_external_menu" = "false" ]; then
            printf "%s" "$1" && read -r answer
        else
            answer=$(printf "Yes\nNo" | launcher "$1")
        fi
        case "$answer" in
            "Yes" | "yes" | "y" | "Y") update_script ;;
        esac
    fi

    if [ "$discord_presence" = "true" ]; then
        if [ ! -f "$(command -v "$presence_script_path")" ]; then
            if [ "$use_external_menu" = 0 ] || [ "$use_external_menu" = "false" ]; then
                printf "No presence script found in path, would you like to download the default one?" && read -r answer
            else
                answer=$(printf "Yes\nNo" | launcher "No presence script found in path, would you like to download the default one?")
            fi
            case "$answer" in
                "Yes" | "yes" | "y" | "Y")
                    case "$(uname -a)" in
                        *Darwin*)
                            curl -sL github.com/justchokingaround/jerry/raw/main/jerrydiscordpresence.py -o "$(brew --prefix)"/bin/jerrydiscordpresence.py
                            chmod +x "$(brew --prefix)"/bin/jerrydiscordpresence.py
                            ;;
                        *MINGW*)
                            curl -sL github.com/justchokingaround/jerry/raw/main/jerrydiscordpresence.py -o /usr/bin/jerrydiscordpresence.py
                            chmod +x /usr/bin/jerrydiscordpresence.py
                            ;;
                        *)
                            sudo curl -sL github.com/justchokingaround/jerry/raw/main/jerrydiscordpresence.py -o /usr/local/bin/jerrydiscordpresence.py
                            sudo chmod +x /usr/local/bin/jerrydiscordpresence.py
                            ;;
                    esac
                    ;;
                *) exit 0 ;;
            esac
        else
            update=$(curl -s "https://raw.githubusercontent.com/justchokingaround/jerry/main/jerrydiscordpresence.py" || return)
            update="$(printf '%s\n' "$update" | diff -u "$(command -v "$presence_script_path")" -)"
            if [ -n "$update" ]; then
                if [ "$use_external_menu" = 0 ] || [ "$use_external_menu" = "false" ]; then
                    printf "%s" "$2" && read -r answer
                else
                    answer=$(printf "Yes\nNo" | launcher "$2")
                fi
                case "$answer" in
                    "Yes" | "yes" | "y" | "Y")
                        case "$(uname -a)" in
                            *Darwin* | *MINGW*) sucess=$(printf '%s\n' "$update" | patch "$(command -v "$presence_script_path")" -) ;;
                            *) sucess=$(printf '%s\n' "$update" | sudo patch "$(command -v "$presence_script_path")" -) ;;
                        esac
                        if $sucess; then
                            send_notification "Script has been updated!"
                        else
                            send_notification "Can't update for some reason!"
                        fi
                        ;;
                    *) exit 0 ;;
                esac
            fi
        fi
    fi

}

get_input() {
    if [ "$use_external_menu" = "0" ]; then
        printf "%s" "$1" && read -r query
    else
        if [ -n "$rofi_prompt_config" ]; then
            query=$(printf "" | rofi -theme "$rofi_prompt_config" -sort -dmenu -i -width 1500 -p "" -mesg "$1")
        else
            query=$(printf "" | launcher "$1")
        fi
    fi
}

convert_hex() {
  text="$(cat -)"
  len=${#text}

  for i in $(seq 0 $((len - 1))); do
	  char=$(printf "%s" "$text" | cut -c "$((i + 1))")
	  hex_val=$(printf "%02x" "'$char")
	  printf "%s" "$hex_val"
  done
  printf "\n"
}

generate_desktop() {
    cat <<EOF
[Desktop Entry]
Name=$1
Exec=echo %k %c
Icon=$2
Type=Application
Categories=jerry;
EOF
}

launcher() {
    case "$use_external_menu" in
        1)
            [ -z "$2" ] && rofi -sort -matching fuzzy -dmenu -i -width 1500 -p "" -mesg "$1" -matching fuzzy -sorting-method fzf
            [ -n "$2" ] && rofi -sort -matching fuzzy -dmenu -i -width 1500 -p "" -mesg "$1" -display-columns "$2" -matching fuzzy -sorting-method fzf
            ;;
        *)
            [ -z "$2" ] && fzf --cycle --reverse --prompt "$1"
            [ -n "$2" ] && fzf --cycle --reverse --prompt "$1" --with-nth "$2" -d "\t"
            ;;
    esac
}

nth() {
    stdin=$(cat -)
    [ -z "$stdin" ] && return 1
    prompt="$1"
    [ $# -ne 1 ] && shift
    line=$(printf "%s" "$stdin" | $sed -nE "s@^([0-9]*)[[:space:]]*[0-9]*[[:space:]]*([0-9/]*)[[:space:]]*[0-9:]*[[:space:]]*(.*)@\1\t\3 - Episode \2@p" | tr '\t' ' ' | launcher "$prompt" | cut -d\  -f1)
    [ -n "$line" ] && printf "%s" "$stdin" | $sed -nE "s@^$line\t(.*)@\1@p" || exit 1
}

nine_anime_helper() {
    curl -s "$base_helper_url/$1?query=$2&apikey=jerry" | $sed -nE "s@.*\"$3\":\"([^\"]*)\".*@\1@p"
}

nine_anime_extractor() {
    futoken=$(curl -s "vidstream.pro/futoken")
    curl -s "$base_helper_url/$1?query=$2&apikey=jerry" -d "query=${2}&futoken=${futoken}" | $sed -nE "s@.*\"$3\":\"([^\"]*)\".*@\1@p"
}

download_images() {
    [ ! -d "$manga_dir/$title/chapter_$((progress + 1))" ] && mkdir -p "$manga_dir/$title/chapter_$((progress + 1))"
    send_notification "Downloading images" "" "$images_cache_dir/  $title $progress|$chapters_total chapters [$score] $media_id.jpg" "$title - Chapter: $((progress + 1)) $chapter_title"
    printf "%s\n" "$1" | while read -r link; do
        number=$(printf "%03d" "$(printf "%s" "$link" | $sed -nE "s@[a-zA-Z]?([0-9]*)-.*@\1@p")")
        image_name=$(printf "%s.%s" "$number" "$(printf "%s" "$link" | $sed -nE "s@.*\.(.*)@\1@p")")
        download_link=$(printf "%s/data/%s/%s" "$mangadex_data_base_url" "$mangadex_hash" "$link")
        curl -s "$download_link" -o "$manga_dir/$title/chapter_$((progress + 1))/$image_name" &
    done
    wait && sleep 2
}

convert_to_pdf() {
    send_notification "Converting $title - Chapter: $((progress + 1)) $chapter_title to PDF" "2000" "$images_cache_dir/  $title $media_id.jpg"
    convert "$manga_dir/$title/chapter_$((progress + 1))"/* "$manga_dir/$title/chapter_$((progress + 1))/$title - Chapter $((progress + 1)).pdf" && wait
}

hdrezka_data_and_translation_id() {
    data_id=$(printf "%s" "$episode_id" | sed -nE "s@[a-z]*/([0-9]*)-.*@\1@p")
    case "$media_type" in
        films)
            default_translator_id=$(curl -s "https://hdrezka.website/${media_type}/$(printf "%s" "$episode_id" | tr '=' '/').html" -A "uwu" --compressed |
                sed -nE "s@.*initCDNMoviesEvents\(${data_id}\, ([0-9]*)\,.*@\1@p")
            ;;
        *)
            default_translator_id=$(curl -s "https://hdrezka.website/${media_type}/$(printf "%s" "$episode_id" | tr '=' '/').html" -A "uwu" --compressed |
                sed -nE "s@.*initCDNSeriesEvents\(${data_id}\, ([0-9]*)\,.*@\1@p")
            ;;
    esac
    translations=$(curl -s "https://hdrezka.website/${media_type}/$(printf "%s" "$episode_id" | tr '=' '/').html" -A "uwu" --compressed |
        sed 's/b-translator__item/\n/g' | sed -nE "s@.*data-translator_id=\"([0-9]*)\"[^>]*>(.*)</li.*@\2\t\1@p" |
        sed 's/<img title="\([^\"]*\)" .*>\(.*\)/(\1)\2/;s/^\(.*\)<\/li><\/ul> <\/div>.*\t\([0-9]*\)/\1\t\2/')
    if [ -z "$translations" ]; then
        translator_id=$default_translator_id
    else
        translator_id=$(printf "%s" "$translations" | fzf --cycle --reverse --with-nth 1 -d "\t" --header "Choose a translation" | cut -f2)
    fi
}

download_thumbnails() {
    printf "%s\n" "$1" | while read -r cover_url media_id title; do
        curl -s -o "$images_cache_dir/  $title $media_id.jpg" "$cover_url" &
        if [ "$use_external_menu" = "1" ]; then
            entry=/tmp/jerry/applications/"$media_id.desktop"
            generate_desktop "$title" "$images_cache_dir/  $title $media_id.jpg" >"$entry" &
        fi
    done
    sleep "$2"
}

image_preview_fzf() {
    UB_PID_FILE="/tmp/.$(uuidgen)"
    if [ -z "$ueberzug_output" ]; then
        ueberzugpp layer --no-stdin --silent --use-escape-codes --pid-file "$UB_PID_FILE"
    else
        ueberzugpp layer -o "$ueberzug_output" --no-stdin --silent --use-escape-codes --pid-file "$UB_PID_FILE"
    fi
    UB_PID="$(cat "$UB_PID_FILE")"
    JERRY_UEBERZUG_SOCKET=/tmp/ueberzugpp-"$UB_PID".socket
    choice=$(find "$images_cache_dir" -type f -exec basename {} \; | fzf -i -q "$1" --cycle --preview-window="$preview_window_size" --preview="ueberzugpp cmd -s $JERRY_UEBERZUG_SOCKET -i fzfpreview -a add -x $ueberzug_x -y $ueberzug_y --max-width $ueberzug_max_width --max-height $ueberzug_max_height -f $images_cache_dir/{}" --reverse --with-nth 1..-2 -d " ")
    ueberzugpp cmd -s "$JERRY_UEBERZUG_SOCKET" -a exit
}

select_desktop_entry() {
    if [ "$use_external_menu" = "1" ]; then
        [ -n "$image_config_path" ] && choice=$(rofi -show drun -drun-categories jerry -filter "$1" -show-icons -theme "$image_config_path" -i -matching fuzzy -sorting-method fzf |
            $sed -nE "s@.*/([0-9]*)\.desktop@\1@p") 2>/dev/null ||
            choice=$(rofi -show drun -drun-categories jerry -filter "$1" -show-icons -i -matching fuzzy -sorting-method fzf | $sed -nE "s@.*/([0-9]*)\.desktop@\1@p") 2>/dev/null
    else
        image_preview_fzf "$1"
    fi
}

#### ANILIST ANIME FUNCTIONS ####
get_anime_from_list() {
    anime_list=$(curl -s -X POST "$anilist_base" \
        -H 'Content-Type: application/json' \
        -H "Authorization: Bearer $access_token" \
        -d "{\"query\":\"query(\$userId:Int,\$userName:String,\$type:MediaType){MediaListCollection(userId:\$userId,userName:\$userName,type:\$type){lists{name isCustomList isCompletedList:isSplitCompletedList entries{...mediaListEntry}}user{id name avatar{large}mediaListOptions{scoreFormat rowOrder animeList{sectionOrder customLists splitCompletedSectionByFormat theme}mangaList{sectionOrder customLists splitCompletedSectionByFormat theme}}}}}fragment mediaListEntry on MediaList{id mediaId status score progress progressVolumes repeat priority private hiddenFromStatusLists customLists advancedScores notes updatedAt startedAt{year month day}completedAt{year month day}media{id title{userPreferred romaji english native}coverImage{extraLarge large}type format status(version:2)episodes volumes chapters averageScore popularity isAdult countryOfOrigin genres bannerImage nextAiringEpisode{airingAt timeUntilAiring episode} startDate{year month day}}}\",\"variables\":{\"userId\":$user_id,\"type\":\"ANIME\"}}" | $sed "s@},{@\n@g" | $sed -nE "s@.*\"mediaId\":([0-9]*),\"status\":\"$1\",\"score\":(.*),\"progress\":([0-9]*),.*\"userPreferred\":\"([^\"]*)\".*\"coverImage\":\{\"extraLarge\":\"([^\"]*)\".*\"episode([\"]*)s*[\"]*:([0-9]*).*@\5\t\1\t\4 \3|\7 episodes \6 \[\2\]@p" | $sed 's/\\\//\//g;s/\"/(releasing)/')
    if [ "$use_external_menu" = 1 ]; then
        case "$image_preview" in
            "true" | 1)
                download_thumbnails "$anime_list" "2"
                select_desktop_entry ""
                [ -z "$choice" ] && exit 1
                media_id=$(printf "%s" "$choice" | cut -d\  -f1)
                title=$(printf "%s" "$choice" | $sed -nE "s@$media_id (.*) [0-9?|]* episodes.*@\1@p")
                [ -z "$progress" ] && progress=$(printf "%s" "$choice" | $sed -nE "s@.* ([0-9]*)\|[0-9?]* episodes.*@\1@p")
                episodes_total=$(printf "%s" "$choice" | $sed -nE "s@.*[\| ]([0-9?]*) episodes.*@\1@p")
                [ -z "$episodes_total" ] && episodes_total=9999
                score=$(printf "%s" "$choice" | $sed -nE "s@.* episodes \[([0-9]*)\].*@\1@p")
                ;;
            *)
                tmp_anime_list=$(printf "%s" "$anime_list" | $sed -nE "s@(.*\.[jpneg]*)[[:space:]]*([0-9]*)[[:space:]]*(.*)@\3\t\2\t\1@p")
                choice=$(printf "%s" "$tmp_anime_list" | launcher "Choose anime: " "1")
                [ -z "$choice" ] && exit 1
                media_id=$(printf "%s" "$choice" | cut -f2)
                title=$(printf "%s" "$choice" | $sed -nE "s@(.*) [0-9?|]* episodes.*@\1@p")
                [ -z "$progress" ] && progress=$(printf "%s" "$choice" | $sed -nE "s@.* ([0-9]*)\|[0-9?]* episodes.*@\1@p")
                episodes_total=$(printf "%s" "$choice" | $sed -nE "s@.*[\| ]([0-9?]*) episodes.*@\1@p")
                [ -z "$episodes_total" ] && episodes_total=9999
                score=$(printf "%s" "$choice" | $sed -nE "s@.* episodes \[([0-9]*)\].*@\1@p")
                ;;
        esac
    else
        case "$image_preview" in
            "true" | 1)
                download_thumbnails "$anime_list" "2"
                select_desktop_entry ""
                [ -z "$choice" ] && exit 0
                media_id=$(printf "%s" "$choice" | $sed -nE "s@.* ([0-9]*)\.jpg@\1@p")
                title=$(printf "%s" "$choice" | $sed -nE "s@[[:space:]]*(.*) [0-9?|]* episodes.*@\1@p")
                [ -z "$progress" ] && progress=$(printf "%s" "$choice" | $sed -nE "s@.* ([0-9]*)\|[0-9?]* episodes.*@\1@p")
                episodes_total=$(printf "%s" "$choice" | $sed -nE "s@.*[\| ]([0-9?]*) episodes.*@\1@p")
                [ -z "$episodes_total" ] && episodes_total=9999
                score=$(printf "%s" "$choice" | $sed -nE "s@.* episodes \[([0-9]*)\].*@\1@p")
                ;;
            *)
                choice=$(printf "%s" "$anime_list" | launcher "Choose anime: " "3")
                [ -z "$choice" ] && exit 1
                media_id=$(printf "%s" "$choice" | cut -f2)
                title=$(printf "%s" "$choice" | $sed -nE "s@.*$media_id\t(.*) [0-9?|]* episodes.*@\1@p")
                [ -z "$progress" ] && progress=$(printf "%s" "$choice" | $sed -nE "s@.* ([0-9]*)\|[0-9?]* episodes.*@\1@p")
                episodes_total=$(printf "%s" "$choice" | $sed -nE "s@.*[\| ]([0-9?]*) episodes.*@\1@p")
                [ -z "$episodes_total" ] && episodes_total=9999
                score=$(printf "%s" "$choice" | $sed -nE "s@.* episodes \[([0-9]*)\].*@\1@p")
                ;;
        esac
    fi
}

search_anime_anilist() {
    anime_list=$(curl -s -X POST "$anilist_base" \
        -H 'Content-Type: application/json' \
        -d "{\"query\":\"query(\$page:Int = 1 \$id:Int \$type:MediaType \$isAdult:Boolean = false \$search:String \$format:[MediaFormat]\$status:MediaStatus \$countryOfOrigin:CountryCode \$source:MediaSource \$season:MediaSeason \$seasonYear:Int \$year:String \$onList:Boolean \$yearLesser:FuzzyDateInt \$yearGreater:FuzzyDateInt \$episodeLesser:Int \$episodeGreater:Int \$durationLesser:Int \$durationGreater:Int \$chapterLesser:Int \$chapterGreater:Int \$volumeLesser:Int \$volumeGreater:Int \$licensedBy:[Int]\$isLicensed:Boolean \$genres:[String]\$excludedGenres:[String]\$tags:[String]\$excludedTags:[String]\$minimumTagRank:Int \$sort:[MediaSort]=[POPULARITY_DESC,SCORE_DESC]){Page(page:\$page,perPage:20){pageInfo{total perPage currentPage lastPage hasNextPage}media(id:\$id type:\$type season:\$season format_in:\$format status:\$status countryOfOrigin:\$countryOfOrigin source:\$source search:\$search onList:\$onList seasonYear:\$seasonYear startDate_like:\$year startDate_lesser:\$yearLesser startDate_greater:\$yearGreater episodes_lesser:\$episodeLesser episodes_greater:\$episodeGreater duration_lesser:\$durationLesser duration_greater:\$durationGreater chapters_lesser:\$chapterLesser chapters_greater:\$chapterGreater volumes_lesser:\$volumeLesser volumes_greater:\$volumeGreater licensedById_in:\$licensedBy isLicensed:\$isLicensed genre_in:\$genres genre_not_in:\$excludedGenres tag_in:\$tags tag_not_in:\$excludedTags minimumTagRank:\$minimumTagRank sort:\$sort isAdult:\$isAdult){id title{userPreferred}coverImage{extraLarge large color}startDate{year month day}endDate{year month day}bannerImage season seasonYear description type format status(version:2)episodes duration chapters volumes genres isAdult averageScore popularity nextAiringEpisode{airingAt timeUntilAiring episode}mediaListEntry{id status}studios(isMain:true){edges{isMain node{id name}}}}}}\",\"variables\":{\"page\":1,\"type\":\"ANIME\",\"sort\":\"SEARCH_MATCH\",\"search\":\"$1\"}}" | $sed "s@edges@\n@g" | $sed -nE "s@.*\"id\":([0-9]*),.*\"userPreferred\":\"(.*)\"\},\"coverImage\":.*\"extraLarge\":\"([^\"]*)\".*\"episode([\"]*)s*[\"]*:([0-9]*).*@\3\t\1\t\2 \5 episodes \4@p" | $sed 's/\\\//\//g;s/\"/(releasing)/')

    if [ "$use_external_menu" = 1 ]; then
        case "$image_preview" in
            "true" | 1)
                download_thumbnails "$anime_list" "2"
                select_desktop_entry ""
                [ -z "$choice" ] && exit 1
                media_id=$(printf "%s" "$choice" | cut -d\  -f1)
                title=$(printf "%s" "$choice" | $sed -nE "s@$media_id (.*) [0-9?]* episodes.*@\1@p")
                episodes_total=$(printf "%s" "$choice" | $sed -nE "s@.*[\| ]([0-9?]*) episodes.*@\1@p")
                [ -z "$episodes_total" ] && episodes_total=9999
                ;;
            *)
                tmp_anime_list=$(printf "%s" "$anime_list" | $sed -nE "s@(.*\.[jpneg]*)[[:space:]]*([0-9]*)[[:space:]]*(.*)@\3\t\2\t\1@p")
                choice=$(printf "%s" "$tmp_anime_list" | launcher "Choose anime: " "1")
                media_id=$(printf "%s" "$choice" | cut -f2)
                title=$(printf "%s" "$choice" | $sed -nE "s@(.*) [0-9?|]* episodes.*@\1@p")
                [ -z "$progress" ] && progress=$(printf "%s" "$choice" | $sed -nE "s@.* ([0-9]*)\|[0-9?]* episodes.*@\1@p")
                episodes_total=$(printf "%s" "$choice" | $sed -nE "s@.*[\| ]([0-9?]*) episodes.*@\1@p")
                [ -z "$episodes_total" ] && episodes_total=9999
                ;;
        esac
    else
        case "$image_preview" in
            "true" | 1)
                download_thumbnails "$anime_list" "2"
                select_desktop_entry ""
                [ -z "$choice" ] && exit 0
                media_id=$(printf "%s" "$choice" | $sed -nE "s@.* ([0-9]*)\.jpg@\1@p")
                title=$(printf "%s" "$choice" | $sed -nE "s@[[:space:]]*(.*) [0-9?|]* episodes.*@\1@p")
                episodes_total=$(printf "%s" "$choice" | $sed -nE "s@.*[\| ]([0-9?]*) episodes.*@\1@p")
                [ -z "$episodes_total" ] && episodes_total=9999
                ;;
            *)
                choice=$(printf "%s" "$anime_list" | launcher "Choose anime: " "3")
                media_id=$(printf "%s" "$choice" | cut -f2)
                title=$(printf "%s" "$choice" | $sed -nE "s@.*$media_id\t(.*) [0-9?|]* episodes.*@\1@p")
                [ -z "$progress" ] && progress=$(printf "%s" "$choice" | $sed -nE "s@.* ([0-9]*)\|[0-9?]* episodes.*@\1@p")
                episodes_total=$(printf "%s" "$choice" | $sed -nE "s@.*[\| ]([0-9?]*) episodes.*@\1@p")
                ;;
        esac
    fi
    [ -z "$title" ] && exit 0

    if [ -n "$no_anilist" ]; then
        episodes_total=$(curl -s -X POST "https://graphql.anilist.co" -A "uwu" -H "Accept: application/json" -H "Content-Type: application/json" --data-raw "{\"query\":\"query media(\$id:Int,\$type:MediaType,\$isAdult:Boolean){Media(id:\$id,type:\$type,isAdult:\$isAdult){episodes nextAiringEpisode{episode}}}\",\"variables\":{\"id\":\"${media_id}\",\"type\":\"ANIME\",\"isAdult\":false}}" | $sed -nE "s@.*episode([s]{0,1})\":([0-9]+).*@\1\2@p")
        numeric_part=$(printf "%s" "$episodes_total" | sed -nE "s@s([0-9]*)@\1@p")
        [ -n "$numeric_part" ] && episodes_total=$numeric_part || episodes_total=$((episodes_total - 1))

        [ -n "$progress" ] && return
        if [ "$episodes_total" = 1 ]; then
            progress=0
        else
            [ -z "$episodes_total" ] && episodes_total=9999
            if [ "$use_external_menu" = 1 ]; then
                if [ -n "$rofi_prompt_config" ]; then
                    progress=$(printf "" | rofi -theme "$rofi_prompt_config" -sort -dmenu -i -width 1500 -p "" -mesg "Please enter the episode number (1-${episodes_total}): ")
                else
                    progress=$(printf "" | launcher "Please enter the episode number (1-${episodes_total}): ")
                fi
            else
                printf "%s" "Please enter the episode number (1-${episodes_total}): " && read -r progress
            fi
            if [ -z "$progress" ]; then
                send_notification "Error" "1000" "$images_cache_dir/  $title $media_id.jpg" "No episode number provided"
                exit 1
            fi
            progress=$((progress - 1))
        fi
    fi
}

update_progress() {
    curl -s -X POST "$anilist_base" \
        -H 'Content-Type: application/json' \
        -H "Authorization: Bearer $access_token" \
        -d "{\"query\":\"mutation(\$id:Int \$mediaId:Int \$status:MediaListStatus \$score:Float \$progress:Int \$progressVolumes:Int \$repeat:Int \$private:Boolean \$notes:String \$customLists:[String]\$hiddenFromStatusLists:Boolean \$advancedScores:[Float]\$startedAt:FuzzyDateInput \$completedAt:FuzzyDateInput){SaveMediaListEntry(id:\$id mediaId:\$mediaId status:\$status score:\$score progress:\$progress progressVolumes:\$progressVolumes repeat:\$repeat private:\$private notes:\$notes customLists:\$customLists hiddenFromStatusLists:\$hiddenFromStatusLists advancedScores:\$advancedScores startedAt:\$startedAt completedAt:\$completedAt){id mediaId status score advancedScores progress progressVolumes repeat priority private hiddenFromStatusLists customLists notes updatedAt startedAt{year month day}completedAt{year month day}user{id name}media{id title{userPreferred}coverImage{large}type format status episodes volumes chapters averageScore popularity isAdult startDate{year}}}}\",\"variables\":{\"status\":\"$3\",\"progress\":$(($1 + 1)),\"mediaId\":$2}}"
    [ "$3" = "COMPLETED" ] && send_notification "Completed $title" "5000"
    [ "$3" = "COMPLETED" ] && $sed -i "/$media_id/d" "$history_file"
}

update_episode_from_list() {
    status_choice=$(printf "CURRENT\nCOMPLETED\nPAUSED\nDROPPED\nPLANNING" | launcher "Filter by status: ")
    get_anime_from_list "$status_choice"

    if [ -z "$title" ] || [ -z "$progress" ]; then
        exit 0
    fi

    send_notification "Current progress: $progress/$episodes_total episodes watched" "5000"

    if [ "$use_external_menu" = "0" ]; then
        printf "Enter a new episode number: "
        read -r new_episode_number
    else
        new_episode_number=$(printf "" | launcher "Enter a new episode number: ")
    fi
    [ "$new_episode_number" -gt "$episodes_total" ] && new_episode_number=$episodes_total
    [ "$new_episode_number" -lt 0 ] && new_episode_number=0

    if [ -z "$new_episode_number" ]; then
        send_notification "No episode number given"
        exit 1
    fi

    send_notification "Updating progress for $title..."
    [ "$new_episode_number" -eq "$episodes_total" ] && status="COMPLETED" || status="CURRENT"
    response=$(update_progress "$((new_episode_number - 1))" "$media_id" "$status")
    send_notification "New progress: $new_episode_number/$episodes_total episodes watched"
    [ "$new_episode_number" -eq "$episodes_total" ] && send_notification "Completed $title"
}

#### ANILIST MANGA FUNCTIONS ####
get_manga_from_list() {
    manga_list=$(curl -s -X POST "$anilist_base" \
        -H 'Content-Type: application/json' \
        -H "Authorization: Bearer $access_token" \
        -d "{\"query\":\"query(\$userId:Int,\$userName:String,\$type:MediaType){MediaListCollection(userId:\$userId,userName:\$userName,type:\$type){lists{name isCustomList isCompletedList:isSplitCompletedList entries{...mediaListEntry}}user{id name avatar{large}mediaListOptions{scoreFormat rowOrder animeList{sectionOrder customLists splitCompletedSectionByFormat theme}mangaList{sectionOrder customLists splitCompletedSectionByFormat theme}}}}}fragment mediaListEntry on MediaList{id mediaId status score progress progressVolumes repeat priority private hiddenFromStatusLists customLists advancedScores notes updatedAt startedAt{year month day}completedAt{year month day}media{id title{userPreferred romaji english native}coverImage{extraLarge large}type format status(version:2)episodes volumes chapters averageScore popularity isAdult countryOfOrigin genres bannerImage startDate{year month day}}}\",\"variables\":{\"userId\":$user_id,\"type\":\"MANGA\"}}" |
        tr "\[|\]" "\n" | $sed -nE "s@.*\"mediaId\":([0-9]*),\"status\":\"$1\",\"score\":(.*),\"progress\":([0-9]*),.*\"userPreferred\":\"([^\"]*)\".*\"coverImage\":\{\"extraLarge\":\"([^\"]*)\".*\"chapters\":([0-9]*).*@\5\t\1\t\4 \3|\6 chapters \[\2\]@p" | $sed 's/\\\//\//g')

    if [ "$use_external_menu" = 1 ]; then
        case "$image_preview" in
            "true" | 1)
                download_thumbnails "$manga_list" "2"
                select_desktop_entry ""
                [ -z "$choice" ] && exit 1
                media_id=$(printf "%s" "$choice" | cut -d\  -f1)
                title=$(printf "%s" "$choice" | $sed -nE "s@$media_id (.*) [0-9?|]* chapters.*@\1@p")
                [ -z "$progress" ] && progress=$(printf "%s" "$choice" | $sed -nE "s@.* ([0-9]*)\|[0-9?]* chapters.*@\1@p")
                chapters_total=$(printf "%s" "$choice" | $sed -nE "s@.*\|([0-9?]*) chapters.*@\1@p")
                score=$(printf "%s" "$choice" | $sed -nE "s@.*\|[0-9?]* chapters[[:space:]]*\[([0-9]*)\][[:space:]]*.*@\1@p")
                ;;
            *)
                tmp_manga_list=$(printf "%s" "$manga_list" | $sed -nE "s@(.*\.[jpneg]*)[[:space:]]*([0-9]*)[[:space:]]*(.*)@\3\t\2\t\1@p")
                choice=$(printf "%s" "$tmp_manga_list" | launcher "Choose manga: " "1")
                [ -z "$choice" ] && exit 1
                media_id=$(printf "%s" "$choice" | cut -f2)
                title=$(printf "%s" "$choice" | $sed -nE "s@(.*) [0-9?|]* chapters.*@\1@p")
                [ -z "$progress" ] && progress=$(printf "%s" "$choice" | $sed -nE "s@.* ([0-9]*)\|[0-9?]* chapters.*@\1@p")
                chapters_total=$(printf "%s" "$choice" | $sed -nE "s@.*\|([0-9?]*) chapters.*@\1@p")
                score=$(printf "%s" "$choice" | $sed -nE "s@.*\|[0-9?]* chapters[[:space:]]*\[([0-9]*)\][[:space:]]*.*@\1@p")
                ;;
        esac
    else
        case "$image_preview" in
            "true" | 1)
                download_thumbnails "$manga_list" "2"
                select_desktop_entry ""
                [ -z "$choice" ] && exit 0
                media_id=$(printf "%s" "$choice" | $sed -nE "s@.* ([0-9]*)\.jpg@\1@p")
                title=$(printf "%s" "$choice" | $sed -nE "s@[[:space:]]*(.*) [0-9?|]* chapters.*@\1@p")
                [ -z "$progress" ] && progress=$(printf "%s" "$choice" | $sed -nE "s@.* ([0-9]*)\|[0-9?]* chapters.*@\1@p")
                chapters_total=$(printf "%s" "$choice" | $sed -nE "s@.*\|([0-9?]*) chapters.*@\1@p")
                score=$(printf "%s" "$choice" | $sed -nE "s@.*\|[0-9?]* chapters[[:space:]]*\[([0-9]*)\][[:space:]]*.*@\1@p")
                ;;
            *)
                choice=$(printf "%s" "$manga_list" | launcher "Choose manga: " "3")
                [ -z "$choice" ] && exit 1
                media_id=$(printf "%s" "$choice" | cut -f2)
                title=$(printf "%s" "$choice" | $sed -nE "s@.*$media_id\t(.*) [0-9?|]* chapters.*@\1@p")
                [ -z "$progress" ] && progress=$(printf "%s" "$choice" | $sed -nE "s@.* ([0-9]*)\|[0-9?]* chapters.*@\1@p")
                chapters_total=$(printf "%s" "$choice" | $sed -nE "s@.*\|([0-9?]*) chapters.*@\1@p")
                score=$(printf "%s" "$choice" | $sed -nE "s@.*\|[0-9?]* chapters[[:space:]]*\[([0-9]*)\][[:space:]]*.*@\1@p")
                ;;
        esac
    fi
}

search_manga_anilist() {
    manga_list=$(curl -s -X POST "$anilist_base" \
        -H 'Content-Type: application/json' \
        -d "{\"query\":\"query(\$page:Int = 1 \$id:Int \$type:MediaType \$isAdult:Boolean = false \$search:String \$format:[MediaFormat]\$status:MediaStatus \$countryOfOrigin:CountryCode \$source:MediaSource \$season:MediaSeason \$seasonYear:Int \$year:String \$onList:Boolean \$yearLesser:FuzzyDateInt \$yearGreater:FuzzyDateInt \$episodeLesser:Int \$episodeGreater:Int \$durationLesser:Int \$durationGreater:Int \$chapterLesser:Int \$chapterGreater:Int \$volumeLesser:Int \$volumeGreater:Int \$licensedBy:[Int]\$isLicensed:Boolean \$genres:[String]\$excludedGenres:[String]\$tags:[String]\$excludedTags:[String]\$minimumTagRank:Int \$sort:[MediaSort]=[POPULARITY_DESC,SCORE_DESC]){Page(page:\$page,perPage:20){pageInfo{total perPage currentPage lastPage hasNextPage}media(id:\$id type:\$type season:\$season format_in:\$format status:\$status countryOfOrigin:\$countryOfOrigin source:\$source search:\$search onList:\$onList seasonYear:\$seasonYear startDate_like:\$year startDate_lesser:\$yearLesser startDate_greater:\$yearGreater episodes_lesser:\$episodeLesser episodes_greater:\$episodeGreater duration_lesser:\$durationLesser duration_greater:\$durationGreater chapters_lesser:\$chapterLesser chapters_greater:\$chapterGreater volumes_lesser:\$volumeLesser volumes_greater:\$volumeGreater licensedById_in:\$licensedBy isLicensed:\$isLicensed genre_in:\$genres genre_not_in:\$excludedGenres tag_in:\$tags tag_not_in:\$excludedTags minimumTagRank:\$minimumTagRank sort:\$sort isAdult:\$isAdult){id title{userPreferred}coverImage{extraLarge large color}startDate{year month day}endDate{year month day}bannerImage season seasonYear description type format status(version:2)episodes duration chapters volumes genres isAdult averageScore popularity nextAiringEpisode{airingAt timeUntilAiring episode}mediaListEntry{id status}studios(isMain:true){edges{isMain node{id name}}}}}}\",\"variables\":{\"page\":1,\"type\":\"MANGA\",\"sort\":\"SEARCH_MATCH\",\"search\":\"$1\"}}" |
        tr "\[\]" "\n" | $sed -nE "s@.*\"id\":([0-9]*),.*\"userPreferred\":\"(.*)\"\},\"coverImage\":.*\"extraLarge\":\"([^\"]*)\".*\"chapters\":([^,]*),.*@\3\t\1\t\2 \4 chapters@p" | $sed 's/\\\//\//g;s/null/?/')

    if [ "$use_external_menu" = 1 ]; then
        case "$image_preview" in
            "true" | 1)
                download_thumbnails "$manga_list" "2"
                select_desktop_entry ""
                [ -z "$choice" ] && exit 1
                media_id=$(printf "%s" "$choice" | cut -d\  -f1)
                title=$(printf "%s" "$choice" | $sed -nE "s@$media_id (.*) [0-9?]* chapters.*@\1@p")
                chapters_total=$(printf "%s" "$choice" | $sed -nE "s@.* ([0-9?]*) chapters.*@\1@p")
                ;;
            *)
                tmp_manga_list=$(printf "%s" "$manga_list" | $sed -nE "s@(.*\.[jpneg]*)[[:space:]]*([0-9]*)[[:space:]]*(.*)@\3\t\2\t\1@p")
                choice=$(printf "%s" "$tmp_manga_list" | launcher "Choose manga: " "1")
                media_id=$(printf "%s" "$choice" | cut -f2)
                title=$(printf "%s" "$choice" | $sed -nE "s@(.*) [0-9?|]* chapters.*@\1@p")
                [ -z "$progress" ] && progress=$(printf "%s" "$choice" | $sed -nE "s@.* ([0-9]*)\|[0-9?]* chapters.*@\1@p")
                chapters_total=$(printf "%s" "$choice" | $sed -nE "s@.*\|([0-9?]*) chapters.*@\1@p")
                ;;
        esac
    else
        case "$image_preview" in
            "true" | 1)
                download_thumbnails "$manga_list" "2"
                select_desktop_entry ""
                [ -z "$choice" ] && exit 0
                media_id=$(printf "%s" "$choice" | $sed -nE "s@.* ([0-9]*)\.jpg@\1@p")
                title=$(printf "%s" "$choice" | $sed -nE "s@[[:space:]]*(.*) [0-9?|]* chapters.*@\1@p")
                chapters_total=$(printf "%s" "$choice" | $sed -nE "s@.* ([0-9?]*) chapters.*@\1@p")
                ;;
            *)
                choice=$(printf "%s" "$manga_list" | launcher "Choose manga: " "3")
                media_id=$(printf "%s" "$choice" | cut -f2)
                title=$(printf "%s" "$choice" | $sed -nE "s@.*$media_id\t(.*) [0-9?|]* chapters.*@\1@p")
                [ -z "$progress" ] && progress=$(printf "%s" "$choice" | $sed -nE "s@.* ([0-9]*)\|[0-9?]* chapters.*@\1@p")
                chapters_total=$(printf "%s" "$choice" | $sed -nE "s@.*\|([0-9?]*) chapters.*@\1@p")
                ;;
        esac
    fi

    [ -z "$title" ] && exit 0
}

update_chapter_from_list() {
    status_choice=$(printf "CURRENT\nCOMPLETED\nPAUSED\nDROPPED\nPLANNING" | launcher "Filter by status: ")
    get_manga_from_list "$status_choice"

    if [ -z "$title" ] || [ -z "$progress" ]; then
        exit 0
    fi

    send_notification "Current progress: $progress/$chapters_total chapters read" "5000"

    if [ "$use_external_menu" = "0" ]; then
        printf "Enter a new chapters read number: "
        read -r new_chapter_number
    else
        new_chapter_number=$(printf "" | launcher "Enter a new chapters read number: ")
    fi
    [ "$new_chapter_number" -gt "$chapters_total" ] && new_chapter_number=$chapters_total
    [ "$new_chapter_number" -lt 0 ] && new_chapter_number=0

    if [ -z "$chapters_total" ]; then
        send_notification "No chapter number given"
        exit 1
    fi

    send_notification "Updating progress for $title..."
    [ "$new_chapter_number" -eq "$chapters_total" ] && status="COMPLETED" || status="CURRENT"
    response=$(update_progress "$((new_chapter_number - 1))" "$media_id" "$status")
    send_notification "New progress: $new_chapter_number/$chapters_total chapters read"
    [ "$new_chapter_number" -eq "$chapters_total" ] && send_notification "Completed $title"
}

#### ANILIST META FUICTIONS ####

update_status() {
    status_choice=$(printf "CURRENT\nCOMPLETED\nPAUSED\nDROPPED\nPLANNING" | launcher "Filter by status: ")
    if [ "$1" = "ANIME" ]; then
        get_anime_from_list "$status_choice"
    else
        get_manga_from_list "$status_choice"
    fi
    [ -z "$title" ] && exit 0
    send_notification "Choose a new status for $title" "5000"
    new_status=$(printf "CURRENT\nCOMPLETED\nPAUSED\nDROPPED\nPLANNING" | launcher "Choose a new status: ")
    [ -z "$new_status" ] && exit 0
    send_notification "Updating status for $title..."
    response=$(update_progress "$((progress - 1))" "$media_id" "$new_status")
    if printf "%s" "$response" | grep -q "errors"; then
        send_notification "Failed to update status for $title"
    else
        send_notification "New status: $new_status"
    fi
}

update_score() {
    [ "$percentage_progress" -lt 85 ] && return
    if [ "$2" = "immediate" ]; then
        [ "$1" = "ANIME" ] && total="$episodes_total"
        [ "$1" = "MANGA" ] && total="$chapters_total"
        [ $((progress + 1)) != "$total" ] && return
    else
        status_choice=$(printf "CURRENT\nCOMPLETED\nPAUSED\nDROPPED\nPLANNING" | launcher "Filter by status: ")
        case "$1" in
            "ANIME") get_anime_from_list "$status_choice" ;;
            "MANGA") get_manga_from_list "$status_choice" ;;
        esac
    fi
    send_notification "Enter new score for: \"$title\"" "5000"
    send_notification "Current score: $score" "5000"
    if [ "$use_external_menu" = "0" ]; then
        printf "Enter new score: "
        read -r new_score
    else
        new_score=$(printf "" | launcher "Enter new score: ")
    fi
    [ -z "$new_score" ] && send_notification "No score given" && exit 1
    send_notification "Updating score for $title..."
    response=$(curl -s -X POST "$anilist_base" \
        -H 'Content-Type: application/json' \
        -H "Authorization: Bearer $access_token" \
        -d "{\"query\":\"mutation(\$id:Int \$mediaId:Int \$status:MediaListStatus \$score:Float \$progress:Int \$progressVolumes:Int \$repeat:Int \$private:Boolean \$notes:String \$customLists:[String]\$hiddenFromStatusLists:Boolean \$advancedScores:[Float]\$startedAt:FuzzyDateInput \$completedAt:FuzzyDateInput){SaveMediaListEntry(id:\$id mediaId:\$mediaId status:\$status score:\$score progress:\$progress progressVolumes:\$progressVolumes repeat:\$repeat private:\$private notes:\$notes customLists:\$customLists hiddenFromStatusLists:\$hiddenFromStatusLists advancedScores:\$advancedScores startedAt:\$startedAt completedAt:\$completedAt){id mediaId status score advancedScores progress progressVolumes repeat priority private hiddenFromStatusLists customLists notes updatedAt startedAt{year month day}completedAt{year month day}user{id name}media{id title{userPreferred}coverImage{large}type format status episodes volumes chapters averageScore popularity isAdult startDate{year}}}}\",\"variables\":{\"score\":$new_score,\"mediaId\":$media_id}}")
    if printf "%s" "$response" | grep -q "errors"; then
        send_notification "Failed to update score for $title"
    else
        send_notification "New score: $new_score"
    fi
}

get_anilist_info() {
    case "$1" in
        "ANIME")
            get_input "Search anime: "
            [ -z "$query" ] && exit 1
            search_anime_anilist "$query"
            ;;
        "MANGA")
            get_input "Search manga: "
            [ -z "$query" ] && exit 1
            search_manga_anilist "$query"
            ;;
    esac
    [ -z "$media_id" ] && exit 1
    info="$(curl -s -X POST "$anilist_base" \
        -H 'Content-Type: application/json' \
        -d "{\"query\":\"query media(\$id:Int,\$type:MediaType,\$isAdult:Boolean){Media(id:\$id,type:\$type,isAdult:\$isAdult){id title{userPreferred romaji english native}coverImage{extraLarge large}bannerImage startDate{year month day}endDate{year month day}description season seasonYear type format status(version:2)episodes duration chapters volumes genres synonyms source(version:3)isAdult isLocked meanScore averageScore popularity favourites isFavouriteBlocked hashtag countryOfOrigin isLicensed isFavourite isRecommendationBlocked isFavouriteBlocked isReviewBlocked nextAiringEpisode{airingAt timeUntilAiring episode}relations{edges{id relationType(version:2)node{id title{userPreferred}format type status(version:2)bannerImage coverImage{large}}}}characterPreview:characters(perPage:6,sort:[ROLE,RELEVANCE,ID]){edges{id role name voiceActors(language:JAPANESE,sort:[RELEVANCE,ID]){id name{userPreferred}language:languageV2 image{large}}node{id name{userPreferred}image{large}}}}staffPreview:staff(perPage:8,sort:[RELEVANCE,ID]){edges{id role node{id name{userPreferred}language:languageV2 image{large}}}}studios{edges{isMain node{id name}}}reviewPreview:reviews(perPage:2,sort:[RATING_DESC,ID]){pageInfo{total}nodes{id summary rating ratingAmount user{id name avatar{large}}}}recommendations(perPage:7,sort:[RATING_DESC,ID]){pageInfo{total}nodes{id rating userRating mediaRecommendation{id title{userPreferred}format type status(version:2)bannerImage coverImage{large}}user{id name avatar{large}}}}externalLinks{id site url type language color icon notes isDisabled}streamingEpisodes{site title thumbnail url}trailer{id site}rankings{id rank type format year season allTime context}tags{id name description rank isMediaSpoiler isGeneralSpoiler userId}mediaListEntry{id status score}stats{statusDistribution{status amount}scoreDistribution{score amount}}}}\",\"variables\":{\"id\":$media_id,\"type\":\"$1\"}}" |
        jq -r '.data.Media.description' | $sed "s/<br>/\n/g")"
    if [ "$use_external_menu" = 1 ]; then
        if ! command -v "zenity" >/dev/null; then
            send_notification "For this feature to work in the rofi mode, you must have zenity installed."
            exit 1
        fi
        zenity --info --text="$info"
    else
        echo "$info" | $display
    fi
}

#### ANIME SCRAPING FUNCTIONS ####
get_episode_info() {
    case "$provider" in
        aniwatch)
            aniwatch_id=$(curl -s "https://raw.githubusercontent.com/bal-mackup/mal-backup/master/anilist/anime/${media_id}.json" |
                tr -d '\n ' | tr '}' '\n' | $sed -nE "s@.*\"Zoro\".*\"url\":\".*-([0-9]*)\".*@\1@p")
            episode_info=$(curl -s "https://aniwatch.to/ajax/v2/episode/list/${aniwatch_id}" | $sed -e "s/</\n/g" -e "s/\\\\//g" | $sed -nE "s_.*a title=\"([^\"]*)\".*data-id=\"([0-9]*)\".*_\2\t\1_p" | $sed -n "$((progress + 1))p")
            ;;
        yugen)
            href=$(curl -s "https://raw.githubusercontent.com/bal-mackup/mal-backup/master/anilist/anime/${media_id}.json" |
                tr -d '\n' | tr '}' '\n' | $sed -nE 's@.*"YugenAnime".*"url": *"([^"]*)".*@\1@p')
            tmp_episode_info=$(curl -s "${href}watch/" | $sed -nE "s@.*href=\"/([^\"]*)\" title=\"([^\"]*)\".*@\1\t\2@p" | $sed -n "$((progress + 1))p")
            tmp_href=$(printf "%s" "$tmp_episode_info" | cut -f1)
            ep_title=$(printf "%s" "$tmp_episode_info" | cut -f2)
            if [ "$dub" = true ]; then
                tmp_href=$(printf "%s" "$tmp_href" | $sed -E 's|(/[^/]+)/([0-9]+)/$|\1-dub/\2/|')
            fi
            yugen_id=$(curl -s "https://yugenanime.tv/$tmp_href" | $sed -nE "s@.*id=\"main-embed\" src=\".*/e/([^/]*)/\".*@\1@p")
            episode_info=$(printf "%s\t%s" "$yugen_id" "$ep_title")
            ;;
        hdrezka)
            query=$(curl -s "https://raw.githubusercontent.com/bal-mackup/mal-backup/master/anilist/anime/${media_id}.json" |
                sed -nE "s@.*\"title\":.\"([^\"]*)\".*@\1@p" | head -1 | tr ' ' '+')
            request=$(curl -s "https://hdrezka.website/search/?do=search&subaction=search&q=${query}" -A "uwu" --compressed)
            response=$(printf "%s" "$request" | sed "s/<img/\n/g" | sed -nE "s@.*src=\"([^\"]*)\".*<a href=\"https://hdrezka\.website/(.*)/(.*)/(.*)\.html\">([^<]*)</a> <div>([0-9]*).*@\3/\4\t\5 [\6]\t\2@p")
            [ -z "$response" ] && exit 1
            if [ "$(printf "%s\n" "$response" | wc -l)" -eq 1 ]; then
                send_notification "Jerry" "" "" "Since there is only one result, it was automatically selected"
                episode_info=$response
            else
                episode_info=$(printf "%s" "$response" | launcher "Choose anime: " 2)
            fi
            ;;
        9anime)
            nineanime_href=$(curl -s "https://raw.githubusercontent.com/bal-mackup/mal-backup/master/anilist/anime/${media_id}.json" |
                tr -d '\n ' | tr '}' '\n' | $sed -nE "s@.*\"9anime\".*\"url\":\"([^\"]*)\".*@\1@p" | head -1 | $sed "s/9anime\.../aniwave.to/")
            data_id=$(curl -s "$nineanime_href" | $sed -nE "s@.*data-id=\"([0-9]*)\" data-url.*@\1@p")

            ep_list_vrf=$(nine_anime_helper "vrf" "$data_id" "url" | convert_hex | tr -d '\n' | $sed 's/\(..\)/%\1/g')
            episode_info=$(curl -sL "https://aniwave.to/ajax/episode/list/$data_id?vrf=$ep_list_vrf" | $sed 's/<li/\n/g;s/\\//g' |
                $sed -nE "s@.*data-ids=\"([^\"]*)\".*data-jp=\"[^\"]*\">([^<]*)<.*@\1\t\2@p" | $sed -n "$((progress + 1))p")
            [ -z "$episode_info" ] && episode_info=$(curl -sL "https://aniwave.to/ajax/episode/list/$data_id?vrf=$ep_list_vrf" | $sed 's/<li/\n/g;s/\\//g' |
                $sed -nE "s@.*data-ids=\"([^\"]*)\".*@\1@p" | $sed -n "$((progress + 1))p")
            ;;
    esac
}

extract_from_json() {
    case "$provider" in
        aniwatch)
            json_key="file"
            encrypted=$(printf "%s" "$json_data" | tr "{}" "\n" | $sed -nE "s_.*\"${json_key}\":\"([^\"]*)\".*_\1_p" | grep "\.m3u8")
            if [ -n "$encrypted" ]; then
                video_link=$(printf "%s" "$json_data" | tr "{|}" "\n" | $sed -nE "s_.*\"${json_key}\":\"([^\"]*)\".*_\1_p" | head -1)
            else
                json_key="sources"
                encrypted=$(printf "%s" "$json_data" | tr "{}" "\n" | $sed -nE "s_.*\"${json_key}\":\"([^\"]*)\".*_\1_p")
                embed_type="6"
                enikey=$(curl -s "https://github.com/enimax-anime/key/blob/e${embed_type}/key.txt" | $sed -nE "s@.*rawLines\":\[\"([^\"]*)\".*@\1@p" |
                    $sed 's/\[\([0-9]*\),\([0-9]*\)\]/\1-\2/g;s/\[//g;s/\]//g;s/,/ /g')

                encrypted_video_link=$(printf "%s" "$json_data" | tr "{|}" "\n" | $sed -nE "s_.*\"sources\":\"([^\"]*)\".*_\1_p" | head -1)

                final_key=""
                tmp_encrypted_video_link="$encrypted_video_link"
                for key in $enikey; do
                    start="${key%-*}"
                    start=$((start + 1))
                    end="${key#*-}"
                    key=$(printf "%s" "$encrypted_video_link" | cut -c"$start-$end")
                    final_key="$final_key$key"
                    tmp_encrypted_video_link=$(printf "%s" "$tmp_encrypted_video_link" | $sed "s/$key//g")
                done

                # ty @CoolnsX for helping me with figuring out how to implement aes in openssl
                video_link=$(printf "%s" "$tmp_encrypted_video_link" | base64 -d |
                    openssl enc -aes-256-cbc -d -md md5 -k "$final_key" 2>/dev/null | $sed -nE "s_.*\"file\":\"([^\"]*)\".*_\1_p")
                json_data=$(printf "%s" "$json_data" | $sed -e "s|${encrypted_video_link}|${video_link}|")
            fi
            [ -n "$quality" ] && video_link=$(printf "%s" "$video_link" | $sed -e "s|/playlist.m3u8|/$quality/index.m3u8|")

            if [ "$json_output" = "1" ]; then
                printf "%s\n" "$json_data"
                exit 0
            fi
            subs_links=$(printf "%s" "$json_data" | tr "{}" "\n" | $sed -nE "s@\"file\":\"([^\"]*)\",\"label\":\"(.$subs_language)[,\"\ ].*@\1@p")
            num_subs=$(printf "%s" "$subs_links" | wc -l)
            if [ "$num_subs" -gt 0 ]; then
                subs_links=$(printf "%s" "$subs_links" | $sed -e "s/:/\\$path_thing:/g" -e "H;1h;\$!d;x;y/\n/$separator/" -e "s/$separator\$//")
                subs_arg="--sub-files=$subs_links"
            else
                subs_arg="--sub-file=$subs_links"
            fi
            [ -z "$subs_links" ] && send_notification "No subtitles found"
            ;;
        yugen)
            if [ "$json_output" = "1" ]; then
                printf "%s\n" "$json_data"
                exit 0
            fi
            hls_link_1=$(printf "%s" "$json_data" | tr '{}' '\n' | $sed -nE "s@.*\"hls\": \[\"([^\"]*)\".*@\1@p")
            # hls_link_2=$(printf "%s" "$json_data" | tr '{}' '\n' | $sed -nE "s@.*hls.*, \"([^\"]*)\".\]*@\1@p")
            # gogo_link=$(printf "%s" "$json_data" | tr '{}' '\n' | $sed -nE "s@.*\"src\": \"([^\"]*)\", \"type\": \"embed.*@\1@p")
            if [ -n "$quality" ]; then
                video_link=$(printf "%s" "$hls_link_1" | $sed -e "s/\.m3u8$/\.$quality.m3u8/")
            else
                video_link=$hls_link_1
            fi
            ;;
        hdrezka)
            encrypted_video_link=$(printf "%s" "$json_data" | sed -nE "s@.*\"url\":\"([^\"]*)\".*@\1@p" | sed "s/\\\//g" | cut -c'3-' | sed 's|//_//||g')
            # the part below is pain
            subs_links=$(printf "%s" "$json_data" | sed -nE "s@.*\"subtitle\":\"([^\"]*)\".*@\1@p" |
                sed -e 's/\[[^]]*\]//g' -e 's/,/\n/g' -e 's/\\//g' -e "s/:/\\$path_thing:/g" -e "H;1h;\$!d;x;y/\n/$separator/" -e "s/$separator\$//")
            # TODO: fix subs
            subs_arg="--sub-files=$subs_links"

            # ty @CoolnsX for helping me out with the decryption
            table='ISE=,IUA=,IV4=,ISM=,ISQ=,QCE=,QEA=,QF4=,QCM=,QCQ=,XiE=,XkA=,Xl4=,XiM=,XiQ=,IyE=,I0A=,I14=,IyM=,IyQ=,JCE=,JEA=,JF4=,JCM=,JCQ=,ISEh,ISFA,ISFe,ISEj,ISEk,IUAh,IUBA,IUBe,IUAj,IUAk,IV4h,IV5A,IV5e,IV4j,IV4k,ISMh,ISNA,ISNe,ISMj,ISMk,ISQh,ISRA,ISRe,ISQj,ISQk,QCEh,QCFA,QCFe,QCEj,QCEk,QEAh,QEBA,QEBe,QEAj,QEAk,QF4h,QF5A,QF5e,QF4j,QF4k,QCMh,QCNA,QCNe,QCMj,QCMk,QCQh,QCRA,QCRe,QCQj,QCQk,XiEh,XiFA,XiFe,XiEj,XiEk,XkAh,XkBA,XkBe,XkAj,XkAk,Xl4h,Xl5A,Xl5e,Xl4j,Xl4k,XiMh,XiNA,XiNe,XiMj,XiMk,XiQh,XiRA,XiRe,XiQj,XiQk,IyEh,IyFA,IyFe,IyEj,IyEk,I0Ah,I0BA,I0Be,I0Aj,I0Ak,I14h,I15A,I15e,I14j,I14k,IyMh,IyNA,IyNe,IyMj,IyMk,IyQh,IyRA,IyRe,IyQj,IyQk,JCEh,JCFA,JCFe,JCEj,JCEk,JEAh,JEBA,JEBe,JEAj,JEAk,JF4h,JF5A,JF5e,JF4j,JF4k,JCMh,JCNA,JCNe,JCMj,JCMk,JCQh,JCRA,JCRe,JCQj,JCQk'

            for i in $(printf "%s" "$table" | tr ',' '\n'); do
                encrypted_video_link=$(printf "%s" "$encrypted_video_link" | sed "s/$i//g")
            done

            video_links=$(printf "%s" "$encrypted_video_link" | sed 's/_//g' | base64 -d | tr ',' '\n' | sed -nE "s@\[([^\]*)\](.*)@\"\1\":\"\2\",@p")
            video_links_json=$(printf "%s" "$video_links" | tr -d '\n' | sed "s/,$//g")
            json_data=$(printf "%s" "$json_data" | sed -E "s@\"url\":\"[^\"]*\"@\"url\":\{$video_links_json\}@")
            if [ "$json_output" = "1" ]; then
                printf "%s\n" "$json_data"
                exit 0
            fi
            if [ -n "$quality" ]; then
                video_link=$(printf "%s" "$video_links" | sed -nE "s@\"${quality}.*\":\".* or ([^\"]*)\".*@\1@p" | tail -1)
            else
                # auto selects best quality
                video_link=$(printf "%s" "$video_links" | sed -nE "s@\".*\":\".* or ([^\"]*)\".*@\1@p" | tail -1)
            fi
            [ -z "$video_link" ] && exit 1
            ;;
        9anime)
            if [ "$json_output" = "1" ]; then
                printf "%s\n" "$json_data"
                exit 0
            fi
            case "$video_provider" in
                "Vidstream")
                    video_link="$(printf "%s" "$json_data" | $sed -nE "s@.*file\":\"([^\"]*\.mp4)\".*@\1@p")"
                    case "$quality" in
                        1080) video_link="$(printf "%s" "$video_link" | $sed "s@/br/list\.m3u8@/br/H4/v\.m3u8@")" ;;
                        720) video_link="$(printf "%s" "$video_link" | $sed "s@/br/list\.m3u8@/br/H3/v\.m3u8@")" ;;
                        480) video_link="$(printf "%s" "$video_link" | $sed "s@/br/list\.m3u8@/br/H2/v\.m3u8@")" ;;
                        360) video_link="$(printf "%s" "$video_link" | $sed "s@/br/list\.m3u8@/br/H1/v\.m3u8@")" ;;
                    esac
                    ;;
                "MyCloud")
                    video_link="$(printf "%s" "$json_data" | $sed -nE "s@.*file\":\"([^\"]*\.m3u8)\".*@\1@p")"
                    ;;
            esac
            ;;
    esac
    [ "$((progress + 1))" -eq "$episodes_total" ] && status="COMPLETED" || status="CURRENT"
}

get_json() {
    case "$provider" in
        aniwatch)

            if [ "$dub" = true ]; then
                source_id=$(curl -s "https://aniwatch.to/ajax/v2/episode/servers?episodeId=$episode_id" |
                    $sed "s/</\n/g;s/\\\//g" | $sed -nE "s@.*data-type=\"dub\" data-id=\"([0-9]*)\".*@\1@p" | head -1)
            else
                source_id=$(curl -s "https://aniwatch.to/ajax/v2/episode/servers?episodeId=$episode_id" |
                    $sed "s/</\n/g;s/\\\//g" | $sed -nE "s@.*data-type=\"sub\" data-id=\"([0-9]*)\".*@\1@p" | head -1)
            fi
            [ -z "$source_id" ] && source_id=$(curl -s "https://aniwatch.to/ajax/v2/episode/servers?episodeId=$episode_id" |
                $sed "s/</\n/g;s/\\\//g" | $sed -nE "s@.*data-type=\"raw\" data-id=\"([0-9]*)\".*@\1@p" | head -1)
            embed_link=$(curl -s "https://aniwatch.to/ajax/v2/episode/sources?id=$source_id" | $sed -nE "s_.*\"link\":\"([^\"]*)\".*_\1_p")

            # get the juicy links
            parse_embed=$(printf "%s" "$embed_link" | $sed -nE "s_(.*)/embed-(2|4|6)/e-([0-9])/(.*)\?k=1\$_\1\t\2\t\3\t\4_p")
            provider_link=$(printf "%s" "$parse_embed" | cut -f1)
            embed_type=$(printf "%s" "$parse_embed" | cut -f2)
            e_number=$(printf "%s" "$parse_embed" | cut -f3)
            source_id=$(printf "%s" "$parse_embed" | cut -f4)

            json_data=$(curl -s "${provider_link}/embed-${embed_type}/ajax/e-${e_number}/getSources?id=${source_id}" -H "X-Requested-With: XMLHttpRequest")
            ;;
        yugen)
            json_data=$(curl -s 'https://yugenanime.tv/api/embed/' -X POST -H 'X-Requested-With: XMLHttpRequest' --data-raw "id=$episode_id&ac=0")
            ;;
        hdrezka)
            hdrezka_data_and_translation_id
            tmp_season_id=$(curl -s "https://hdrezka.website/${media_type}/${episode_id}.html" -A "uwu" --compressed | sed "s/<li/\n/g" |
                sed -nE "s@.*data-tab_id=\"([0-9]*)\">([^<]*)</li>.*@\2\t\1@p")
            if [ -n "$tmp_season_id" ]; then
                tmp_season_id=$(printf "%s" "$tmp_season_id" | fzf -1 --cycle --reverse --with-nth 1 -d '\t' --header "Choose a season: ")
                [ -z "$tmp_season_id" ] && exit 1
                season_title=$(printf "%s" "$tmp_season_id" | cut -f1)
                season_id=$(printf "%s" "$tmp_season_id" | cut -f2)
            fi
            episode_id=$((progress + 1))
            json_data=$(curl -s -X POST "https://hdrezka.website/ajax/get_cdn_series/" -A "uwu" --data-raw "id=${data_id}&translator_id=${translator_id}&season=${season_id}&episode=${episode_id}&action=get_stream" --compressed)
            ;;
        9anime)
            server_list_vrf=$(nine_anime_helper "vrf" "$episode_id" "url" | convert_hex | tr -d '\n' | sed 's/\(..\)/%\1/g')

            if [ "$dub" = true ]; then
                provider_id=$(curl -sL "https://aniwave.to/ajax/server/list/$episode_id?vrf=$server_list_vrf" | $sed "s/</\n/g;s/\\\//g" | $sed -nE "s@.*data-link-id=\"([^\"]*)\">$video_provider.*@\1@p" | tail -1)
                provider_vrf=$(nine_anime_helper "vrf" "$provider_id" "url" | convert_hex | tr -d '\n' | sed 's/\(..\)/%\1/g')
            else
                provider_id=$(curl -sL "https://aniwave.to/ajax/server/list/$episode_id?vrf=$server_list_vrf" | $sed "s/</\n/g;s/\\\//g" | $sed -nE "s@.*data-link-id=\"([^\"]*)\">$video_provider.*@\1@p" | head -1)
                provider_vrf=$(nine_anime_helper "vrf" "$provider_id" "url" | convert_hex | tr -d '\n' | sed 's/\(..\)/%\1/g')
            fi

            encrypted_provider_url=$(curl -sL "https://aniwave.to/ajax/server/$provider_id?vrf=$provider_vrf" | $sed "s/\\\//g" | $sed -nE "s@.*\{\"url\":\"([^\"]*)\".*@\1@p")
            provider_embed=$(nine_anime_helper "decrypt" "$encrypted_provider_url" "url")
            provider_query=$(printf "%s" "$provider_embed" | $sed -nE "s@.*/e/(.*)@\1@p")

            case "$video_provider" in
                "Vidstream")
                    raw_url=$(nine_anime_extractor "rawvizcloud" "$provider_query" "rawURL")
                    json_data=$(curl -s "$raw_url" -e "$provider_embed" | $sed "s/\\\//g")
                    ;;
                "MyCloud")
                    raw_url=$(nine_anime_extractor "rawmcloud" "$provider_query" "rawURL")
                    json_data=$(curl -s "$raw_url" -e "$provider_embed" | $sed "s/\\\//g")
                    ;;
                    # "Mp4upload")
                    #     video_link=$(curl -s "$provider_embed" |$sed -nE "s@.*src: \"([^\"]*)\".*@\1@p")
                    #     ;;
            esac
            ;;
    esac

    [ -n "$json_data" ] && extract_from_json
}

#### MANGA SCRAPING FUNCTIONS ####
get_chapter_info() {
    manga_provider="mangadex"
    case "$manga_provider" in
        mangadex)
            mangadex_id=$(curl -s "https://raw.githubusercontent.com/bal-mackup/mal-backup/master/anilist/manga/${media_id}.json" | tr -d "\n" | $sed -nE "s@.*\"Mangadex\":[[:space:]{]*\"([^\"]*)\".*@\1@p")
            chapter_info=$(curl -s "https://api.mangadex.org/manga/$mangadex_id/feed?limit=164&translatedLanguage[]=en" | $sed "s/}]},/\n/g" |
                $sed -nE "s@.*\"id\":\"([^\"]*)\".*\"chapter\":\"$((progress + 1))\",\"title\":\"([^\"]*)\".*@\1\t\2@p" | head -1)
            ;;
    esac
}

get_manga_json() {
    case "$manga_provider" in
        mangadex)
            json_data=$(curl -s "https://api.mangadex.org/at-home/server/$chapter_id" | $sed "s/\\\//g")
            if [ "$json_output" = "1" ]; then
                printf "%s\n" "$json_data"
                exit 0
            fi
            mangadex_data_base_url=$(printf "%s" "$json_data" | $sed -nE "s@.*\"baseUrl\":\"([^\"]*)\".*@\1@p")
            mangadex_hash=$(printf "%s" "$json_data" | $sed -nE "s@.*\"hash\":\"([^\"]*)\".*@\1@p")
            image_links=$(printf "%s" "$json_data" | $sed -nE "s@.*data\":\[(.*)\],.*@\1@p" | $sed "s/,/\n/g;s/\"//g")
            if [ -z "$mangadex_data_base_url" ] || [ -z "$mangadex_hash" ] || [ -z "$image_links" ]; then
                send_notification "Jerry" "3000" "" "Error: could not get manga"
                exit 1
            fi
            download_images "$image_links"
            ;;
    esac
}

#### MEDIA FUNCTIONS ####

add_to_history() {
    if [ "$percentage_progress" -gt 85 ]; then
        if [ -z "$no_anilist" ]; then
            response=$(update_progress "$progress" "$media_id" "$status")
            if printf "%s" "$response" | grep -q "errors"; then
                send_notification "Error" "" "" "Could not update progress"
            else
                send_notification "Updated progress to $((progress + 1))/$episodes_total episodes watched" ""
                [ -n "$history" ] && $sed -i "/^$media_id/d" "$history_file"
            fi
        else
            if [ -n "$history" ]; then
                if [ $((progress + 1)) -eq "$episodes_total" ]; then
                    $sed -i "/^$media_id/d" "$history_file"
                    send_notification "Completed" "" "" "$title"
                else
                    $sed -i "s/^${media_id}\t[0-9/]*\t[0-9:]*/${media_id}\t$((progress + 2))\/${episodes_total}\t00:00:00/" "$history_file"
                    send_notification "Updated progress to $((progress + 1)) episodes watched"
                fi
            else
                printf "%s\t%s/%s\t00:00:00\t%s\n" "$media_id" "$((progress + 2))" "$episodes_total" "$title" >>"$history_file"
                send_notification "Updated progress to $((progress + 1)) episodes watched"
            fi
        fi
    else
        send_notification "Current progress" "" "" "$progress/$episodes_total episodes watched"
        [ -z "$no_anilist" ] && send_notification "Your progress has not been updated"
        if ! grep -q "^$media_id" "$history_file" 2>&1; then
            printf "%s\t%s/%s\t%s\t%s\n" "$media_id" "$((progress + 1))" "$episodes_total" "$stopped_at" "$title" >>"$history_file"
        else
            $sed -i "s/^${media_id}\t[0-9/]*\t[0-9:]*/${media_id}\t$((progress + 1))\/${episodes_total}\t${stopped_at}/" "$history_file"
        fi
        send_notification "Stopped at: $stopped_at" "5000"
    fi
}

play_video() {
    case "$provider" in
        aniwatch)
            displayed_episode_title="Ep $((progress + 1)) $episode_title"
            ;;
        yugen)
            displayed_episode_title="Ep $episode_title"
            ;;
        9anime)
            displayed_episode_title="Ep $((progress + 1)) $episode_title"
            ;;
    esac
    case "$provider" in
        hdrezka) displayed_title="$episode_title - Ep $((progress + 1))" ;;
        *) displayed_title="$title - $displayed_episode_title" ;;
    esac
    case $player in
        mpv)
            if [ -f "$history_file" ] && [ -z "$using_number" ]; then
                history=$(grep -E "^${media_id}[[:space:]]*$((progress + 1))" "$history_file")
            elif [ -f "$history_file" ]; then
                history=$(grep -E "^${media_id}[[:space:]]*[0-9/]*" "$history_file")
            fi
            [ -n "$history" ] && resume_from=$(printf "%s" "$history" | cut -f3)
            if [ -n "$resume_from" ]; then
                opts="--start=${resume_from}"
                send_notification "Resuming from" "" "" "$resume_from"
            else
                opts=""
            fi
            if [ -n "$subs_links" ]; then
                send_notification "$title" "4000" "$images_cache_dir/  $title $progress|$episodes_total episodes $media_id.jpg" "$displayed_episode_title"
                if [ "$discord_presence" = "true" ]; then
                    eval "$presence_script_path" \"mpv\" \"${title}\" \"$((progress + 1))\" \"${video_link}\" \"${subs_links}\" \"${opts}\" 2>&1 | tee $tmp_position
                else
                    mpv "$video_link" "$opts" "$subs_arg" "$subs_links" --force-media-title="$displayed_title" --msg-level=ffmpeg/demuxer=error 2>&1 | tee $tmp_position
                fi
            else
                send_notification "$title" "4000" "$images_cache_dir/  $title $progress|$episodes_total episodes $media_id.jpg" "$displayed_episode_title"
                if [ "$discord_presence" = "true" ]; then
                    eval "$presence_script_path" \"mpv\" \"${title}\" \"$((progress + 1))\" \"${video_link}\" \"\" \"${opts}\" 2>&1 | tee $tmp_position
                else
                    mpv "$video_link" "$opts" --force-media-title="$displayed_title" --msg-level=ffmpeg/demuxer=error 2>&1 | tee $tmp_position
                fi
            fi
            stopped_at=$($sed -nE "s@.*AV: ([0-9:]*) / ([0-9:]*) \(([0-9]*)%\).*@\1@p" "$tmp_position" | tail -1)
            percentage_progress=$($sed -nE "s@.*AV: ([0-9:]*) / ([0-9:]*) \(([0-9]*)%\).*@\3@p" "$tmp_position" | tail -1)
            add_to_history
            ;;
    esac
}

read_chapter() {
    # zathura --mode fullscreen
    case "$manga_format" in
        pdf)
            [ -f "$manga_dir/$title/chapter_$((progress + 1))/$title - Chapter $((progress + 1)).pdf" ] || convert_to_pdf
            send_notification "Opening - $title" "1000" "$images_cache_dir/  $title $progress|$chapters_total chapters [$score] $media_id.jpg" "Chapter: $((progress + 1)) $chapter_title"
            ${manga_opener} "$manga_dir/$title/chapter_$((progress + 1))/$title - Chapter $((progress + 1)).pdf"
            ;;
        image)
            send_notification "Opening - $title" "1000" "$images_cache_dir/  $title $progress|$chapters_total chapters [$score] $media_id.jpg" "Chapter: $((progress + 1)) $chapter_title"
            ${manga_opener} "$manga_dir/$title/chapter_$((progress + 1))"
            ;;
    esac
    [ "$((progress + 1))" -eq "$chapters_total" ] && status="COMPLETED" || status="CURRENT"
    completed_chapter=$(printf "Yes\nNo" | launcher "Do you want to update progress? [Y/n] ")
    case "$completed_chapter" in
        "Yes" | "yes" | "y" | "Y")
            response=$(update_progress "$progress" "$media_id" "$status")
            if printf "%s" "$response" | grep -q "errors"; then
                send_notification "Error" "" "" "Could not update progress"
            else
                send_notification "Updated progress to $((progress + 1))/$chapters_total chapters read" "" "$images_cache_dir/  $title $progress|$chapters_total chapters [$score] $media_id.jpg"
                progress=$((progress + 1))
            fi
            ;;
        "No" | "no" | "n" | "N")
            send_notification "Your progress has not been updated"
            ;;
        *) exit 0 ;;
    esac
}

watch_anime() {

    get_episode_info

    if [ -z "$episode_info" ]; then
        send_notification "Error" "" "" "$title not found"
        exit 1
    fi
    episode_id=$(printf "%s" "$episode_info" | cut -f1)
    episode_title=$(printf "%s" "$episode_info" | cut -f2)
    [ "$provider" = "hdrezka" ] && media_type=$(printf "%s" "$episode_info" | cut -f3)
    if [ "$episode_id" = "$episode_title" ]; then
        episode_title=""
    fi

    get_json
    [ -z "$video_link" ] && exit 1
    play_video

}

read_manga() {

    get_chapter_info
    if [ -z "$chapter_info" ]; then
        send_notification "Error" "" "" "$title not found"
        exit 1
    fi
    chapter_id=$(printf "%s" "$chapter_info" | cut -f1)
    chapter_title=$(printf "%s" "$chapter_info" | cut -f2)

    get_manga_json
    read_chapter

}

watch_anime_choice() {
    if [ -z "$media_id" ] && [ -z "$no_anilist" ]; then
        get_anime_from_list "CURRENT"
    elif [ -z "$media_id" ]; then
        [ -z "$query" ] && get_input "Search anime: "
        [ -z "$query" ] && exit 1
        search_anime_anilist "$query"
    fi
    if [ -z "$media_id" ] || [ -z "$title" ] || [ -z "$episodes_total" ]; then
        send_notification "Jerry" "" "" "Error, no anime found"
        exit 1
    fi
    send_notification "Loading" "3000" "$images_cache_dir/  $title $progress|$episodes_total episodes $media_id.jpg" "$title"
    watch_anime
    [ "$score_on_completion" = true ] && update_score "ANIME" "immediate"
}

read_manga_choice() {
    [ -z "$media_id" ] && get_manga_from_list "CURRENT"
    [ -z "$chapters_total" ] && chapters_total="9999"
    if [ -z "$media_id" ] || [ -z "$title" ] || [ -z "$progress" ]; then
        send_notification "Jerry" "" "" "Error, no manga found"
        exit 1
    fi
    send_notification "Loading" "" "$images_cache_dir/  $title $progress|$chapters_total chapters [$score] $media_id.jpg" "$title"
    read_manga
    [ "$score_on_completion" = true ] && update_score "MANGA" "immediate"
}

binge() {
    while :; do
        if [ "$1" = "ANIME" ]; then
            watch_anime_choice
            [ "$percentage_progress" -lt 85 ] && break
            [ $((progress + 1)) = "$episodes_total" ] && break
            send_notification "Please only select Yes if you have finished watching the episode" "5000"
            binge_watching=$(printf "Yes\nNo" | launcher "Do you want to keep binge watching? [Y/n] ")
            case $binge_watching in
                "Yes" | "yes" | "y" | "Y")
                    progress=$((progress + 1))
                    resume_from=""
                    continue
                    ;;
                "No" | "no" | "n" | "N") break ;;
            esac
            sleep 1
        elif [ "$1" = "MANGA" ]; then
            read_manga_choice
            [ $((progress + 1)) = "$chapters_total" ] && break
            case $completed_chapter in
                "No" | "no" | "n" | "N") break ;;
            esac
            sleep 1
        else
            exit 1
        fi
    done
}

main() {
    if [ -z "$no_anilist" ]; then
        check_credentials
        if [ -z "$access_token" ] || [ -z "$user_id" ]; then
            exit 1
        fi
        [ -n "$query" ] && mode_choice="Watch New Anime"
        [ -z "$mode_choice" ] && mode_choice=$(printf "Watch Anime\nRead Manga\nUpdate (Episodes, Status, Score)\nInfo\nWatch New Anime\nRead New Manga" | launcher "Choose an option: ")
    else
        # TODO: implement manga stuff for no_anilist
        [ -n "$query" ] && mode_choice="Watch Anime"
        [ -z "$mode_choice" ] && mode_choice=$(printf "Resume from History\nWatch Anime" | launcher "Choose an option: ")
    fi
    case "$mode_choice" in
        "Watch Anime") binge "ANIME" ;;
        "Read Manga") binge "MANGA" ;;
        "Update (Episodes, Status, Score)")
            update_choice=$(printf "Change Episodes Watched\nChange Chapters Read\nChange Status\nChange Score" | launcher "Choose an option: ")
            case "$update_choice" in
                "Change Episodes Watched") update_episode_from_list ;;
                "Change Chapters Read") update_chapter_from_list ;;
                "Change Status")
                    media_type=$(printf "ANIME\nMANGA" | launcher "Choose a media type: ")
                    [ -z "$media_type" ] && exit 0
                    update_status "$media_type"
                    ;;
                "Change Score")
                    media_type=$(printf "ANIME\nMANGA" | launcher "Choose a media type: ")
                    [ -z "$media_type" ] && exit 0
                    update_score "$media_type"
                    ;;
            esac
            ;;
        # TODO: implement more info features
        "Info")
            if ! command -v "jq" >/dev/null; then
                send_notification "For this feature to work, you must have jq installed."
                exit 1
            fi
            media_type=$(printf "ANIME\nMANGA" | launcher "Choose a media type: ")
            [ -z "$media_type" ] && exit 0
            get_anilist_info "$media_type"
            ;;
        "Watch New Anime")
            [ -z "$query" ] && get_input "Search anime: "
            [ -z "$query" ] && exit 1
            search_anime_anilist "$query"
            [ -z "$progress" ] && progress=0
            [ "$json_output" = true ] || send_notification "Disclaimer" "5000" "" "You need to complete the 1st episode to update your progress"
            binge "ANIME"
            ;;
        "Read New Manga")
            [ -z "$query" ] && get_input "Search manga: "
            [ -z "$query" ] && exit 1
            search_manga_anilist "$query"
            [ -z "$progress" ] && progress=0
            [ "$json_output" = true ] || send_notification "Disclaimer" "5000" "" "You need to complete the 1st chapter to update your progress"
            binge "MANGA"
            ;;
        "Resume from History")
            history_choice=$($sed -n "1h;1!{x;H;};\${g;p;}" "$history_file" | nl -w 1 | nth "Choose an entry: ")
            media_id=$(printf "%s" "$history_choice" | cut -f1)
            progress=$(printf "%s" "$history_choice" | cut -f2 | cut -d'/' -f1)
            progress=$((progress - 1))
            episodes_total=$(printf "%s" "$history_choice" | cut -f2 | cut -d'/' -f2)
            resume_from=$(printf "%s" "$history_choice" | cut -f3)
            title=$(printf "%s" "$history_choice" | cut -f4)
            [ -z "$media_id" ] && exit 1
            binge "ANIME"
            ;;
    esac
}

configuration
query=""
# TODO: add an argument for video_providers
while [ $# -gt 0 ]; do
    case "$1" in
        --)
            shift
            query="$*"
            break
            ;;
        -c | --continue) mode_choice="Watch Anime" && shift ;;
        --clear-history | --delete-history)
            while true; do
                printf "This will delete your jerry history. Are you sure? [Y/n] "
                read -r choice
                case $choice in
                    [Yy]* | "")
                        #shellcheck disable=1090
                        [ -f "$config_file" ] && . "$config_file"
                        [ -z "$history_file" ] && history_file="$HOME/.local/share/jerry/jerry_history.txt"
                        rm "$history_file"
                        echo "History deleted."
                        exit 0
                        ;;
                    [Nn]*)
                        return 1
                        ;;
                    *) echo "Please answer yes or no." ;;
                esac
            done
            shift
            ;;
        -d | --discord) discord_presence=true && shift ;;
        --dub) dub="true" && shift ;;
        -e | --edit) edit_configuration ;;
        -h | --help)
            usage && exit 0
            ;;
        -i | --image-preview)
            image_preview=1
            shift
            ;;
        -j | --json)
            json_output=1
            no_anilist=1
            shift
            ;;
        -l | --language)
            subs_language="$2"
            if [ -z "$subs_language" ]; then
                subs_language="english"
                shift
            else
                if [ "${subs_language#-}" != "$subs_language" ]; then
                    subs_language="english"
                    shift
                else
                    subs_language="$(echo "$subs_language" | cut -c2-)"
                    shift 2
                fi
            fi
            ;;
        -n | --number)
            progress=$(($2 - 1))
            using_number=1
            shift 2
            ;;
        --no-anilist) no_anilist=1 && shift ;;
        --rofi | --dmenu | --external-menu)
            use_external_menu="1"
            shift
            ;;
        -q | --quality)
            quality="$2"
            if [ -z "$quality" ]; then
                quality="1080"
                shift
            else
                if [ "${quality#-}" != "$quality" ]; then
                    quality="1080"
                    shift
                else
                    shift 2
                fi
            fi
            ;;
        -s | --syncplay)
            player="syncplay"
            shift
            ;;
        -u | -U | --update)
            update_script
            ;;
        -v | -V | --version)
            send_notification "Jerry Version: $JERRY_VERSION"
            exit 0
            ;;
        -w | --website)
            provider="$2"
            if [ -z "$provider" ]; then
                provider="9anime"
                shift
            else
                if [ "${provider#-}" != "$provider" ]; then
                    provider="9anime"
                    shift
                else
                    shift 2
                fi
            fi
            ;;
        *)
            if [ "${1#-}" != "$1" ]; then
                query="$query $1"
            else
                query="$query $1"
            fi
            shift
            ;;
    esac
done
# check for update
check_update "A new update is out. Would you like to update jerry? [Y/n] " "A new update for the presence script is out. Would you like to update jerrydiscordpresence.py? [Y/n] "
query="$(printf "%s" "$query" | tr ' ' '-' | $sed "s/^-//g")"
case "$provider" in
    zoro | kaido | aniwatch) provider="aniwatch" ;;
    9anime | nineanime | aniwave) provider="9anime" ;;
    yugen | yugenanime) provider="yugen" ;;
    hdrezka | rezka) provider="hdrezka" ;;
    *) send_notification "Invalid provider" && exit 1 ;;
esac
if [ "$image_preview" = 1 ]; then
    test -d "$images_cache_dir" || mkdir -p "$images_cache_dir"
    if [ "$use_external_menu" = 1 ]; then
        mkdir -p "/tmp/jerry/applications/"
        [ ! -L "$applications" ] && ln -sf "/tmp/jerry/applications/" "$applications"
    fi
fi

main
