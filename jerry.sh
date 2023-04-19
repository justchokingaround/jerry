#!/bin/sh
# shellcheck disable=SC2154,SC2086,SC1090

JERRY_VERSION=1.2.2

anilist_base="https://graphql.anilist.co"
config_file="$HOME/.config/jerry/jerry.conf"
cache_dir="$HOME/.cache/jerry"
command -v bat >/dev/null 2>&1 && display="bat" || display="less"
jerry_editor=${VISUAL:-${EDITOR:-vim}}
default_config="discord_presence=false\nconsumet_base=\"api.consumet.org\"\nprovider=zoro\nmanga_provider\nsubs_language=English\nuse_external_menu=0\nvideo_quality=best\nhistory_file=$HOME/.cache/anime_history\nmanga_format=\"jpg\"\nmanga_opener=\"nsxiv\"\njerry_editor=$jerry_editor\nmanga_dir=\"/tmp/jerry-manga\"\nimages_cache_dir=\"/tmp/jerry-images\"\nimage_preview=false\nimage_config_path=\"$HOME/.config/rofi/styles/image-preview.rasi"\"
case "$(uname -s)" in
MINGW* | *Msys) separator=';' && path_thing='' ;;
*) separator=':' && path_thing="\\" ;;
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
dep_ch "grep" "sed" "awk" "curl" "fzf" "mpv" || true

cleanup() {
	rm -rf $images_cache_dir && exit
}
trap cleanup EXIT INT TERM

