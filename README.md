# Video Downloader

[![Checks](https://github.com/sleeeeeeeeeeeeeep-cmyl/VideoDownloader/actions/workflows/ci.yml/badge.svg)](https://github.com/sleeeeeeeeeeeeeep-cmyl/VideoDownloader/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/sleeeeeeeeeeeeeep-cmyl/VideoDownloader)](https://github.com/sleeeeeeeeeeeeeep-cmyl/VideoDownloader/releases/latest)

A free app for **Windows and Linux** that puts a **Download** button under YouTube videos and saves them to your
computer or your phone.
No ads, no account, no server: everything runs on your own computer, using the open-source
[yt-dlp](https://github.com/yt-dlp/yt-dlp) to do the downloading.

## Contents

- [What it does](#what-it-does)
- [Install](#install)
- [Linux](#linux)
- [Add the Download button to YouTube](#add-the-download-button-to-youtube)
- [Downloading](#downloading)
- [Download types](#download-types)
- [Where your files go](#where-your-files-go)
- [Getting videos onto your phone](#getting-videos-onto-your-phone)
- [Age-restricted and members-only videos](#age-restricted-and-members-only-videos)
- [Your watch history, sorted by length](#your-watch-history-sorted-by-length)
- [Settings](#settings)
- [The Help menu](#the-help-menu)
- [Updates](#updates)
- [Troubleshooting](#troubleshooting)
- [Privacy and security](#privacy-and-security)
- [What runs on your PC (and why antivirus might warn)](#what-runs-on-your-pc-and-why-antivirus-might-warn)
- [Advanced: text version, command line and links](#advanced-text-version-command-line-and-links)
- [Uninstall](#uninstall)
- [For developers](#for-developers)
- [Please use responsibly](#please-use-responsibly)

## What it does

- **A Download button on YouTube**: on videos, Shorts, live streams and YouTube Music. One click downloads; a small
  menu next to it offers every type of download.
- **Eight download types**: Video, Phone, Best quality, Editor-friendly, Audio only, Clip (just part of a video),
  Whole playlist and Shrink. See [Download types](#download-types).
- **A queue that never loses anything**: click as many videos as you like. They download one after another, survive a
  restart, and wait patiently when the internet drops, then carry on by themselves.
- **Pause and resume**: half-finished downloads continue where they stopped.
- **Straight to your phone**: Phone downloads are made to play on every iPhone and Android, and can go into iCloud
  Drive, OneDrive or Google Drive so they appear on your phone.
- **Your watch history, sorted by length** (Windows): read your recent history from YouTube or import your whole
  history from Google Takeout, then sort, search and download from it.
- **Keeps itself working**: YouTube changes often, so the parts that talk to it (yt-dlp and Deno) update themselves
  every week, and Video Downloader itself updates in one click.
- **Private by design**: no tracking, your optional YouTube sign-in is encrypted, and nothing about you leaves your PC.
  See [Privacy and security](#privacy-and-security).

## Install

This section is for Windows. On Linux, see [Linux](#linux).

**You need** Windows 10 (version 1809 or newer) or Windows 11. No administrator rights are needed: everything is
installed for your Windows account only.

1. Open the [latest release](https://github.com/sleeeeeeeeeeeeeep-cmyl/VideoDownloader/releases/latest) and download
   **`VideoDownloader-x.y.zip`**. (Not the "Source code" files, and not the extension ZIP.)
2. Right-click the ZIP and choose **Extract All...**. Setup can't run from inside a ZIP.
3. Open the extracted folder and double-click **`Setup.cmd`**.
   - If Windows shows **"Windows protected your PC"**, click **More info**, then **Run anyway**. This appears for any
     program that isn't code-signed or from the Microsoft Store.
4. Setup takes a minute or two. It:
   - installs the free helper programs [yt-dlp](https://github.com/yt-dlp/yt-dlp) (downloads),
     [FFmpeg](https://ffmpeg.org) (joins video and sound, converts) and [Deno](https://deno.com) (needed by YouTube)
     with Windows' own package manager, winget, if you don't already have them;
   - adds **Video Downloader** to your Start menu and desktop;
   - connects the browser button, and lists the app in **Settings > Apps** so it can be removed like any other program.
5. When it finishes, the setup guide opens. It walks you through adding the Download button (next section).

> [!TIP]
> **Check your download (optional).** Every release includes `SHA256SUMS.txt`. In PowerShell, run
> `Get-FileHash .\VideoDownloader-x.y.zip` and compare the long code with the line for that file. If they match,
> your file is exactly the one GitHub built from this repository.

**"winget was not found"?** Open the Microsoft Store, search for **App Installer**, install or update it, then run
Setup again.

## Linux

The Linux version does the same downloading as the Windows one, with its own window, and the same YouTube Download
button works with it. It runs on any current distribution (Ubuntu, Debian, Mint, Pop!_OS, Fedora, Arch, openSUSE,
ChromeOS's Linux, and others) and installs for your account only, so it never asks for your password.

**You need** Python 3.8 or newer (every current distribution has it) and, for the window, Tk.

### Install on Linux

Either download **`VideoDownloader-linux-x.y.tar.gz`** from the
[latest release](https://github.com/sleeeeeeeeeeeeeep-cmyl/VideoDownloader/releases/latest), extract it, open a
terminal in the extracted folder and run:

```sh
sh install.sh
```

or do it all in one line (this downloads the newest Linux release and checks it against the release's SHA-256
checksums before running anything from it):

```sh
curl -fsSL https://raw.githubusercontent.com/sleeeeeeeeeeeeeep-cmyl/VideoDownloader/main/install.sh | sh
```

Setup:

- installs [yt-dlp](https://github.com/yt-dlp/yt-dlp) and [Deno](https://deno.com) into
  `~/.local/lib/video-downloader/bin`, plus [FFmpeg](https://ffmpeg.org) if your system doesn't have it, each checked
  against the checksum its makers publish;
- adds **Video Downloader** to your applications menu and the `video-downloader` command to `~/.local/bin`;
- registers `ytdl://` links, so the YouTube button can hand downloads to the app.

If setup says Tk is missing, install it and you're done:

| Distribution | Command |
| --- | --- |
| Ubuntu, Debian, Mint, Pop!_OS | `sudo apt install python3-tk` |
| Fedora | `sudo dnf install python3-tkinter` |
| Arch, Manjaro | `sudo pacman -S tk` |
| openSUSE | `sudo zypper install python3-tk` |

Then add the Download button exactly as on Windows: see
[Add the Download button to YouTube](#add-the-download-button-to-youtube). The first time you click it, your browser
asks whether to open **Video Downloader link**: allow it, and tick "always" so it doesn't ask again.

### Using it on Linux

The window works like the Windows one: paste links, pick a type, watch progress, pause and resume, remove downloads,
double-click a finished one to show it in your file manager, or a failed one to see why it failed. **Settings** has the
same tabs, and **Help** has the guide, "Check for updates now", "Check my connection" (DNS, secure connections, ping,
Wi-Fi and a speed test), the data folder and this page.

Or use the terminal:

```sh
video-downloader                                   # open the window
video-downloader https://youtu.be/...              # download as Video
video-downloader --type audio LINK [LINK...]       # also: phone, best, edit, playlist, shrink
video-downloader --resume                          # continue paused or waiting downloads
video-downloader --update-now                      # update yt-dlp and Deno
video-downloader --connection-check                # write and open a connection report
video-downloader --uninstall                       # remove it (asks about your settings and history)
```

In the terminal, **Ctrl+C pauses**: nothing is lost, and `--resume` (or Resume in the window) carries on.

| | Windows | Linux |
| --- | --- | --- |
| Videos, phone, audio folders | `Downloads\Videos`, `\Phone`, `\Audio` | `~/Downloads/Videos`, `/Phone`, `/Audio` |
| Settings, history, logs | `%LOCALAPPDATA%\VideoDownloader` | `~/.local/share/video-downloader` (only your account can open it) |
| YouTube sign-in | Firefox, or an encrypted cookies.txt | Firefox, Chrome, Chromium, Brave, Edge, Opera or Vivaldi, or a cookies.txt readable only by you |
| Watch history sorted by length | Yes | Not yet |
| Notifications | Windows notifications | Your desktop's notifications (`notify-send`) |
| Updates | yt-dlp and Deno weekly; the app in one click | The same |

Every download type, setting and troubleshooting tip below applies to Linux too, apart from the Windows-specific
paths and the watch history.

## Add the Download button to YouTube

The button is a small script that runs on YouTube pages. There are two ways to add it.

### Option 1: Tampermonkey (recommended, updates itself)

1. Install the free [Tampermonkey](https://www.tampermonkey.net) extension for your browser (Chrome, Edge, Firefox,
   Brave, Opera or Opera GX).
2. **Chrome, Edge, Brave and Opera only:** right-click the Tampermonkey icon, choose **Manage extension**, and turn on
   **Allow User Scripts** (on older versions: turn on **Developer mode** on the extensions page). Without this the
   browser silently refuses to run the button.
3. Open
   [**VideoDownloader.user.js**](https://raw.githubusercontent.com/sleeeeeeeeeeeeeep-cmyl/VideoDownloader/main/VideoDownloader.user.js).
   Tampermonkey shows its install page: click **Install**.
4. Open any YouTube video (refresh it if it was already open). The first time you click **Download**, the browser asks
   whether to open Video Downloader: tick **Always allow** and click **Open**.

Installed this way, Tampermonkey updates the button by itself whenever a new version is published here.
If the install link doesn't open Tampermonkey, use the guide's fallback: Tampermonkey icon, **Create a new script**,
select everything, paste the script (Setup already put it on your clipboard) and press **Ctrl+S**.

### Option 2: browser extension (no Tampermonkey)

Every release also has `VideoDownloader-extension-x.y.zip`: the same button as a browser extension that asks for no
permissions at all. It isn't in any add-on store yet, so it's installed by hand:

- **Chrome, Edge, Brave, Opera:** unzip it, open `chrome://extensions` (or `edge://extensions`), turn on
  **Developer mode**, click **Load unpacked** and pick the unzipped folder.
- **Firefox:** open `about:debugging#/runtime/this-firefox`, click **Load Temporary Add-on** and pick `manifest.json`
  inside the ZIP. Firefox removes temporary add-ons when it restarts.

Use one or the other, not both, or you'll see two buttons.

### What the button can and can't do

- It runs only on `www.youtube.com` and `music.youtube.com`, never inside frames.
- It needs no special permissions (`@grant none`), makes no network requests of its own, and never reads your YouTube
  account or cookies.
- The only thing it passes on is a `ytdl://` link holding the download type and the 11-character video ID (plus start
  and end seconds for clips), and only to the Video Downloader app on your own PC.
- It remembers your last download type in your browser's local storage. Nothing else is stored.

## Downloading

### From YouTube

- Click **Download** to download with the type that has the **✓**.
- Click the small **▾** next to it to pick another type. The type you pick gets the ✓ and becomes the default.
- **Clip part of this video...** opens two time boxes (start and end, like `1:30` and `2:05`). **Now** fills in the
  current playback time.
- Shortcuts: **Shift+D** downloads with your ✓ type, **Shift+C** opens the clip panel.
- The same menu opens the Video Downloader window or its settings.
- The button sits next to Like and Share. If YouTube has no room there, it moves under the title, or floats in the
  bottom-right corner (as it always does on Shorts). A floating button hides while a video is full screen.

When you click, the Video Downloader window opens to show the progress. When everything finished fine it closes
itself after a few seconds; click anywhere in it to keep it open. (Both can be turned off in Settings.)

### From the Video Downloader window

Open **Video Downloader** from the Start menu.

1. Paste one or more links into the box at the top. Links from YouTube and most other video sites work, and Google or
   YouTube redirect links are unwrapped automatically. If you copied a link before opening the window, it's already
   filled in.
2. Pick a type and click **Download**.

The window shows:

- **Now downloading**: title, progress bar, speed and time left, and a **Pause** / **Resume** button.
- **The list**: what's downloading, what's waiting, and what finished (newest first).
  - Double-click a **finished** item to show the file in Explorer.
  - Double-click a **red (failed)** item to see why it failed and what to do.
  - **Remove** takes a waiting download out of the queue, stops the current one, or hides a finished one.
  - **Clear finished** empties the finished part of the list (your files are not touched).
- **Open videos folder**, **Watch history**, **Help** and **Settings** buttons.

### The queue, pausing and dropped connections

- Downloads run one at a time in a background process, so closing the window doesn't stop them.
- **Pause** stops the current download; the half-done file is kept. **Resume** continues from where it stopped.
- If the internet drops, YouTube temporarily blocks your connection, or your network interferes with secure
  connections, nothing is lost: the download goes back into the queue and is retried automatically after 1, 2, 5, 10
  and then every 15 minutes (every 30 minutes while YouTube is blocking). Press **Resume** to try straight away.
- After a restart, waiting downloads continue as soon as you open the window (unless you had pressed Pause).

## Download types

| Type | What you get | Saved to |
| --- | --- | --- |
| **Video** | Good quality in a small file: up to 1080p, AV1 preferred, MP4. Best for watching on a PC. | Videos folder |
| **Phone** | H.264 video + AAC sound in an MP4 that starts playing instantly on every iPhone and Android and in every messaging app. Up to 720p. Videos in other formats are converted. | Phone folder |
| **Best quality** | The highest quality available, up to 4K/8K. Big files. | Videos folder |
| **Editor-friendly** | H.264 MP4 up to 1080p that opens in any editor (Premiere, DaVinci Resolve, CapCut, iMovie...). | Videos folder |
| **Audio only** | Just the sound, with cover art. M4A by default (no quality loss); MP3, Opus, FLAC or WAV in Settings. | Audio folder |
| **Clip** | Only the part between the two times you choose. File names end in `(clip 1m30s-2m05s)`. | Videos folder |
| **Whole playlist** | Every video in a playlist, numbered (`001 - Title`), in a folder named after the playlist. Videos you already downloaded are skipped, so running it again only fetches new ones. | Videos folder |
| **Shrink** | Downloads, then re-encodes to a much smaller file (AV1 if your FFmpeg supports it, otherwise H.265). Slow, but great for saving space. Saved as `Title (small).mp4`. | Videos folder |

**Clip** is in the button's menu; **Whole playlist** and **Shrink** are in the window (paste a playlist link and choose
Whole playlist).

**If a download fails** with an unknown error, Video Downloader updates yt-dlp and tries once more by itself. If a
YouTube video needs a sign-in, it retries with your saved sign-in (if you set one up). Double-click the red line for the
reason; the common ones are explained in [Troubleshooting](#troubleshooting).

## Where your files go

| Folder | Default | Change it in |
| --- | --- | --- |
| Videos | `Videos` inside your Downloads folder | Settings > Video |
| Phone | `iCloud Drive\Phone Videos` if iCloud for Windows is installed, otherwise `Phone` inside Downloads | Settings > Phone |
| Audio | `Audio` inside your Downloads folder | Settings > Audio |

"Your Downloads folder" is wherever Windows keeps it, including when you moved it to another drive or into OneDrive.

File names default to `Title [video id].mp4`. Settings > General offers `Title.mp4`, `Channel - Title.mp4` and
`2026-01-31 - Title.mp4` (upload date). Characters Windows doesn't allow in file names are replaced, and very long
titles are shortened.

## Getting videos onto your phone

Use the **Phone** type: the file is made to play everywhere. Then:

- **iPhone with iCloud for Windows:** Phone downloads go into `iCloud Drive\Phone Videos` automatically. On the iPhone,
  open the **Files** app, then **iCloud Drive**, then **Phone Videos**. To put one in your Photos, open it, tap Share,
  then **Save Video**.
- **OneDrive or Google Drive:** in Settings > Phone, choose a folder inside your OneDrive or Google Drive folder, then
  open that app on your phone.
- **Cable:** connect the phone and copy the files from the Phone folder.

Settings > Phone lets you pick 480p (smallest), 720p (recommended) or 1080p (sharpest), and limit the frame rate to
30 fps for smaller files.

## Age-restricted and members-only videos

YouTube only shows these to signed-in accounts, so Video Downloader needs your YouTube sign-in for them. It's only used
when a video won't download without it (you can change that in Settings > Network), and only ever sent to YouTube.

### If you use Firefox (easiest)

Stay signed in to YouTube in Firefox. In Video Downloader, open **Settings > Network** and set
**Where your sign-in comes from** to **Firefox**. Nothing to export. (Chrome and the browsers built on it encrypt their
sign-ins so that other programs can't read them, so for those use the steps below.)

### Any other browser: a cookies.txt file

1. Install **Get cookies.txt LOCALLY** (free and open-source) from your browser's extension store.
2. Open a **private / incognito window** (Ctrl+Shift+N; allow the extension in private windows if asked), sign in to
   youtube.com there, click the extension and click **Export**.
3. **Close the private window without signing out.** (If you export from your normal window, YouTube quietly replaces
   the sign-in as soon as you keep browsing there, and the file stops working.)
4. Rename the file to `cookies.txt` and move it into `%LOCALAPPDATA%\VideoDownloader` (Help > Open the data folder).

The next time Video Downloader starts, it **encrypts the file and deletes the plain copy**. The encryption (Windows
DPAPI) is tied to your Windows account, so a copy of it is useless on any other PC or account. To stop using your
sign-in, delete `cookies.dpapi` from that folder. If YouTube signs you out or the sign-in stops working, export a fresh
one the same way.

> [!WARNING]
> A cookies.txt file works like the password to your Google account. Never send it to anyone, and don't leave a copy in
> your Downloads folder.

## Your watch history, sorted by length

Click **Watch history** in the window to see what you've watched, with every video's length, so you can find the long
ones (or the Shorts) and download them.

- **Get from YouTube** reads your most recent history (up to about 5,000 videos) straight from YouTube. This needs your
  [YouTube sign-in](#age-restricted-and-members-only-videos).
- **Import Google Takeout file...** loads your whole history, going back years, with no sign-in needed:
  1. Go to [takeout.google.com](https://takeout.google.com) and click **Deselect all**.
  2. Tick **YouTube and YouTube Music**, click **All YouTube data included**, click **Deselect all** again and tick only
     **history**. (Optional: under Multiple formats, set History to JSON. HTML works too.)
  3. Click **Next step**, then **Create export**. Google emails you a link, usually within minutes.
  4. Download the .zip and pick it in **Import Google Takeout file...** (no need to unzip it).
- **Find missing lengths** looks up lengths that aren't known yet. Takeout files have no lengths (and newer ones have no
  links either, so those videos are first searched for by title and channel). A few thousand videos take roughly
  10 to 30 minutes. You can close the window meanwhile; **Stop** pauses it.

In the list:

- Click a column to sort by it (Length is sorted longest first). **Search** filters by title or channel, and **Show**
  narrows it to videos longer than 10 minutes, 1 hour or 3 hours, Shorts, or videos without a length yet.
- Double-click a video to open it on YouTube. Select several (Ctrl or Shift) and click **Download** to queue them with
  the type you choose.
- **Save as CSV...** exports the current view for Excel or Google Sheets.
- **Clear list...** only empties Video Downloader's copy. It never touches your history on YouTube.

The length shown is the whole video's length, not how long you watched (YouTube doesn't share that). Removed videos
show "-". Your history is stored only on your PC, in `watch-history.tsv` in the data folder.

## Settings

Open **Settings** in the window (or from the button's menu). Changes apply to the next download.

### General

| Setting | Default | What it does |
| --- | --- | --- |
| Default download type | Video | The type picked when the window opens (the button remembers its own) |
| File names | Title [id] | `Title [id]`, `Title`, `Channel - Title` or `Upload date - Title` |
| Show this window when a download starts | On | Opens the window when you click Download on YouTube |
| ...and close it when all went well | On | Closes it again a few seconds after everything finished without errors |
| Notification when done | On | A Windows notification when downloads finish or fail |
| Show file in Explorer when done | Off | Opens the folder with the new file selected |
| Auto-update yt-dlp | Weekly | Weekly, monthly or never (also updates Deno) |
| Tell me about new versions | On | Checks GitHub once a day for a newer Video Downloader |
| Forget finished downloads after | Never | 1, 7, 30 or 90 days: older entries leave the list and the logs by themselves |

### Video

| Setting | Default | What it does |
| --- | --- | --- |
| Save videos to | Downloads\Videos | Folder for Video, Best, Editor, Clip, Playlist and Shrink |
| Video / clip / playlist quality | 1080p | 480p, 720p, 1080p, 1440p or 4K |
| Best quality limit | No limit | No limit (up to 8K), 4K or 1440p |
| Editor-friendly quality | 1080p | 720p or 1080p (YouTube's H.264 stops at 1080p) |
| Preferred video format | AV1 | AV1 (smallest), VP9, or H.264 (plays on anything, bigger) |
| Frame rate | Same as the video | Or up to 60 / up to 30 fps |
| File type | MP4 | MP4 (works everywhere) or MKV |
| Add chapters | On | Keeps the video's chapters |
| Add thumbnail as cover | Off | Embeds the thumbnail as the file's cover picture |

### Phone

| Setting | Default | What it does |
| --- | --- | --- |
| Save phone videos to | iCloud Drive\Phone Videos or Downloads\Phone | See [Getting videos onto your phone](#getting-videos-onto-your-phone) |
| Phone quality | 720p | 480p, 720p or 1080p |
| Phone frame rate | Same as the video | Or up to 30 fps (smaller) |

### Audio

| Setting | Default | What it does |
| --- | --- | --- |
| Save audio to | Downloads\Audio | Folder for Audio only |
| Audio format | M4A | M4A (no quality loss), MP3, Opus, FLAC or WAV |
| MP3 / Opus quality | Best | Best, 256, 192 or 128 kbps |
| Add cover art | On | Embeds the thumbnail as album art (not for WAV) |

### Extras

| Setting | Default | What it does |
| --- | --- | --- |
| Subtitles | None | Inside the video, or a separate .srt file |
| Subtitle languages | English | English or all languages |
| Include auto-generated subtitles | Off | Adds YouTube's automatic captions |
| Sponsor segments | Leave alone | Mark them as chapters, or cut out sponsor, self-promotion and "like and subscribe" segments ([SponsorBlock](https://sponsor.ajay.app)) |
| Exact clip start/end | On | Frame-exact clips (slower); off cuts at the nearest keyframe |
| Shrink mode | Balanced | Smallest file, balanced, or better quality |
| Playlists get their own folder | On | A folder per playlist |

### Network

| Setting | Default | What it does |
| --- | --- | --- |
| Parallel download pieces | 4 | 1 (gentlest), 4 or 8 (fastest) |
| Speed limit | No limit | 10, 5, 2 or 1 MB/s |
| Use your YouTube sign-in | Only when a video needs it | Or always, or never |
| Where your sign-in comes from | A cookies.txt file | Or Firefox |

**Reset to defaults** in the Settings window puts everything back. Settings are stored in `settings.json` in the
data folder.

## The Help menu

Click **Help** in the window:

| Item | What it does |
| --- | --- |
| Open the guide | The illustrated setup and how-to guide |
| Check for updates now (yt-dlp and Deno) | Updates the parts that talk to YouTube; a notification says when it's done |
| Check my connection (makes a report) | About two minutes: Wi-Fi signal, band and driver, adapter settings, nearby channel crowding, ping times, a 25 MB speed test from Cloudflare, and whether secure connections to YouTube are being intercepted. The report opens in Notepad. |
| Erase my download history | Deletes the list of finished downloads, all logs, connection reports and the playlist memory in one go (asks first; your files, settings, sign-in and waiting downloads are kept) |
| Open the data folder | Settings, logs, your encrypted sign-in and watch history |
| Project page, new versions, report a problem | This page |

## Updates

- **Video Downloader itself:** when a new version is out, a blue **"Version x.y is out - update"** link appears at the
  top right of the window. Click it and choose **Yes**: it downloads the new version from this repository's releases,
  checks it against the published SHA-256 checksum, installs it and reopens the window. Your settings, queue and
  history are kept. **No** shows what's new instead.
- **yt-dlp and Deno:** updated every week by themselves (Settings > General), and whenever a download fails in a way
  that an update might fix. **Help > Check for updates now** does it straight away.
- **The YouTube button:** Tampermonkey updates it by itself if you installed it from the link above.

Updating by hand also works: download the new release and run Setup again. It replaces the app and keeps your data.

## Troubleshooting

**There's no Download button on YouTube.**
Refresh the page. Check that Tampermonkey shows the script as enabled (Tampermonkey icon, Dashboard). In Chrome, Edge,
Brave and Opera, check that **Allow User Scripts** (or Developer mode) is on. On long videos, look under the title or
in the bottom-right corner. Still nothing? Try the [browser extension](#option-2-browser-extension-no-tampermonkey).

**I click Download but nothing happens.**
The browser may have blocked the "Open Video Downloader?" question: look for a small icon in the address bar. Running
Setup again reconnects the button. You can always paste the link into the window instead.

**A download failed.**
Double-click the red line. Common reasons:

| Message | What it means and what to do |
| --- | --- |
| The video is private, removed or not available | Nothing to fix: the video is gone or private. |
| It is age-restricted | Set up your [YouTube sign-in](#age-restricted-and-members-only-videos). |
| It is members-only | It needs the sign-in of an account that is a member of the channel. |
| YouTube Restricted Mode is switched on | Your network, a parental filter or a school/work account hides the video. The app can't change that. |
| Try again later | Usually YouTube changed something. Click **Help > Check for updates now**, then try again. |

**"Waiting for the internet" or "YouTube is blocking downloads for a while".**
Your downloads are safe in the queue and retry by themselves. Turn off any VPN and check your Wi-Fi. YouTube's block
usually lifts within an hour.

**"Your network is blocking secure connections".**
Something between your PC and the internet (a router or ISP filter, parental controls, a work or school network, or
security software that scans encrypted traffic) is answering secure connections with its own certificate instead of
YouTube's. Video Downloader refuses to send anything over such a connection. Your downloads wait in the queue and
continue on a normal connection. **Help > Check my connection** shows where the certificate comes from.

**Downloads are slow.**
Usually it's the connection: VPNs, a busy network, or YouTube limiting speed. Try Settings > Network >
Parallel download pieces: 8, and run **Help > Check my connection**.

**"The settings window couldn't open: Access to the path ... is denied".**
This was a bug in version 4.2. Version 4.4 and newer repair it automatically the first time they start.

**Where are the logs?**
**Help > Open the data folder**: `history.log` (every download), `runner.log` (recent downloads in detail) and
`error.log`. Logs are trimmed automatically and connection reports are deleted after 30 days.

**Still stuck?** [Open an issue](https://github.com/sleeeeeeeeeeeeeep-cmyl/VideoDownloader/issues/new/choose) with
your Windows version, Video Downloader version and the error message. Never paste your cookies.txt.

## Privacy and security

- **Nothing about you is sent anywhere.** The app only talks to the video site you download from, to winget (to update
  its helpers) and to GitHub: once a day for the newest version number (turn it off in Settings > General), and when
  you click update. No analytics, no accounts.
- **Your optional YouTube sign-in is encrypted** with Windows DPAPI, tied to your Windows account, and only ever used
  for YouTube addresses. yt-dlp gets a short-lived copy in a private folder that is deleted straight after. With the
  Firefox option, yt-dlp reads the sign-in from Firefox only when needed and nothing is saved.
- **Links from web pages can't do anything unexpected.** `ytdl://` links only ever carry a download type and a YouTube
  video ID; anything else is refused and logged.
- **yt-dlp runs with `--ignore-config --no-plugin-dirs`**, so settings files or plugins planted elsewhere on the PC
  can't change what it does.
- **The data folder is private** to your account: on Windows only your account (and Windows itself) can open it; on
  Linux it is `chmod 700` and everything the app makes, downloads included, is readable by your account only.
- **You decide how long the history stays.** *Clear finished* removes finished downloads from the list and from the
  log that names them. *Help > Erase my download history* deletes the list, every log, the connection reports and the
  playlist memory at once. *Settings > General > Forget finished downloads after* does it automatically after 1, 7, 30
  or 90 days. No log stores the links you click on YouTube, and notifications never show the video's name (they
  appear on the lock screen).
- **Half-done downloads are private too**: each one keeps its pieces in its own folder inside the data folder, deleted
  when it finishes or when you remove it.
- **Logs are kept short**, and connection reports (which describe your network, never the names of your neighbours'
  Wi-Fi) are deleted after 30 days.
- **A hand-edited settings file can't change what runs**: every choice must be one of the listed ones and every
  folder a full path, otherwise the default is used.
- **Pause and Stop only ever stop Video Downloader's own programs**, even if an old process number has been reused.
- **"Update now" only installs this repository's official releases**, and only after checking the download against the
  release's SHA-256 checksums (on Linux also: https only, and archives with unsafe paths are refused).

What it can't protect against: anyone who can sign in to your account, or an administrator of the computer, can see
your files and the app's folder, and anything already running as you could too. Use a password on your account, and
delete downloaded files like any other files when you don't want them any more.

Found a security problem? Please report it privately, as described in [SECURITY.md](SECURITY.md).

## What runs on your PC (and why antivirus might warn)

Video Downloader is a PowerShell script you can read in Notepad, not a compiled program. To stay out of your way it
starts PowerShell **hidden**, like this:

```text
conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File VideoDownloader.ps1 ...
```

It does that for the window, for downloads running in the background, and when a `ytdl://` link arrives from the
browser. `-ExecutionPolicy Bypass` only means Windows runs this one script file without asking about script policy; it
doesn't turn off any protection.

Some malware starts PowerShell the same way, so a few antivirus programs may be suspicious of it, and SmartScreen warns
because the app isn't code-signed. Everything it runs is in this repository. Every release is built by GitHub from
these files after the automatic checks pass, and the checksums let you confirm your download is that build.

**What it installs or changes** (all for your Windows account only):

| Where | What |
| --- | --- |
| `%LOCALAPPDATA%\Programs\VideoDownloader` | The app |
| `%LOCALAPPDATA%\VideoDownloader` | Your settings, queue, download history, logs, watch history and encrypted sign-in |
| Start menu and desktop | Video Downloader shortcuts |
| `HKEY_CURRENT_USER\Software\Classes\ytdl` | The `ytdl://` link handler the button uses |
| Settings > Apps | The uninstall entry |
| winget | yt-dlp, FFmpeg and Deno, if you didn't have them |

## Advanced: text version, command line and links

**Text version.** For people who prefer typing, run:

```text
powershell -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\Programs\VideoDownloader\VideoDownloader.ps1" -Menu
```

Paste links, then pick a letter: **V** video, **P** phone, **4** best, **E** editor, **A** audio, **C** clip,
**L** playlist, **S** shrink, **T** settings, **U** update, **O** open the Videos folder.

**Command-line switches** of `VideoDownloader.ps1`:

| Switch | What it does |
| --- | --- |
| (none) or `-App` | The window |
| `-Menu` | The text version |
| `-Settings` | The settings window |
| `-History` | The watch history window |
| `-UpdateNow` | Update yt-dlp and Deno |
| `-ConnectionCheck` | Check the connection and open the report |
| `-NetCheck` | Only the secure-connection part of that check |
| `-Uri "ytdl://..."` | Handle a link from the button (see below) |

**Links the button sends** (anything else is refused):

| Link | What it does |
| --- | --- |
| `ytdl://video/<id>` (also `phone`, `best`, `edit`, `audio`) | Queue that type of download for the YouTube video `<id>` |
| `ytdl://clip/<id>/<start>-<end>` | Queue a clip; start and end are whole seconds |
| `ytdl://app`, `ytdl://settings`, `ytdl://history` | Open the window, settings or watch history |

## Uninstall

Windows **Settings > Apps > Installed apps > Video Downloader > Uninstall**. It asks whether to also delete your
settings, history, waiting downloads and saved sign-in, or keep them for a future reinstall. Your downloaded videos
are never touched.

Two things are left for you to remove if you like: the Download button (Tampermonkey's dashboard, or the extension),
and the helper programs yt-dlp, FFmpeg and Deno (in Settings > Apps; other programs may use them).

## For developers

### Files

| File | What it is |
| --- | --- |
| `Setup.cmd` | Double-click to install; runs `Install.ps1` |
| `VideoDownloader.ps1` | The whole app: window, background downloader, settings, watch history, updates (PowerShell 5.1 + Windows Forms) |
| `Install.ps1`, `Uninstall.ps1` | Installer and uninstaller |
| `VideoDownloader.user.js` | The YouTube button (Tampermonkey userscript, also the extension's content script) |
| `Guide.html` | The setup guide; the installer fills in the button script and version |
| `extension-manifest.json`, `extension-icon.png` | The button as a browser extension |
| `Tests.ps1` | Automatic checks (run by GitHub on Windows for every upload) |
| `Build-Release.ps1` | Builds the release ZIPs and SHA-256 checksums |
| `video-downloader.py` | The whole Linux app: window (Tk), background downloader, settings, updates, installer (Python 3.8+, standard library only) |
| `install.sh` | Linux setup: runs `video-downloader.py --install`, or downloads and checks the newest release first |
| `README-linux.txt`, `video-downloader.png` | The Linux download's quick guide and icon |
| `tests_linux.py`, `ruff.toml` | The Linux checks (run by GitHub on Ubuntu for every upload) |
| `build-linux-release.py` | Builds `VideoDownloader-linux-x.y.tar.gz` and adds it to the checksums |
| `.github/` | The GitHub Actions workflow and the issue forms |

### Checks

`Tests.ps1` runs on Windows PowerShell 5.1 (what most users have) for every upload. It checks that:

- every script parses, is plain ASCII, and has **no PSScriptAnalyzer findings at all** (errors, warnings or
  information);
- the version numbers agree and the changelog covers this version;
- the button only runs on YouTube, asks for no permissions and makes no network requests;
- the app's logic works: the download-link checks, YouTube address matching, argument quoting, version comparison,
  clip times and watch-history matching;
- on Windows, the privacy and security features work: sign-in encryption, the private data folder (including the 4.2
  repair), refusing tampered `ytdl://` links, and the installer's guide.

Run them yourself with `powershell -ExecutionPolicy Bypass -File Tests.ps1`.

`tests_linux.py` runs on Ubuntu with Python 3.8 (the oldest supported) and with the system Python, after `ruff`,
`vermin` (nothing newer than Python 3.8 is used) and `shellcheck`. Without downloading anything (a stand-in for yt-dlp
writes small files), it checks the `ytdl://` link checks, the options given to yt-dlp for every type and setting,
failure detection and the signed-in retry, pausing and waiting for the internet, the Phone conversion to H.264/AAC,
installing and uninstalling, refusing unsafe archives and wrong checksums in "Update now", and that the window opens.
Run them with `python3 tests_linux.py` (use `xvfb-run -a python3 tests_linux.py` to include the window).

### Making a new version

1. Change the version number in four places, which must match: `$AppVersion` in `VideoDownloader.ps1`,
   `APP_VERSION` in `video-downloader.py`, `@version` in `VideoDownloader.user.js` and `"version"` in
   `extension-manifest.json`. Add a section to `CHANGELOG.md`.
2. Upload the changed files and wait for the green tick on the **Actions** tab. A red X means something is broken.
3. Create a release whose tag is the version number (for example `4.7`). Don't attach anything: GitHub builds
   `VideoDownloader-x.y.zip`, `VideoDownloader-linux-x.y.tar.gz`, the extension ZIP and `SHA256SUMS.txt` and
   attaches them within a few minutes. "Update now" in both apps picks the new version up from there.

## Please use responsibly

Only download videos you have the right to save: your own uploads, Creative Commons or public-domain content, or where
the creator allows it. Downloading may be against YouTube's Terms of Service, and you are responsible for how you use
this tool. This project isn't affiliated with YouTube or Google.

## Credits and license

Built on [yt-dlp](https://github.com/yt-dlp/yt-dlp) (Unlicense), [FFmpeg](https://ffmpeg.org) and
[Deno](https://deno.com), with [SponsorBlock](https://sponsor.ajay.app) data for sponsor segments.
Licensed under the [MIT License](LICENSE).
