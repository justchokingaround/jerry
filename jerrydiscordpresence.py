#!/usr/bin/env python3
import subprocess
import sys
import time

import httpx
from pypresence import Presence

# id of ani-cli as title
# CLIENT_ID = "963136145691140097"
CLIENT_ID = "995856834558689410"
ENDPONT = "https://kitsu.io/api/"

rpc_client = Presence(CLIENT_ID)
rpc_client.connect()

http_client = httpx.Client(base_url=ENDPONT)


(
    _,
    mpv_executable,
    anime_name,
    episode_count,
    content_stream,
    subtitle_stream,
    referrer,
    opts,
    *_,
) = sys.argv


anime = http_client.get("edge/anime", params={"filter[text]": anime_name}).json()[
    "data"
]

if not anime:
    raise SystemExit()

media = anime[0]["attributes"]
media_title = "%s %s" % (media["canonicalTitle"], "Episode "+episode_count)

process = subprocess.Popen(
    args=[
        mpv_executable,
        content_stream,
        f"--fs",
        f"--force-media-title={media_title}",
        f"--sub-files={subtitle_stream}",
        f"--referrer={referrer}",
        f"{opts}",
    ]
)

rpc_client.update(
    details="Watching anime",
    state=media_title,
    large_image=media["posterImage"]["original"],
    start=int(time.time()),
)

process.wait()
