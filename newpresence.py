#!/usr/bin/env python3
import subprocess
import sys
import re
import time

import httpx

import json
import os
import socket
import struct
from collections.abc import Mapping
from enum import IntEnum
from uuid import uuid4


CLIENT_ID = "1084791136981352558"
ENDPONT = "https://kitsu.io/api/"

class OpCode(IntEnum):
    HANDSHAKE = 0
    FRAME = 1
    CLOSE = 2

SOCKET_NAME = "discord-ipc-{}"

class Presence:
    def __init__(self, client_id: str) -> None:
        self.client_id = client_id
        self._connect()
        self._handshake()

    def set(self, activity: Mapping[str, object] | None) -> None:
        payload = {
            "cmd": "SET_ACTIVITY",
            "args": {
                "pid": os.getpid(),
                "activity": activity,
            },
            "nonce": str(uuid4()),
        }
        self._send(payload, OpCode.FRAME)

    def _connect(self) -> None:
        pipe = self._get_pipe()
        for i in range(10):
            try:
                self._try_socket(pipe, i)
                break
            except FileNotFoundError:
                pass
        else:
            raise Exception("Cannot find a socket to connect to Discord")

    def _get_pipe(self) -> str:
        for env in ("XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"):
            path = os.environ.get(env)
            if path is not None:
                return os.path.join(path, SOCKET_NAME)

        return os.path.join("/tmp/", SOCKET_NAME)

    def _try_socket(self, pipe: str, i: int) -> None:
        self._socket = socket.socket(socket.AF_UNIX)
        self._socket.connect(pipe.format(i))

    def _handshake(self) -> None:
        data = {
            "v": 1,
            "client_id": self.client_id,
        }
        self._send(data, OpCode.HANDSHAKE)
        _, response = self._read()


        if response.get("evt") != "READY":
            raise Exception("Discord returned an error response after a handshake request")

    def _read(self) -> tuple[int, Mapping[str, object]]:
        op, length = self._read_header()
        payload = self._read_bytes(length)
        decoded = payload.decode("utf-8")
        data = json.loads(decoded)
        return op, data

    def _read_header(self) -> tuple[int, int]:
        return struct.unpack("<ii", self._read_bytes(8))

    def _read_bytes(self, size: int) -> bytes:
        data = b""
        while size > 0:
            chunk = self._socket.recv(size)
            if not chunk:
                raise Exception("Connection closed before all bytes were read")

            data += chunk
            size -= len(chunk)

        return data

    def _send(self, payload: Mapping[str, object], op: OpCode) -> None:
        data_json = json.dumps(payload)
        encoded = data_json.encode("utf-8")
        header = struct.pack("<ii", int(op), len(encoded))
        self._write(header + encoded)

    def _write(self, data: bytes) -> None:
        self._socket.sendall(data)

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

file_path = '/tmp/jerry_position'

RPC = Presence(CLIENT_ID)

pattern = r'(\(Paused\)\s)?AV:\s([0-9:]*) / ([0-9:]*) \(([0-9]*)%\)'

while True:
    with open(file_path, 'r') as file:
        content = file.read()
    matches = re.findall(pattern, content)
    small_image = "https://cdn-icons-png.flaticon.com/128/3669/3669483.png"
    if matches:
        if matches[-1][0] == "(Paused) ":
            small_image = "https://cdn-icons-png.flaticon.com/128/3669/3669483.png"  # <- pause
            elapsed = matches[-1][1]
        else:
            small_image = "https://cdn-icons-png.flaticon.com/128/5577/5577228.png"  # <- play
            elapsed = matches[-1][1]
        duration = matches[-1][2]
        position = f"{elapsed} / {duration}"
    else:
        position = "00:00:00"

    # print(position)

    activity = {
        "details": anime_name,
        "state": position,
        "assets": {
            "large_image": media["posterImage"]["original"],
            "large_text": anime_name,
            "small_image": small_image,
            "small_text": "Jerry",
        },
        "buttons": [
            {
                "label": "Github",
                "url": "https://github.com/justchokingaround/jerry"
            }, 
            {
                "label": "Discord",
                "url": "https://discord.gg/4P2DaJFxbm",
            }
        ],
    }

    RPC.set(activity=activity)

    if process.poll() is not None:
        break

process.wait()
