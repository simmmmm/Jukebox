#!/usr/bin/env python3
"""The demo library the screenshots are taken with: what the Jellyfin test
server (dev/jellyfin-test-server.sh) answers to everything JukeboxKit's
client asks for, recorded into dev/demo/, with what a test library of sine
tones and flat colours does not have — covers, artist photos, music, lyrics
and a listener's history worth looking at. dev/fake-jellyfin.py serves it to
the app in the iOS Simulator on CI, where there is no Docker and so no real
Jellyfin.

    dev/jellyfin-test-server.sh && python3 dev/record-demo.py
    python3 dev/record-demo.py --pictures-only   redraw from dev/demo/items.json
    python3 dev/record-demo.py --sheet out.jpg   also a contact sheet of every picture

Python 3 with Pillow; ffmpeg here, or the Jellyfin image's own through Docker.
Every picture and sound is seeded by an id or a name, so a second recording
of the same library gives the same files (with the same Pillow and ffmpeg).

What is made up, on purpose, and said so here rather than passed off as the
server's: the listener (favourites, play counts, when things were played and
added — the test server's are whatever the kit tests left), five playlists,
seven songs' lyrics, the pictures, and the sound. What the library holds —
items, names, ids, genres, artists, years, track numbers and lengths — is the
server's, untouched, so the kit's live tests pass against the fake too.
"""
import argparse
import colorsys
import hashlib
import io
import json
import math
import os
import random
import shutil
import struct
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
import wave
from datetime import datetime, timedelta, timezone

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------------------
# Recording

# The fields the probe asks for one at a time, to learn which keys each adds
# to each kind of item. The fake leaves out what was not asked for, as
# Jellyfin does, so a client that stops asking for Genres gets none from the
# fake either. Only fields a music client has a use for: Path, ParentId,
# ProviderIds and the like would cost a sixth of the demo's 4 MB.
PROBE_FIELDS = ["Genres", "DateCreated", "ChildCount", "ItemCounts", "Overview", "SortName",
                "CumulativeRunTimeTicks", "PrimaryImageAspectRatio"]

# What a home server is called. The test server's name is its container's
# hostname ("0548ac3b6612"), which nobody's server at home is.
DEMO_SERVER_NAME = "Jellyfin"


class Jellyfin:
    def __init__(self, url, device_id):
        self.url = url.rstrip("/")
        # Straight to the server, not through a proxy the environment may name.
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        self.header = ('MediaBrowser Client="JukeboxDemoRecorder", Device="Linux", '
                       f'DeviceId="{device_id}", Version="1.0"')
        self.token = None
        self.user_id = None

    def call(self, method, path, query=None, body=None):
        url = self.url + path
        if query:
            url += "?" + urllib.parse.urlencode(query, quote_via=urllib.parse.quote)
        data = None if body is None else json.dumps(body).encode()
        request = urllib.request.Request(url, data=data, method=method)
        request.add_header("Authorization", self.header + (f', Token="{self.token}"' if self.token else ""))
        if data is not None:
            request.add_header("Content-Type", "application/json")
        with self.opener.open(request, timeout=120) as response:
            raw = response.read()
        return json.loads(raw) if raw.strip() else None

    def items(self, path, **query):
        query.setdefault("userId", self.user_id)
        return self.call("GET", path, query)["Items"]


def probe_fields(jf, samples):
    """{kind: {field: [keys it adds]}} for each kind's sample request."""
    out = {}
    for kind, (path, query) in samples.items():
        def keys(fields=None):
            q = dict(query)
            if fields:
                q["Fields"] = fields
            found = jf.items(path, **q)
            return set(found[0]) if found else set()
        base = keys()
        everything = keys(",".join(PROBE_FIELDS))
        mapping = {}
        for field in PROBE_FIELDS:
            extra = sorted(keys(field) - base)
            if extra:
                mapping[field] = extra
        unexplained = everything - base - {k for ks in mapping.values() for k in ks}
        if unexplained:
            print(f"  {kind}: {sorted(unexplained)} come only with several fields; the fake always sends them")
        out[kind] = mapping
    return out


def record(url, user, password):
    jf = Jellyfin(url, "jukebox-demo-recorder")
    public = jf.call("GET", "/System/Info/Public")
    signed_in = jf.call("POST", "/Users/AuthenticateByName", body={"Username": user, "Pw": password})
    jf.token = signed_in["AccessToken"]
    jf.user_id = signed_in["User"]["Id"]
    everything = ",".join(PROBE_FIELDS)
    try:
        me = jf.call("GET", "/Users/Me")
        views = jf.items("/UserViews")
        tracks = jf.items("/Items", IncludeItemTypes="Audio", Recursive="true", Fields=everything, SortBy="SortName")
        albums = jf.items("/Items", IncludeItemTypes="MusicAlbum", Recursive="true", Fields=everything,
                          SortBy="SortName")
        # The album artists as /Artists/AlbumArtists has them (its counts are
        # the album artist's), and the rest — the test library's guest credits,
        # "MC Polder; Lyric Engine" — as /Artists has them.
        album_artists = jf.items("/Artists/AlbumArtists", Fields=everything, SortBy="SortName")
        listed = {a["Id"] for a in album_artists}
        others = [a for a in jf.items("/Artists", Fields=everything, SortBy="SortName") if a["Id"] not in listed]
        genres = jf.items("/MusicGenres", Fields=everything, SortBy="SortName")
        similar = {a["Id"]: [i["Id"] for i in jf.items(f"/Items/{a['Id']}/Similar", limit="50")]
                   for a in album_artists}
        print(f"recorded {len(tracks)} tracks, {len(albums)} albums, {len(album_artists)} album artists "
              f"(+{len(others)} credits), {len(genres)} genres")

        # A playlist, made and thrown away again, for the shape of one.
        made = jf.call("POST", "/Playlists", body={"Name": "Jukebox demo recorder", "Ids": [tracks[0]["Id"]],
                                                   "UserId": jf.user_id, "MediaType": "Audio"})
        try:
            playlist = jf.items("/Items", Ids=made["Id"], Fields=everything)[0]
            fields = probe_fields(jf, {
                "Audio": ("/Items", {"Ids": tracks[0]["Id"]}),
                "MusicAlbum": ("/Items", {"Ids": albums[0]["Id"]}),
                "MusicArtist": ("/Artists/AlbumArtists", {"SortBy": "SortName", "Limit": "1"}),
                "MusicGenre": ("/MusicGenres", {"SortBy": "SortName", "Limit": "1"}),
                "Playlist": ("/Items", {"Ids": made["Id"]}),
            })
        finally:
            jf.call("DELETE", f"/Items/{made['Id']}")
    finally:
        jf.call("POST", "/Sessions/Logout")

    return {"public": public, "signIn": signed_in, "me": me, "views": views, "tracks": tracks,
            "albums": albums, "albumArtists": album_artists, "otherArtists": others, "genres": genres,
            "similar": similar, "playlistTemplate": playlist, "fields": fields}


# ---------------------------------------------------------------------------
# Dates, as Jellyfin writes them: seven fractional digits and a Z.

def parse_date(text):
    text = text.rstrip("Z")
    if "." in text:
        head, fraction = text.split(".")
        text = head + "." + (fraction + "000000")[:6]
    return datetime.fromisoformat(text).replace(tzinfo=timezone.utc)


def format_date(moment):
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.") + f"{moment.microsecond:06d}0Z"


# ---------------------------------------------------------------------------
# Genres: which corner of the library an item is in, for its colours, its
# picture's style and its sound.

FAMILY = {
    "rock; alternative": "rock", "rock; hard rock": "hardrock", "rock; shoegaze": "shoegaze",
    "alternative; indie": "alt", "indie; alternative": "indie", "electronic; synthwave": "synthwave",
    "electronic; house": "house", "electronic; ambient": "ambient", "electronic; techno": "techno",
    "jazz": "jazz", "jazz; bebop": "bebop", "jazz; vocal jazz": "vocaljazz", "hip-hop": "hiphop",
    "hip-hop; nederhop": "hiphop", "hip-hop; rap": "hiphop", "classical": "classical",
    "classical; piano": "piano", "folk; acoustic": "folk", "folk; americana": "folk", "folk; indie": "folk",
    "pop": "pop", "pop; dance": "dance", "pop; electronic": "electropop",
}
FIRST_WORD = {"rock": "rock", "alternative": "alt", "indie": "indie", "electronic": "techno", "jazz": "jazz",
              "hip-hop": "hiphop", "classical": "classical", "folk": "folk", "pop": "pop"}


def family(genres, seed=""):
    # A library that splits "Rock; Shoegaze" into two genres reads the same.
    key = "; ".join(p.strip().lower() for g in genres for p in g.split(";") if p.strip())
    if key in FAMILY:
        return FAMILY[key]
    first = key.split(";")[0].strip()
    if first in FIRST_WORD:
        return FIRST_WORD[first]
    return sorted(PALETTES)[int(hashlib.md5(seed.encode()).hexdigest(), 16) % len(PALETTES)]


# The four clips, by corner. Hip-hop gets the one with a beat.
CLIP = {"jazz": "keys", "bebop": "keys", "vocaljazz": "keys", "classical": "keys", "piano": "keys",
        "synthwave": "drive", "ambient": "drive", "techno": "drive", "electropop": "drive",
        "pop": "bright", "dance": "bright", "house": "bright", "hiphop": "bright",
        "rock": "strings", "hardrock": "strings", "shoegaze": "strings", "alt": "strings", "indie": "strings",
        "folk": "strings"}


# ---------------------------------------------------------------------------
# The listener. Their taste: shoegaze and guitars, a jazz singer, synthwave
# at night, folk, piano. Names the library may not have are skipped.

LOVED = ["Velvet Static", "Saskia de Wit", "Nightdrive", "Willow & Pine", "The Lanterns", "Clara Venn",
         "MC Polder"]
LIKED = ["Blue Room Trio", "Low Orbit", "June Hollow", "Sunny Side", "Paper Harbour", "Miles Ahead Quartet"]
FAVOURITE_ARTISTS = ["Velvet Static", "Saskia de Wit", "Nightdrive", "Willow & Pine"]