usage() {
	printf "
  Usage: %s [options] [query]
  If a query is provided, it will be used to search for an anime, and will default to the 'Watch New Anime' option.

  Options:
    -c, --continue
      Continue watching from currently watching list (using the user's anilist account)
    -d, --discord
      Display currently watching anime in Discord Rich Presence (jerrydiscordpresence.py is required for this, check the readme for instructions on how to install it)
    -D, --dmenu
      Use an external menu (instead of the default fzf) to select an anime (default one is rofi, but this can be specified in the config file)
    -e, --edit
      Edit config file using an editor defined with jerry_editor in the config (\$EDITOR by default)
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
     ${0##*/} -q 720p banana fish
     ${0##*/} -l spanish cyberpunk edgerunners -i -n 2
     ${0##*/} -l spanish cyberpunk edgerunners --number 2 --json

" "${0##*/}"
}

configuration() {
	[ ! -d "$HOME/.config/jerry" ] && mkdir -p "$HOME/.config/jerry"
	[ -f "$config_file" ] && . "${config_file}"
	[ -z "$discord_presence" ] && discord_presence="false"
	[ -z "$consumet_base" ] && consumet_base="api.consumet.org"
	[ -z "$preferred_provider" ] && provider="zoro" || provider="$preferred_provider"
	[ -z "$manga_provider" ] && manga_provider="mangakalot"
	[ -z "$subs_language" ] && subs_language="English"
	case "$dub" in
	"true" | "dub" | 1) dub="dub" ;;
	*) dub="sub" ;;
	esac
	[ -z "$use_external_menu" ] && use_external_menu="0"
	[ -z "$video_quality" ] && video_quality="best"
	[ -z "$history_file" ] && history_file="$HOME/.cache/anime_history"
	[ -z "$manga_format" ] && manga_format="jpg"
	[ -z "$manga_opener" ] && manga_opener="nsxiv"
	[ -z "$manga_dir" ] && manga_dir="/tmp/jerry-manga"
	[ -z "$images_cache_dir" ] && images_cache_dir="/tmp/jerry-images"
	[ -z "$image_preview" ] && image_preview="false"
	[ -z "$image_config_path" ] && image_config_path="$HOME/.config/rofi/styles/image-preview.rasi"
}

check_credentials() {
	[ ! -d "$cache_dir" ] && mkdir -p "$cache_dir"
	[ -f "$cache_dir/anilist_token.txt" ] && access_token=$(cat "$cache_dir/anilist_token.txt")
	[ -z "$access_token" ] && printf "Paste your access token from this page:
https://anilist.co/api/v2/oauth/authorize?client_id=9857&response_type=token : " && read -r access_token &&
		echo "$access_token" >"$cache_dir/anilist_token.txt"
	[ -f "$cache_dir/anilist_user_id.txt" ] && user_id=$(cat "$cache_dir/anilist_user_id.txt")
	[ -z "$user_id" ] &&
		user_id=$(curl -s -X POST "$anilist_base" \
			-H "Content-Type: application/json" \
			-H "Accept: application/json" \
			-H "Authorization: Bearer $access_token" \
			-d "{\"query\":\"query { Viewer { id } }\"}" | sed -nE "s@.*\"id\":([0-9]*).*@\1@p") &&
		echo "$user_id" >"$cache_dir/anilist_user_id.txt"
}

launcher() {
	[ "$use_external_menu" = "0" ] && fzf $opt_fzf_args --prompt "$1: "
	[ "$use_external_menu" = "1" ] && external_menu "$1"
}

external_menu() {
	rofi -dmenu -i -width 1500 -p "" -mesg "$1"
}

nth() {
	stdin=$(cat -)
	[ -z "$stdin" ] && return 1
	line=$(printf "%b\n" "$stdin" | awk -F '\t' "{ print NR, $1 }" | launcher "$2" | cut -d\  -f1)
	[ -n "$line" ] && printf "%b\n" "$stdin" | sed "${line}q;d" || exit 1
}

get_input() {
	if [ "$use_external_menu" = "0" ]; then
		printf "Enter a query: " && read -r query
	else
		query=$(printf "" | launcher "Enter a query")
	fi
	[ -n "$query" ] && query=$(echo "$query" | tr ' ' '+')
	[ -z "$query" ] && send_notification "Error: No query provided" "1000"
}

get_from_list() {
	list=$(curl -s -X POST "$anilist_base" \
		-H 'Content-Type: application/json' \
		-H "Authorization: Bearer $access_token" \
		-d "{\"query\":\"query(\$userId:Int,\$userName:String,\$type:MediaType){MediaListCollection(userId:\$userId,userName:\$userName,type:\$type){lists{name isCustomList isCompletedList:isSplitCompletedList entries{...mediaListEntry}}user{id name avatar{large}mediaListOptions{scoreFormat rowOrder animeList{sectionOrder customLists splitCompletedSectionByFormat theme}mangaList{sectionOrder customLists splitCompletedSectionByFormat theme}}}}}fragment mediaListEntry on MediaList{id mediaId status score progress progressVolumes repeat priority private hiddenFromStatusLists customLists advancedScores notes updatedAt startedAt{year month day}completedAt{year month day}media{id title{userPreferred romaji english native}coverImage{extraLarge large}type format status(version:2)episodes volumes chapters averageScore popularity isAdult countryOfOrigin genres bannerImage startDate{year month day}}}\",\"variables\":{\"userId\":$user_id,\"type\":\"$2\"}}")
	case "$2" in
	"ANIME")
		anime_list=$(printf "%s" "$list" | tr "\[|\]" "\n" | sed -nE "s@.*\"mediaId\":([0-9]*),\"status\":\"$1\",\"score\":(.*),\"progress\":([0-9]*),.*\"userPreferred\":\"([^\"]*)\".*\"coverImage\":\{\"extraLarge\":\"([^\"]*)\".*\"episodes\":([0-9]*).*@\4 (\3/\6 episodes) \t[\2]\t[\1]\t\5@p" | sed 's/\\\//\//g')
		;;
	"MANGA")
		manga_list=$(printf "%s" "$list" | tr "\[|\]" "\n" | sed -nE "s@.*\"mediaId\":([0-9]*),\"status\":\"$1\",\"score\":(.*),\"progress\":([0-9]*),.*\"userPreferred\":\"([^\"]*)\".*\"coverImage\":\{\"extraLarge\":\"([^\"]*)\".*\"chapters\":([0-9]*).*@\4 (\3/\6 chapters) \t[\2]\t[\1]\t\5@p" | sed 's/\\\//\//g')
		;;
	esac

	case "$image_preview" in
	"true" | 1)
		mkdir -p "$images_cache_dir"
		case "$2" in
		"ANIME")
			printf "%s\n" "$anime_list" | sed -nE "s@.*\[([0-9]*)\].*(https://.*)@\1\t\2@p" | while read -r media_id cover_url; do
				curl -s -o "$images_cache_dir/$media_id.jpg" "$cover_url" &
			done
			;;
		"MANGA")
			printf "%s\n" "$manga_list" | sed -nE "s@.*\[([0-9]*)\].*(https://.*)@\1\t\2@p" | while read -r media_id cover_url; do
				curl -s -o "$images_cache_dir/$media_id.jpg" "$cover_url" &
			done
			;;
		esac
		wait && sleep 1

		case "$2" in
		"ANIME")
			anime_choice=$(printf "%b\n" "$anime_list" | sed -nE "s@(.*) \(([0-9]*/.*) episodes\) \t\[([0-9]*)\]\t\[([0-9]*)\].*@\4\t\3\t\2\t\1@p" |
				while read -r media_id score episodes anime_title; do
					printf "[%s]\t%s (%s episodes) [%d]\x00icon\x1f%s/%s.jpg\n" "$media_id" "$anime_title" "$episodes" "$score" "$images_cache_dir" "$media_id"
				done | rofi -dmenu -i -p "" -theme "$image_config_path" -mesg "Select anime" -display-columns 2..)
			anime_title=$(printf "%s" "$anime_choice" | sed -nE "s@.*\t(.*) \([0-9]*/[0-9]* episodes\) \[.*\]@\1@p")
			progress=$(printf "%s" "$anime_choice" | sed -nE "s@.*\t.* \(([0-9]*)\/.* episodes\) \[.*\]@\1@p")
			episodes_total=$(printf "%s" "$anime_choice" | sed -nE "s@.*\t.* \([0-9]*/([0-9]*) episodes\) \[.*\]@\1@p")
			score=$(printf "%s" "$anime_choice" | sed -nE "s@.*\t.* \([0-9]*/[0-9]* episodes\) \[([0-9]*)\]@\1@p")
			media_id=$(printf "%s" "$anime_choice" | sed -nE "s@\[([0-9]*)\].*@\1@p")
			;;
		"MANGA")
			manga_choice=$(printf "%s\n" "$manga_list" | sed -nE "s@(.*) \(([0-9]*/[^\"]* chapters)\) \t\[([0-9]*)\]\t\[([0-9]*)\].*@\4\t\3\t\2\t\1@p" |
				while read -r media_id score chapters_done _chapters_total manga_title; do
					printf "[%s]\t%s (%s) [%d]\x00icon\x1f%s/%s.jpg\n" "$media_id" "$manga_title" "$chapters_done" "$score" "$images_cache_dir" "$media_id"
				done | rofi -dmenu -i -p "" -theme "$image_config_path" -mesg "Select manga" -display-columns 2..)
			manga_title=$(printf "%s" "$manga_choice" | cut -f2 | sed -nE "s@(.*) \([0-9]*/.*\) \[.*\]@\1@p")
			progress=$(printf "%s" "$manga_choice" | sed -nE "s@.* \(([0-9]*)\/.*\) \[.*\]@\1@p")
			score=$(printf "%s" "$manga_choice" | sed -nE "s@.* \([0-9]*/.*\) \[([0-9]*)\]@\1@p")
			media_id=$(printf "%s" "$manga_choice" | sed -nE "s@\[([0-9]*)\].*@\1@p")
			chapters_total=$(printf "%s" "$manga_choice" | sed -nE "s@.* \([0-9]*\/([0-9]*)\) \[.*\]@\1@p")
			;;
		esac
		;;
	*)
		case "$2" in
		"ANIME")
			anime_choice="$(printf "%s" "$anime_list" | nth "\$1,\$2" "Select anime")"
			anime_title=$(printf "%s" "$anime_choice" | sed -E "s@(.*) \([0-9]*/[0-9]*\ episodes\) \t.*@\1@")
			progress=$(printf "%s" "$anime_choice" | sed -nE "s@($anime_title) \(([0-9]*)\/([0-9]*)\ episodes\) \t.*@\2@p")
			episodes_total=$(printf "%s" "$anime_choice" | sed -nE "s@($anime_title) \(([0-9]*)\/(.*)\ episodes\) \t.*@\3@p")
			score=$(printf "%s" "$anime_choice" | sed -nE "s@$anime_title \([0-9]*/[0-9]*\ episodes\) \t\[([0-9]*)\].*@\1@p")
			media_id=$(printf "%s" "$anime_choice" | sed -nE "s@.*\t\[([0-9]*)\].*@\1@p")
			;;
		"MANGA")
			manga_choice="$(printf "%s" "$manga_list" | nth "\$1,\$2" "Select manga")"
			manga_title=$(printf "%s" "$manga_choice" | sed -E "s@(.*) \([0-9]*/[^\"]* chapters\) \t.*@\1@")
			progress=$(printf "%s" "$manga_choice" | sed -nE "s@($manga_title) \(([0-9]*)\/[^\"]* chapters\) \t.*@\2@p")
			score=$(printf "%s" "$manga_choice" | sed -nE "s@$manga_title \([0-9]*/[^\"]* chapters\) \t\[([0-9]*)\].*@\1@p")
			media_id=$(printf "%s" "$manga_choice" | sed -nE "s@.*\t\[([0-9]*)\].*@\1@p")
			;;
		esac
		;;
	esac
	[ -z "$episodes_total" ] && episodes_total="null"

}

