#!/bin/sh
# shellcheck disable=SC2154,SC2086,SC1090

JERRY_VERSION=1.1.0

anilist_base="https://graphql.anilist.co"
config_file="$HOME/.config/jerry/jerry.conf"
cache_dir="$HOME/.cache/jerry"
command -v bat >/dev/null 2>&1 && display="bat" || display="less"
[ -f "$config_file" ] && . "${config_file}" && [ -z "$jerry_editor" ] && jerry_editor=${VISUAL:-${EDITOR:-vim}}
default_config="discord_presence=false\npreferred_provider=zoro\nsubs_language=English\nuse_external_menu=0\nvideo_quality=best\nhistory_file=$HOME/.cache/anime_history\njerry_editor=$jerry_editor"
case "$(uname -s)" in
MINGW* | *Msys) separator=';' && path_thing='' ;;
*) separator=':' && path_thing="\\" ;;
esac
dep_ch() {
	for dep; do
		command -v "$dep" >/dev/null || notify-send "Program \"$dep\" not found. Please install it."
	done
}
dep_ch "grep" "sed" "awk" "curl" "fzf" "mpv" || true

usage() {
	printf "
  Usage: %s [options] [query]
  If a query is provided, it will be used to search for an anime, and will default to the 'Watch New' option.

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
	[ -z "$preferred_provider" ] && provider="zoro" || provider="$preferred_provider"
	[ -z "$subs_language" ] && subs_language="English"
	[ -z "$use_external_menu" ] && use_external_menu="0"
	[ -z "$video_quality" ] && video_quality="best"
	[ -z "$history_file" ] && history_file="$HOME/.cache/anime_history"
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

send_notification() {
	[ -z "$2" ] && timeout=3000 || timeout="$2"
	if command -v notify-send >/dev/null 2>&1; then
		notify-send "$1" -t "$timeout"
	fi
	[ -n "$json_output" ] && return
	[ "$use_external_menu" = "0" ] && printf "\33[2K\r\033[1;34m%s\n\033[0m" "$1"
}

launcher() {
	[ "$use_external_menu" = "0" ] && fzf $opt_fzf_args --prompt "$1"
	[ "$use_external_menu" = "1" ] && external_menu "$1"
}

external_menu() {
	rofi -dmenu -i -width 1500 -p "$1"
}

nth() {
	stdin=$(cat)
	[ -z "$stdin" ] && return 1
	[ "$(echo "$stdin" | wc -l)" -eq 1 ] && echo "$stdin" && return 0
	line=$(echo "$stdin" | awk -F '\t' "{ print NR, $1 }" | launcher "" | cut -d\  -f1)
	[ -n "$line" ] && echo "$stdin" | sed "${line}q;d" || exit 1
}

get_input() {
	if [ "$use_external_menu" = "0" ]; then
		printf "Enter a query: " && read -r query
	else
		query=$(printf "" | launcher "Enter a query: ")
	fi
	query=$(echo "$query" | tr ' ' '+')
	[ -z "$query" ] && send_notification "Error: No query provided" && exit 1
}

get_anime_from_list() {
	anime_list=$(curl -s -X POST "$anilist_base" \
		-H 'Content-Type: application/json' \
		-H "Authorization: Bearer $access_token" \
		-d "{\"query\":\"query(\$userId:Int,\$userName:String,\$type:MediaType){MediaListCollection(userId:\$userId,userName:\$userName,type:\$type){lists{name isCustomList isCompletedList:isSplitCompletedList entries{...mediaListEntry}}user{id name avatar{large}mediaListOptions{scoreFormat rowOrder animeList{sectionOrder customLists splitCompletedSectionByFormat theme}mangaList{sectionOrder customLists splitCompletedSectionByFormat theme}}}}}fragment mediaListEntry on MediaList{id mediaId status score progress progressVolumes repeat priority private hiddenFromStatusLists customLists advancedScores notes updatedAt startedAt{year month day}completedAt{year month day}media{id title{userPreferred romaji english native}coverImage{extraLarge large}type format status(version:2)episodes volumes chapters averageScore popularity isAdult countryOfOrigin genres bannerImage startDate{year month day}}}\",\"variables\":{\"userId\":$user_id,\"type\":\"ANIME\"}}")
	anime_choice=$(printf "%s" "$anime_list" | tr "\[|\]" "\n" | sed -nE "s@.*\"mediaId\":([0-9]*),\"status\":\"$1\",\"score\":(.*),\"progress\":([0-9]*),.*\"userPreferred\":\"([^\"]*)\".*\"status\":\"([^\"]*)\",\"episodes\":([0-9]*).*@\4 (\3/\6) \t[\2]\t[\1]@p" |
		nth "\$1,\$2")
	anime_title=$(printf "%s" "$anime_choice" | sed -E "s@(.*) \([0-9]*/[0-9]*\) \t.*@\1@")
	[ -z "$progress" ] && progress=$(printf "%s" "$anime_choice" | sed -nE "s@^([^\(]*)\(([0-9]*)\/([0-9]*)\).*@\2@p")
	episodes_total=$(printf "%s" "$anime_choice" | sed -nE "s@^([^\(]*)\(([0-9]*)\/([0-9]*)\).*@\3@p")
	score=$(printf "%s" "$anime_choice" | sed -nE "s@$anime_title \([0-9]*/[0-9]*\) \t\[([0-9]*)\].*@\1@p")
	media_id=$(printf "%s" "$anime_choice" | sed -nE "s@.*\[([0-9]*)\]@\1@p")
	[ -z "$anime_title" ] && exit 0
}

search_anime() {
	[ -z "$query" ] && get_input
	anime_list=$(curl -s -X POST "$anilist_base" \
		-H 'Content-Type: application/json' \
		-d "{\"query\":\"query(\$page:Int = 1 \$id:Int \$type:MediaType \$isAdult:Boolean = false \$search:String \$format:[MediaFormat]\$status:MediaStatus \$countryOfOrigin:CountryCode \$source:MediaSource \$season:MediaSeason \$seasonYear:Int \$year:String \$onList:Boolean \$yearLesser:FuzzyDateInt \$yearGreater:FuzzyDateInt \$episodeLesser:Int \$episodeGreater:Int \$durationLesser:Int \$durationGreater:Int \$chapterLesser:Int \$chapterGreater:Int \$volumeLesser:Int \$volumeGreater:Int \$licensedBy:[Int]\$isLicensed:Boolean \$genres:[String]\$excludedGenres:[String]\$tags:[String]\$excludedTags:[String]\$minimumTagRank:Int \$sort:[MediaSort]=[POPULARITY_DESC,SCORE_DESC]){Page(page:\$page,perPage:20){pageInfo{total perPage currentPage lastPage hasNextPage}media(id:\$id type:\$type season:\$season format_in:\$format status:\$status countryOfOrigin:\$countryOfOrigin source:\$source search:\$search onList:\$onList seasonYear:\$seasonYear startDate_like:\$year startDate_lesser:\$yearLesser startDate_greater:\$yearGreater episodes_lesser:\$episodeLesser episodes_greater:\$episodeGreater duration_lesser:\$durationLesser duration_greater:\$durationGreater chapters_lesser:\$chapterLesser chapters_greater:\$chapterGreater volumes_lesser:\$volumeLesser volumes_greater:\$volumeGreater licensedById_in:\$licensedBy isLicensed:\$isLicensed genre_in:\$genres genre_not_in:\$excludedGenres tag_in:\$tags tag_not_in:\$excludedTags minimumTagRank:\$minimumTagRank sort:\$sort isAdult:\$isAdult){id title{userPreferred}coverImage{extraLarge large color}startDate{year month day}endDate{year month day}bannerImage season seasonYear description type format status(version:2)episodes duration chapters volumes genres isAdult averageScore popularity nextAiringEpisode{airingAt timeUntilAiring episode}mediaListEntry{id status}studios(isMain:true){edges{isMain node{id name}}}}}}\",\"variables\":{\"page\":1,\"type\":\"ANIME\",\"sort\":\"SEARCH_MATCH\",\"search\":\"$query\"}}" |
		tr "\[|\]" "\n" | sed -nE "s@.*\"id\":([0-9]*),.*\"userPreferred\":\"(.*)\"\},\"coverImage\".*\"episodes\":([0-9]*).*@\2 (\3 episodes)\t[\1]@p" | nth "\$1" | sed -nE "s@(.*) \(([0-9]*) episodes\).*\[([0-9]*)\]@\1\t\2\t\3@p")
	anime_title=$(printf "%s" "$anime_list" | cut -f1)
	episodes_total=$(printf "%s" "$anime_list" | cut -f2)
	media_id=$(printf "%s" "$anime_list" | cut -f3)
	[ -z "$anime_title" ] && anime_title=query
}

update_episode() {
	curl -s -X POST "$anilist_base" \
		-H 'Content-Type: application/json' \
		-H "Authorization: Bearer $access_token" \
		-d "{\"query\":\"mutation(\$id:Int \$mediaId:Int \$status:MediaListStatus \$score:Float \$progress:Int \$progressVolumes:Int \$repeat:Int \$private:Boolean \$notes:String \$customLists:[String]\$hiddenFromStatusLists:Boolean \$advancedScores:[Float]\$startedAt:FuzzyDateInput \$completedAt:FuzzyDateInput){SaveMediaListEntry(id:\$id mediaId:\$mediaId status:\$status score:\$score progress:\$progress progressVolumes:\$progressVolumes repeat:\$repeat private:\$private notes:\$notes customLists:\$customLists hiddenFromStatusLists:\$hiddenFromStatusLists advancedScores:\$advancedScores startedAt:\$startedAt completedAt:\$completedAt){id mediaId status score advancedScores progress progressVolumes repeat priority private hiddenFromStatusLists customLists notes updatedAt startedAt{year month day}completedAt{year month day}user{id name}media{id title{userPreferred}coverImage{large}type format status episodes volumes chapters averageScore popularity isAdult startDate{year}}}}\",\"variables\":{\"status\":\"$3\",\"progress\":$(($1 + 1)),\"mediaId\":$2}}"
	[ "$3" = "COMPLETED" ] && send_notification "Completed $anime_title" "5000" && sed -i "/$media_id/d" "$history_file" && exit
}

update_episode_from_list() {
	status_choice=$(printf "CURRENT\nCOMPLETED\nPAUSED\nDROPPED\nPLANNING" | launcher "Filter by status: ")
	# status_choice="CURRENT"
	get_anime_from_list "$status_choice"
	send_notification "Enter new progress for: $anime_title" "5000"
	send_notification "Current progress: $progress/$episodes_total episodes watched" "5000"
	if [ "$use_external_menu" = "0" ]; then
		new_episode_number=$(printf "Enter a new episode number: " && read -r new_episode_number)
	else
		new_episode_number=$(printf "" | launcher "Enter a new episode number: ")
	fi
	[ "$new_episode_number" -gt "$episodes_total" ] && new_episode_number=$episodes_total
	[ "$new_episode_number" -lt 0 ] && new_episode_number=0
	[ -z "$new_episode_number" ] && send_notification "No episode number given" && exit 1
	send_notification "Updating progress for $anime_title..."
	[ "$new_episode_number" -eq "$episodes_total" ] && status="COMPLETED" || status="CURRENT"
	response=$(update_episode "$((new_episode_number - 1))" "$media_id" "$status")
	send_notification "New progress: $new_episode_number/$episodes_total episodes watched"
	[ "$new_episode_number" -eq "$episodes_total" ] && send_notification "Completed $anime_title"
}

update_status() {
	status_choice=$(printf "CURRENT\nCOMPLETED\nPAUSED\nDROPPED\nPLANNING" | launcher "Filter by status: ")
	get_anime_from_list "$status_choice"
	send_notification "Choose a new status for $anime_title" "5000"
	new_status=$(printf "CURRENT\nCOMPLETED\nPAUSED\nDROPPED\nPLANNING" | launcher "Choose a new status: ")
	[ -z "$new_status" ] && exit 0
	send_notification "Updating status for $anime_title..."
	response=$(update_episode "$((progress - 1))" "$media_id" "$new_status")
	if printf "%s" "$response" | grep -q "errors"; then
		send_notification "Failed to update status for $anime_title"
	else
		send_notification "New status: $new_status"
	fi
}

update_score() {
	status_choice=$(printf "CURRENT\nCOMPLETED\nPAUSED\nDROPPED\nPLANNING" | launcher "Filter by status: ")
	get_anime_from_list "$status_choice"
	send_notification "Enter new score for: \"$anime_title\"" "5000"
	send_notification "Current score: $score" "5000"
	if [ "$use_external_menu" = "0" ]; then
		new_score=$(printf "Enter new score: " && read -r new_score)
	else
		new_score=$(printf "" | launcher "Enter new score: ")
	fi
	[ -z "$new_score" ] && send_notification "No score given" && exit 1
	[ -z "$new_score" ] && send_notification "No score given" && exit 1
	send_notification "Updating score for $anime_title..."
	response=$(curl -s -X POST "$anilist_base" \
		-H 'Content-Type: application/json' \
		-H "Authorization: Bearer $access_token" \
		-d "{\"query\":\"mutation(\$id:Int \$mediaId:Int \$status:MediaListStatus \$score:Float \$progress:Int \$progressVolumes:Int \$repeat:Int \$private:Boolean \$notes:String \$customLists:[String]\$hiddenFromStatusLists:Boolean \$advancedScores:[Float]\$startedAt:FuzzyDateInput \$completedAt:FuzzyDateInput){SaveMediaListEntry(id:\$id mediaId:\$mediaId status:\$status score:\$score progress:\$progress progressVolumes:\$progressVolumes repeat:\$repeat private:\$private notes:\$notes customLists:\$customLists hiddenFromStatusLists:\$hiddenFromStatusLists advancedScores:\$advancedScores startedAt:\$startedAt completedAt:\$completedAt){id mediaId status score advancedScores progress progressVolumes repeat priority private hiddenFromStatusLists customLists notes updatedAt startedAt{year month day}completedAt{year month day}user{id name}media{id title{userPreferred}coverImage{large}type format status episodes volumes chapters averageScore popularity isAdult startDate{year}}}}\",\"variables\":{\"score\":$new_score,\"mediaId\":$media_id}}")
	if printf "%s" "$response" | grep -q "errors"; then
		send_notification "Failed to update score for $anime_title"
	else
		send_notification "New score: $new_score"
	fi
}

get_video_url_quality() {
	[ -z "$video_link" ] && video_link=$(printf "%s" "$episode_links" | tr "{|}" "\n" | sed -nE "s@\"url\":\"([^\"]*)\",\"quality\":\"$1\".*@\1@p")
}

get_episode_info() {
	anime_response=$(curl -s "https://api.consumet.org/meta/anilist/info/${media_id}?provider=${provider}" | tr "{|}" "\n")
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

get_episode_links() {
	episode_links=$(curl -s "https://api.consumet.org/meta/anilist/watch/${episode_id}?provider=${provider}")
	[ -z "$episode_links" ] && send_notification "Error: no links found for $anime_title episode $((progress + 1))/$episodes_total" "1000" && exit 1
	[ "$json_output" = "true" ] && printf "%s\n" "$episode_links" && exit 0

	[ "$((progress + 1))" -eq "$episodes_total" ] && status="COMPLETED" || status="CURRENT"
	send_notification "Watching $anime_title - Ep: $((progress + 1)) $episode_title"

	case $provider in
	zoro)
		# [ "$video_quality" = "best" ] && video_link=$(printf "%s" "$episode_links"|sed -nE "s@\{\"sources\":\[\{\"url\":\"([^\"]*)\",.*@\1@p")
		[ -z "$video_link" ] && get_video_url_quality "$video_quality"
		[ -z "$video_link" ] &&
			for quality in "1080p" "720p" "480p" "360p" "auto"; do
				get_video_url_quality "$quality"
				[ -n "$video_link" ] && break
			done
		[ -z "$video_link" ] && provider="gogoanime" && send_notification "No video links found from zoro, trying gogoanime" && provider="gogoanime" && get_episode_info
		subs_links=$(printf "%s" "$episode_links" | tr "{|}" "\n" | tr "{|}" "\n" | sed -nE "s@\"url\":\"([^\"]*.vtt)\",\"lang\":\"$subs_language.*@\1@p" | sed -e "s/:/\\$path_thing:/g" -e "H;1h;\$!d;x;y/\n/$separator/" -e "s/$separator\$//")
		[ -z "$subs_links" ] && subs_links=$(printf "%s" "$episode_links" | tr "{|}" "\n" | tr "{|}" "\n" | sed -nE "s@\"url\":\"([^\"]*.vtt)\",\"lang\":\"English.*@\1@p" | sed -e "s/:/\\$path_thing:/g" -e "H;1h;\$!d;x;y/\n/$separator/" -e "s/$separator\$//")
		;;
	*)
		referrer=$(printf "%s" "$episode_links" | tr "{|}" "\n" | sed -nE "s@\"Referer\":\"([^\"]*)\"\$@\1@p")
		video_link=$(printf "%s" "$episode_links" | tr "{|}" "\n" | sed -nE "s@\"url\":\"([^\"]*)\".*\"quality\":\"1080p\"\$@\1@p")
		;;
	esac
}