PLAYLISTS = [
    ("Sunday Morning", ["folk", "vocaljazz", "piano"], 14),
    ("Late Night Drive", ["synthwave", "ambient", "techno"], 16),
    ("Dinner Jazz", ["jazz", "bebop", "vocaljazz"], 12),
    ("Loud Guitars", ["rock", "shoegaze", "hardrock", "alt"], 15),
    ("Run Club", ["dance", "house", "electropop", "hiphop"], 18),
]


def user_data(item_id, key, plays=0, favourite=False, last=None):
    data = {"PlaybackPositionTicks": 0, "PlayCount": plays, "IsFavorite": favourite}
    if last:
        data["LastPlayedDate"] = format_date(last)
    data.update({"Played": plays > 0, "Key": key, "ItemId": item_id})
    return data


def make_listener(rec, now):
    """Favourites, play counts and dates added and played, made up."""
    rng = random.Random("jukebox demo listener")
    tracks, albums = rec["tracks"], rec["albums"]
    artists = rec["albumArtists"] + rec["otherArtists"]

    # When each album came into the library: four in the last fortnight (for
    # "Recently Added"), the rest over three years before.
    order = sorted(albums, key=lambda a: a["Id"])
    rng.shuffle(order)
    added = {}
    for k, album in enumerate(order):
        days = rng.uniform(1, 14) if k < 4 else rng.uniform(30, 1100)
        added[album["Id"]] = now - timedelta(days=days, seconds=rng.uniform(0, 3600))
    for album in albums:
        album["DateCreated"] = format_date(added[album["Id"]])
    position = {}
    for track in tracks:
        moment = added.get(track.get("AlbumId"), now - timedelta(days=400))
        index = (track.get("ParentIndexNumber") or 1) * 100 + (track.get("IndexNumber") or 0)
        track["DateCreated"] = format_date(moment + timedelta(milliseconds=90 * index))
        position[track["Id"]] = index
    for artist in artists:
        theirs = [added[a["Id"]] for a in albums
                  if artist["Id"] in [x.get("Id") for x in a.get("AlbumArtists") or []]]
        if "DateCreated" in artist and theirs:
            artist["DateCreated"] = format_date(min(theirs))

    def by(names):
        return {n for n in names if any(a["Name"] == n for a in artists)}
    loved, liked = by(LOVED), by(LIKED)

    played = []
    for track in tracks:
        owner = track.get("AlbumArtist") or ""
        roll = rng.random()
        if owner in loved and roll < 0.75:
            plays = int(rng.paretovariate(2.2) * 4) if rng.random() < 0.8 else rng.randint(1, 2)
            last = now - timedelta(days=rng.uniform(0, 1) ** 2 * 21, minutes=rng.uniform(0, 600))
        elif owner in liked and roll < 0.5:
            plays = rng.randint(1, 8)
            last = now - timedelta(days=rng.uniform(2, 60))
        elif roll < 0.12:
            plays = rng.randint(1, 3)
            last = now - timedelta(days=rng.uniform(10, 200))
        else:
            plays, last = 0, None
        # A few old loves not heard for a year: what a "rediscover" mix is for.
        if owner in loved and plays >= 6 and rng.random() < 0.12:
            last = now - timedelta(days=rng.uniform(300, 520))
        plays = min(plays, 40)
        track["UserData"] = user_data(track["Id"], track["UserData"]["Key"], plays, False, last)
        if plays:
            played.append(track)

    candidates = sorted([t for t in played if (t.get("AlbumArtist") or "") in loved | liked], key=lambda t: t["Id"])
    favourite_tracks = set(t["Id"] for t in rng.sample(candidates, k=min(24, len(candidates))))
    for track in tracks:
        track["UserData"]["IsFavorite"] = track["Id"] in favourite_tracks
    favourite_albums = set()
    for name in sorted(loved):
        theirs = sorted([a for a in albums if a.get("AlbumArtist") == name], key=lambda a: a["Id"])
        if theirs:
            favourite_albums.add(rng.choice(theirs)["Id"])
    for album in albums:
        album["UserData"] = user_data(album["Id"], album["UserData"]["Key"], 0, album["Id"] in favourite_albums)
    for artist in artists:
        artist["UserData"] = user_data(artist["Id"], artist["UserData"]["Key"], 0,
                                       artist["Name"] in FAVOURITE_ARTISTS)
    for genre in rec["genres"]:
        if "UserData" in genre:
            genre["UserData"] = user_data(genre["Id"], genre["UserData"].get("Key", genre["Name"]))
    print(f"listener: {len(played)} tracks played, {len(favourite_tracks)} favourite tracks, "
          f"{len(favourite_albums)} albums, {len(by(FAVOURITE_ARTISTS))} artists")


def make_playlists(rec, now):
    rng = random.Random("jukebox demo playlists")
    template = rec["playlistTemplate"]
    by_family = {}
    for track in rec["tracks"]:
        by_family.setdefault(family(track.get("Genres") or [], track["Id"]), []).append(track)
    playlists, entries = [], {}
    for k, (name, families, count) in enumerate(PLAYLISTS):
        pool = sorted([t for f in families for t in by_family.get(f, [])], key=lambda t: t["Id"])
        if not pool:
            continue
        # Favourites and the much-played first, as a person's own list has them.
        pool.sort(key=lambda t: -(t["UserData"]["PlayCount"] + 10 * t["UserData"]["IsFavorite"] + rng.random() * 6))
        chosen = pool[:count]
        rng.shuffle(chosen)
        ident = hashlib.md5(f"jukebox demo playlist {name}".encode()).hexdigest()
        item = new_playlist(template, ident, name, now - timedelta(days=3 + 17 * k, hours=rng.uniform(0, 12)))
        playlists.append(item)
        entries[ident] = [t["Id"] for t in chosen]
    return playlists, entries


def new_playlist(template, ident, name, created):
    """A Playlist item in the shape of the one the recorder made on the server."""
    item = json.loads(json.dumps(template))
    old = template["Name"]
    item["Name"] = name
    item["Id"] = ident
    for key in ("SortName",):
        if key in item:
            item[key] = name.lower()
    if "Path" in item:
        item["Path"] = item["Path"].replace(old, name)
    if "DateCreated" in item:
        item["DateCreated"] = format_date(created)
    dashed = f"{ident[:8]}-{ident[8:12]}-{ident[12:16]}-{ident[16:20]}-{ident[20:]}"
    item["UserData"] = user_data(ident, dashed)
    item["ImageTags"] = {}
    return item


# ---------------------------------------------------------------------------
# Lyrics, synced, written for these songs: short, original, about the title.
# Lines a second or so apart, since every clip is eight seconds.

LYRICS = [
    ("Night Drive", "Silver Roads", [
        "Headlights on the gravel, the radio low",
        "Your hand out the window, catching the cold",
        "Every town we pass is sleeping",
        "Every sign says almost home",
        "Night drive, night drive",
        "Keep the engine humming",
        "Night drive, night drive",
        "Till the morning's coming"]),
    ("Rain Window", "Echo Fieldss", [
        "Fingerprints on the rain window",
        "Counting taillights going home",
        "Every drop is racing every other",
        "None of them will race alone",
        "Let it pour, let it pour",
        "I've got nowhere else to be",
        "Let it pour, let it pour",
        "The glass is holding up for me"]),
    ("Paper Heart", "Glass Hearts", [
        "Ik vouw een hart van krantenpapier",
        "Met de koppen van gisteren erop",
        "Het waait weg over het plein hier",
        "Ik ren erachteraan, ik stop niet, nee",
        "Papieren hart, het scheurt zo snel",
        "Maar ik plak het elke dag weer heel",
        "Papieren hart, zo licht als wind",
        "Waar het landt, daar begint het"]),
    ("Summer Dream", "Northern Tides", [
        "Sun on the water, nothing to do",
        "Ice in the glass and the sky so blue",
        "Turn up the radio, open the door",
        "Summer dream, I want a little more",
        "Oh-oh, summer dream",
        "Nothing's ever what it seems",
        "Oh-oh, stay with me",
        "Till the stars come out to see"]),
    ("Winter Sky", "Quiet Rooms", [
        "Grey above the canal tonight",
        "The streetlamps hum a minor key",
        "I wrap your scarf around the light",
        "And let the winter sing to me",
        "Oh winter sky, so wide, so low",
        "You hold the snow you never show",
        "Oh winter sky, stay grey a while",
        "I'm only waiting for her smile"]),
    ("Velvet Sky", "Velvet Songs", [
        "Neon fading into violet",
        "Highway pulling like a thread",
        "Every light a little planet",
        "Spinning softly overhead",
        "Velvet sky",
        "Take me through the night",
        "Velvet sky",
        "Hold the city light"]),
    ("River Song", "Rain Hearts", [
        "The river knows a song I used to know",
        "It hums it under bridges, soft and slow",
        "I left my name in pebbles on the shore",
        "The water took it, wanted nothing more",
        "Sing it, river, sing it low",
        "Carry me where the willows grow",
        "Sing it, river, take it on",
        "I'll be humming when you're gone"]),
]
LINE_STARTS = [0.0, 0.9, 1.8, 2.7, 3.8, 4.7, 5.8, 6.8]


def make_lyrics(tracks):
    out = {}
    for title, album, lines in LYRICS:
        track = next((t for t in tracks if t["Name"] == title and t.get("Album") == album), None)
        if not track:
            print(f"  no track {title} on {album}: no lyrics for it")
            continue
        out[track["Id"]] = {
            "Metadata": {"Artist": track.get("AlbumArtist"), "Album": album, "Title": title,
                         "Length": track.get("RunTimeTicks"), "IsSynced": True},
            "Lyrics": [{"Text": text, "Start": round(start * 10_000_000)}
                       for start, text in zip(LINE_STARTS, lines)],
        }
        track["HasLyrics"] = True
    return out


# ---------------------------------------------------------------------------
# Pictures. Drawn at twice the size and halved (ImageDraw does not smooth
# edges), grained, saved as JPEG under a budget.

S = 1200
SIZE = 600