search_anime() {
	[ -z "$query" ] && get_input
	[ -z "$query" ] && exit 1
	anime_list=$(curl -s -X POST "$anilist_base" \
		-H 'Content-Type: application/json' \
		-d "{\"query\":\"query(\$page:Int = 1 \$id:Int \$type:MediaType \$isAdult:Boolean = false \$search:String \$format:[MediaFormat]\$status:MediaStatus \$countryOfOrigin:CountryCode \$source:MediaSource \$season:MediaSeason \$seasonYear:Int \$year:String \$onList:Boolean \$yearLesser:FuzzyDateInt \$yearGreater:FuzzyDateInt \$episodeLesser:Int \$episodeGreater:Int \$durationLesser:Int \$durationGreater:Int \$chapterLesser:Int \$chapterGreater:Int \$volumeLesser:Int \$volumeGreater:Int \$licensedBy:[Int]\$isLicensed:Boolean \$genres:[String]\$excludedGenres:[String]\$tags:[String]\$excludedTags:[String]\$minimumTagRank:Int \$sort:[MediaSort]=[POPULARITY_DESC,SCORE_DESC]){Page(page:\$page,perPage:20){pageInfo{total perPage currentPage lastPage hasNextPage}media(id:\$id type:\$type season:\$season format_in:\$format status:\$status countryOfOrigin:\$countryOfOrigin source:\$source search:\$search onList:\$onList seasonYear:\$seasonYear startDate_like:\$year startDate_lesser:\$yearLesser startDate_greater:\$yearGreater episodes_lesser:\$episodeLesser episodes_greater:\$episodeGreater duration_lesser:\$durationLesser duration_greater:\$durationGreater chapters_lesser:\$chapterLesser chapters_greater:\$chapterGreater volumes_lesser:\$volumeLesser volumes_greater:\$volumeGreater licensedById_in:\$licensedBy isLicensed:\$isLicensed genre_in:\$genres genre_not_in:\$excludedGenres tag_in:\$tags tag_not_in:\$excludedTags minimumTagRank:\$minimumTagRank sort:\$sort isAdult:\$isAdult){id title{userPreferred}coverImage{extraLarge large color}startDate{year month day}endDate{year month day}bannerImage season seasonYear description type format status(version:2)episodes duration chapters volumes genres isAdult averageScore popularity nextAiringEpisode{airingAt timeUntilAiring episode}mediaListEntry{id status}studios(isMain:true){edges{isMain node{id name}}}}}}\",\"variables\":{\"page\":1,\"type\":\"ANIME\",\"sort\":\"SEARCH_MATCH\",\"search\":\"$query\"}}" |
		tr "\[|\]" "\n" | sed -nE "s@.*\"id\":([0-9]*),.*\"userPreferred\":\"(.*)\"\},\"coverImage\":.*\"extraLarge\":\"([^\"]*)\".*\"episodes\":([0-9]*).*@\2 (\4 episodes)\t[\1]\t\3@p" | sed 's/\\\//\//g')

	case "$image_preview" in
	"true" | "1")
		mkdir -p "$images_cache_dir"
		printf "%s\n" "$anime_list" | sed -nE "s@.*\[([0-9]*)\].*(https://.*)@\1\t\2@p" | while read -r media_id cover_url; do
			curl -s -o "/tmp/jerry-images/$media_id.jpg" "$cover_url" &
		done
		wait && sleep 1

		anime_selected=$(printf "%s\n" "$anime_list" | sed -nE "s@(.*) \(([0-9]*) episodes\).*\[([0-9]*)\]@\3\t\2\t\1@p" | while read -r media_id episodes_total anime_title; do
			anime_title=$(printf "%s\n" "$anime_title" | cut -f1)
			printf "[%s]\t%s (%d episodes)\x00icon\x1f%s/%s.jpg\n" "$media_id" "$anime_title" "$episodes_total" "$images_cache_dir" "$media_id"
		done | rofi -dmenu -i -p "" -theme "$image_config_path" -mesg "Select anime" -display-columns 2..)
		anime_title=$(printf "%s" "$anime_selected" | sed -nE "s@.*\t([^\t]*) \([0-9]* episodes\).*@\1@p")
		episodes_total=$(printf "%s" "$anime_selected" | sed -nE "s@.*\t[^\t]* \(([0-9]*) episodes\).*@\1@p")
		media_id=$(printf "%s" "$anime_selected" | sed -nE "s@\[([0-9]*)\].*@\1@p")
		;;
	*)
		anime_selected=$(printf "%s" "$anime_list" | nth "\$1" "Select anime")
		anime_title=$(printf "%s" "$anime_selected" | cut -f1 | sed -nE "s@(.*) \([0-9]* episodes\).*@\1@p")
		episodes_total=$(printf "%s" "$anime_selected" | sed -nE "s@.*\(([0-9]*) episodes\).*@\1@p")
		media_id=$(printf "%s" "$anime_selected" | sed -nE "s@.*\[([0-9]*)\].*@\1@p")
		;;
	esac

	[ -z "$anime_title" ] && exit 0
}