play_video() {
	[ -f "$history_file" ] && history=$(grep -E "^$media_id" "$history_file")
	[ -n "$history" ] && resume_from=$(printf "%s" "$history" | cut -f2)
	[ -n "$resume_from" ] && [ "$resume_from" -gt 0 ] && [ -z "$incognito" ] && send_notification "Resuming from saved progress: $resume_from%"
	[ -z "$resume_from" ] && opts="" || opts="--start=${resume_from}%"
	[ -n "$incognito" ] && opts=""

	[ "$discord_presence" = "true" ] && launch_mpv="jerrydiscordpresence.py \"mpv\" \"${anime_title}\" \"$((progress + 1))\" \"${video_link}\" \"${subs_links}\" \"${referrer}\" \"${opts}\"" ||
		launch_mpv="mpv --fs --referrer=\"$referrer\" --sub-files=\"$subs_links\" --force-media-title=\"$anime_title - Ep: $((progress + 1)) $episode_title\" ${opts} \"$video_link\""

	stopped_at=$(eval "$launch_mpv" 2>&1 | grep AV | tail -n1 | sed -nE "s_.*AV: ([^ ]*) / ([^ ]*) \(([0-9]*)%\).*_\3_p" &)
	[ -n "$incognito" ] && exit 0
	[ -z "$stopped_at" ] && exit 0
	if [ "$stopped_at" -gt 85 ]; then
		response=$(update_episode "$progress" "$media_id" "$status")
		if printf "%s" "$response" | grep -q "errors"; then
			send_notification "Error updating progress"
		else
			send_notification "Updated progress to $((progress + 1))/$episodes_total episodes watched"
			[ -n "$history" ] && sed -i "/^$media_id/d" "$history_file"
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
	[ -z "$video_link" ] && send_notification "Error: $query not found" && exit 1
	[ -z "$video_link" ] && send_notification "Error: no video link found for $anime_title episode $((progress + 1))/$episodes_total" "1000" && exit 1
	play_video
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
	-c | --continue) choice="Watch" && shift ;;
	-d | --discord) discord_presence="true" && shift ;;
	-D | --dmenu) use_external_menu="1" && shift ;;
	-e | --edit) [ -f "$config_file" ] && "$jerry_editor" "$config_file" && exit 0 || echo "$default_config" >"$config_file" && "$jerry_editor" "$config_file" && exit 0 ;;
	-h | --help) usage && exit 0 ;;
	-i | --incognito) incognito="true" && shift ;;
	-j | --json) json_output="true" && incognito="true" && shift ;;
	-l | --language) subs_language="$2" && shift 2 ;;
	-n | --number) progress=$(($2 - 1)) && shift 2 ;;
	-p | --provider) preferred_provider="$2" && shift 2 ;;
	-q | --quality) video_quality="$2" && shift 2 ;;
	-u | --update) update_script ;;
	-v | --version) printf "Jerry Version: %s\n" "$JERRY_VERSION" && exit 0 ;;
	*) query="$(printf "%s" "$query $1" | sed "s/^ //;s/ /+/g")" && shift && choice="Watch New" ;;
	esac