PALETTES = {
    # background, ink (for type), accents
    "rock": [["#1c1a19", "#efe6d6", "#c4472f", "#e0a33a", "#7d2a1f"],
             ["#ece3d2", "#1c1c1c", "#b8372a", "#1f3f5c", "#d9a13b"],
             ["#2b2f33", "#f2ede4", "#d65a31", "#9aa5a8", "#e8c66a"]],
    "hardrock": [["#0e0e0f", "#e8e2d6", "#b5291c", "#f08a24", "#5a5a5e"],
                 ["#151515", "#d9d4c7", "#8c8f94", "#e2c044", "#a3241a"]],
    "shoegaze": [["#f3c6d3", "#2e1d3b", "#b799e0", "#88b7e8", "#f7e3a3", "#e58fb4"],
                 ["#2a1f3d", "#f6e9f2", "#d77fa1", "#7f9cf5", "#f2b5c4", "#5ec2c6"],
                 ["#cfd8ef", "#2d2240", "#f0a7c1", "#a68be0", "#fbe3c4"]],
    "alt": [["#efe9df", "#1e2a38", "#ff5a5f", "#1e88e5", "#ffd166"],
            ["#f4efe6", "#1b1b1b", "#00a6a6", "#f26419", "#2f2d7a"],
            ["#e9e4da", "#222222", "#5b8c5a", "#e4572e", "#29335c"]],
    "indie": [["#f5f0e6", "#2c2a29", "#e76f51", "#2a9d8f", "#e9c46a"],
              ["#eae2d0", "#2e294e", "#9055a2", "#ffb238", "#1b998b"],
              ["#1f2d3d", "#f2e8cf", "#f4a259", "#5b8e7d", "#bc4b51"]],
    "synthwave": [["#140a2e", "#ffe6f7", "#ff3d81", "#ff9e3d", "#3df2ff", "#7b2ff7"],
                  ["#0b0f2e", "#f6f0ff", "#f72585", "#ffb703", "#4cc9f0", "#7209b7"]],
    "house": [["#fff3b0", "#1d1d1b", "#ff6b35", "#004e89", "#1a936f", "#ff99c8"],
              ["#1a2a6c", "#fdfcdc", "#fdb833", "#f72c25", "#3fc1c9", "#fdfcdc"],
              ["#f4f1de", "#22223b", "#e07a5f", "#3d405b", "#81b29a", "#f2cc8f"]],
    "ambient": [["#dfe7ec", "#2e3a44", "#a9bcc9", "#f1e3d3", "#7d93a6", "#c8d5b9"],
                ["#1d2731", "#e6edf1", "#4b6a82", "#9fb7c9", "#d8c3a5", "#6d8a96"],
                ["#efe9e1", "#3a3a3a", "#c9b79c", "#9aa8a2", "#e3d5c3", "#7f8c8d"]],
    "techno": [["#0b0b0b", "#f2f2f2", "#c6ff00", "#4a4a4a", "#f2f2f2"],
               ["#f0f0ee", "#111111", "#ff2e2e", "#111111", "#9a9a9a"],
               ["#101418", "#e9eef2", "#00e5ff", "#39424e", "#e9eef2"]],
    "jazz": [["#0f3057", "#f2eadf", "#e3a72f", "#d7263d", "#f2eadf"],
             ["#e9e1d3", "#141414", "#1d4e89", "#d1495b", "#edae49"],
             ["#1b1b1b", "#f0e6d2", "#e0b040", "#2e86ab", "#c73e1d"]],
    "bebop": [["#e8dcc4", "#151515", "#e05a1c", "#1b6e74", "#151515"],
              ["#123c45", "#f3ead8", "#f29e38", "#e8dcc4", "#c2412d"],
              ["#c2412d", "#f6eee0", "#151515", "#f0b23e", "#f6eee0"]],
    "vocaljazz": [["#3b0d11", "#f3e6d8", "#c9a227", "#6a2c2f", "#e8c8a0"],
                  ["#16302b", "#efe4d4", "#d4a373", "#7a9e7e", "#b5544b"],
                  ["#f1e7da", "#2b1d1d", "#8c2f39", "#c9a227", "#3e5c76"]],
    "hiphop": [["#8d8d8a", "#121212", "#ff7a00", "#ffd200", "#121212", "#e9e9e4"],
               ["#121212", "#f2f2f2", "#ffd200", "#7b2cbf", "#ff3c38"],
               ["#d9d4c7", "#141414", "#2b59c3", "#ff5d3a", "#141414"]],
    "classical": [["#f2ece1", "#2b2a28", "#8b6f47", "#1f3a5f", "#a33b3b", "#c8b88a"],
                  ["#1d2430", "#efe6d4", "#c9a96e", "#7c8a99", "#efe6d4"],
                  ["#ece6da", "#30302e", "#6b7f73", "#b08d57", "#2e4a62"]],
    "piano": [["#f4f0e8", "#1e1e1e", "#1e1e1e", "#9c8c74", "#b84a3a"],
              ["#181a1f", "#ece7dc", "#ece7dc", "#8a93a3", "#c9a96e"]],
    "folk": [["#efe2c8", "#3a2e25", "#c46a3a", "#6f8f6b", "#2f4f4f", "#e3b25b"],
             ["#d9c8a9", "#2d2a26", "#8c5e3c", "#a3b18a", "#3d5a6c", "#f2d492"],
             ["#24323a", "#efe2c8", "#d98c5f", "#7d9b84", "#e8c07d", "#4f6d7a"]],
    "pop": [["#ffd6e0", "#2b1e3a", "#ff6f91", "#ffc75f", "#845ec2", "#00c9a7"],
            ["#c3f0ff", "#1b2441", "#ff8fab", "#fdffb6", "#9b5de5", "#00bbf9"],
            ["#ffe5d9", "#3a2a3d", "#f4978e", "#f8ad9d", "#7c6a9e", "#fbc4ab"]],
    "dance": [["#140f2d", "#fdf0ff", "#f72585", "#4cc9f0", "#fee440", "#7209b7"],
              ["#fff1e6", "#1d1a31", "#ff006e", "#3a86ff", "#ffbe0b", "#8338ec"]],
    "electropop": [["#1a1033", "#f5ecff", "#c77dff", "#ff9e00", "#48cae4", "#ff5d8f"],
                   ["#f7e1ff", "#2a1740", "#ff70a6", "#70d6ff", "#ffd670", "#9b5de5"]],
}

STYLES = {
    "rock": ["bands", "bauhaus", "riso"], "hardrock": ["bands", "rings", "lines"], "shoegaze": ["orbs"],
    "alt": ["riso", "bauhaus"], "indie": ["riso", "landscape", "orbs"], "synthwave": ["sunset"],
    "house": ["pattern", "orbs"], "ambient": ["rings", "lines", "orbs", "landscape"],
    "techno": ["rings", "lines", "bands"], "jazz": ["bauhaus", "blocks"], "bebop": ["blocks", "bauhaus"],
    "vocaljazz": ["orbs", "bauhaus", "blocks"], "hiphop": ["blocks", "bands", "riso"],
    "classical": ["lines", "rings", "landscape"], "piano": ["lines", "rings"], "folk": ["landscape", "riso"],
    "pop": ["orbs", "pattern"], "dance": ["pattern", "orbs", "sunset"], "electropop": ["orbs", "sunset"],
}
SOFT = {"ambient", "classical", "piano", "shoegaze", "vocaljazz", "folk"}

FONTS = {
    "bold": ["/usr/share/fonts/opentype/inter/InterDisplay-Black.otf", "/usr/share/fonts/opentype/inter/Inter-Black.otf",
             "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/Library/Fonts/Arial Bold.ttf"],
    "sans": ["/usr/share/fonts/opentype/inter/Inter-SemiBold.otf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
             "/Library/Fonts/Arial.ttf"],
    "light": ["/usr/share/fonts/opentype/inter/Inter-Light.otf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"],
    "serif": ["/usr/share/fonts/truetype/crosextra/Caladea-Regular.ttf",
              "/usr/share/fonts/truetype/liberation/LiberationSerif-Regular.ttf",
              "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf"],
    "mono": ["/usr/share/fonts/truetype/jetbrains-mono/JetBrainsMono-Medium.ttf",
             "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"],
}
TYPE_FOR = {"classical": "serif", "piano": "serif", "vocaljazz": "serif", "techno": "mono", "ambient": "light",
            "folk": "serif"}
_font_cache = {}


def font(kind, size):
    key = (kind, size)
    if key not in _font_cache:
        path = next((p for p in FONTS[kind] if os.path.exists(p)), None)
        _font_cache[key] = ImageFont.truetype(path, size) if path else ImageFont.load_default(size)
    return _font_cache[key]


