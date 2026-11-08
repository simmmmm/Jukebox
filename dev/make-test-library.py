#!/usr/bin/env python3
"""A small, made-up music library for the Jellyfin test server
(dev/jellyfin-test-server.sh): tagged tones in the formats a real library
has (MP3, FLAC, AAC in M4A), with album covers, so JukeboxKit's tests run
against a real Jellyfin and the radio can be measured on a library with
genres, eras and artists that belong together.

Prints a shell script of ffmpeg calls; the server script runs it inside the
Jellyfin image, which brings its own ffmpeg.

    python3 dev/make-test-library.py > /tmp/gen.sh
"""
import random
import shlex

random.seed(7)

# artist, genres, first year, cover colour. Clusters on purpose: the radio
# is measured by whether it stays inside one and drifts to a neighbour.
ARTISTS = [
    ("The Lanterns", ["Rock", "Alternative"], 1994, "0x8a3b2c"),
    ("Paper Harbour", ["Alternative", "Indie"], 2003, "0x2c5d8a"),
    ("Glass Animals Club", ["Indie", "Alternative"], 2012, "0x6d2c8a"),
    ("Iron Meadow", ["Rock", "Hard Rock"], 1979, "0x5a5a5a"),
    ("Velvet Static", ["Rock", "Shoegaze"], 1991, "0x8a2c6d"),
    ("Nightdrive", ["Electronic", "Synthwave"], 2015, "0x2c8a7a"),
    ("Kalimba Sound System", ["Electronic", "House"], 2008, "0x8a7a2c"),
    ("Low Orbit", ["Electronic", "Ambient"], 1998, "0x1f3a5a"),
    ("Hexagon Lights", ["Electronic", "Techno"], 2019, "0x3a1f5a"),
    ("Miles Ahead Quartet", ["Jazz"], 1962, "0x5a3a1f"),
    ("Blue Room Trio", ["Jazz", "Bebop"], 1957, "0x1f5a4a"),
    ("Saskia de Wit", ["Jazz", "Vocal Jazz"], 2010, "0x5a1f2a"),
    ("MC Polder", ["Hip-Hop", "Nederhop"], 2006, "0x2a5a1f"),
    ("Concrete Poets", ["Hip-Hop"], 1996, "0x4a4a2a"),
    ("Lyric Engine", ["Hip-Hop", "Rap"], 2018, "0x2a2a4a"),
    ("Amsterdam Strings", ["Classical"], 1985, "0x6a5a3a"),
    ("Clara Venn", ["Classical", "Piano"], 2001, "0x3a5a6a"),
    ("Willow & Pine", ["Folk", "Acoustic"], 2009, "0x3a6a3a"),
    ("Old Mill Road", ["Folk", "Americana"], 1972, "0x6a4a2a"),
    ("June Hollow", ["Folk", "Indie"], 2016, "0x4a6a5a"),
    ("Neon Hearts", ["Pop"], 1986, "0x8a2c4a"),
    ("Sunny Side", ["Pop", "Dance"], 2011, "0x8a6a2c"),
    ("Mira Lux", ["Pop", "Electronic"], 2021, "0x6a2c8a"),
]

WORDS = ["Night", "River", "Glass", "Summer", "Echo", "Signal", "Paper", "Gold",
         "Winter", "Harbour", "Lights", "Static", "Morning", "Ghost", "Fire",
         "Silver", "Northern", "Quiet", "Wild", "Electric", "Ocean", "Dust",
         "Velvet", "Hollow", "Neon", "Iron", "Blue", "Red", "Satellite", "Rain"]
NOUNS = ["Song", "Drive", "Waltz", "Dream", "Line", "Heart", "City", "Road",
         "Garden", "Room", "Sky", "Tide", "Fields", "Machine", "Letters",
         "Parade", "Window", "Dance", "Story", "Mirror"]

FORMATS = [("mp3", ["-c:a", "libmp3lame", "-b:a", "128k"]),
           ("flac", ["-c:a", "flac"]),
           ("m4a", ["-c:a", "aac", "-b:a", "128k"])]


def title():
    return f"{random.choice(WORDS)} {random.choice(NOUNS)}"


def q(s):
    return shlex.quote(s)


print("set -e")
print("FF=/usr/lib/jellyfin-ffmpeg/ffmpeg")
print("mkdir -p /media/music")
names = [a[0] for a in ARTISTS]
for index, (artist, genres, first, colour) in enumerate(ARTISTS):
    albums = 2 if index % 3 else 3
    for a in range(albums):
        year = first + a * random.randint(2, 6)
        album = f"{random.choice(WORDS)} {random.choice(NOUNS)}s"
        ext, codec = FORMATS[(index + a) % len(FORMATS)]
        folder = f"/media/music/{artist}/{year} - {album}"
        print(f"mkdir -p {q(folder)}")
        print(f"$FF -loglevel error -y -f lavfi -i color=c={colour}:s=600x600 "
              f"-frames:v 1 {q(folder + '/folder.jpg')}")
        tracks = random.randint(5, 8)
        for t in range(1, tracks + 1):
            name = title()
            # A guest on one track in five, from the same cluster or the next.
            performers = artist
            if random.random() < 0.2:
                guest = names[(index + random.choice([1, 2, -1])) % len(names)]
                performers = f"{artist}; {guest}"
            freq = 220 + (index * 37 + a * 11 + t * 5) % 600
            seconds = random.choice([5, 6, 7, 8])
            out = f"{folder}/{t:02d} {name}.{ext}"
            meta = ["-metadata", f"title={name}", "-metadata", f"artist={performers}",
                    "-metadata", f"album_artist={artist}", "-metadata", f"album={album}",
                    "-metadata", f"track={t}/{tracks}", "-metadata", "disc=1",
                    "-metadata", f"date={year}", "-metadata", f"genre={'; '.join(genres)}"]
            args = ["$FF", "-loglevel", "error", "-y", "-f", "lavfi", "-i",
                    f"sine=frequency={freq}:duration={seconds}", *codec, *meta, out]
            print(" ".join(a if a == "$FF" else q(a) for a in args))
print("echo made the library")
