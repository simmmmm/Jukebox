# Jukebox

The photographer's music app for their own music server (Jellyfin, Navidrome
and the other Subsonic servers): iPhone and iPad in SwiftUI, Linux in GTK 4
and libadwaita, one Swift codebase under both. `docs/ARCHITECTURE.md` is how
it is built and who owns what; read it first. `docs/RADIO.md` is how the
radio chooses, with measurements; `docs/LINUX.md` is the Linux client.

- `JukeboxKit/` is Foundation only and is tested on Linux: `dev/jellyfin-test-server.sh`
  starts a real Jellyfin with a made-up library in Docker, `dev/kit-test.sh`
  builds and tests the package against it.
- `Jukebox/` (the iPhone's app) is compiled only by CI on GitHub's macOS
  (`ci/app.sh`); there is no Mac here, so read Swift twice before pushing it.
  The files named in `Package.swift`'s `shared` are Linux's too: those do
  compile here, so build Linux after changing one.
- `Linux/` is the Linux client, built and run here: `dev/linux-build.sh`
  (Docker, no Swift needed on the machine), then `.build-linux/debug/Jukebox`.
- The workflow file is generic and calls `ci/*.sh`: the session's token may not
  push workflow files, so change the scripts, not the workflow.
- A commit message with `[testflight]` anywhere in it, body included, uploads
  that build to TestFlight (and skips the plain build and the screenshots).
- Each platform at its best: Apple's HIG, SF Symbols and controls on the
  iPhone; GNOME's HIG and libadwaita's own widgets on Linux ("ik wil net als
  met numa dat het vooral super nice werkt op gnome"). On both, Jukebox's
  own soul, the Arch, from `Theme.swift` (`Linux/App/Style.swift`) and
  `docs/BRAND.md` — Copper and Glow, the mark, a serif for titles as on
  sleeves, flat grounds, light for the station on air.
- A screen should feel made by someone with taste: `docs/design/tells.md`
  says what gives it that, with a checklist to walk before a screen ships.
- Guidance like this file says what to aim for: "niet 'minder ai' maar
  vooral meer ziel" (the photographer, 14 November 2026).
- Comments say why; the photographer's words where they decided something.
- Commits are the photographer's: author and committer `simmmmm
  <38768749+simmmmm@users.noreply.github.com>` (set in the clone's git
  config), and no Claude co-author line — "Maak mij de main contributor van
  alles ipv jou" (8 November 2026).