search_manga() {
	get_input
	[ -z "$query" ] && exit 1
	manga_list=$(curl -s -X POST "$anilist_base" \
		-H "Content-Type: aplication/json" \
		-d "{\"query\":\"query(\$page:Int = 1 \$id:Int \$type:MediaType \$isAdult:Boolean = false \$search:String \$format:[MediaFormat]\$status:MediaStatus \$countryOfOrigin:CountryCode \$source:MediaSource \$season:MediaSeason \$seasonYear:Int \$year:String \$onList:Boolean \$yearLesser:FuzzyDateInt \$yearGreater:FuzzyDateInt \$episodeLesser:Int \$episodeGreater:Int \$durationLesser:Int \$durationGreater:Int \$chapterLesser:Int \$chapterGreater:Int \$volumeLesser:Int \$volumeGreater:Int \$licensedBy:[Int]\$isLicensed:Boolean \$genres:[String]\$excludedGenres:[String]\$tags:[String]\$excludedTags:[String]\$minimumTagRank:Int \$sort:[MediaSort]=[POPULARITY_DESC,SCORE_DESC]){Page(page:\$page,perPage:20){pageInfo{total perPage currentPage lastPage hasNextPage}media(id:\$id type:\$type season:\$season format_in:\$format status:\$status countryOfOrigin:\$countryOfOrigin source:\$source search:\$search onList:\$onList seasonYear:\$seasonYear startDate_like:\$year startDate_lesser:\$yearLesser startDate_greater:\$yearGreater episodes_lesser:\$episodeLesser episodes_greater:\$episodeGreater duration_lesser:\$durationLesser duration_greater:\$durationGreater chapters_lesser:\$chapterLesser chapters_greater:\$chapterGreater volumes_lesser:\$volumeLesser volumes_greater:\$volumeGreater licensedById_in:\$licensedBy isLicensed:\$isLicensed genre_in:\$genres genre_not_in:\$excludedGenres tag_in:\$tags tag_not_in:\$excludedTags minimumTagRank:\$minimumTagRank sort:\$sort isAdult:\$isAdult){id title{userPreferred}coverImage{extraLarge large color}startDate{year month day}endDate{year month day}bannerImage season seasonYear description type format status(version:2)episodes duration chapters volumes genres isAdult averageScore popularity nextAiringEpisode{airingAt timeUntilAiring episode}mediaListEntry{id status}studios(isMain:true){edges{isMain node{id name}}}}}}\",\"variables\":{\"page\":1,\"type\":\"MANGA\",\"sort\":\"SEARCH_MATCH\",\"search\":\"$query\"}}" |
		tr "\[|\]" "\n" | sed -nE "s@.*\"id\":([0-9]*),.*\"userPreferred\":\"(.*)\"\},\"coverImage\":.*\"extraLarge\":\"([^\"]*)\".*\"chapters\":([^,]*),.*@\2 (\4 chapters)\t[\1]\t\3@p" | sed 's/\\\//\//g')

	case "$image_preview" in
	"true" | '1')
		mkdir -p "$images_cache_dir"
		printf "%s\n" "$manga_list" | sed -nE "s@.*\[([0-9]*)\].*(https://.*)@\1\t\2@p" | while read -r media_id cover_url; do
			curl -s -o "/tmp/jerry-images/$media_id.jpg" "$cover_url" &
		done
		wait && sleep 1

		manga_selected=$(printf "%s\n" "$manga_list" | sed -nE "s@(.*) \(([0-9]*) chapters\).*\[([0-9]*)\]@\3\t\2\t\1@p" | while read -r media_id chapters_total manga_title; do
			manga_title=$(printf "%s\n" "$manga_title" | cut -f1)
			printf "[%s]\t%s (%d chapters)\x00icon\x1f%s/%s.jpg\n" "$media_id" "$manga_title" "$chapters_total" "$images_cache_dir" "$media_id"
		done | rofi -dmenu -i -p "" -theme "$image_config_path" -mesg "Select manga" -display-columns 2..)
		manga_title=$(printf "%s" "$manga_selected" | sed -nE "s@.*\t([^\t]*) \([0-9]* chapters\).*@\1@p")
		chapters_total=$(printf "%s" "$manga_selected" | sed -nE "s@.*\t[^\t]* \(([0-9]*) chapters\).*@\1@p")
		media_id=$(printf "%s" "$manga_selected" | sed -nE "s@\[([0-9]*)\].*@\1@p")
		;;
	*)
		manga_selected=$(printf "%s" "$manga_list" | nth "\$1" "Select manga")
		manga_title=$(printf "%s" "$manga_selected" | cut -f1 | sed -nE "s@(.*) \([0-9]* chapters\).*@\1@p")
		chapters_total=$(printf "%s" "$manga_selected" | sed -nE "s@.*\(([0-9]*) chapters\).*@\1@p")
		media_id=$(printf "%s" "$manga_selected" | sed -nE "s@.*\[([0-9]*)\].*@\1@p")
		;;
	esac

	[ -z "$manga_title" ] && exit 0

}

update_progress() {
	curl -s -X POST "$anilist_base" \
		-H 'Content-Type: application/json' \
		-H "Authorization: Bearer $access_token" \
		-d "{\"query\":\"mutation(\$id:Int \$mediaId:Int \$status:MediaListStatus \$score:Float \$progress:Int \$progressVolumes:Int \$repeat:Int \$private:Boolean \$notes:String \$customLists:[String]\$hiddenFromStatusLists:Boolean \$advancedScores:[Float]\$startedAt:FuzzyDateInput \$completedAt:FuzzyDateInput){SaveMediaListEntry(id:\$id mediaId:\$mediaId status:\$status score:\$score progress:\$progress progressVolumes:\$progressVolumes repeat:\$repeat private:\$private notes:\$notes customLists:\$customLists hiddenFromStatusLists:\$hiddenFromStatusLists advancedScores:\$advancedScores startedAt:\$startedAt completedAt:\$completedAt){id mediaId status score advancedScores progress progressVolumes repeat priority private hiddenFromStatusLists customLists notes updatedAt startedAt{year month day}completedAt{year month day}user{id name}media{id title{userPreferred}coverImage{large}type format status episodes volumes chapters averageScore popularity isAdult startDate{year}}}}\",\"variables\":{\"status\":\"$3\",\"progress\":$(($1 + 1)),\"mediaId\":$2}}"
	[ "$3" = "COMPLETED" ] && send_notification "Completed $anime_title" "5000"
	[ "$3" = "COMPLETED" ] && sed -i "/$media_id/d" "$history_file"
}

