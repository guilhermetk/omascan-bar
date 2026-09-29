# OmaScan for the Omarchy bar

A scanner button for the Omarchy bar. One click scans a page with your saved
scanner and settings, and saves a finished file: a **PDF in Documents** or a
**PNG in Pictures**. A notification says where it went; click it to open the
file.

- **Click** to scan. With a document feeder, every page comes through.
- **Click again** while it scans to cancel.
- **Right-click** to open [OmaScan](https://github.com/guilhermetk/omascan),
  to scan a longer document, crop or adjust pages.

The widget does no scanning of its own. It runs `omascan scan`, so it needs
the OmaScan app, version 0.2 or newer.

## Install

1. Install [OmaScan](https://github.com/guilhermetk/omascan#install).
2. Add the widget:

   ```sh
   omarchy plugin add https://github.com/guilhermetk/omascan-bar.git --enable
   ```

The first click asks which scanner to use, in a terminal. If you've scanned
in OmaScan before, it already knows. To change it later:

```sh
omascan setup
```

## Settings

In the bar settings, OmaScan has two:

| Setting | What it does |
| --- | --- |
| **Save as** | **PDF** or **PNG** for every scan from the bar. **Saved choice** uses the one from `omascan setup`. |
| **OmaScan command** | Only for a build outside `PATH`, e.g. `~/omascan/build/omascan`. |

Everything else, such as colour, resolution, paper size and PDF quality, is
what OmaScan has saved. Change it in the app, or with `omascan config`.

## A key for it

The widget answers `scan` over the shell's IPC, so a key can scan too. In
`~/.config/hypr/bindings.conf`:

```
bindd = SUPER SHIFT, S, Scan a page, exec, omarchy-shell guilhermetk.omascan scan
```

## How it works

`BarWidget.qml` runs `omascan scan --json` and reads the line it prints. The
exit code says what happened (see OmaScan's README), and the widget turns it
into a notification: saved, pick a scanner first, scanner busy or failed.
Cancelling sends the scan `SIGTERM`, which OmaScan takes as "stop the scanner
cleanly".

The widget runs no install steps or sudo. It only runs `omascan`,
`notify-send`, `xdg-open` and Omarchy's own launch helpers.

## Licence

GPL-3.0-or-later, like OmaScan.
