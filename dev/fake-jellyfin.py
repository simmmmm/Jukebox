#!/usr/bin/env python3
"""A fake Jellyfin for the screenshots: serves the demo library that
dev/record-demo.py recorded from the test server (dev/demo/) to the app in
the iOS Simulator on CI, where there is no Docker and so no real Jellyfin.

    python3 dev/fake-jellyfin.py --port 8096 --data dev/demo
    python3 dev/fake-jellyfin.py --song-lengths    2:30–5:30 songs, for the pictures

Python's standard library only, Python 3.9 or later: the macOS runner has
python3 and no packages.

It answers every route JukeboxKit's JellyfinClient uses, the way Jellyfin
12.4 does where the client depends on it (each measured on the test server;
the client's own comments say how): filters, sorts and pages as /Items does;
only the fields asked for; the play count going up at the start report; the
user's favourites and playlists changing, in memory, until it stops; images
by id at any size; the audio with byte ranges, as AVPlayer asks for it.
Signing in takes the recorded user's name with the password ("test"); Quick
Connect is off. A route it does not know is logged as UNKNOWN ROUTE and
answered 404, so what is missing shows in the log.

The sign-in screen asks every address both ways at once (JukeboxKit's
MusicServers.detect): Jellyfin's /System/Info/Public and Subsonic's
/rest/ping.view. The fake answers the second as Jellyfin 12.4 does, measured
on the test server: 404 with no body, which the kit reads as "not a Subsonic
server", so the Jellyfin answer wins. It is a known route, not an UNKNOWN one.

Deliberately unlike Jellyfin:
- Any token is taken until it is signed out, not only the ones it gave: the
  UI tests may sign in with a token of their own, and a restarted fake keeps
  the app signed in.
- Every track plays one of four 8-second AAC clips, looped to the length the
  track says (Clip, below), and nothing is transcoded: a bitrate limit gets
  the same file, never HLS.
- Images are 600×600 whatever size is asked.
- Dates move with the clock: the library is as fresh as the day it was
  recorded (things played "yesterday" stay yesterday).
"""
import argparse
import errno
import functools
import hashlib
import json
import os
import random
import re
import socket
import struct
import sys
import threading
import time
import traceback
import unicodedata
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qsl, unquote, urlsplit

TICKS = 10_000_000


def log(line):
    print(time.strftime("%H:%M:%S ") + line, flush=True)


# ---------------------------------------------------------------------------
# Dates, as Jellyfin writes them: seven fractional digits and a Z.

def parse_date(text):
    text = text.rstrip("Z")
    if "." in text:
        head, fraction = text.split(".", 1)
        text = head + "." + (fraction + "000000")[:6]
    return datetime.fromisoformat(text).replace(tzinfo=timezone.utc)


def format_date(moment):
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.") + "%06d0Z" % moment.microsecond


def now_date():
    return format_date(datetime.now(timezone.utc))


def shifted(text, delta):
    # Year 1 is Jellyfin's "never" (DateLastMediaAdded): left alone.
    if not text or not text.startswith(("19", "20")):
        return text
    return format_date(parse_date(text) + delta)


def norm(item_id):
    """Jellyfin takes ids with and without dashes, in any case."""
    return (item_id or "").replace("-", "").lower()


def fold(text):
    """For comparing names: no case, no accents."""
    text = unicodedata.normalize("NFKD", text or "")
    return "".join(c for c in text if not unicodedata.combining(c)).lower()


class Query:
    """The query string; names in any case, as ASP.NET binds them."""

    def __init__(self, raw):
        self.raw = raw
        self.values = {}
        for key, value in parse_qsl(raw, keep_blank_values=True):
            self.values.setdefault(key.lower(), []).append(value)

    def get(self, name, default=None):
        values = self.values.get(name.lower())
        return values[-1] if values else default

    def list(self, name, sep=","):
        out = []
        for value in self.values.get(name.lower(), []):
            out += [part.strip() for part in value.split(sep) if part.strip()]
        return out

    def flag(self, name):
        value = self.get(name)
        return None if value is None else value.lower() == "true"

    def number(self, name, default=None):
        try:
            return int(self.get(name))
        except (TypeError, ValueError):
            return default


class HTTPError(Exception):
    def __init__(self, status, detail=None):
        super().__init__(detail)
        self.status = status
        self.detail = detail


# ---------------------------------------------------------------------------
# The audio: an 8-second clip, as long as the track says

# MP4 boxes that hold other boxes, on the way to the sample tables.
CONTAINERS = {b"moov", b"trak", b"mdia", b"minf", b"stbl", b"edts"}


def parse_boxes(data, start, end):
    """[[type, payload]], a container's payload parsed in turn."""
    out = []
    while start < end:
        size, kind = struct.unpack(">I4s", data[start:start + 8])
        if size < 8 or start + size > end:
            raise ValueError("a box the fake does not read: %r" % kind)
        body = data[start + 8:start + size]
        out.append([kind, parse_boxes(data, start + 8, start + size) if kind in CONTAINERS else body])
        start += size
    return out


def build_boxes(tree):
    out = []
    for kind, body in tree:
        payload = build_boxes(body) if isinstance(body, list) else body
        out.append(struct.pack(">I4s", 8 + len(payload), kind) + payload)
    return b"".join(out)


def find_box(tree, *path):
    """The entry [type, payload] at the path of types."""
    for entry in tree:
        if entry[0] == path[0]:
            return entry if len(path) == 1 else find_box(entry[1], *path[1:])
    raise KeyError(path)


