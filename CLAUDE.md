# Jukebox

The photographer's music app for their Jellyfin server, iPhone and iPad,
SwiftUI. `docs/ARCHITECTURE.md` is how it is built and who owns what; read it
first. `docs/RADIO.md` is how the radio chooses, with measurements.

- `JukeboxKit/` is Foundation only and is tested on Linux: `dev/jellyfin-test-server.sh`
  starts a real Jellyfin with a made-up library in Docker, `dev/kit-test.sh`
  builds and tests the package against it.
- `Jukebox/` (the app) is compiled only by CI on GitHub's macOS (`ci/app.sh`);
  there is no Mac here, so read Swift twice before pushing it.
- The workflow file is generic and calls `ci/*.sh`: the session's token may not
  push workflow files, so change the scripts, not the workflow.
- A commit message with `[testflight]` uploads that build to TestFlight.
- Native first (HIG, SF Symbols, Apple's controls); Numa's signatures from
  `Theme.swift` — the white accent, the eclipse, grey section labels.
- Comments say why; the photographer's words where they decided something.