update_episode_from_list() {
	status_choice=$(printf "CURRENT\nCOMPLETED\nPAUSED\nDROPPED\nPLANNING" | launcher "Filter by status")
	get_from_list "$status_choice" "$1"
	case "$1" in
	"ANIME")
		title="$anime_title"
		unit="episode"
		total="$episodes_total"
		;;
	"MANGA")
		title="$manga_title"
		unit="chapter"
		total="$chapters_total"
		;;
	esac
	[ -z "$title" ] && exit 0
	case "$1" in
	"ANIME") send_notification "Current progress: $progress/$total episodes watched" "5000" ;;
	"MANGA")
		[ -z "$total" ] && chapters_total="?"
		send_notification "Current progress: $progress/$chapters_total chapters read" "5000"
		;;
	esac
	[ -z "$progress" ] && exit 0
	if [ "$use_external_menu" = "0" ]; then
		new_episode_number=$(printf "Enter a new %s number: " "$unit" && read -r new_episode_number)
	else
		new_episode_number=$(printf "" | launcher "Enter a new $unit number")
	fi
	case "$1" in
	"ANIME") [ "$new_episode_number" -gt "$total" ] && new_episode_number=$total ;;
	"MANGA") [ "$new_episode_number" -gt "$total" ] && exit 0 ;;
	esac
	[ "$new_episode_number" -lt 0 ] && new_episode_number=0
	[ -z "$new_episode_number" ] && send_notification "No $unit number given"
	[ -z "$new_episode_number" ] && exit 1
	send_notification "Updating progress for $title..."
	[ "$new_episode_number" -eq "$total" ] && status="COMPLETED" || status="CURRENT"
	response=$(update_progress "$((new_episode_number - 1))" "$media_id" "$status")
	send_notification "New progress: $new_episode_number/$total episodes watched"
	[ "$new_episode_number" -eq "$total" ] && send_notification "Completed $title"
}

update_status() {
	status_choice=$(printf "CURRENT\nCOMPLETED\nPAUSED\nDROPPED\nPLANNING" | launcher "Filter by status")
	get_from_list "$status_choice" "$1"
	[ "$1" = "ANIME" ] && title=$anime_title || title=$manga_title
	[ -z "$title" ] && exit 0
	send_notification "Choose a new status for $title" "5000"
	new_status=$(printf "CURRENT\nCOMPLETED\nPAUSED\nDROPPED\nPLANNING" | launcher "Choose a new status")
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
	status_choice=$(printf "CURRENT\nCOMPLETED\nPAUSED\nDROPPED\nPLANNING" | launcher "Filter by status")
	get_from_list "$status_choice" "$1"
	[ "$1" = "ANIME" ] && title=$anime_title || title=$manga_title
	send_notification "Enter new score for: \"$title\"" "5000"
	send_notification "Current score: $score" "5000"
	if [ "$use_external_menu" = "0" ]; then
		new_score=$(printf "Enter new score: " && read -r new_score)
	else
		new_score=$(printf "" | launcher "Enter new score")
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

get_video_url_quality() {
	[ -z "$video_link" ] && video_link=$(printf "%s" "$episode_links" | tr "{|}" "\n" | sed -nE "s@\"url\":\"([^\"]*)\",\"quality\":\"$1\".*@\1@p")
}

get_episode_info() {
	case "$dub" in
	"true" | "dub" | 1) anime_response=$(curl -s "https://$consumet_base/meta/anilist/info/${media_id}?provider=${provider}&dub=true" | tr "{|}" "\n") ;;
	*) anime_response=$(curl -s "https://$consumet_base/meta/anilist/info/${media_id}?provider=${provider}" | tr "{|}" "\n") ;;
	esac
	case $provider in
	zoro)
		episode_info=$(printf "%s" "$anime_response" | sed -nE "s@\"id\":\"([^\"]*)\",\"title\":\"([^\"]*)\",.*\"number\":$((progress + 1)).*@\1\t\2@p" | head -1)
		[ -z "$episode_info" ] && episode_info=$(printf "%s" "$anime_response" | sed -nE "s@.*\"id\":\"([^\"]*)\",.*\"number\":$((progress + 1)),.*@\1@p" | head -1)
		;;
	*)
		episode_info=$(printf "%s" "$anime_response" | sed -nE "s@.*\"id\":\"([^\"]*)\",\"title\":\"(.*)\",\"description\".*\"number\":$((progress + 1)),.*@\1\t\2@p" | head -1)
		[ -z "$episode_info" ] && episode_info=$(printf "%s" "$anime_response" | sed -nE "s@.*\"id\":\"([^\"]*)\",.*\"description\".*\"number\":$((progress + 1)),.*@\1@p" | head -1)
		;;
	esac
}

get_chapter_info() {
	manga_response=$(curl -s "https://$consumet_base/meta/anilist-manga/info/${media_id}?provider=${manga_provider}" | tr "{|}" "\n")
	case $manga_provider in
	"mangakalot")
		chapter_info=$(printf "%s" "$manga_response" | sed -nE "s@\"id\":\"(.*-chapter-$((progress + 1)))\",\"title\":\"([^\"]*)\",\"releaseDate\".*@\1\t\2@p")
		;;
	"mangahere")
		temp_progress=$(printf "%03d" "$((progress + 1))")
		chapter_info=$(printf "%s" "$manga_response" | sed -nE "s@\"id\":\"(.*/c$temp_progress)\",\"title\":\"(.*)\",\"releasedDate\".*@\1\t\2@p")
		;;
	*)
		send_notification "Provider not supported" "2000"
		;;
	esac
}