class Clip:
    """One of the demo's clips, served as long as the track it stands for.

    Why: a song that says 3:42 (--song-lengths) but ends after 8 s is, to
    the app, a skip (PlayOutcome: under 30 s heard of a long song), so the
    radio would learn from skips the listener never made, Now Playing's
    scrubber would read 0:08 (it takes the length AVPlayer finds in the
    file), and the queue would move on every 8 s while the screenshot walk
    is taking its pictures.

    How: the clip's AAC frames, repeated, in a new MP4 of the same shape as
    the one ffmpeg wrote (one track, one chunk, the encoder's 1024 priming
    samples skipped by the edit list, a roll group over every sample). The
    first frame primes the decoder once; frames 1 to the last full one then
    loop, so the first 8 s are the clip's own bytes and each seam is a fade
    out meeting a fade in. The sample tables and the durations are written
    for the new length; nothing is re-encoded. A clip in another shape is
    served as it is, 8 s, and the log says why.
    """

    def __init__(self, name, data):
        self.name = name
        self.data = data
        try:
            self.read()
            self.ok = True
        except (KeyError, ValueError, struct.error) as error:
            log(f"audio/{name}.m4a is served as it is, 8 s whatever the track says: {error}")
            self.ok = False

    def read(self):
        tree = parse_boxes(self.data, 0, len(self.data))
        moov = find_box(tree, b"moov")[1]
        if len([e for e in moov if e[0] == b"trak"]) != 1:
            raise ValueError("not one track")
        # Version 0 of each: their durations are 32 bits at the offsets file() writes.
        for path in ((b"mvhd",), (b"trak", b"tkhd"), (b"trak", b"mdia", b"mdhd")):
            if find_box(moov, *path)[1][0] != 0:
                raise ValueError("%s is not version 0" % path[-1].decode())
        stbl = find_box(moov, b"trak", b"mdia", b"minf", b"stbl")[1]
        self.rate = struct.unpack(">I", find_box(moov, b"trak", b"mdia", b"mdhd")[1][12:16])[0]
        elst = find_box(moov, b"trak", b"edts", b"elst")[1]
        if elst[0] != 0 or struct.unpack(">I", elst[4:8])[0] != 1:
            raise ValueError("not one version-0 edit")
        self.priming = struct.unpack(">i", elst[12:16])[0]
        stts = find_box(stbl, b"stts")[1]
        deltas = []
        for k in range(struct.unpack(">I", stts[4:8])[0]):
            count, delta = struct.unpack(">II", stts[8 + 8 * k:16 + 8 * k])
            deltas += [delta] * count
        stsz = find_box(stbl, b"stsz")[1]
        fixed, count = struct.unpack(">II", stsz[4:12])
        sizes = [fixed] * count if fixed else list(struct.unpack(">%dI" % count, stsz[12:12 + 4 * count]))
        stsc = find_box(stbl, b"stsc")[1]
        stco = find_box(stbl, b"stco")[1]
        if struct.unpack(">I", stsc[4:8])[0] != 1 or struct.unpack(">I", stco[4:8])[0] != 1 \
                or struct.unpack(">I", stsc[12:16])[0] != count or len(deltas) != count:
            raise ValueError("not one chunk of every sample")
        offset = struct.unpack(">I", stco[8:12])[0]
        self.frame = deltas[0]
        self.frames = []
        for size in sizes:
            self.frames.append(self.data[offset:offset + size])
            offset += size
        # Frame 0 is the priming; the loop is 1 … the last of full length.
        self.loop = 1
        while self.loop < count and deltas[self.loop] == self.frame:
            self.loop += 1
        if self.priming != self.frame or self.loop < 2:
            raise ValueError("priming of %d samples, %d full frames" % (self.priming, self.loop - 1))
        # One group over every sample, as ffmpeg writes it for AAC, or none.
        sbgp = next((e[1] for e in stbl if e[0] == b"sbgp"), None)
        if sbgp is not None and (sbgp[0] != 0 or struct.unpack(">I", sbgp[8:12])[0] != 1):
            raise ValueError("a sample group of another shape")
        self.tree = tree

    @functools.lru_cache(maxsize=8)
    def file(self, seconds):
        """The MP4 for a track of `seconds` (whole seconds are enough: the
        app shows minutes and seconds); the clip as it is if that fails."""
        if not self.ok or seconds <= 0:
            return self.data
        try:
            return self.looped(seconds)
        except (KeyError, ValueError, struct.error) as error:
            log(f"audio/{self.name}.m4a served as it is for {seconds} s: {error}")
            return self.data

    def looped(self, seconds):
        samples = seconds * self.rate
        needed = -(-samples // self.frame)
        order = [0] + [1 + k % (self.loop - 1) for k in range(needed)]
        frames = [self.frames[k] for k in order]
        movie_scale = struct.unpack(">I", find_box(self.tree, b"moov", b"mvhd")[1][12:16])[0]
        length = seconds * movie_scale

        # ftyp and moov ('free' and the old mdat left out), moov copied so the
        # clip's own tree stays as it is for the next length.
        tree = [[kind, copy_tree(body) if kind == b"moov" else body]
                for kind, body in self.tree if kind in (b"ftyp", b"moov")]
        moov = find_box(tree, b"moov")[1]

        def patch(path, at, value, fmt=">I"):
            entry = find_box(moov, *path)
            body = bytearray(entry[1])
            struct.pack_into(fmt, body, at, value)
            entry[1] = bytes(body)

        patch((b"mvhd",), 16, length)
        patch((b"trak", b"tkhd"), 20, length)
        patch((b"trak", b"edts", b"elst"), 8, length)
        patch((b"trak", b"mdia", b"mdhd"), 16, len(frames) * self.frame)
        stbl = find_box(moov, b"trak", b"mdia", b"minf", b"stbl")[1]
        find_box(stbl, b"stts")[1] = struct.pack(">IIII", 0, 1, len(frames), self.frame)
        find_box(stbl, b"stsc")[1] = struct.pack(">IIIII", 0, 1, 1, len(frames), 1)
        find_box(stbl, b"stsz")[1] = struct.pack(">III%dI" % len(frames), 0, 0, len(frames),
                                                 *[len(f) for f in frames])
        sbgp = next((e for e in stbl if e[0] == b"sbgp"), None)
        if sbgp is not None:
            # Its one entry now counts every sample (read() checked the shape).
            body = bytearray(sbgp[1])
            struct.pack_into(">I", body, 12, len(frames))
            sbgp[1] = bytes(body)
        stco = find_box(stbl, b"stco")
        stco[1] = struct.pack(">III", 0, 1, 0)
        head = build_boxes(tree)
        stco[1] = struct.pack(">III", 0, 1, len(head) + 8)
        head = build_boxes(tree)
        payload = b"".join(frames)
        return head + struct.pack(">I4s", 8 + len(payload), b"mdat") + payload


def copy_tree(tree):
    return [[kind, copy_tree(body) if isinstance(body, list) else body] for kind, body in tree]


# ---------------------------------------------------------------------------
# The library and what the user changes in it

class Library:
    def __init__(self, folder, song_lengths, seed, password):
        self.folder = folder
        self.password = password
        self.lock = threading.RLock()
        self.rng = random.Random(seed)
        with open(os.path.join(folder, "server.json"), encoding="utf-8") as f:
            server = json.load(f)
        with open(os.path.join(folder, "items.json"), encoding="utf-8") as f:
            items = json.load(f)["Items"]
        with open(os.path.join(folder, "relations.json"), encoding="utf-8") as f:
            relations = json.load(f)
        with open(os.path.join(folder, "lyrics.json"), encoding="utf-8") as f:
            self.lyrics = {norm(k): v for k, v in json.load(f).items()}

        delta = datetime.now(timezone.utc) - parse_date(server["recordedAt"])
        self.public = server["publicInfo"]
        self.server_id = self.public["Id"]
        self.user = server["user"]
        for key in ("LastLoginDate", "LastActivityDate"):
            if key in self.user:
                self.user[key] = shifted(self.user[key], delta)
        self.sign_in = server["signIn"]
        self.views = server["views"]
        self.template = server["playlistTemplate"]
        # {type: {field: [keys]}}: what each field adds, so what to leave out.
        self.fields = {kind: {f.lower(): keys for f, keys in fields.items()}
                       for kind, fields in server["fields"].items()}

        self.items = {}
        self.userdata = {}
        self.order = []
        for item in items:
            for key in ("DateCreated", "DateLastMediaAdded"):
                if key in item:
                    item[key] = shifted(item[key], delta)
            data = item.pop("UserData", None)
            if data is not None:
                if "LastPlayedDate" in data:
                    data["LastPlayedDate"] = shifted(data["LastPlayedDate"], delta)
                self.userdata[item["Id"]] = data
            self.items[item["Id"]] = item
            self.order.append(item["Id"])
        self.album_artists = set(relations["albumArtists"])
        self.similar = relations["similar"]
        self.entries = {k: list(v) for k, v in relations["playlists"].items()}
        self.audio = relations["audio"]
        self.tracks = [i for i in self.order if self.items[i]["Type"] == "Audio"]
        self.genre_ids = {self.items[i]["Name"]: i for i in self.order if self.items[i]["Type"] == "MusicGenre"}
        self.album_tracks = {}
        for track_id in self.tracks:
            self.album_tracks.setdefault(self.items[track_id].get("AlbumId"), []).append(track_id)
        if song_lengths:
            self.stretch()

        self.revoked = set()
        self.device_tokens = {}
        self.files = {}
        self.clips = {}
        # --clips-as-recorded: every track the 8-second clip itself.
        self.clips_as_recorded = False

    def stretch(self):
        """Song lengths a listener expects (2:30 to 5:30, by id) instead of
        the test library's 5 to 8 seconds, with the albums and artists summed
        again. The audio follows: each clip is looped to its track's length (Clip)."""
        for track_id in self.tracks:
            seconds = 150 + int(hashlib.md5(track_id.encode()).hexdigest()[:6], 16) % 181
            self.items[track_id]["RunTimeTicks"] = seconds * TICKS
        for item in self.items.values():
            if item["Type"] == "MusicAlbum":
                ticks = sum(self.items[t]["RunTimeTicks"] for t in self.album_tracks.get(item["Id"], []))
            elif item["Type"] == "MusicArtist":
                ticks = sum(self.items[t]["RunTimeTicks"] for t in self.tracks if self.by_artist(self.items[t], item["Id"]))
            else:
                continue
            for key in ("RunTimeTicks", "CumulativeRunTimeTicks"):
                if key in item:
                    item[key] = ticks
        for track_id, lyrics in self.lyrics.items():
            if track_id in self.items:
                lyrics["Metadata"]["Length"] = self.items[track_id]["RunTimeTicks"]

    @staticmethod
    def by_artist(item, artist_id):
        refs = (item.get("ArtistItems") or []) + (item.get("AlbumArtists") or [])
        return any(norm(r.get("Id")) == artist_id for r in refs)

    # --- tokens

    def issue_token(self, device_id):
        token = uuid.uuid4().hex
        # Signing in again from the same device signs its old token out, as on 12.4.
        old = self.device_tokens.get(device_id)
        if old:
            self.revoked.add(old)
        self.device_tokens[device_id] = token
        return token

    def valid(self, token):
        return bool(token) and token not in self.revoked

    # --- items as Jellyfin sends them

    def shape(self, item, fields, user_data=True, entry=False):
        kind = item["Type"]
        gated = self.fields.get(kind, {})
        keep = set()
        for field in fields:
            keep.update(gated.get(field, []))
        drop = set(k for keys in gated.values() for k in keys) - keep
        out = {"Name": item["Name"], "ServerId": self.server_id}
        for key, value in item.items():
            if key == "Name" or key in drop:
                continue
            out[key] = value
            if key == "Id" and entry:
                # On 12.4 a playlist entry's id is the track's own.
                out["PlaylistItemId"] = item["Id"]
        if kind == "Playlist":
            entries = self.entries.get(item["Id"], [])
            ticks = sum(self.items[t].get("RunTimeTicks") or 0 for t in entries if t in self.items)
            for key, value in (("ChildCount", len(entries)), ("RunTimeTicks", ticks), ("CumulativeRunTimeTicks", ticks)):
                if key in out:
                    out[key] = value
        if user_data and item["Id"] in self.userdata:
            out["UserData"] = self.userdata_dto(item["Id"])
        return out

    def userdata_dto(self, item_id):
        data = self.userdata[item_id]
        out = {"PlaybackPositionTicks": data.get("PlaybackPositionTicks", 0), "PlayCount": data.get("PlayCount", 0),
               "IsFavorite": bool(data.get("IsFavorite"))}
        if data.get("LastPlayedDate"):
            out["LastPlayedDate"] = data["LastPlayedDate"]
        out.update({"Played": bool(data.get("Played")), "Key": data.get("Key", item_id), "ItemId": item_id})
        return out

    def page(self, pool, q, entry=False):
        start = max(0, q.number("StartIndex", 0) or 0)
        limit = q.number("Limit")
        chosen = pool[start:] if limit is None else pool[start:start + max(0, limit)]
        fields = {f.lower() for f in q.list("Fields")}
        user_data = q.flag("EnableUserData") is not False
        return {"Items": [self.shape(i, fields, user_data, entry) for i in chosen],
                "TotalRecordCount": len(pool), "StartIndex": start}

    # --- /Items and friends: the pool, then filters, then order

    def pool(self, scope, q):
        ids = [norm(i) for i in q.list("Ids")]
        if ids:
            return [self.items[i] for i in ids if i in self.items], "ids"
        if scope == "albumartists":
            return [self.items[i] for i in self.order if i in self.album_artists], "list"
        if scope == "artists":
            return [self.items[i] for i in self.order if self.items[i]["Type"] == "MusicArtist"], "list"
        if scope == "genres":
            return [self.items[i] for i in self.order if self.items[i]["Type"] == "MusicGenre"], "list"
        parent = norm(q.get("ParentId"))
        include = {t.lower() for t in q.list("IncludeItemTypes")}
        if parent:
            if parent in self.entries:
                return [self.items[t] for t in self.entries[parent] if t in self.items], "playlist"
            item = self.items.get(parent)
            if item and item["Type"] == "MusicAlbum":
                return [self.items[t] for t in self.album_tracks.get(parent, [])], "list"
            if item and item["Type"] == "MusicArtist":
                return [self.items[i] for i in self.order if self.items[i]["Type"] in ("MusicAlbum", "Audio")
                        and self.by_artist(self.items[i], parent)], "list"
            if item and item["Type"] == "MusicGenre":
                return [self.items[i] for i in self.order if item["Name"] in (self.items[i].get("Genres") or [])
                        and self.items[i]["Type"] in ("MusicAlbum", "Audio")], "list"
            view = next((v for v in self.views if norm(v["Id"]) == parent), None)
            if view and view.get("CollectionType") == "playlists":
                return [self.items[i] for i in self.order if self.items[i]["Type"] == "Playlist"], "list"
            if view:
                return [self.items[i] for i in self.order if self.items[i]["Type"] in ("MusicAlbum", "Audio")
                        or self.items[i]["Type"].lower() in include], "list"
            return [], "list"
        if q.flag("Recursive"):
            # Artists and genres are not in the folders: only when asked for by type.
            return [self.items[i] for i in self.order
                    if self.items[i]["Type"] not in ("MusicArtist", "MusicGenre")
                    or self.items[i]["Type"].lower() in include], "list"
        return list(self.views), "views"

    def query(self, scope, q):
        pool, context = self.pool(scope, q)
        if context == "views":
            return {"Items": [dict(v, ServerId=self.server_id) for v in pool], "TotalRecordCount": len(pool),
                    "StartIndex": 0}
        include = {t.lower() for t in q.list("IncludeItemTypes")}
        exclude = {t.lower() for t in q.list("ExcludeItemTypes")}
        media = {t.lower() for t in q.list("MediaTypes")}
        if include:
            pool = [i for i in pool if i["Type"].lower() in include]
        if exclude:
            pool = [i for i in pool if i["Type"].lower() not in exclude]
        if media:
            pool = [i for i in pool if (i.get("MediaType") or "").lower() in media]
        for name in ("ArtistIds", "AlbumArtistIds", "ContributingArtistIds"):
            wanted = {norm(i) for i in q.list(name)}
            if not wanted:
                continue
            def refs(item, name=name):
                if name == "AlbumArtistIds":
                    found = item.get("AlbumArtists") or []
                elif name == "ContributingArtistIds":
                    album = {norm(r.get("Id")) for r in item.get("AlbumArtists") or []}
                    found = [r for r in item.get("ArtistItems") or [] if norm(r.get("Id")) not in album]
                else:
                    found = (item.get("ArtistItems") or []) + (item.get("AlbumArtists") or [])
                return {norm(r.get("Id")) for r in found}
            pool = [i for i in pool if refs(i) & wanted]
        albums = {norm(i) for i in q.list("AlbumIds")}
        if albums:
            pool = [i for i in pool if norm(i.get("AlbumId")) in albums]
        genres = {fold(g) for g in q.list("Genres", sep="|")}
        genres |= {fold(self.items[norm(g)]["Name"]) for g in q.list("GenreIds") if norm(g) in self.items}
        if genres:
            pool = [i for i in pool if genres & {fold(g) for g in i.get("Genres") or []}]
        years = {int(y) for y in q.list("Years") if y.isdigit()}
        if years:
            pool = [i for i in pool if i.get("ProductionYear") in years]
        filters = {f.lower() for f in q.list("Filters")}
        favourite = True if {"isfavorite", "isfavoriteorlikes"} & filters else q.flag("IsFavorite")
        if favourite is not None:
            pool = [i for i in pool if bool(self.userdata.get(i["Id"], {}).get("IsFavorite")) == favourite]
        played = True if "isplayed" in filters else False if "isunplayed" in filters else q.flag("IsPlayed")
        if played is not None:
            pool = [i for i in pool if bool(self.userdata.get(i["Id"], {}).get("Played")) == played]
        starts = q.get("NameStartsWith")
        if starts:
            pool = [i for i in pool if fold(i.get("SortName") or i["Name"]).startswith(fold(starts))]
        term = (q.get("SearchTerm") or "").strip()
        if term:
            # Matched in the name only, ordered by relevance whatever SortBy
            # says (both measured on 12.4: tracks are not found by artist).
            t = fold(term)
            pool = [i for i in pool if t in fold(i["Name"])]
            pool.sort(key=lambda i: (self.relevance(i, t), fold(i.get("SortName") or i["Name"])))
        else:
            pool = self.sorted(pool, q, context)
        return self.page(pool, q, entry=context == "playlist")

    @staticmethod
    def relevance(item, term):
        name = fold(item["Name"])
        if name == term:
            return 0
        if name.startswith(term):
            return 1
        if any(word.startswith(term) for word in name.split()):
            return 2
        return 3

    def sort_key(self, key):
        data = self.userdata
        keys = {
            "sortname": lambda i: fold(i.get("SortName") or i["Name"]),
            "name": lambda i: fold(i["Name"]),
            "albumartist": lambda i: fold(i.get("AlbumArtist") or ""),
            "artist": lambda i: fold((i.get("Artists") or [""])[0]),
            "album": lambda i: fold(i.get("Album") or ""),
            "productionyear": lambda i: i.get("ProductionYear") or 0,
            "premieredate": lambda i: i.get("PremiereDate") or "",
            "datecreated": lambda i: i.get("DateCreated") or "",
            "dateplayed": lambda i: data.get(i["Id"], {}).get("LastPlayedDate") or "",
            "datelastcontentadded": lambda i: i.get("DateCreated") or "",
            "playcount": lambda i: data.get(i["Id"], {}).get("PlayCount", 0),
            "isfavoriteorliked": lambda i: bool(data.get(i["Id"], {}).get("IsFavorite")),
            "indexnumber": lambda i: i.get("IndexNumber") or 0,
            "parentindexnumber": lambda i: i.get("ParentIndexNumber") or 0,
            "runtime": lambda i: i.get("RunTimeTicks") or 0,
            "childcount": lambda i: i.get("ChildCount") or 0,
        }
        return keys.get(key.lower())

    def sorted(self, pool, q, context):
        keys = q.list("SortBy")
        orders = [o.lower() for o in q.list("SortOrder")]
        if not keys:
            # Ids in the order asked; a playlist in its own; the rest by name.
            if context in ("ids", "playlist"):
                return pool
            keys = ["SortName"]
        if any(k.lower() == "random" for k in keys):
            pool = list(pool)
            self.rng.shuffle(pool)
            return pool
        pool = list(pool)
        # One SortOrder applies to every key; several go one for one (12.4).
        for n in range(len(keys) - 1, -1, -1):
            key = self.sort_key(keys[n])
            if key is None:
                log(f"  (SortBy {keys[n]} is not known to the fake: ignored)")
                continue
            order = orders[0] if len(orders) == 1 else orders[n] if n < len(orders) else "ascending"
            pool.sort(key=key, reverse=order == "descending")
        return pool

    def instant_mix(self, seed_id, q):
        """The seed's genres, shuffled; a track's mix starts with the track
        (12.4 does both: an artist's mix was all 23 tracks of its genre)."""
        seed = self.items.get(seed_id)
        if seed is None:
            raise HTTPError(404)
        first = []
        if seed["Type"] == "Audio":
            genres = set(seed.get("Genres") or [])
            first = [seed]
        elif seed["Type"] == "MusicGenre":
            genres = {seed["Name"]}
        elif seed["Type"] == "Playlist":
            genres = {g for t in self.entries.get(seed_id, []) for g in self.items[t].get("Genres") or []}
        else:
            genres = set(seed.get("Genres") or [])
        rest = [self.items[t] for t in self.tracks if t != seed_id and genres & set(self.items[t].get("Genres") or [])]
        self.rng.shuffle(rest)
        mix = (first + rest)[:max(1, q.number("Limit", 200) or 200)]
        fields = {f.lower() for f in q.list("Fields")}
        return {"Items": [self.shape(i, fields) for i in mix], "TotalRecordCount": len(mix), "StartIndex": 0}

    def similar_to(self, item_id, q):
        """The server's own answer for an album artist (recorded); for
        anything else, items of its kind sharing a genre, as 12.4 does."""
        item = self.items.get(item_id)
        if item is None:
            raise HTTPError(404)
        if item_id in self.similar:
            found = [self.items[i] for i in self.similar[item_id] if i in self.items]
        else:
            genres = set(item.get("Genres") or [])
            found = [self.items[i] for i in self.order if i != item_id and self.items[i]["Type"] == item["Type"]
                     and genres & set(self.items[i].get("Genres") or [])]
        found = found[:max(1, q.number("Limit", 50) or 50)]
        fields = {f.lower() for f in q.list("Fields")}
        return {"Items": [self.shape(i, fields) for i in found], "TotalRecordCount": len(found), "StartIndex": 0}

    def search_hints(self, q):
        term = fold((q.get("SearchTerm") or "").strip())
        if not term:
            return {"SearchHints": [], "TotalRecordCount": 0}
        kinds = {t.lower() for t in q.list("IncludeItemTypes")}
        found = [self.items[i] for i in self.order if term in fold(self.items[i]["Name"])
                 and (not kinds or self.items[i]["Type"].lower() in kinds)]
        found.sort(key=lambda i: (self.relevance(i, term), fold(i.get("SortName") or i["Name"])))
        total = len(found)
        start = max(0, q.number("StartIndex", 0) or 0)
        limit = q.number("Limit")
        found = found[start:] if limit is None else found[start:start + limit]
        hints = []
        for item in found:
            hint = {"ItemId": item["Id"], "Id": item["Id"], "Name": item["Name"]}
            for key in ("IndexNumber", "ProductionYear", "ParentIndexNumber"):
                if key in item:
                    hint[key] = item[key]
            primary = (item.get("ImageTags") or {}).get("Primary")
            if primary:
                hint["PrimaryImageTag"] = primary
            hint.update({"Type": item["Type"], "RunTimeTicks": item.get("RunTimeTicks"),
                         "MediaType": item.get("MediaType", "Unknown")})
            for key in ("Album", "AlbumId", "AlbumArtist", "Artists"):
                if key in item:
                    hint[key] = item[key]
            hint["ChannelId"] = None
            hints.append(hint)
        return {"SearchHints": hints, "TotalRecordCount": total}

    # --- changes

    def create_playlist(self, name, ids):
        ident = uuid.uuid4().hex
        item = json.loads(json.dumps(self.template))
        old = item["Name"]
        item["Name"] = name
        item["Id"] = ident
        if "SortName" in item:
            item["SortName"] = name.lower()
        if "Path" in item:
            item["Path"] = item["Path"].replace(old, name)
        if "DateCreated" in item:
            item["DateCreated"] = now_date()
        item["ImageTags"] = {}
        self.items[ident] = item
        self.order.append(ident)
        self.userdata[ident] = {"PlaybackPositionTicks": 0, "PlayCount": 0, "IsFavorite": False, "Played": False,
                                "Key": str(uuid.UUID(ident)), "ItemId": ident}
        self.entries[ident] = [norm(i) for i in ids if norm(i) in self.items]
        return ident

    def favourite(self, item_id, value):
        if item_id not in self.items:
            raise HTTPError(404)
        data = self.userdata.setdefault(item_id, {"PlaybackPositionTicks": 0, "PlayCount": 0, "Played": False,
                                                  "Key": item_id, "ItemId": item_id})
        data["IsFavorite"] = value
        return self.userdata_dto(item_id)

    def played(self, item_id, value):
        if item_id not in self.items:
            raise HTTPError(404)
        data = self.userdata.setdefault(item_id, {"PlaybackPositionTicks": 0, "PlayCount": 0, "IsFavorite": False,
                                                  "Key": item_id, "ItemId": item_id})
        data["Played"] = value
        if value:
            data["PlayCount"] = max(1, data.get("PlayCount", 0))
            data["LastPlayedDate"] = now_date()
        return self.userdata_dto(item_id)

    def report(self, kind, body):
        """12.4, measured: the start report counts the play and sets the
        date; progress or a stop alone set the date and Played; a stop
        without PositionTicks counts one more."""
        item_id = norm((body or {}).get("ItemId"))
        data = self.userdata.get(item_id)
        if data is None:
            return
        data["LastPlayedDate"] = now_date()
        data["Played"] = True
        if kind == "start" or (kind == "stopped" and "PositionTicks" not in body):
            data["PlayCount"] = data.get("PlayCount", 0) + 1

    def file(self, path):
        if path not in self.files:
            with open(path, "rb") as f:
                self.files[path] = f.read()
        return self.files[path]

    def clip(self, name):
        with self.lock:
            if name not in self.clips:
                self.clips[name] = Clip(name, self.file(os.path.join(self.folder, "audio", name + ".m4a")))
            return self.clips[name]


# ---------------------------------------------------------------------------
# HTTP

def parse_authorization(value):
    """`MediaBrowser Client="…", Device="…", DeviceId="…", Version="…", Token="…"`,
    each value percent-encoded."""
    return {k.lower(): unquote(v) for k, v in re.findall(r'(\w+)="([^"]*)"', value or "")}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "FakeJellyfin/12.4"
    library = None  # set in main

    def log_message(self, *args):
        pass

    def do_GET(self):
        self.handle_request("GET")

    def do_HEAD(self):
        self.handle_request("HEAD")

    def do_POST(self):
        self.handle_request("POST")

    def do_DELETE(self):
        self.handle_request("DELETE")

    def do_PUT(self):
        self.handle_request("PUT")

    # --- plumbing

    def read_body(self):
        if self.headers.get("Transfer-Encoding", "").lower() == "chunked":
            data = b""
            while True:
                size = int(self.rfile.readline().strip() or b"0", 16)
                if size == 0:
                    self.rfile.readline()
                    return data
                data += self.rfile.read(size)
                self.rfile.readline()
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length) if length else b""

    def send(self, status, body=b"", content_type=None, headers=()):
        self.status = status
        self.send_response(status)
        if content_type:
            self.send_header("Content-Type", content_type)
        # A 204 has no length, as 12.4 (Kestrel) sends it and HTTP says.
        if status != 204:
            self.send_header("Content-Length", str(len(body)))
        for name, value in headers:
            self.send_header(name, value)
        self.end_headers()
        if self.command != "HEAD" and body:
            self.wfile.write(body)
        self.sent = len(body)

    def send_json(self, value, status=200):
        self.send(status, json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode(),
                  "application/json; charset=utf-8")

    def send_problem(self, status, detail=None):
        titles = {400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found",
                  405: "Method Not Allowed", 416: "Range Not Satisfiable", 500: "Internal Server Error"}
        if status == 401 and detail is None:
            # 12.4 answers a missing or dead token with an empty 401.
            return self.send(401)
        problem = {"type": "https://tools.ietf.org/html/rfc9110", "title": titles.get(status, "Error"),
                   "status": status}
        if detail:
            problem["detail"] = detail
        self.send(status, json.dumps(problem).encode(), "application/problem+json; charset=utf-8")

    def token(self, q):
        for name in ("Authorization", "X-Emby-Authorization"):
            token = parse_authorization(self.headers.get(name)).get("token")
            if token:
                return token
        for name in ("X-Emby-Token", "X-MediaBrowser-Token"):
            if self.headers.get(name):
                return self.headers.get(name)
        # ApiKey in the URL, as AVPlayer's requests carry it; 12.4 refuses api_key.
        return q.get("ApiKey")

    def require(self, q):
        if not self.library.valid(self.token(q)):
            raise HTTPError(401)

    def handle_request(self, method):
        started = time.monotonic()
        url = urlsplit(self.path)
        path = re.sub(r"/{2,}", "/", url.path).rstrip("/") or "/"
        q = Query(url.query)
        self.status, self.sent = 0, 0
        known = True
        try:
            self.body = self.read_body()
            handler, args, allowed = self.match(method, path)
            if handler is None:
                if allowed:
                    raise HTTPError(405)
                known = False
                raise HTTPError(404)
            handler(self, q, *args)
        except HTTPError as error:
            try:
                self.send_problem(error.status, error.detail)
            except (BrokenPipeError, ConnectionResetError):
                pass
        except (BrokenPipeError, ConnectionResetError):
            # AVPlayer drops connections it no longer needs.
            self.status = self.status or "dropped"
        except Exception:
            traceback.print_exc()
            try:
                self.send_problem(500, "the fake failed: see its log")
            except (BrokenPipeError, ConnectionResetError):
                pass
        shown = path + ("?" + url.query if url.query else "")
        if len(shown) > 300:
            shown = shown[:300] + "…"
        ms = (time.monotonic() - started) * 1000
        prefix = "" if known else "UNKNOWN ROUTE "
        log(f"{prefix}{method} {shown} → {self.status} ({self.sent} B, {ms:.1f} ms)")

    def match(self, method, path):
        allowed = False
        for methods, pattern, handler in ROUTES:
            found = pattern.match(path)
            if found:
                if method in methods or (method == "HEAD" and "GET" in methods):
                    return handler, [unquote(g) if g else g for g in found.groups()], True
                allowed = True
        return None, [], allowed

    # --- routes

    def public_info(self, q):
        info = dict(self.library.public)
        host = self.headers.get("Host")
        if host:
            info = {"LocalAddress": f"http://{host}", **info}
        self.send_json(info)

    def ping(self, q):
        self.send_json("Jellyfin Server")

    def authenticate(self, q):
        lib = self.library
        try:
            body = json.loads(self.body or b"{}")
        except ValueError:
            raise HTTPError(400, "the body is not JSON")
        name = (body.get("Username") or "").strip()
        if name.lower() != lib.user["Name"].lower() or (body.get("Pw") or "") != lib.password:
            # As 12.4: 401 with a line of text.
            return self.send(401, b"Error processing request.", "text/plain; charset=utf-8")
        header = parse_authorization(self.headers.get("Authorization") or self.headers.get("X-Emby-Authorization"))
        with lib.lock:
            token = lib.issue_token(header.get("deviceid", ""))
            answer = json.loads(json.dumps(lib.sign_in))
            stamp = now_date()
            lib.user["LastLoginDate"] = lib.user["LastActivityDate"] = stamp
            answer["User"] = lib.user
            answer["AccessToken"] = token
            answer["ServerId"] = lib.server_id
            session = answer.get("SessionInfo") or {}
            for key, value in (("Client", header.get("client")), ("DeviceName", header.get("device")),
                               ("DeviceId", header.get("deviceid")), ("ApplicationVersion", header.get("version")),
                               ("UserId", lib.user["Id"]), ("UserName", lib.user["Name"]),
                               ("LastActivityDate", stamp), ("Id", uuid.uuid4().hex)):
                if key in session and value is not None:
                    session[key] = value
        self.send_json(answer)

    def logout(self, q):
        token = self.token(q)
        with self.library.lock:
            if token:
                self.library.revoked.add(token)
        self.send(204)

    def not_subsonic(self, q, *args):
        # As 12.4 answers a Subsonic client's /rest/…: 404, no body.
        self.send(404)

    def quick_enabled(self, q):
        self.send_json(False)

    def quick_disabled(self, q, *args):
        raise HTTPError(401, "Quick connect is disabled")

    def me(self, q, user_id=None):
        self.require(q)
        if user_id and norm(user_id) != self.library.user["Id"]:
            raise HTTPError(404)
        self.send_json(self.library.user)

    def user_views(self, q, *args):
        self.require(q)
        lib = self.library
        self.send_json({"Items": [dict(v, ServerId=lib.server_id) for v in lib.views],
                        "TotalRecordCount": len(lib.views), "StartIndex": 0})

    def items(self, q, *args):
        self.require(q)
        with self.library.lock:
            self.send_json(self.library.query("items", q))

    def album_artists(self, q):
        self.require(q)
        with self.library.lock:
            self.send_json(self.library.query("albumartists", q))

    def artists(self, q):
        self.require(q)
        with self.library.lock:
            self.send_json(self.library.query("artists", q))

    def genres(self, q):
        self.require(q)
        with self.library.lock:
            self.send_json(self.library.query("genres", q))

    def item(self, q, item_id):
        self.require(q)
        lib = self.library
        with lib.lock:
            item = lib.items.get(norm(item_id))
            if item is None:
                raise HTTPError(404)
            self.send_json(lib.shape(item, {f.lower() for f in q.list("Fields")}))

    def delete_item(self, q, item_id):
        self.require(q)
        lib = self.library
        item_id = norm(item_id)
        with lib.lock:
            item = lib.items.get(item_id)
            if item is None:
                raise HTTPError(404)
            if item["Type"] != "Playlist":
                raise HTTPError(403, "the fake deletes playlists only")
            del lib.items[item_id]
            lib.order.remove(item_id)
            lib.entries.pop(item_id, None)
            lib.userdata.pop(item_id, None)
        self.send(204)

    def similar(self, q, item_id):
        self.require(q)
        with self.library.lock:
            self.send_json(self.library.similar_to(norm(item_id), q))

    def instant_mix(self, q, item_id=None):
        self.require(q)
        with self.library.lock:
            self.send_json(self.library.instant_mix(norm(item_id or q.get("Id")), q))

    def search_hints(self, q):
        self.require(q)
        with self.library.lock:
            self.send_json(self.library.search_hints(q))

    def playlist_items(self, q, playlist_id):
        self.require(q)
        lib = self.library
        playlist_id = norm(playlist_id)
        with lib.lock:
            if playlist_id not in lib.entries:
                raise HTTPError(404)
            pool = [lib.items[t] for t in lib.entries[playlist_id] if t in lib.items]
            pool = lib.sorted(pool, q, "playlist")
            self.send_json(lib.page(pool, q, entry=True))

    def create_playlist(self, q):
        self.require(q)
        try:
            body = json.loads(self.body) if self.body else {}
        except ValueError:
            raise HTTPError(400, "the body is not JSON")
        name = body.get("Name") or q.get("Name") or "New Playlist"
        ids = body.get("Ids") or q.list("Ids")
        with self.library.lock:
            ident = self.library.create_playlist(name, ids)
        self.send_json({"Id": ident})

    def add_to_playlist(self, q, playlist_id):
        self.require(q)
        lib = self.library
        playlist_id = norm(playlist_id)
        with lib.lock:
            if playlist_id not in lib.entries:
                raise HTTPError(404)
            # At the end, in order; a track already there is there twice (12.4).
            lib.entries[playlist_id] += [norm(i) for i in q.list("Ids") if norm(i) in lib.items]
        self.send(204)

    def remove_from_playlist(self, q, playlist_id):
        self.require(q)
        lib = self.library
        playlist_id = norm(playlist_id)
        with lib.lock:
            if playlist_id not in lib.entries:
                raise HTTPError(404)
            # An entry id is the track's id, so every entry of that track goes;
            # an id the playlist does not have is ignored (12.4).
            gone = {norm(i) for i in q.list("EntryIds")}
            lib.entries[playlist_id] = [t for t in lib.entries[playlist_id] if t not in gone]
        self.send(204)

    def move_in_playlist(self, q, playlist_id, entry_id, index):
        self.require(q)
        lib = self.library
        playlist_id, entry_id = norm(playlist_id), norm(entry_id)
        with lib.lock:
            entries = lib.entries.get(playlist_id)
            if entries is None or entry_id not in entries:
                raise HTTPError(404)
            # The first entry of that id, taken out and put in at the index.
            entries.pop(entries.index(entry_id))
            entries.insert(min(max(0, int(index)), len(entries)), entry_id)
        self.send(204)

    def favourite(self, q, item_id):
        self.require(q)
        with self.library.lock:
            self.send_json(self.library.favourite(norm(item_id), self.command == "POST"))

    def played(self, q, item_id):
        self.require(q)
        with self.library.lock:
            self.send_json(self.library.played(norm(item_id), self.command == "POST"))

    def playing(self, q, kind=None):
        self.require(q)
        try:
            body = json.loads(self.body) if self.body else {}
        except ValueError:
            body = {}
        with self.library.lock:
            if kind is None:
                self.library.report("start", body)
            elif kind.lower() in ("progress", "stopped"):
                self.library.report(kind.lower(), body)
        self.send(204)

    def capabilities(self, q):
        self.require(q)
        self.send(204)

    def lyrics(self, q, track_id):
        self.require(q)
        lyrics = self.library.lyrics.get(norm(track_id))
        if lyrics is None:
            raise HTTPError(404)
        self.send_json(lyrics)

    def image(self, q, item_id, kind, index=None):
        lib = self.library
        item_id = norm(item_id)
        item = lib.items.get(item_id)
        tag = ((item or {}).get("ImageTags") or {}).get("Primary")
        path = os.path.join(lib.folder, "images", item_id + ".jpg")
        if kind.lower() != "primary" or not tag or not os.path.exists(path):
            raise HTTPError(404)
        # With the tag the URL never changes its picture: cache for good (12.4).
        cache = "public, max-age=31536000, immutable" if q.get("tag") else "public"
        self.send(200, lib.file(path), "image/jpeg", [("Cache-Control", cache), ("ETag", f'"{tag}"')])

    def audio(self, q, track_id, kind=None):
        self.require(q)
        lib = self.library
        track_id = norm(track_id)
        name = lib.audio.get(track_id)
        if name is None:
            raise HTTPError(404)
        # As long as the track says, so the app hears it to its end (Clip).
        seconds = 0 if lib.clips_as_recorded else round((lib.items[track_id].get("RunTimeTicks") or 0) / TICKS)
        data = lib.clip(name).file(seconds)
        size = len(data)
        headers = [("Accept-Ranges", "bytes"), ("ETag", f'"{name}-{seconds}"')]
        wanted = self.headers.get("Range")
        if not wanted:
            return self.send(200, data, "audio/mp4", headers)
        # One range, as AVPlayer asks: "bytes=0-1", "bytes=1000-", "bytes=-500".
        found = re.match(r"\s*bytes\s*=\s*(\d*)\s*-\s*(\d*)", wanted)
        if not found or (found.group(1) == "" and found.group(2) == ""):
            return self.send(416, b"", None, [("Content-Range", f"bytes */{size}")])
        if found.group(1) == "":
            start, end = max(0, size - int(found.group(2))), size - 1
        else:
            start = int(found.group(1))
            end = min(int(found.group(2)), size - 1) if found.group(2) else size - 1
        if start >= size or start > end:
            return self.send(416, b"", None, [("Content-Range", f"bytes */{size}")])
        self.send(206, data[start:end + 1], "audio/mp4", headers + [("Content-Range", f"bytes {start}-{end}/{size}")])