done

[ "$incognito" = "true" ] || check_credentials
configuration
[ "$(printf "%s" "$subs_language" | head -c 1)" = "$(printf "%s" "$subs_language" | head -c 1 | tr '[:upper:]' '[:lower:]')" ] && subs_language="$(printf "%s" "$subs_language" | head -c 1 | tr '[:lower:]' '[:upper:]')$(printf "%s" "$subs_language" | tail -c +2)"

[ -z "$choice" ] && choice=$(printf "Watch\nUpdate\nInfo\nWatch New" | launcher "Choose an option: ")
case "$choice" in
"Watch")
	get_anime_from_list "CURRENT"
	[ -z "$anime_title" ] && exit 0
	send_notification "Loading $anime_title..." "1000"
	query="$anime_title"
	watch_anime
	;;
"Update")
	update_choice=$(printf "Change Episodes Watched\nChange Status\nChange Score" | launcher "Choose an option: ")
	case "$update_choice" in
	"Change Episodes Watched") update_episode_from_list ;;
	"Change Status") update_status ;;
	"Change Score") update_score ;;
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
"Watch New")
	search_anime
	[ -z "$progress" ] && progress="0"
	send_notification "Disclaimer: you need to finish the first episode before you can update your progress" "5000"
	watch_anime
	;;
esac