get_episode_links() {
	case $provider in
	zoro)
		episode_id=$(printf "%s" "$episode_id" | sed -nE 's@.*episode\$([0-9]*)\$.*@\1@p')
		# source_id=$(curl -s "https://zoro.to/ajax/v2/episode/servers?episodeId=$episode_id" | tr "<|>" "\n" | sed -nE 's_.*data-id=\\"([^"]*)\\".*_\1_p' | head -1)
		source_id=$(curl -s "https://zoro.to/ajax/v2/episode/servers?episodeId=$episode_id" | sed "s/\\\n/\n/g" |
			grep -B2 Vidcloud | sed -nE 's_.*data-type=\\"'"$dub"'\\" data-id=\\"([^"]*)\\".*_\1_p')
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
				openssl enc -aes-256-cbc -d -md md5 -k "$key" 2>/dev/null | sed -nE "s_.*\"file\":\"([^\"]*)\".*_\1_p")
			;;
		"false")
			video_link=$(printf "%s" "$json_data" | tr "{|}" "\n" | sed -nE "s_.*\"file\":\"([^\"]*)\".*_\1_p")
			;;
		esac
		[ -z "$video_link" ] && provider="gogoanime" && send_notification "No video links found from zoro, trying gogoanime" && provider="gogoanime" && get_episode_info
		episode_links=$(printf "%s" "$json_data" | sed -E "s@sources\":\"[^\"]*\"@sources\":\"$video_link\"@")
		;;
	gogoanime)
		episode_links=$(curl -s "https://$consumet_base/meta/anilist/watch/${episode_id}?provider=${provider}")
		;;
	esac
	[ -z "$episode_links" ] && send_notification "Error: no links found for $anime_title episode $((progress + 1))/$episodes_total" "1000" && exit 1
	[ "$json_output" = "true" ] && printf "%s\n" "$episode_links" && exit 0

	[ "$((progress + 1))" -eq "$episodes_total" ] && status="COMPLETED" || status="CURRENT"

	case $provider in
	zoro)
		subs_links=$(printf "%s" "$json_data" | tr "{|}" "\n" | sed -nE "s@\"file\":\"([^\"]*.vtt)\",\"label\":\"$subs_language.*@\1@p" | sed -e "s/:/\\$path_thing:/g" -e "H;1h;\$!d;x;y/\n/$separator/" -e "s/$separator\$//")
		[ -z "$subs_links" ] && subs_links=$(printf "%s" "$episode_links" | tr "{|}" "\n" | tr "{|}" "\n" | sed -nE "s@\"url\":\"([^\"]*.vtt)\",\"lang\":\"English.*@\1@p" | sed -e "s/:/\\$path_thing:/g" -e "H;1h;\$!d;x;y/\n/$separator/" -e "s/$separator\$//")
		;;
	*)
		referrer=$(printf "%s" "$episode_links" | tr "{|}" "\n" | sed -nE "s@\"Referer\":\"([^\"]*)\"\$@\1@p")
		video_link=$(printf "%s" "$episode_links" | tr "{|}" "\n" | sed -nE "s@\"url\":\"([^\"]*)\".*\"quality\":\"1080p\"\$@\1@p")
		;;
	esac
}

download_images() {
	[ ! -d "$manga_dir/$manga_title/chapter_$((progress + 1))" ] && mkdir -p "$manga_dir/$manga_title/chapter_$((progress + 1))" || return 0
	send_notification "Downloading $manga_title - Chapter: $((progress + 1)) $chapter_title" "2000"
	printf "%s" "$chapter_links" | while read -r image_link image_number; do
		image_name=$(printf "%03d" "$image_number")
		curl -sL -A "uwu" -e "$referrer" "$image_link" -o "$manga_dir/$manga_title/chapter_$((progress + 1))/$image_name.jpg" &
	done
	wait && sleep 1
}

get_chapter_links() {
	case $manga_provider in
	"mangakalot" | "mangahere")
		json_response=$(curl -s "https://$consumet_base/meta/anilist-manga/read?chapterId=${chapter_id}&provider=${manga_provider}")
		chapter_links=$(printf "%s" "$json_response" | tr "{|}" "\n" | sed -nE "s@.*\"page\":([0-9]*).*\"img\":\"([^\"]*)\".*@\2\t\1@p")
		referrer=$(printf "%s" "$json_response" | sed -nE "s@.*\"Referer\":\"([^\"]*)\".*@\1@p")
		;;
	*) exit 0 ;;
	esac
	status="CURRENT"
	download_images && wait
}

play_video() {
	[ -f "$history_file" ] && history=$(grep -E "^$media_id" "$history_file")
	[ -n "$history" ] && resume_from=$(printf "%s" "$history" | cut -f2)
	[ -z "$resume_from" ] && opts="" || opts="--start=${resume_from}%"
	[ -n "$resume_from" ] && [ "$resume_from" -gt 0 ] && [ -z "$incognito" ] && send_notification "Resuming from saved progress: $resume_from%" "3000"
	[ -n "$incognito" ] && opts=""

	[ "$discord_presence" = "true" ] && launch_mpv="jerrydiscordpresence.py \"mpv\" \"${anime_title}\" \"$((progress + 1))\" \"${video_link}\" \"${subs_links}\" \"${referrer}\" \"${opts}\"" ||
		launch_mpv="mpv --fs --referrer=\"$referrer\" --sub-files=\"$subs_links\" --force-media-title=\"$anime_title - Ep: $((progress + 1)) $episode_title\" ${opts} \"$video_link\""

	stopped_at=$(eval "$launch_mpv" 2>&1 | grep AV | tail -n1 | sed -nE "s_.*AV: ([^ ]*) / ([^ ]*) \(([0-9]*)%\).*_\3_p" &)
	[ -n "$incognito" ] && exit 0
	[ -z "$stopped_at" ] && exit 0
	if [ "$stopped_at" -gt 85 ]; then
		response=$(update_progress "$progress" "$media_id" "$status")
		if printf "%s" "$response" | grep -q "errors"; then
			send_notification "Error updating progress"
		else
			send_notification "Updated progress to $((progress + 1))/$episodes_total episodes watched"
			[ -n "$history" ] && sed -i "/^$media_id/d" $history_file
		fi
	else
		send_notification "Current progress: $progress/$episodes_total episodes watched"
		send_notification "Your progress has not been updated"
		grep -sv "$media_id" "$history_file" >"$history_file.tmp"
		printf "%s\t%s" "$media_id" "$stopped_at" >>"$history_file.tmp"
		mv "$history_file.tmp" "$history_file"
		send_notification "Stopped at: $stopped_at%" "5000"
	fi
}