ID = r"([0-9A-Fa-f-]{32,36})"
ROUTES = [(set(methods.split()), re.compile("^" + pattern + "$", re.IGNORECASE), handler) for methods, pattern, handler in [
    ("GET", r"/System/Info/Public", Handler.public_info),
    ("GET POST", r"/System/Ping", Handler.ping),
    ("GET POST", r"/rest/.*", Handler.not_subsonic),
    ("POST", r"/Users/AuthenticateByName", Handler.authenticate),
    ("POST", r"/Users/AuthenticateWithQuickConnect", Handler.quick_disabled),
    ("POST", r"/Sessions/Logout", Handler.logout),
    ("GET", r"/QuickConnect/Enabled", Handler.quick_enabled),
    ("POST", r"/QuickConnect/Initiate", Handler.quick_disabled),
    ("GET", r"/QuickConnect/Connect", Handler.quick_disabled),
    ("POST", r"/QuickConnect/Authorize", Handler.quick_disabled),
    ("GET", r"/Users/Me", Handler.me),
    ("GET", r"/Users/" + ID, Handler.me),
    ("GET", r"/UserViews", Handler.user_views),
    ("GET", r"/Users/" + ID + r"/Views", Handler.user_views),
    ("GET", r"/Items", Handler.items),
    ("GET", r"/Users/" + ID + r"/Items", Handler.items),
    ("GET", r"/Items/" + ID, Handler.item),
    ("DELETE", r"/Items/" + ID, Handler.delete_item),
    ("GET", r"/Users/[^/]+/Items/" + ID, Handler.item),
    ("GET", r"/Artists/AlbumArtists", Handler.album_artists),
    ("GET", r"/Artists", Handler.artists),
    ("GET", r"/MusicGenres", Handler.genres),
    ("GET", r"/Genres", Handler.genres),
    ("GET", r"/(?:Items|Artists|Albums)/" + ID + r"/Similar", Handler.similar),
    ("GET", r"/(?:Items|Songs|Albums|Artists|Playlists|MusicGenres)/" + ID + r"/InstantMix", Handler.instant_mix),
    ("GET", r"/(?:Artists|MusicGenres)/InstantMix", Handler.instant_mix),
    ("GET", r"/Search/Hints", Handler.search_hints),
    ("POST", r"/Playlists", Handler.create_playlist),
    ("GET", r"/Playlists/" + ID + r"/Items", Handler.playlist_items),
    ("POST", r"/Playlists/" + ID + r"/Items", Handler.add_to_playlist),
    ("DELETE", r"/Playlists/" + ID + r"/Items", Handler.remove_from_playlist),
    ("POST", r"/Playlists/" + ID + r"/Items/" + ID + r"/Move/(-?\d+)", Handler.move_in_playlist),
    ("POST DELETE", r"/UserFavoriteItems/" + ID, Handler.favourite),
    ("POST DELETE", r"/Users/[^/]+/FavoriteItems/" + ID, Handler.favourite),
    ("POST DELETE", r"/UserPlayedItems/" + ID, Handler.played),
    ("POST DELETE", r"/Users/[^/]+/PlayedItems/" + ID, Handler.played),
    ("POST", r"/Sessions/Playing", Handler.playing),
    ("POST", r"/Sessions/Playing/(Progress|Stopped|Ping)", Handler.playing),
    ("POST", r"/Sessions/Capabilities(?:/Full)?", Handler.capabilities),
    ("GET", r"/Audio/" + ID + r"/Lyrics", Handler.lyrics),
    ("GET", r"/Audio/" + ID + r"/(universal|stream)(?:\.\w+)?", Handler.audio),
    ("GET", r"/Items/" + ID + r"/Images/(\w+)(?:/(\d+))?", Handler.image),
]]