def rgb(colour):
    colour = colour.lstrip("#")
    return tuple(int(colour[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def luminance(c):
    return (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) / 255


def solid(colour, size=S):
    return Image.new("RGB", (size, size), colour)


def ramp(angle, size=S, n=96):
    """0 → 255 along `angle` degrees (90: top to bottom), as a mask."""
    a = math.radians(angle)
    dx, dy = math.cos(a), math.sin(a)
    extent = abs(dx) + abs(dy)
    data = []
    for j in range(n):
        y = (j + 0.5) / n * 2 - 1
        for i in range(n):
            x = (i + 0.5) / n * 2 - 1
            data.append(max(0, min(255, round(((x * dx + y * dy) / extent * 0.5 + 0.5) * 255))))
    mask = Image.new("L", (n, n))
    mask.putdata(data)
    return mask.resize((size, size), Image.BICUBIC)


def radial(cx, cy, radius, size=S, n=128):
    """0 at (cx, cy) → 255 at `radius` and beyond (fractions of the size)."""
    data = []
    for j in range(n):
        y = (j + 0.5) / n
        for i in range(n):
            x = (i + 0.5) / n
            data.append(min(255, round(math.hypot(x - cx, y - cy) / radius * 255)))
    mask = Image.new("L", (n, n))
    mask.putdata(data)
    return mask.resize((size, size), Image.BICUBIC)


def gradient(stops, angle=90, size=S):
    """Colour stops [(0..1, colour)] along `angle`."""
    lut = []
    for k in range(256):
        t = k / 255
        for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
            if t <= p1 or (p1, c1) == stops[-1]:
                lut.append(mix(c0, c1, 0 if p1 == p0 else max(0, min(1, (t - p0) / (p1 - p0)))))
                break
    mask = ramp(angle, size)
    return Image.merge("RGB", [mask.point([c[ch] for c in lut]) for ch in range(3)])


def disc_mask(cx, cy, r, size=S):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    return mask


def grain(img, rng, amount, scale=3):
    """Film grain: noise at a third of the size, overlaid. Coarser grain
    looks more like film and costs the JPEG less."""
    w = img.size[0] // scale
    noise = Image.frombytes("L", (w, w), rng.randbytes(w * w)).filter(ImageFilter.GaussianBlur(0.7))
    noise = noise.resize(img.size, Image.BICUBIC)
    over = ImageChops.overlay(img, Image.merge("RGB", [noise] * 3))
    return Image.blend(img, over, amount)


def vignette(img, strength):
    mask = radial(0.5, 0.5, 0.78, img.size[0]).point(lambda v: round(v * strength))
    return Image.composite(solid((0, 0, 0), img.size[0]), img, mask)


def spaced(draw, xy, text, fnt, fill, tracking):
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=fnt, fill=fill)
        x += draw.textlength(ch, font=fnt) + tracking
    return x


def spaced_width(draw, text, fnt, tracking):
    return sum(draw.textlength(ch, font=fnt) + tracking for ch in text) - tracking


def readable(name):
    """The test library's album names have a doubled plural ("Echo Fieldss",
    "Glass Citys"); they stay as they are in the data, but a cover would
    print the slip in big letters, so the cover leaves those names off."""
    return not (name.endswith("ss") or name.endswith("ys"))


# --- the styles: each draws a whole S×S picture -----------------------------

def style_orbs(rng, pal, fam):
    bg, ink = rgb(pal[0]), rgb(pal[1])
    accents = [rgb(c) for c in pal[2:]]
    img = gradient([(0, bg), (1, mix(bg, rng.choice(accents), 0.35))], rng.choice([60, 90, 120, 135]))
    d = ImageDraw.Draw(img)
    for _ in range(rng.randint(3, 6)):
        r = rng.uniform(0.16, 0.4) * S
        x, y = rng.uniform(0.05, 0.95) * S, rng.uniform(0.05, 0.95) * S
        d.ellipse([x - r, y - r, x + r, y + r], fill=rng.choice(accents))
    img = img.filter(ImageFilter.GaussianBlur(rng.uniform(70, 120)))
    d = ImageDraw.Draw(img)
    # One sharp thing in the haze, so it reads as a cover and not a blur.
    kind = rng.choice(["ring", "dot", "line", "arc"])
    cx, cy, r = rng.uniform(0.3, 0.7) * S, rng.uniform(0.3, 0.7) * S, rng.uniform(0.08, 0.2) * S
    fg = ink if rng.random() < 0.5 else mix(ink, bg, 0.15)
    if kind == "ring":
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=fg, width=6)
    elif kind == "dot":
        d.ellipse([cx - r * 0.35, cy - r * 0.35, cx + r * 0.35, cy + r * 0.35], fill=fg)
    elif kind == "line":
        y = rng.uniform(0.55, 0.8) * S
        d.line([(S * 0.18, y), (S * 0.82, y)], fill=fg, width=5)
    else:
        d.arc([cx - r * 1.6, cy - r * 1.6, cx + r * 1.6, cy + r * 1.6], 200, 340, fill=fg, width=6)
    return img


def style_sunset(rng, pal, fam):
    sky, ink = rgb(pal[0]), rgb(pal[1])
    hot, warm, cool, deep = [rgb(c) for c in pal[2:6]]
    horizon = rng.uniform(0.58, 0.68)
    img = gradient([(0, sky), (horizon * 0.55, mix(sky, deep, 0.7)), (horizon, mix(hot, warm, 0.35)), (1, hot)], 90)
    d = ImageDraw.Draw(img)
    for _ in range(rng.randint(25, 60)):
        x, y = rng.uniform(0, 1) * S, rng.uniform(0, horizon * 0.55) * S
        r = rng.choice([1.5, 2, 2, 3, 4])
        d.ellipse([x - r, y - r, x + r, y + r], fill=mix(ink, sky, rng.uniform(0.1, 0.6)))
    cx = S * rng.uniform(0.38, 0.62)
    r = S * rng.uniform(0.17, 0.25)
    cy = S * horizon - r * rng.uniform(0.2, 0.55)
    mask = disc_mask(cx, cy, r)
    md = ImageDraw.Draw(mask)
    for k in range(6):
        y = cy + r * (0.08 + 0.15 * k)
        md.rectangle([0, y, S, y + r * (0.025 + 0.022 * k)], fill=0)
    glow = mask.filter(ImageFilter.GaussianBlur(70)).point(lambda v: round(v * 0.7))
    img = Image.composite(solid(hot), img, glow)
    img = Image.composite(gradient([(0, warm), (1, hot)], 90), img, mask)
    d = ImageDraw.Draw(img)
    hy = S * horizon
    ground = mix(sky, (0, 0, 0), 0.3)
    d.rectangle([0, hy, S, S], fill=ground)
    line = mix(cool, ground, 0.25)
    for i in range(-14, 15):
        d.line([(S / 2 + i * S * 0.018, hy), (S / 2 + i * S * 0.16, S)], fill=line, width=3)
    for k in range(1, 9):
        y = hy + (S - hy) * (k / 8) ** 1.8
        d.line([(0, y), (S, y)], fill=line, width=3)
    d.line([(0, hy), (S, hy)], fill=mix(hot, warm, 0.5), width=4)
    return img


def style_landscape(rng, pal, fam):
    sky, ink = rgb(pal[0]), rgb(pal[1])
    acc = [rgb(c) for c in pal[2:]]
    img = gradient([(0, mix(sky, acc[-1], 0.25)), (0.7, sky), (1, mix(sky, acc[0], 0.25))], 90)
    d = ImageDraw.Draw(img)
    sr = S * rng.uniform(0.07, 0.13)
    sx, sy = S * rng.uniform(0.2, 0.8), S * rng.uniform(0.18, 0.38)
    d.ellipse([sx - sr, sy - sr, sx + sr, sy + sr], fill=mix(rng.choice(acc), sky, 0.15))
    layers = rng.randint(3, 5)
    near = ink if luminance(ink) < luminance(sky) else mix(acc[0], (0, 0, 0), 0.5)
    far = mix(sky, near, 0.2)
    tint = rng.choice(acc)
    for k in range(layers):
        t = k / (layers - 1)
        base = S * (0.46 + 0.42 * t)
        amp = S * rng.uniform(0.04, 0.1) * (1 - 0.35 * t)
        waves = [(rng.uniform(0.6, 2.6), rng.uniform(0, 6.3), rng.uniform(0.3, 1)) for _ in range(3)]
        pts = []
        for i in range(0, S + 1, 6):
            x = i / S
            pts.append((i, base - amp * sum(a * math.sin(2 * math.pi * f * x + p) for f, p, a in waves) / 1.5))
        d.polygon(pts + [(S, S), (0, S)], fill=mix(mix(far, near, t), tint, 0.18 * (1 - t)))
    return img


def style_bauhaus(rng, pal, fam):
    bg, ink = rgb(pal[0]), rgb(pal[1])
    acc = [rgb(c) for c in pal[2:]] + [ink]
    img = solid(bg)
    d = ImageDraw.Draw(img)
    n = rng.choice([2, 3, 3, 4])
    margin = rng.choice([0, S * 0.07])
    cell = (S - 2 * margin) / n
    for i in range(n):
        for j in range(n):
            x0, y0 = margin + i * cell, margin + j * cell
            x1, y1 = x0 + cell, y0 + cell
            cbg = rng.choice([bg, bg, bg] + acc)
            fg = rng.choice([c for c in acc + [bg] if c != cbg])
            d.rectangle([x0, y0, x1, y1], fill=cbg)
            kind = rng.choice(["quarter", "quarter", "half", "circle", "triangle", "stripes", "empty"])
            if kind == "quarter":
                corner = rng.randrange(4)
                cx, cy = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)][corner]
                d.pieslice([cx - cell, cy - cell, cx + cell, cy + cell], 90 * corner, 90 * corner + 90, fill=fg)
            elif kind == "half":
                side = rng.randrange(4)
                h = cell / 2
                cx, cy = [((x0 + x1) / 2, y0), (x1, (y0 + y1) / 2), ((x0 + x1) / 2, y1), (x0, (y0 + y1) / 2)][side]
                start = [0, 90, 180, 270][side]
                d.pieslice([cx - h, cy - h, cx + h, cy + h], start, start + 180, fill=fg)
            elif kind == "circle":
                inset = cell * rng.uniform(0.08, 0.2)
                d.ellipse([x0 + inset, y0 + inset, x1 - inset, y1 - inset], fill=fg)
            elif kind == "triangle":
                corners = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
                del corners[rng.randrange(4)]
                d.polygon(corners, fill=fg)
            elif kind == "stripes":
                bars = rng.choice([3, 4, 5])
                for b in range(bars):
                    if rng.random() < 0.5:
                        bx = x0 + cell * (b + 0.25) / bars
                        d.rectangle([bx, y0, bx + cell * 0.5 / bars, y1], fill=fg)
                    else:
                        by = y0 + cell * (b + 0.25) / bars
                        d.rectangle([x0, by, x1, by + cell * 0.5 / bars], fill=fg)
    return img


