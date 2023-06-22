#!/bin/sh

JERRY_VERSION=2.0.0

anilist_base="https://graphql.anilist.co"
config_file="$HOME/.config/jerry/jerry.conf"
jerry_editor=${VISUAL:-${EDITOR}}
tmp_dir="/tmp/jerry"
image_config_path="$HOME/.config/rofi/styles/launcher.rasi"

if [ "$1" = "--edit" ] || [ "$1" = "-e" ]; then
    if [ -f "$config_file" ]; then
        #shellcheck disable=1090
        . "${config_file}"
        [ -z "$jerry_editor" ] && jerry_editor="vim"
        "$jerry_editor" "$config_file"
    fi
    exit 0
fi

cleanup() {
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
    [ -n "$json_output" ] && return
    [ "$use_external_menu" = "0" ] && printf "\33[2K\r\033[1;34m%s\n\033[0m" "$1" && return
    [ -z "$2" ] && timeout=3000 || timeout="$2"
    if [ "$notify" = "true" ]; then
        [ -z "$3" ] && notify-send "$1" -t "$timeout" -h string:x-dunst-stack-tag:tes
        [ -n "$3" ] && notify-send "$1" -t "$timeout" -i "$3" -r 1 -h string:x-dunst-stack-tag:tes
        # -h string:x-dunst-stack-tag:tes
    fi
}
dep_ch() {
    for dep; do
        command -v "$dep" >/dev/null || send_notification "Program \"$dep\" not found. Please install it."
    done
}
dep_ch "grep" "$sed" "awk" "curl" "fzf" "mpv" || true

if [ "$use_external_menu" = "1" ]; then
    dep_ch "rofi" || true
fi

configuration() {
    [ -n "$XDG_CONFIG_HOME" ] && config_dir="$XDG_CONFIG_HOME/jerry" || config_dir="$HOME/.config/jerry"
    [ -n "$XDG_DATA_HOME" ] && data_dir="$XDG_DATA_HOME/jerry" || data_dir="$HOME/.local/share/jerry"
    [ ! -d "$config_dir" ] && mkdir -p "$config_dir"
    [ ! -d "$data_dir" ] && mkdir -p "$data_dir"
    #shellcheck disable=1090
    [ -f "$config_file" ] && . "${config_file}"
    [ -z "$player" ] && player="mpv"
    [ -z "$download_dir" ] && download_dir="$PWD"
    [ -z "$subs_language" ] && subs_language="english"
    subs_language="$(printf "%s" "$subs_language" | cut -c2-)"
    [ -z "$use_external_menu" ] && use_external_menu="1"
    [ -z "$image_preview" ] && image_preview="1"
    [ -z "$preview_window_size" ] && preview_window_size=up:60%:wrap
    [ -z "$ueberzug_x" ] && ueberzug_x=10
    [ -z "$ueberzug_y" ] && ueberzug_y=3
    [ -z "$ueberzug_max_width" ] && ueberzug_max_width=$(($(tput lines) / 2))
    [ -z "$ueberzug_max_height" ] && ueberzug_max_height=$(($(tput lines) / 2))
    [ -z "$json_output" ] && json_output=0
}

check_credentials() {
    [ -f "$data_dir/anilist_token.txt" ] && access_token=$(cat "$data_dir/anilist_token.txt")
    [ -z "$access_token" ] && printf "Paste your access token from this page:
https://anilist.co/api/v2/oauth/authorize?client_id=9857&response_type=token : " && read -r access_token &&
        echo "$access_token" >"$data_dir/anilist_token.txt"
    [ -f "$data_dir/anilist_user_id.txt" ] && user_id=$(cat "$data_dir/anilist_user_id.txt")
    [ -z "$user_id" ] &&
        user_id=$(curl -s -X POST "$anilist_base" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -H "Authorization: Bearer $access_token" \
            -d "{\"query\":\"query { Viewer { id } }\"}" | sed -nE "s@.*\"id\":([0-9]*).*@\1@p") &&
        echo "$user_id" >"$data_dir/anilist_user_id.txt"
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
            [ -z "$2" ] && rofi -sort -dmenu -i -width 1500 -p "" -mesg "$1"
            [ -n "$2" ] && rofi -sort -dmenu -i -width 1500 -p "" -mesg "$1" -display-columns "$2"
            ;;
        *)
            [ -z "$2" ] && fzf --reverse --prompt "$1"
            [ -n "$2" ] && fzf --reverse --prompt "$1" --with-nth "$2" -d "\t"
            ;;
    esac
}