class Server(ThreadingHTTPServer):
    daemon_threads = True
    # The app opens many connections at once (the library's five lists at
    # launch, the covers, AVPlayer's own): socketserver's backlog of 5 could
    # leave the rest to a TCP retry, a second each.
    request_queue_size = 64


class DualStackServer(Server):
    """[::], taking IPv4 as well: on a Mac "localhost" is ::1 and 127.0.0.1,
    and the simulator's app may try ::1 first."""
    address_family = socket.AF_INET6

    def server_bind(self):
        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        super().server_bind()


def make_server(host, port):
    if host:
        if ":" in host:
            return DualStackServer((host, port), Handler)
        return Server((host, port), Handler)
    try:
        return DualStackServer(("::", port), Handler)
    except OSError as error:
        if error.errno == errno.EADDRINUSE:
            raise
        # No IPv6 here (some containers): IPv4 alone.
        return Server(("0.0.0.0", port), Handler)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default="", help="default: every address, IPv6 and IPv4")
    parser.add_argument("--port", type=int, default=8096)
    parser.add_argument("--data", default=os.path.join(here, "demo"))
    parser.add_argument("--password", default="test", help="the recorded user's password (default: test)")
    parser.add_argument("--seed", type=int, default=1, help="for the random sort and the instant mixes")
    parser.add_argument("--song-lengths", action="store_true",
                        help="tracks of 2:30 to 5:30 instead of the test library's 5 to 8 seconds")
    # The looped files are checked with ffmpeg only (no AVPlayer here): if the
    # simulator's player refuses them, this serves the clips ffmpeg wrote.
    parser.add_argument("--clips-as-recorded", action="store_true",
                        help="every track the 8-second clip as it is, not looped to the track's length")
    args = parser.parse_args()

    Handler.library = Library(os.path.abspath(args.data), args.song_lengths, args.seed, args.password)
    Handler.library.clips_as_recorded = args.clips_as_recorded
    server = make_server(args.host, args.port)
    lib = Handler.library
    kinds = {}
    for item in lib.items.values():
        kinds[item["Type"]] = kinds.get(item["Type"], 0) + 1
    where = server.server_address[0]
    where = f"[{where}]" if ":" in where else where
    log(f"fake Jellyfin {lib.public.get('Version', '')} \"{lib.public.get('ServerName', '')}\" on "
        f"http://{where}:{args.port}: " + ", ".join(f"{n} {k}" for k, n in sorted(kinds.items()))
        + f"; user {lib.user['Name']}")
    # Each clip read once now, so a clip it cannot loop shows in the log at
    # the start rather than at the first song.
    for name in sorted(set(lib.audio.values())):
        lib.clip(name)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    sys.exit(main())