def style_bands(rng, pal, fam):
    bg = rgb(pal[0])
    cols = [rgb(c) for c in pal[1:]]
    base = rng.choice(cols)
    accent = rng.choice([c for c in cols if c != base] or cols)
    big = solid(bg, 2 * S)
    d = ImageDraw.Draw(big)
    y, k = 0.0, 0
    while y < 2 * S:
        h = S * rng.choice([0.015, 0.03, 0.03, 0.06, 0.1, 0.18])
        colour = accent if rng.random() < 0.15 else (base if k % 2 else bg)
        d.rectangle([0, y, 2 * S, y + h], fill=colour)
        y += h
        k += 1
    angle = rng.choice([0, 30, 45, -30, 60, 90, -15])
    img = big.rotate(angle, resample=Image.BICUBIC).crop((S // 2, S // 2, S // 2 + S, S // 2 + S))
    if rng.random() < 0.65:
        # A disc where the stripes turn the other way.
        r = S * rng.uniform(0.18, 0.32)
        cx, cy = S * rng.uniform(0.3, 0.7), S * rng.uniform(0.3, 0.7)
        other = big.rotate(angle + 90, resample=Image.BICUBIC).crop((S // 2, S // 2, S // 2 + S, S // 2 + S))
        img = Image.composite(other, img, disc_mask(cx, cy, r))
    return img


def style_rings(rng, pal, fam):
    bg, ink = rgb(pal[0]), rgb(pal[1])
    acc = [rgb(c) for c in pal[2:]]
    soft = fam in SOFT
    img = gradient([(0, bg), (1, mix(bg, ink, 0.08))], 90)
    d = ImageDraw.Draw(img)
    cx, cy = S * rng.uniform(0.3, 0.7), S * rng.uniform(0.3, 0.7)
    n = rng.randint(9, 24)
    biggest = S * rng.uniform(0.38, 0.62)
    special = rng.randrange(n)
    filled = rng.random() < 0.4
    line = mix(ink, bg, 0.65 if soft else 0.1)
    for k in range(n, 0, -1):
        r = biggest * k / n
        box = [cx - r, cy - r, cx + r, cy + r]
        if filled:
            d.ellipse(box, fill=mix(bg, rng.choice(acc), 0.25 + 0.6 * (k % 2) * (0.4 if soft else 1)))
        elif k == special:
            d.ellipse(box, outline=rng.choice(acc), width=10)
        else:
            d.ellipse(box, outline=line, width=3)
    return img


def style_lines(rng, pal, fam):
    bg, ink = rgb(pal[0]), rgb(pal[1])
    accent = rgb(rng.choice(pal[2:]))
    img = solid(bg)
    d = ImageDraw.Draw(img)
    n = rng.randint(26, 44)
    top, bottom, left, right = S * 0.24, S * 0.84, S * 0.16, S * 0.84
    peaks = [(rng.uniform(0.35, 0.65), rng.uniform(0.05, 0.12), rng.uniform(0.4, 1)) for _ in range(rng.randint(2, 4))]
    phases = [rng.uniform(0, 6.3) for _ in range(3)]
    special = rng.randrange(n)
    for k in range(n):
        y0 = top + (bottom - top) * k / (n - 1)
        pts = []
        for i in range(0, 121):
            x = i / 120
            envelope = sum(a * math.exp(-((x - c) / w) ** 2) for c, w, a in peaks)
            ripple = 0.55 + 0.45 * math.sin(k * 0.9 + x * 23 + phases[0]) * math.sin(k * 0.37 + x * 7 + phases[1])
            pts.append((left + (right - left) * x, y0 - S * 0.16 * envelope * ripple))
        d.polygon(pts + [(right, S), (left, S)], fill=bg)
        d.line(pts, fill=accent if k == special else mix(ink, bg, 0.15), width=4 if k == special else 3)
    return img


def style_riso(rng, pal, fam):
    paper = rgb(pal[0])
    inks = [rgb(c) for c in pal[2:]]
    rng.shuffle(inks)
    img = solid(paper)

    def plate():
        mask = Image.new("L", (S, S), 0)
        d = ImageDraw.Draw(mask)
        for _ in range(rng.randint(1, 3)):
            kind = rng.choice(["circle", "arch", "rect", "half", "waves"])
            cx, cy = rng.uniform(0.25, 0.75) * S, rng.uniform(0.25, 0.75) * S
            r = rng.uniform(0.15, 0.32) * S
            if kind == "circle":
                d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
            elif kind == "arch":
                d.rectangle([cx - r, cy, cx + r, cy + r * 1.4], fill=255)
                d.pieslice([cx - r, cy - r, cx + r, cy + r], 180, 360, fill=255)
            elif kind == "rect":
                d.rectangle([cx - r, cy - r * 0.7, cx + r * 0.8, cy + r], fill=255)
            elif kind == "half":
                d.pieslice([cx - r, cy - r, cx + r, cy + r], rng.choice([0, 90, 180, 270]),
                           rng.choice([0, 90, 180, 270]) + 180, fill=255)
            else:
                for w in range(rng.randint(3, 6)):
                    pts = [(x, cy + w * S * 0.05 + S * 0.025 * math.sin(x / S * 12 + w)) for x in range(0, S + 1, 12)]
                    d.line(pts, fill=255, width=int(S * 0.018))
        return mask

    # Ink darkens light paper; on dark paper it is printed as light.
    blend = ImageChops.multiply if luminance(paper) > 0.4 else ImageChops.screen
    for colour in inks[:2]:
        mask = ImageChops.offset(plate(), rng.randint(-10, 10), rng.randint(-10, 10))
        printed = blend(img, solid(colour))
        img = Image.composite(printed, img, mask)
    return img


def style_blocks(rng, pal, fam):
    bg, ink = rgb(pal[0]), rgb(pal[1])
    acc = [rgb(c) for c in pal[2:]]
    img = solid(bg)
    d = ImageDraw.Draw(img)
    layout = rng.choice(["top", "split", "grid"])
    if layout == "top":
        edge = S * rng.uniform(0.5, 0.64)
        d.rectangle([0, 0, S, edge], fill=acc[0])
        d.rectangle([0, edge, S, edge + S * 0.035], fill=acc[1 % len(acc)])
        r = S * rng.uniform(0.12, 0.2)
        cx, cy = S * rng.uniform(0.25, 0.75), edge * rng.uniform(0.35, 0.6)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=mix(bg, acc[0], 0.1))
    elif layout == "split":
        x = S * rng.uniform(0.3, 0.45)
        d.rectangle([0, 0, x, S * 0.64], fill=acc[0])
        for k in range(rng.randint(3, 5)):
            y = S * (0.1 + 0.1 * k)
            d.rectangle([x + S * 0.06, y, S * rng.uniform(0.7, 0.94), y + S * 0.035], fill=rng.choice(acc[1:] or acc))
    else:
        xs = sorted(rng.uniform(0.2, 0.8) for _ in range(2))
        ys = sorted(rng.uniform(0.15, 0.6) for _ in range(2))
        for i, (a, b) in enumerate(zip([0] + xs, xs + [1])):
            for j, (c, e) in enumerate(zip([0] + ys, ys + [0.66])):
                if rng.random() < 0.6:
                    d.rectangle([a * S + 8, c * S + 8, b * S - 8, e * S - 8], fill=rng.choice(acc + [bg]))
    return img


def style_pattern(rng, pal, fam):
    bg = rgb(pal[0])
    cols = [rgb(c) for c in pal[2:]]
    img = solid(bg)
    d = ImageDraw.Draw(img)
    n = rng.choice([4, 5, 6, 8])
    cell = S / n
    motif = rng.choice(["dots", "halves", "quarters", "checks"])
    for i in range(n):
        for j in range(n):
            x0, y0 = i * cell, j * cell
            c = cols[(i + 2 * j) % len(cols)]
            if motif == "dots":
                r = cell * 0.32
                d.ellipse([x0 + cell / 2 - r, y0 + cell / 2 - r, x0 + cell / 2 + r, y0 + cell / 2 + r], fill=c)
            elif motif == "halves":
                start = 180 if (i + j) % 2 else 0
                d.pieslice([x0, y0 + cell * 0.1, x0 + cell, y0 + cell * 1.1 - cell * 0.2], start, start + 180, fill=c)
            elif motif == "quarters":
                corner = (i * 3 + j) % 4
                cx, cy = [(x0, y0), (x0 + cell, y0), (x0 + cell, y0 + cell), (x0, y0 + cell)][corner]
                d.pieslice([cx - cell, cy - cell, cx + cell, cy + cell], 90 * corner, 90 * corner + 90, fill=c)
            elif (i + j) % 2:
                d.rectangle([x0, y0, x0 + cell, y0 + cell], fill=c)
    if rng.random() < 0.55:
        # A label in the middle, as on a twelve-inch.
        r = S * rng.uniform(0.2, 0.28)
        d.ellipse([S / 2 - r, S / 2 - r, S / 2 + r, S / 2 + r], fill=bg)
        r2 = r * 0.12
        d.ellipse([S / 2 - r2, S / 2 - r2, S / 2 + r2, S / 2 + r2], fill=rng.choice(cols))
    return img


DRAW = {"orbs": style_orbs, "sunset": style_sunset, "landscape": style_landscape, "bauhaus": style_bauhaus,
        "bands": style_bands, "rings": style_rings, "lines": style_lines, "riso": style_riso,
        "blocks": style_blocks, "pattern": style_pattern}


def area_luminance(img, box):
    small = img.crop(box).resize((8, 8), Image.BILINEAR)
    pixels = [small.getpixel((x, y)) for y in range(8) for x in range(8)]
    return sum(luminance(p) for p in pixels) / len(pixels)


def put_title(img, rng, fam, style, artist, album, ink, bg):
    d = ImageDraw.Draw(img)
    kind = TYPE_FOR.get(fam, "sans")
    if style == "blocks":
        # The poster: the artist big, the album small under it.
        name = artist.upper()
        size = 150
        while size > 40 and spaced_width(d, name, font("bold", size), 4) > S * 0.84:
            size -= 6
        y = S * 0.7
        spaced(d, (S * 0.08, y), name, font("bold", size), ink, 4)
        if readable(album):
            spaced(d, (S * 0.08, y + size * 1.15), album.upper(), font("sans", 40), mix(ink, bg, 0.25), 10)
        return
    corner = rng.choice(["tl", "bl", "br"])
    lines = [artist.upper()] + ([album.upper()] if readable(album) else [])
    fnts = [font(kind, 40), font("sans" if kind != "mono" else "mono", 30)]
    margin = S * 0.07
    widths = [spaced_width(d, line, f, 9) for line, f in zip(lines, fnts)]
    height = 40 + (48 if len(lines) > 1 else 0)
    x = margin if corner != "br" else S - margin - max(widths)
    y = margin if corner == "tl" else S - margin - height - 10
    box = (int(x), int(y), int(x + max(widths)), int(y + height + 10))
    colour = ink if abs(area_luminance(img, box) - luminance(ink)) > 0.35 else bg
    for k, (line, f) in enumerate(zip(lines, fnts)):
        spaced(d, (x, y + 48 * k), line, f, colour if k == 0 else mix(colour, bg, 0.2), 9)


def album_cover(album):
    """The cover before its grain (collages are made from these and grained
    once), the same without its type, and the grain's strength.

    The one without type is for the two-cover collage, which shows the
    middle half of each cover: the poster covers' names sit at 70% of the
    height and came out cut through ("MILES AHEAD QUARTET" twice, halved,
    on the Jazz genre). Copying draws nothing from `rng`, so every cover
    stays as it was."""
    rng = random.Random("cover " + album["Id"])
    genres = album.get("Genres") or []
    fam = family(genres, album["Id"])
    pal = rng.choice(PALETTES[fam])
    style = rng.choice(STYLES[fam])
    img = DRAW[style](rng, pal, fam)
    plain = None
    if style == "blocks" or rng.random() < 0.35:
        plain = img.copy()
        put_title(img, rng, fam, style, album.get("AlbumArtist") or "", album["Name"], rgb(pal[1]), rgb(pal[0]))
    strength = 0.18 if fam in SOFT else 0.28

    def finish(picture):
        return vignette(picture.resize((SIZE, SIZE), Image.LANCZOS), strength)
    img = finish(img)
    return img, (finish(plain) if plain else img), (0.15 if style in ("riso", "blocks", "bands") else 0.1)


# How many people are on an artist's photo, for this library's names; any
# other name gets one to four, by its id.
MEMBERS = {"The Lanterns": 4, "Paper Harbour": 3, "Glass Animals Club": 4, "Iron Meadow": 4, "Velvet Static": 3,
           "Nightdrive": 2, "Kalimba Sound System": 3, "Low Orbit": 1, "Hexagon Lights": 1,
           "Miles Ahead Quartet": 4, "Blue Room Trio": 3, "Saskia de Wit": 1, "MC Polder": 1, "Concrete Poets": 3,
           "Lyric Engine": 1, "Amsterdam Strings": 6, "Clara Venn": 1, "Willow & Pine": 2, "Old Mill Road": 3,
           "June Hollow": 1, "Neon Hearts": 3, "Sunny Side": 2, "Mira Lux": 1}
GUITARS = {"rock", "hardrock", "shoegaze", "alt", "indie", "folk"}
SINGERS = {"hiphop", "vocaljazz", "pop", "dance", "electropop"}


def vivid(c, saturation=0.55, value=0.9):
    h, s, v = colorsys.rgb_to_hsv(*(x / 255 for x in c))
    return tuple(round(x * 255) for x in colorsys.hsv_to_rgb(h, max(s, saturation), max(v, value)))


def bezier(p0, p1, p2, steps=14):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1])
            for t in (k / steps for k in range(steps + 1))]