download_thumbnails() {
    printf "%s\n" "$1" | while read -r cover_url id title; do
        curl -s -o "$images_cache_dir/  $title $id.jpg" "$cover_url" &
        if [ "$use_external_menu" = "1" ]; then
            entry=/tmp/jerry/applications/"$id.desktop"
            generate_desktop "$title" "$images_cache_dir/  $title $id.jpg" >"$entry" &
        fi
    done
    sleep "$2"
}

select_desktop_entry() {
    if [ "$use_external_menu" = "1" ]; then
        [ -n "$image_config_path" ] && choice=$(rofi -show drun -drun-categories jerry -filter "$1" -show-icons -theme "$image_config_path" | $sed -nE "s@.*/([0-9]*)\.desktop@\1@p") 2>/dev/null || choice=$(rofi -show drun -drun-categories jerry -filter "$1" -show-icons | $sed -nE "s@.*/([0-9]*)\.desktop@\1@p") 2>/dev/null
    fi
}

get_anime_from_list() {
    anime_list=$(curl -s -X POST "$anilist_base" \
        -H 'Content-Type: application/json' \
        -H "Authorization: Bearer $access_token" \
        -d "{\"query\":\"query(\$userId:Int,\$userName:String,\$type:MediaType){MediaListCollection(userId:\$userId,userName:\$userName,type:\$type){lists{name isCustomList isCompletedList:isSplitCompletedList entries{...mediaListEntry}}user{id name avatar{large}mediaListOptions{scoreFormat rowOrder animeList{sectionOrder customLists splitCompletedSectionByFormat theme}mangaList{sectionOrder customLists splitCompletedSectionByFormat theme}}}}}fragment mediaListEntry on MediaList{id mediaId status score progress progressVolumes repeat priority private hiddenFromStatusLists customLists advancedScores notes updatedAt startedAt{year month day}completedAt{year month day}media{id title{userPreferred romaji english native}coverImage{extraLarge large}type format status(version:2)episodes volumes chapters averageScore popularity isAdult countryOfOrigin genres bannerImage startDate{year month day}}}\",\"variables\":{\"userId\":$user_id,\"type\":\"ANIME\"}}" |
        tr "\[|\]" "\n" | sed -nE "s@.*\"mediaId\":([0-9]*),\"status\":\"$1\",\"score\":(.*),\"progress\":([0-9]*),.*\"userPreferred\":\"([^\"]*)\".*\"coverImage\":\{\"extraLarge\":\"([^\"]*)\".*\"episodes\":([0-9]*).*@\5\t\1\t\4 \3|\6 episodes@p" | sed 's/\\\//\//g')
    case "$image_preview" in
        "true" | 1)
            download_thumbnails "$anime_list" "2"
            select_desktop_entry ""
            [ -z "$choice" ] && exit 1
            id=$(printf "%s" "$choice" | cut -d\  -f1)
            title=$(printf "%s" "$choice" | sed -nE "s@$id (.*) [0-9|]* episodes@\1@p")
            progress=$(printf "%s" "$choice" | sed -nE "s@.* ([0-9]*)\|[0-9]* episodes@\1@p")
            episodes_total=$(printf "%s" "$choice" | sed -nE "s@.*\|([0-9]*) episodes@\1@p")
            ;;
        *)
            send_notification "Jerry" "TODO"
            ;;
    esac
}

