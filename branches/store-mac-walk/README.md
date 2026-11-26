# Jukebox, as it looks

Every main screen of the app, walked in the iOS Simulator on GitHub's runner against a made-up
Jellyfin library (`dev/fake-jellyfin.swift`), by `ci/screenshots.sh` after each push. This branch
holds the latest round of runner and main at its top, and the latest of each work branch in
`branches/<name>/`: each round replaces its own. The iPad's pictures are named as their twins
in Linux's walk (`Linux/App/Shots.swift`, 1440x900; upright, 760x900).

From `80ec445` on `store-runner-walk`, run 148, 2026-11-15 22:22 UTC.

## runner

macOS 26.7.2, 7 pictures.
[Every picture](runner/) · [the sheet at full size](runner-sheet.png)

- runner-dark: Passed

[![The runner's screens](runner-sheet.jpg)](runner-sheet.png)

Steps that found nothing to tap:

```
runner-dark: after 04-now-playing: Albums: no cover of Silver Roads after thirty scrolls; the first in the window instead
runner-dark: after 04-now-playing: the bar's song was not Night Drive within 15 s
```