def person(draw, x, hy, h, rng, guitar=False, hat=False):
    """Head and shoulders, front on; h is half the head's height."""
    draw.ellipse([x - h * 0.8, hy - h, x + h * 0.8, hy + h * 0.45], fill=255)        # crown
    draw.ellipse([x - h * 0.64, hy - h * 0.5, x + h * 0.64, hy + h], fill=255)       # jaw
    hair = rng.random()
    if hat:
        draw.ellipse([x - h * 1.4, hy - h * 0.6, x + h * 1.4, hy - h * 0.32], fill=255)
        draw.rounded_rectangle([x - h * 0.78, hy - h * 1.4, x + h * 0.78, hy - h * 0.45], radius=h * 0.3, fill=255)
    elif hair < 0.3:
        draw.ellipse([x - h * 1.02, hy - h * 1.25, x + h * 1.02, hy + h * 0.6], fill=255)  # curls
    elif hair < 0.45:
        draw.ellipse([x - h * 0.42, hy - h * 1.5, x + h * 0.42, hy - h * 0.7], fill=255)  # a bun
    draw.polygon([(x - h * 0.36, hy + h * 0.6), (x + h * 0.36, hy + h * 0.6),
                  (x + h * 0.46, hy + h * 1.45), (x - h * 0.46, hy + h * 1.45)], fill=255)
    for side in (-1, 1):
        # The neck's slope down to the shoulder, the shoulder's round, the arm.
        outline = bezier((x + side * h * 0.42, hy + h * 1.25), (x + side * h * 0.95, hy + h * 1.45),
                         (x + side * h * 1.75, hy + h * 1.9))
        outline += bezier((x + side * h * 1.75, hy + h * 1.9), (x + side * h * 2.45, hy + h * 2.05),
                          (x + side * h * 2.38, hy + h * 3.1))
        outline += [(x + side * h * 2.3, S + 10), (x, S + 10), (x, hy + h * 1.25)]
        draw.polygon(outline, fill=255)
    if guitar:
        # The neck of a guitar across the body, its head past the shoulder.
        a = (x - h * 1.4, hy + h * 5.0)
        b = (x + h * 3.3, hy + h * 1.7)
        draw.line([a, b], fill=255, width=max(4, int(h * 0.26)))
        draw.line([b, (b[0] + h * 0.55, b[1] - h * 0.36)], fill=255, width=max(6, int(h * 0.44)))