convert_to_pdf() {
	send_notification "Converting $manga_title - Chapter: $((progress + 1)) $chapter_title to PDF" "2000"
	convert "$manga_dir/$manga_title/chapter_$((progress + 1))"/*.jpg "$manga_dir/$manga_title/chapter_$((progress + 1))/$manga_title - Chapter $((progress + 1)).pdf" && wait
}

open_manga() {
	# zathura --mode fullscreen
	case "$manga_format" in
	pdf)
		[ -f "$manga_dir/$manga_title/chapter_$((progress + 1))/$manga_title - Chapter $((progress + 1)).pdf" ] || convert_to_pdf
		send_notification "Opening $manga_title - Chapter: $((progress + 1)) $chapter_title" "1000"
		${manga_opener} "$manga_dir/$manga_title/chapter_$((progress + 1))/$manga_title - Chapter $((progress + 1)).pdf"
		;;
	jpg)
		send_notification "Opening $manga_title - Chapter: $((progress + 1)) $chapter_title" "1000"
		${manga_opener} "$manga_dir/$manga_title/chapter_$((progress + 1))"
		;;
	esac
	case $choice in
	"Read Manga") completed_chapter=$(printf "Yes\nNo" | launcher "Do you want to update progress? [y/N]") ;;
	"Binge Read Manga") completed_chapter=$(printf "Yes\nNo\nExit binge mode" | launcher "Do you want to update progress? [y/N]") ;;
	esac
	case "$completed_chapter" in
	"Yes" | "yes" | "y" | "Y")
		update_progress "$progress" "$media_id" "$status"
		send_notification "Updated progress to $((progress + 1))/$chapters_total chapters read"
		progress=$((progress + 1))
		;;
	"No" | "no" | "n" | "N")
		send_notification "Your progress has not been updated"
		;;
	*) exit 0 ;;
	esac
}

get_anime_info() {
	anime_info="$(curl -s -X POST "$anilist_base" \
		-H 'Content-Type: application/json' \
		-d "{\"query\":\"query media(\$id:Int,\$type:MediaType,\$isAdult:Boolean){Media(id:\$id,type:\$type,isAdult:\$isAdult){id title{userPreferred romaji english native}coverImage{extraLarge large}bannerImage startDate{year month day}endDate{year month day}description season seasonYear type format status(version:2)episodes duration chapters volumes genres synonyms source(version:3)isAdult isLocked meanScore averageScore popularity favourites isFavouriteBlocked hashtag countryOfOrigin isLicensed isFavourite isRecommendationBlocked isFavouriteBlocked isReviewBlocked nextAiringEpisode{airingAt timeUntilAiring episode}relations{edges{id relationType(version:2)node{id title{userPreferred}format type status(version:2)bannerImage coverImage{large}}}}characterPreview:characters(perPage:6,sort:[ROLE,RELEVANCE,ID]){edges{id role name voiceActors(language:JAPANESE,sort:[RELEVANCE,ID]){id name{userPreferred}language:languageV2 image{large}}node{id name{userPreferred}image{large}}}}staffPreview:staff(perPage:8,sort:[RELEVANCE,ID]){edges{id role node{id name{userPreferred}language:languageV2 image{large}}}}studios{edges{isMain node{id name}}}reviewPreview:reviews(perPage:2,sort:[RATING_DESC,ID]){pageInfo{total}nodes{id summary rating ratingAmount user{id name avatar{large}}}}recommendations(perPage:7,sort:[RATING_DESC,ID]){pageInfo{total}nodes{id rating userRating mediaRecommendation{id title{userPreferred}format type status(version:2)bannerImage coverImage{large}}user{id name avatar{large}}}}externalLinks{id site url type language color icon notes isDisabled}streamingEpisodes{site title thumbnail url}trailer{id site}rankings{id rank type format year season allTime context}tags{id name description rank isMediaSpoiler isGeneralSpoiler userId}mediaListEntry{id status score}stats{statusDistribution{status amount}scoreDistribution{score amount}}}}\",\"variables\":{\"id\":$media_id,\"type\":\"ANIME\"}}" |
		tr '{|}' '\n' | sed -nE "s@.*\"description\":\"(.*)\",\"season\".*@\1@p" | sed -e "s@\\\@@g" -e "s@<br>n@\n@g" -e "s@<br>@@g")"
}

watch_anime() {
	get_episode_info
	[ -z "$episode_info" ] && send_notification "Error: $query not found on $provider" && exit 1

	episode_id=$(printf "%s" "$episode_info" | cut -f1)
	episode_title=$(printf "%s" "$episode_info" | cut -f2 | sed "s@\\\@@g")
	[ "$episode_id" = "$episode_title" ] && episode_title=""

	get_episode_links
	case "$image_preview" in
	"true" | '1')
		send_notification "Watching $anime_title
  Ep: $((progress + 1)) $episode_title" "3000" "$images_cache_dir/$media_id.jpg"
		;;
	*)
		send_notification "Watching $anime_title
  Ep: $((progress + 1)) $episode_title" "3000"
		;;
	esac

	[ -z "$video_link" ] && send_notification "Error: no video link found for $anime_title episode $((progress + 1))/$episodes_total" "2000" && exit 1
	play_video
}

read_manga() {
	get_chapter_info
	[ -z "$chapter_info" ] && send_notification "Error: $query not found on $manga_provider"
	[ -z "$chapter_info" ] && exit 1

	chapter_id=$(printf "%s" "$chapter_info" | cut -f1 | head -1)
	chapter_title=$(printf "%s" "$chapter_info" | cut -f2 | head -1 | sed "s@\\\@@g")
	[ "$chapter_id" = "$chapter_title" ] && chapter_title=""

	get_chapter_links && wait
	[ -z "$chapter_links" ] && send_notification "Error: no chapter link found for $manga_title chapter $((progress + 1))/$chapters_total" "1000"
	[ -z "$chapter_links" ] && exit 1
	open_manga
}

update_script() {
	update=$(curl -s "https://raw.githubusercontent.com/justchokingaround/jerry/master/jerry.sh" || die "Connection error")
	update="$(printf '%s\n' "$update" | diff -u "$(which jerry)" -)"
	if [ -z "$update" ]; then
		printf "Script is up to date :)\n"
	else
		if printf '%s\n' "$update" | patch "$(which jerry)" -; then
			printf "Script has been updated\n"
		else
			printf "Can't update for some reason!\n"
		fi
	fi
	exit 0
}

while [ $# -gt 0 ]; do
	case "$1" in
	-c | --continue) choice="Watch Anime" && shift ;;
	-d | --discord) discord_presence="true" && shift ;;
	--dub) dub="dub" && shift ;;
	-D | --dmenu) use_external_menu="1" && shift ;;
	-e | --edit) [ -f "$config_file" ] && "$jerry_editor" "$config_file" && exit 0 || echo "$default_config" >"$config_file" && "$jerry_editor" "$config_file" && exit 0 ;;
	-h | --help) usage && exit 0 ;;
	-i | --incognito) incognito="true" && shift ;;
	-j | --json) json_output="true" && incognito="true" && shift ;;
	-l | --language) subs_language="$2" && shift 2 ;;
	-n | --number) progress=$(($2 - 1)) && shift 2 ;;
	-p | --provider) preferred_provider="$2" && shift 2 ;;
	-q | --quality) video_quality="$2" && shift 2 ;;
	-u | -U | --update) update_script ;;
	-v | -V | --version) printf "Jerry Version: %s\n" "$JERRY_VERSION" && exit 0 ;;
	*) query="$(printf "%s" "$query $1" | sed "s/^ //;s/ /+/g")" && shift && choice="Watch New Anime" ;;
	esac
done

[ "$incognito" = "true" ] || check_credentials
configuration
[ "$(printf "%s" "$subs_language" | head -c 1)" = "$(printf "%s" "$subs_language" | head -c 1 | tr '[:upper:]' '[:lower:]')" ] && subs_language="$(printf "%s" "$subs_language" | head -c 1 | tr '[:lower:]' '[:upper:]')$(printf "%s" "$subs_language" | tail -c +2)"

read_manga_option_choice() {
	[ -z "$media_id" ] && get_from_list "CURRENT" "MANGA"
	[ -z "$manga_title" ] && exit 0
	send_notification "Loading $manga_title..." "1000"
	query="$manga_title"
	read_manga
}

watch_anime_option_choice() {
	[ -z "$media_id" ] && get_from_list "CURRENT" "ANIME"
	[ -z "$anime_title" ] && exit 0
	send_notification "Loading $anime_title..." "1000"
	query="$anime_title"
	watch_anime
}

[ -z "$choice" ] && choice=$(printf "Watch Anime\nRead Manga\nBinge Watch Anime\nBinge Read Manga\nUpdate (Episodes, Status, Score)\nInfo\nWatch New Anime\nRead New Manga\n" | launcher "Choose an option")
case "$choice" in
"Watch Anime") watch_anime_option_choice && exit 0 ;;
"Read Manga") read_manga_option_choice && exit 0 ;;
"Binge Read Manga")
	while :; do
		read_manga_option_choice
		case $completed_chapter in
		"No" | "no" | "n" | "N") break ;;
		esac
		sleep 2
	done
	;;
"Binge Watch Anime")
	while :; do
		watch_anime_option_choice
		binge_watching=$(printf "Yes\nNo" | launcher "Do you want to keep binge watching? [y/N]")
		case $binge_watching in
		"Yes" | "yes" | "y" | "Y")
			progress=$((progress + 1))
			resume_from=""
			continue
			;;
		"No" | "no" | "n" | "N") break ;;
		esac
		sleep 2
	done
	;;
"Update (Episodes, Status, Score)")
	update_choice=$(printf "Change Episodes Watched\nChange Chapters Read\nChange Status\nChange Score" | launcher "Choose an option")
	case "$update_choice" in
	"Change Episodes Watched") update_episode_from_list "ANIME" ;;
	"Change Chapters Read") update_episode_from_list "MANGA" ;;
	"Change Status")
		media_type=$(printf "ANIME\nMANGA" | launcher "Choose a media type")
		[ -z "$media_type" ] && exit 0
		update_status "$media_type"
		;;
	"Change Score")
		media_type=$(printf "ANIME\nMANGA" | launcher "Choose a media type")
		[ -z "$media_type" ] && exit 0
		update_score "$media_type"
		;;
	esac
	;;
"Info")
	search_anime
	if command -v zenity >/dev/null 2>&1; then
		zenity --progress --text="Waiting for an answer" --pulsate &
		[ $? -eq 1 ] && exit 1
		PID=$!
		get_anime_info
		[ -z "$anime_info" ] && notify-send "No description found" && exit 0
		kill $PID
		zenity --info --text="$anime_info"
	else
		notify-send -t 1000 "zenity is not installed, using $display instead" && printf "%s" "$anime_info" | $display
		printf "%s" "$anime_info" | $display
	fi
	;;
"Watch New Anime")
	search_anime
	[ -z "$progress" ] && progress="0"
	[ "$json_output" = "true" ] || send_notification "Disclaimer: you need to finish the first episode before you can update your progress" "5000"
	watch_anime
	;;
"Read New Manga")
	search_manga
	[ -z "$progress" ] && progress="0"
	[ "$json_output" = "true" ] || send_notification "Disclaimer: you need to finish the first chapter before you can update your progress" "5000"
	read_manga
	;;
esac
