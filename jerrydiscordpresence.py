#!/usr/bin/env python3
import subprocess
import sys
import time

import httpx
from pypresence import Presence

CLIENT_ID = "1084791136981352558"
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
    opts,
    *_,
) = sys.argv


anime = http_client.get("edge/anime", params={"filter[text]": anime_name}).json()[
    "data"
]

if not anime:
    raise SystemExit()

media = anime[0]["attributes"]
media_title = "%s %s" % (media["canonicalTitle"], "- Episode "+episode_count)

if subtitle_stream != "":
    args = [
        mpv_executable,
        content_stream,
        f"--force-media-title={media_title}",
        f"--sub-files={subtitle_stream}",
        "--msg-level=ffmpeg/demuxer=error",
        f"{opts}",
    ]
else:
    args = [
        mpv_executable,
        content_stream,
        f"--force-media-title={media_title}",
        "--msg-level=ffmpeg/demuxer=error",
        f"{opts}",
    ]


process = subprocess.Popen(
    args
)

rpc_client.update(
    details="Watching anime",
    state=media_title,
    large_image=media["posterImage"]["original"],
    start=int(time.time()),
)

process.wait()
