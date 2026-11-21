# Jukebox, as it looks

Every main screen of the app, walked in the iOS Simulator on GitHub's Mac against a made-up
Jellyfin library (`dev/fake-jellyfin.swift`), by `ci/screenshots.sh` after each push. This branch
holds the latest round of mac and main at its top, and the latest of each work branch in
`branches/<name>/`: each round replaces its own. The iPad's pictures are named as their twins
in Linux's walk (`Linux/App/Shots.swift`, 1440x900; upright, 760x900).

From `d359d65` on `cleanup-walk`, run 130, 2026-11-15 11:52 UTC.

## iPhone

iPhone 17 Pro, iOS 26.5, 29 pictures.
[Every picture](iphone/) · [the sheet at full size](iphone-sheet.png)

- iphone-dark: Passed
- iphone-light: Passed

[![The iPhone's screens](iphone-sheet.jpg)](iphone-sheet.png)


## iPad

iPad Pro 13-inch (M5), iOS 26.5, 23 pictures.
[Every picture](ipad/) · [the sheet at full size](ipad-sheet.png)

- ipad-dark: Passed

[![The iPad's screens](ipad-sheet.jpg)](ipad-sheet.png)

Steps that found nothing to tap:

```
ipad-dark: after 16-preferences: skipped: no place.search within 3 s
```

## iPad, upright

iPad Pro 11-inch (M5), iOS 26.5, 3 pictures.
[Every picture](ipad11/) · [the sheet at full size](ipad11-sheet.png)

- ipad11-dark: Passed

[![The iPad, upright's screens](ipad11-sheet.jpg)](ipad11-sheet.png)


## Problems in this round

- the iphone simulator did not turn dark
