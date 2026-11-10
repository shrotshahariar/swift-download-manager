# Swift DM

A native Mac download manager modeled on [Motrix](https://github.com/agalwood/Motrix), built with SwiftUI instead of Electron.
It uses the same engine as Motrix (aria2) and comes with a Chrome extension that catches your downloads automatically.

## Features

**Downloads**
- HTTP, HTTPS, FTP, BitTorrent and magnet links, with up to 16 connections per file
- Downloading / Waiting / Completed / Stopped lists, plus search
- Pause, resume, restart, copy link or magnet, show in Finder, remove (with or without deleting files)
- New-download sheet: rename, save folder with recent folders, connections, and advanced User-Agent, Referer, Cookie, Authorization and Proxy
- Torrents: see the files inside before adding, pick which ones to download, and change your selection later
- Details panel: general info, live activity with a piece map, files, peers (with client names) and trackers
- Drag and drop links, magnets or .torrent files onto the window
- Downloads survive quitting and relaunching

**Dashboard**
- Widgets: engine status, speed mode (full / limited / quiet), live download and upload graphs, active tasks, transfer totals (today / all time), a year-long activity heatmap, a task list, and disk space
- Customize mode: drag to reorder, resize, remove or add widgets; presets Balanced, Task Focus, Speed Focus and Compact

**App**
- Menu bar icon with live speed, active downloads, pause/resume all and speed-limit toggle
- Dock icon badge and progress bar
- Speed-limit mode (tortoise button / ⇧⌘L) with separate download and upload limits
- Notifications when downloads finish or fail; click one to show the file
- Keeps the Mac awake while downloading
- Light/dark/system theme, menu-bar-only mode, open at login
- Default app for magnet links and .torrent files
- BitTorrent settings: seeding ratio and time, keep seeding, encryption, magnet behavior, and an extra tracker list that updates daily
- Proxy, ports, User-Agent presets, engine restart, and resetting the download list

## Build

```bash
cd app && ./build.sh
```

The app is built to `app/build/Swift DM.app`. Drag it to `/Applications`.
It needs only Apple's Command Line Tools, not Xcode. The aria2 engine is kept in `app/vendor/aria2c`, so Motrix isn't needed. To use a different one, pass `ARIA2=/path/to/aria2c`.

## Chrome extension

1. Open `chrome://extensions`, turn on **Developer mode**, click **Load unpacked**, and pick the `extension` folder.
2. In Swift DM, open **Settings → Browser** and click **Copy Key**.
3. Paste the key into the extension's popup.

From then on, Chrome downloads go to Swift DM. If the app isn't running, Chrome downloads normally.
You can also right-click a link and choose **Download with Swift DM**.

## Firewall (LuLu)

If downloads stay at 0 B/s, allow `Swift DM.app/Contents/Resources/aria2c` in LuLu.
Rebuilding the app can make LuLu ask again.

## Not included from Motrix

UPnP port mapping, auto-update, plugins, CLI/Docker server mode, and translations.

## Release downloads

Download the app and Chrome extension from [GitHub Releases](https://github.com/shrotshahariar/swift-download-manager/releases). The app requires Apple Silicon and macOS 14 or later. Unzip `Swift-DM-macOS-arm64.zip` and move Swift DM.app to Applications. The app is ad-hoc signed and is not notarized.

For the extension, unzip `Swift-DM-Chrome-Extension.zip`, load the extracted folder in Chrome Developer mode, and pair it using Settings → Browser.

## Bundled engine

This distribution includes aria2 version `1.37.0-motrix.23`, a Motrix-flavored build. It runs from the Swift DM app bundle and does not require the Motrix app to be installed. aria2 reports its license as GNU GPL version 2 or later; see `THIRD_PARTY_NOTICES.md`.