get_episode_info() {
    zoro_id=$(curl -s "https://raw.githubusercontent.com/MALSync/MAL-Sync-Backup/master/data/anilist/anime/$id.json" | tr -d '\n' | sed -nE "s@.*\"Zoro\":[[:space:]{]*\"([0-9]*)\".*@\1@p")
    episode_info=$(curl -s "https://zoro.to/ajax/v2/episode/list/$zoro_id" | sed -e "s/</\n/g" -e "s/\\\\//g" | sed -nE "s_.*a title=\"([^\"]*)\".*data-id=\"([0-9]*)\".*_\2\t\1_p" | sed -n "$((progress + 1))p")
}

get_episode_links() {
    source_id=$(curl -s "https://zoro.to/ajax/v2/episode/servers?episodeId=$episode_id" | tr "<|>" "\n" | sed -nE 's_.*data-id=\\"([^"]*)\\".*_\1_p' | head -1)
    embed_link=$(curl -s "https://zoro.to/ajax/v2/episode/sources?id=$source_id" | sed -nE "s_.*\"link\":\"([^\"]*)\".*_\1_p")

    # get the juicy links
    parse_embed=$(printf "%s" "$embed_link" | sed -nE "s_(.*)/embed-(4|6)/(.*)\?k=1\$_\1\t\2\t\3_p")
    provider_link=$(printf "%s" "$parse_embed" | cut -f1)
    source_id=$(printf "%s" "$parse_embed" | cut -f3)
    embed_type=$(printf "%s" "$parse_embed" | cut -f2)

    json_data=$(curl -s "${provider_link}/ajax/embed-${embed_type}/getSources?id=${source_id}" -H "X-Requested-With: XMLHttpRequest")
    encrypted=$(printf "%s" "$json_data" | sed -nE "s_.*\"encrypted\":([^\,]*)\,.*_\1_p")
    case "$encrypted" in
        "true")
            key="$(curl -s "https://github.com/enimax-anime/key/blob/e${embed_type}/key.txt" | sed -nE "s_.*js-file-line\">(.*)<.*_\1_p")"
            video_link=$(printf "%s" "$json_data" | tr "{|}" "\n" | sed -nE "s_.*\"sources\":\"([^\"]*)\".*_\1_p" | base64 -d |
                openssl enc -aes-256-cbc -d -md md5 -k "$key" 2>/dev/null | sed -nE "s_.*\"file\":\"([^\"]*)\".*_\1_p" | head -1)
            ;;
        "false")
            video_link=$(printf "%s" "$json_data" | tr "{|}" "\n" | sed -nE "s_.*\"file\":\"([^\"]*)\".*_\1_p" | head -1)
            ;;
    esac
}

watch_anime() {

    get_episode_info

    if [ -z "$episode_info" ]; then
        send_notification "Error" "$title not found"
        exit 1
    fi
    episode_id=$(printf "%s" "$episode_info" | cut -f1)
    episode_title=$(printf "%s" "$episode_info" | cut -f2)

    get_episode_links

}

main() {
    check_credentials
    # [ -z "$choice" ] && choice=$(printf "Watch\nUpdate\nInfo\nWatch New" | launcher "Choose an option")
    choice="Watch"
    case "$choice" in
        "Watch")
            get_anime_from_list "CURRENT"
            if [ -z "$id" ] || [ -z "$title" ] || [ -z "$progress" ] || [ -z "$episodes_total" ]; then
                send_notification "Jerry" "Error, no anime found"
                exit 1
            fi
            send_notification "Loading" "$title" "1000"
            watch_anime
            ;;
    esac
}

configuration
query=""
while [ $# -gt 0 ]; do
    case "$1" in
        --)
            shift
            query="$*"
            break
            ;;
        -h | --help)
            usage && exit 0
            ;;
        -i | --image-preview)
            image_preview="1"
            shift
            ;;
        -j | --json)
            json_output="1"
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
            send_notification "Jerry Version: $JERRY_VERSION" && exit 0
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
query="$(printf "%s" "$query" | tr ' ' '-')"
if [ "$image_preview" = 1 ]; then
    test -d "$images_cache_dir" || mkdir -p "$images_cache_dir"
    if [ "$use_external_menu" = 1 ]; then
        mkdir -p "/tmp/jerry/applications/"
        [ ! -L "$applications" ] && ln -sf "/tmp/jerry/applications/" "$applications"
    fi
fi

main