def artist_portrait(artist):
    """A stage photograph, not of anyone: coloured lights, a beam, haze, the
    band in silhouette, each with a rim of light, the ones at the back paler."""
    rng = random.Random("portrait " + artist["Id"])
    genres = artist.get("Genres") or []
    fam = family(genres, artist["Id"])
    pal = rng.choice(PALETTES[fam])
    accents = [rgb(c) for c in pal[2:]]
    lights = [vivid(c) for c in rng.sample(accents, k=min(2, len(accents)))]
    dark = mix(lights[0], (6, 6, 10), 0.86)
    img = solid(dark)
    for k, colour in enumerate(lights):
        lx = rng.uniform(0.1, 0.9)
        ly = rng.uniform(-0.2, 0.15)
        strength = 0.95 - 0.3 * k
        mask = radial(lx, ly, rng.uniform(0.75, 1.1)).point(lambda v, s=strength: round((255 - v) * s))
        img = Image.composite(solid(colour), img, mask)
        beam = Image.new("L", (S, S), 0)
        bx = lx * S
        spread = rng.uniform(0.1, 0.22) * S
        drift = rng.uniform(-0.25, 0.25) * S
        ImageDraw.Draw(beam).polygon([(bx - 12, ly * S), (bx + 12, ly * S), (bx + drift + spread, S),
                                      (bx + drift - spread, S)], fill=90)
        img = Image.composite(solid(mix(colour, (255, 255, 255), 0.3)), img, beam.filter(ImageFilter.GaussianBlur(35)))
    if rng.random() < 0.45:
        # A light straight behind the band.
        cx, cy, r = S * 0.5 + rng.uniform(-0.1, 0.1) * S, S * rng.uniform(0.32, 0.45), S * rng.uniform(0.25, 0.4)
        glow = disc_mask(cx, cy, r).filter(ImageFilter.GaussianBlur(r * 0.45)).point(lambda v: round(v * 0.8))
        img = Image.composite(solid(mix(lights[-1], (255, 255, 255), 0.45)), img, glow)
    w = 9
    haze = Image.frombytes("L", (w, w), rng.randbytes(w * w)).resize((S, S), Image.BICUBIC)
    hazy = mix(lights[0], (255, 255, 255), 0.5)
    img = Image.composite(solid(hazy), img, haze.point(lambda v: v // 6))

    members = MEMBERS.get(artist["Name"]) or 1 + int(artist["Id"][:2], 16) % 4
    spacing = min(0.22, 0.8 / members) * S
    scale = 1.0 if members == 1 else max(0.5, 0.92 - 0.07 * members)
    # Front and back: every other one a step back, smaller, higher, paler.
    people = []
    for m in range(members):
        depth = 0.0 if members == 1 else ((m + (members // 2)) % 2) * rng.uniform(0.6, 1.0)
        people.append((depth, m))
    people.sort(reverse=True)
    guitars = fam in GUITARS
    hats = fam == "folk"
    rim_colour = mix(lights[-1], (255, 255, 255), 0.5)
    for k, (depth, m) in enumerate(people):
        x = S / 2 + (m - (members - 1) / 2) * spacing + rng.uniform(-0.015, 0.015) * S
        h = S * 0.08 * scale * (1 - 0.14 * depth) * rng.uniform(0.94, 1.05)
        hy = S * (0.4 if members == 1 else 0.48) - depth * S * 0.045 + rng.uniform(-0.015, 0.02) * S
        mask = Image.new("L", (S, S), 0)
        draw = ImageDraw.Draw(mask)
        person(draw, x, hy, h, rng, guitar=guitars and depth == 0 and rng.random() < 0.7,
               hat=hats and rng.random() < 0.5)
        if members == 1 and fam in SINGERS:
            # A microphone at the mouth, on a boom stand beside the singer.
            foot = (x + h * 3.3, hy + h * 1.9)
            draw.line([(x + h * 0.55, hy + h * 0.55), (x + h * 1.25, hy + h * 0.85)], fill=255, width=int(h * 0.32))
            draw.line([(x + h * 1.1, hy + h * 0.8), foot], fill=255, width=max(4, int(h * 0.1)))
            draw.line([foot, (foot[0] + h * 0.15, S + 10)], fill=255, width=max(4, int(h * 0.12)))
        tone = mix(mix(dark, (0, 0, 0), 0.6), hazy, 0.28 * depth)
        img = Image.composite(solid(tone), img, mask.filter(ImageFilter.GaussianBlur(2 + 2 * depth)))
        rim = ImageChops.subtract(mask.filter(ImageFilter.MaxFilter(7)), mask)
        rim = rim.filter(ImageFilter.GaussianBlur(4)).point(lambda v, a=0.85 - 0.35 * depth: round(v * a))
        img = Image.composite(solid(rim_colour), img, rim)
    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    img = vignette(img, 0.3)
    return grain(img, rng, 0.16)


def collage(pictures, plain):
    """As Jellyfin makes them for genres and playlists: four covers in a
    square, or two halves when there are fewer than four (12.4's collage of
    a playlist with two albums is the two, one above the other). The halves
    come from `plain`, the covers without their type, which the crop would
    cut through."""
    if len(pictures) >= 4:
        out = Image.new("RGB", (SIZE, SIZE))
        half = SIZE // 2
        for k, p in enumerate(pictures[:4]):
            out.paste(p.resize((half, half), Image.LANCZOS), ((k % 2) * half, (k // 2) * half))
        return out
    if len(pictures) >= 2:
        out = Image.new("RGB", (SIZE, SIZE))
        quarter = SIZE // 4
        for k, p in enumerate(plain[:2]):
            out.paste(p.crop((0, quarter, SIZE, SIZE - quarter)), (0, k * SIZE // 2))
        return out
    return pictures[0].copy()


def jpeg(img, budget_kb):
    """The best quality under the budget."""
    data = b""
    for quality in (88, 84, 80, 76, 72, 68, 64, 60, 56, 50):
        buf = io.BytesIO()
        img.save(buf, "JPEG", quality=quality, optimize=True, progressive=True)
        data = buf.getvalue()
        if len(data) <= budget_kb * 1024:
            break
    return data


def make_pictures(items, entries, out_dir):
    """Every album, album artist, genre and demo playlist gets a picture;
    the image tags in `items` follow them, as Jellyfin's do."""
    images = os.path.join(out_dir, "images")
    shutil.rmtree(images, ignore_errors=True)
    os.makedirs(images)
    by_type = {}
    for item in items:
        by_type.setdefault(item["Type"], []).append(item)
    album_art = {}
    tags = {}
    # Grain for a collage: seeded by the item, as everything else.
    def grained(item_id, img, amount=0.08):
        return grain(img, random.Random("grain " + item_id), amount)

    def save(item_id, img, budget):
        data = jpeg(img, budget)
        with open(os.path.join(images, item_id + ".jpg"), "wb") as f:
            f.write(data)
        tags[item_id] = hashlib.md5(data).hexdigest()
        return len(data)

    plain_art = {}
    sizes = {}
    for album in by_type.get("MusicAlbum", []):
        album_art[album["Id"]], plain_art[album["Id"]], amount = album_cover(album)
        sizes.setdefault("album covers", []).append(
            save(album["Id"], grained(album["Id"], album_art[album["Id"]], amount), 33))
    albums_of_artist = {}
    for album in by_type.get("MusicAlbum", []):
        for ref in album.get("AlbumArtists") or []:
            albums_of_artist.setdefault(ref.get("Id"), []).append(album)
    for artist in by_type.get("MusicArtist", []):
        if artist["Id"] in albums_of_artist:
            sizes.setdefault("artist photos", []).append(save(artist["Id"], artist_portrait(artist), 28))
    for genre in by_type.get("MusicGenre", []):
        theirs = sorted([a for a in by_type.get("MusicAlbum", []) if genre["Name"] in (a.get("Genres") or [])],
                        key=lambda a: a["Id"])
        if theirs:
            pictures = collage([album_art[a["Id"]] for a in theirs], [plain_art[a["Id"]] for a in theirs])
            sizes.setdefault("genre collages", []).append(save(genre["Id"], grained(genre["Id"], pictures), 27))
    track_album = {t["Id"]: t.get("AlbumId") for t in by_type.get("Audio", [])}
    for playlist in by_type.get("Playlist", []):
        seen = []
        for track_id in entries.get(playlist["Id"], []):
            album_id = track_album.get(track_id)
            if album_id in album_art and album_id not in seen:
                seen.append(album_id)
        if seen:
            pictures = collage([album_art[a] for a in seen], [plain_art[a] for a in seen])
            sizes.setdefault("playlist collages", []).append(save(playlist["Id"], grained(playlist["Id"], pictures), 27))

    for item in items:
        if item["Id"] in tags:
            item["ImageTags"] = {"Primary": tags[item["Id"]]}
            if "PrimaryImageAspectRatio" in item:
                item["PrimaryImageAspectRatio"] = 1
        elif item["Type"] in ("MusicArtist", "MusicGenre", "Playlist"):
            item["ImageTags"] = {}
            item.pop("PrimaryImageAspectRatio", None)
        if item["Type"] == "Audio" and item.get("AlbumId") in tags:
            item["AlbumPrimaryImageTag"] = tags[item["AlbumId"]]
    for kind, list_ in sizes.items():
        print(f"  {len(list_)} {kind}: {sum(list_) // 1024} KB, {min(list_) // 1024}–{max(list_) // 1024} KB each")
    return album_art


def contact_sheet(out_dir, path):
    names = sorted(os.listdir(os.path.join(out_dir, "images")))
    columns = 10
    cell = 150
    rows = (len(names) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * cell, rows * cell), (20, 20, 20))
    for k, name in enumerate(names):
        img = Image.open(os.path.join(out_dir, "images", name)).resize((cell - 6, cell - 6), Image.LANCZOS)
        sheet.paste(img, ((k % columns) * cell + 3, (k // columns) * cell + 3))
    sheet.save(path, quality=88)
    print(f"contact sheet: {path}")


# ---------------------------------------------------------------------------
# Sound: four eight-second clips, synthesised here and encoded to AAC by
# ffmpeg. Every track plays the one for its corner of the library.

RATE = 44100
SECONDS = 8.0


def hz(note):
    return 440.0 * 2 ** ((note - 69) / 12)


class Mix:
    def __init__(self):
        self.n = int(SECONDS * RATE)
        self.left = [0.0] * self.n
        self.right = [0.0] * self.n

    def add(self, start, samples, pan=0.0):
        gl = math.cos((pan + 1) * math.pi / 4)
        gr = math.sin((pan + 1) * math.pi / 4)
        i0 = int(start * RATE)
        left, right = self.left, self.right
        for k, v in enumerate(samples):
            i = i0 + k
            if i >= self.n:
                break
            left[i] += v * gl
            right[i] += v * gr


def envelope(samples, attack, release):
    n = len(samples)
    a, r = max(1, int(attack * RATE)), max(1, int(release * RATE))
    for i in range(min(a, n)):
        samples[i] *= i / a
    for i in range(max(0, n - r), n):
        samples[i] *= (n - i) / r
    return samples


def epiano(f, length, amp):
    """An electric piano: a few partials, the upper ones dying first."""
    n = int(length * RATE)
    out = [0.0] * n
    for ratio, a, decay in ((1, 1.0, 1.3), (2, 0.3, 2.6), (3, 0.09, 4.5), (7.02, 0.035, 12)):
        if f * ratio > 9000:
            continue
        w = 2 * math.pi * f * ratio / RATE
        g = a
        k = math.exp(-decay / RATE)
        for i in range(n):
            out[i] += g * math.sin(w * i)
            g *= k
    return envelope([v * amp for v in out], 0.004, 0.06)


def pad(f, length, amp):
    """Two slightly detuned, soft saw-like voices."""
    n = int(length * RATE)
    out = [0.0] * n
    for detune in (0.997, 1.003):
        for h in range(1, 5):
            w = 2 * math.pi * f * detune * h / RATE
            a = 0.5 / h
            for i in range(n):
                out[i] += a * math.sin(w * i)
    for i in range(n):
        out[i] *= amp * (1 + 0.08 * math.sin(2 * math.pi * 0.4 * i / RATE))
    return envelope(out, 0.5, 0.7)


def bell(f, length, amp, decay=9.0):
    n = int(length * RATE)
    w = 2 * math.pi * f / RATE
    out = []
    g = amp
    k = math.exp(-decay / RATE)
    for i in range(n):
        out.append(g * (math.sin(w * i) + 0.25 * math.sin(2 * w * i)))
        g *= k
    return envelope(out, 0.003, 0.03)


def bass(f, length, amp, decay=2.5):
    n = int(length * RATE)
    w = 2 * math.pi * f / RATE
    out = []
    g = amp
    k = math.exp(-decay / RATE)
    for i in range(n):
        out.append(g * (math.sin(w * i) + 0.3 * math.sin(2 * w * i)))
        g *= k
    return envelope(out, 0.006, 0.05)


def kick(amp):
    n = int(0.35 * RATE)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        phase += 2 * math.pi * (45 + 90 * math.exp(-t * 32)) / RATE
        out.append(amp * math.sin(phase) * math.exp(-t * 9))
    return envelope(out, 0.001, 0.02)


def snap(rng, amp):
    n = int(0.12 * RATE)
    out, last = [], 0.0
    for i in range(n):
        noise = rng.uniform(-1, 1)
        high = noise - last
        last = noise
        out.append(amp * high * math.exp(-i / RATE * 38))
    return out


def string(rng, f, length, amp, bright=0.5):
    """Karplus–Strong: a plucked string."""
    period = max(2, int(round(RATE / f)))
    buf = [rng.uniform(-1, 1) for _ in range(period)]
    for _ in range(int(1 + (1 - bright) * 5)):
        buf = [(buf[i] + buf[i - 1]) * 0.5 for i in range(period)]
    n = int(length * RATE)
    out = [0.0] * n
    idx = 0
    for i in range(n):
        v = buf[idx]
        nxt = idx + 1 if idx + 1 < period else 0
        buf[idx] = 0.4985 * (v + buf[nxt])
        out[i] = v * amp
        idx = nxt
    return envelope(out, 0.002, 0.04)


def echo(samples, delay, feedback, wet):
    d = int(delay * RATE)
    out = list(samples)
    for i in range(d, len(out)):
        out[i] += out[i - d] * feedback
    return [s * (1 - wet) + o * wet for s, o in zip(samples, out)]


def reverb(channel, wet, seed):
    """Schroeder: four combs, two all-passes. Different delays per side."""
    combs = [1557, 1617, 1491, 1422] if seed == 0 else [1580, 1640, 1514, 1445]
    out = [0.0] * len(channel)
    for d in combs:
        buf = [0.0] * d
        idx = 0
        for i, x in enumerate(channel):
            y = buf[idx]
            buf[idx] = x + y * 0.8
            out[i] += y * 0.25
            idx = idx + 1 if idx + 1 < d else 0
    for d in (225, 556):
        buf = [0.0] * d
        idx = 0
        for i in range(len(out)):
            b = buf[idx]
            x = out[i]
            y = -x + b
            buf[idx] = x + b * 0.5
            out[i] = y
            idx = idx + 1 if idx + 1 < d else 0
    return [c + o * wet for c, o in zip(channel, out)]


def clip_keys():
    """Jazz, classical: an electric piano through ii–V–I–vi, with bass."""
    m = Mix()
    chords = [(38, [65, 69, 72, 76]), (31, [65, 71, 76, 81]), (36, [64, 67, 71, 74]), (33, [67, 71, 72, 76])]
    for bar, (root, notes) in enumerate(chords):
        t = bar * 2.0
        for k, note in enumerate(notes):
            m.add(t + 0.012 * k, epiano(hz(note), 1.9, 0.11), pan=-0.3 + 0.2 * k)
            m.add(t + 1.25 + 0.01 * k, epiano(hz(note), 0.7, 0.06), pan=-0.3 + 0.2 * k)
        m.add(t, bass(hz(root), 0.95, 0.32))
        m.add(t + 1.0, bass(hz(root + 7), 0.95, 0.26))
    melody = [(0.5, 81), (0.75, 79), (1.0, 77), (2.5, 77), (2.75, 76), (3.0, 74), (4.5, 76), (4.75, 79),
              (5.0, 83), (6.5, 84), (6.75, 83), (7.0, 79)]
    for t, note in melody:
        m.add(t, epiano(hz(note), 0.9, 0.07), pan=0.25)
    return m, 0.28


def clip_drive():
    """Electronic: a pad through Am–F–C–G, an arpeggio with an echo, a soft kick."""
    m = Mix()
    chords = [[57, 60, 64], [53, 57, 60], [55, 60, 64], [55, 59, 62]]
    for bar, notes in enumerate(chords):
        for k, note in enumerate(notes):
            m.add(bar * 2.0, pad(hz(note), 2.3, 0.05), pan=-0.4 + 0.4 * k)
        m.add(bar * 2.0, bass(hz(notes[0] - 24), 1.9, 0.22, decay=1.0))
    arp = []
    for bar, notes in enumerate(chords):
        pattern = [notes[0] + 12, notes[1] + 12, notes[2] + 12, notes[1] + 24]
        for step in range(16):
            arp.append((bar * 2.0 + step * 0.125, pattern[step % 4]))
    line = [0.0] * m.n
    for t, note in arp:
        i0 = int(t * RATE)
        for k, v in enumerate(bell(hz(note), 0.3, 0.06, decay=14)):
            if i0 + k < m.n:
                line[i0 + k] += v
    m.add(0, echo(line, 0.375, 0.35, 0.4), pan=0.2)
    for beat in range(16):
        m.add(beat * 0.5, kick(0.28 if beat % 2 == 0 else 0.18))
    return m, 0.3


def clip_bright():
    """Pop, dance, hip-hop: I–V–vi–IV, plucked chords on the off-beats, a beat."""
    rng = random.Random("bright")
    m = Mix()
    chords = [(38, [62, 66, 69, 74]), (33, [61, 64, 69, 73]), (35, [62, 66, 71, 74]), (31, [62, 67, 71, 74])]
    for bar, (root, notes) in enumerate(chords):
        t0 = bar * 2.0
        for off in (0.25, 0.75, 1.25, 1.75):
            for k, note in enumerate(notes):
                m.add(t0 + off + 0.004 * k, string(rng, hz(note), 0.24, 0.09, bright=0.9), pan=-0.35 + 0.23 * k)
        for off in (0.25, 0.75, 1.25, 1.75):
            m.add(t0 + off, bass(hz(root), 0.22, 0.3, decay=6))
    for beat in range(16):
        m.add(beat * 0.5, kick(0.42))
        if beat % 2:
            m.add(beat * 0.5, snap(rng, 0.12), pan=0.1)
    hook = [(0.0, 78), (0.5, 76), (1.0, 74), (1.5, 76), (2.0, 76), (2.5, 73), (3.0, 69), (4.0, 78), (4.5, 81),
            (5.0, 83), (5.5, 81), (6.0, 79), (6.5, 78), (7.0, 74)]
    for t, note in hook:
        m.add(t, bell(hz(note), 0.45, 0.07, decay=6), pan=0.3)
    return m, 0.18


def clip_strings():
    """Guitars and folk: an acoustic guitar strumming G–D–Em–C, a bass note."""
    rng = random.Random("strings")
    m = Mix()
    chords = [(43, [43, 47, 50, 55, 59, 67]), (38, [50, 57, 62, 66]), (40, [40, 47, 52, 55, 59, 64]),
              (36, [48, 52, 55, 60, 64])]
    strums = [(0.0, "D", 1.0), (0.5, "D", 0.8), (0.75, "U", 0.55), (1.25, "U", 0.55), (1.5, "D", 0.8),
              (1.75, "U", 0.5)]
    for bar, (root, notes) in enumerate(chords):
        t0 = bar * 2.0
        for k, (off, way, force) in enumerate(strums):
            ring = (strums[k + 1][0] if k + 1 < len(strums) else 2.0) - off + 0.05
            order = notes if way == "D" else list(reversed(notes))[:4]
            for s, note in enumerate(order):
                m.add(t0 + off + s * (0.011 if way == "D" else 0.008),
                      string(rng, hz(note), ring, 0.08 * force, bright=0.55), pan=-0.3 + 0.1 * s)
        m.add(t0, bass(hz(root - 12 if root > 40 else root), 1.9, 0.18, decay=1.2))
    return m, 0.22


CLIPS = {"keys": clip_keys, "drive": clip_drive, "bright": clip_bright, "strings": clip_strings}


def ffmpeg_command():
    if shutil.which("ffmpeg"):
        return lambda folder, src, dst: ["ffmpeg", "-loglevel", "error", "-y", "-i", os.path.join(folder, src),
                                          "-c:a", "aac", "-b:a", "64k", "-movflags", "+faststart",
                                          "-map_metadata", "-1", os.path.join(folder, dst)]
    # The Jellyfin image's own ffmpeg, through Docker.
    return lambda folder, src, dst: ["docker", "run", "--rm", "-v", f"{folder}:/w", "--entrypoint",
                                      "/usr/lib/jellyfin-ffmpeg/ffmpeg", "jellyfin/jellyfin:latest", "-loglevel",
                                      "error", "-y", "-i", f"/w/{src}", "-c:a", "aac", "-b:a", "64k", "-movflags",
                                      "+faststart", "-map_metadata", "-1", f"/w/{dst}"]


def make_audio(out_dir):
    folder = os.path.join(out_dir, "audio")
    shutil.rmtree(folder, ignore_errors=True)
    os.makedirs(folder)
    command = ffmpeg_command()
    with tempfile.TemporaryDirectory() as work:
        for name, make in CLIPS.items():
            m, wet = make()
            left, right = reverb(m.left, wet, 0), reverb(m.right, wet, 1)
            peak = max(max(abs(v) for v in left), max(abs(v) for v in right)) or 1
            fade = int(0.6 * RATE)
            frames = bytearray()
            for i in range(m.n):
                g = 0.85 / peak * min(1.0, i / 200, (m.n - i) / fade)
                frames += struct.pack("<hh", int(math.tanh(left[i] * g) * 32000), int(math.tanh(right[i] * g) * 32000))
            with wave.open(os.path.join(work, name + ".wav"), "wb") as w:
                w.setnchannels(2)
                w.setsampwidth(2)
                w.setframerate(RATE)
                w.writeframes(bytes(frames))
            subprocess.run(command(work, name + ".wav", name + ".m4a"), check=True)
            shutil.copy(os.path.join(work, name + ".m4a"), folder)
            print(f"  audio/{name}.m4a: {os.path.getsize(os.path.join(folder, name + '.m4a')) // 1024} KB")


# ---------------------------------------------------------------------------
# Putting it together

def strip(item):
    """What is not worth keeping: blur hashes of the old pictures, and the
    server id on every item (the fake puts it back)."""
    item.pop("ImageBlurHashes", None)
    item.pop("ServerId", None)
    return item


def write_items(path, items):
    with open(path, "w", encoding="utf-8") as f:
        f.write('{"Items": [\n')
        f.write(",\n".join(json.dumps(i, ensure_ascii=False, separators=(",", ":")) for i in items))
        f.write("\n]}\n")


def write_json(path, value):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(value, f, ensure_ascii=False, indent=1)
        f.write("\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--url", default=os.environ.get("JELLYFIN_URL", "http://localhost:8096"))
    parser.add_argument("--user", default="test")
    parser.add_argument("--password", default="test")
    parser.add_argument("--out", default=os.path.join(HERE, "demo"))
    parser.add_argument("--pictures-only", action="store_true", help="redraw the pictures, change nothing else")
    parser.add_argument("--no-audio", action="store_true", help="keep the clips that are there")
    parser.add_argument("--sheet", help="also write a contact sheet of every picture to this file")
    args = parser.parse_args()
    out = os.path.abspath(args.out)
    os.makedirs(out, exist_ok=True)

    if args.pictures_only:
        with open(os.path.join(out, "items.json"), encoding="utf-8") as f:
            items = json.load(f)["Items"]
        with open(os.path.join(out, "relations.json"), encoding="utf-8") as f:
            relations = json.load(f)
        make_pictures(items, relations["playlists"], out)
        write_items(os.path.join(out, "items.json"), items)
    else:
        rec = record(args.url, args.user, args.password)
        now = datetime.now(timezone.utc)
        for kind in ("tracks", "albums", "albumArtists", "otherArtists", "genres"):
            for item in rec[kind]:
                strip(item)
        strip(rec["playlistTemplate"])
        # The fake serves every track as AAC in M4A: say so.
        for track in rec["tracks"]:
            track["Container"] = "mov,mp4,m4a,3gp,3g2,mj2"
        make_listener(rec, now)
        playlists, entries = make_playlists(rec, now)
        lyrics = make_lyrics(rec["tracks"])
        items = rec["tracks"] + rec["albums"] + rec["albumArtists"] + rec["otherArtists"] + rec["genres"] + playlists
        make_pictures(items, entries, out)
        audio = {t["Id"]: CLIP[family(t.get("Genres") or [], t["Id"])] for t in rec["tracks"]}
        if not args.no_audio:
            make_audio(out)

        public = dict(rec["public"])
        public["ServerName"] = DEMO_SERVER_NAME
        public.pop("LocalAddress", None)
        sign_in = rec["signIn"]
        sign_in["AccessToken"] = ""
        template = rec["playlistTemplate"]
        template["ImageTags"] = {}
        write_json(os.path.join(out, "server.json"), {
            "recordedAt": format_date(now),
            "publicInfo": public,
            "user": rec["me"],
            "signIn": sign_in,
            "views": [strip(v) for v in rec["views"]],
            "fields": rec["fields"],
            "playlistTemplate": template,
        })
        write_items(os.path.join(out, "items.json"), items)
        write_json(os.path.join(out, "relations.json"), {
            "albumArtists": [a["Id"] for a in rec["albumArtists"]],
            "similar": rec["similar"],
            "playlists": entries,
            "audio": audio,
        })
        write_json(os.path.join(out, "lyrics.json"), lyrics)
        print(f"lyrics for {len(lyrics)} tracks")

    if args.sheet:
        contact_sheet(out, args.sheet)
    total = sum(os.path.getsize(os.path.join(root, f)) for root, _, files in os.walk(out) for f in files)
    print(f"{out}: {total / 1024 / 1024:.2f} MB")


if __name__ == "__main__":
    sys.exit(main())
