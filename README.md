# Video Downloader

A free Windows app that adds a **Download** button under YouTube videos and saves them to your PC or phone. No ads, no account, no server — everything runs on your own computer using [yt-dlp](https://github.com/yt-dlp/yt-dlp).

## Features

- **Download button on YouTube** (videos, Shorts, Live, YouTube Music) via a small Tampermonkey userscript ([details below](#the-youtube-download-button-tampermonkey-userscript))
- **Modes:** Video · Phone (H.264, plays anywhere) · Best quality · Editor-friendly · Audio only · Clip (just part of a video) · Whole playlist · Shrink
- **Queue** that survives restarts, with pause/resume and automatic retry when the connection drops
- **Watch history:** import your Google Takeout history and sort what you've watched by length
- **Keeps itself working:** updates yt-dlp and Deno automatically, since YouTube changes often
- **Tells you about new versions**, and the YouTube button updates itself through Tampermonkey

## Install

1. Go to [**Releases**](../../releases) and download `VideoDownloader-x.y.zip`.
2. Right-click the ZIP → **Extract All…** (Setup doesn't run from inside a ZIP).
3. Double-click **`Setup.cmd`**. If Windows shows "Windows protected your PC", click **More info → Run anyway** (the app isn't code-signed).
4. Follow the guide that opens to add the Download button (about 2 minutes).

**Needs:** Windows 10 or 11. Setup installs the free helpers [yt-dlp](https://github.com/yt-dlp/yt-dlp), [FFmpeg](https://ffmpeg.org) and [Deno](https://deno.com) with winget if they're missing. No administrator rights needed; it installs for your Windows account only.

**Uninstall:** Settings → Apps → Installed apps → Video Downloader → Uninstall. Downloaded videos are never touched.

## The YouTube Download button (Tampermonkey userscript)

`VideoDownloader.user.js` is a small userscript that puts a red **Download** button under YouTube videos. It doesn't download anything itself: clicking it hands the video's ID to the Video Downloader app on your PC through a `ytdl://` link, and the app does the downloading.

**What it adds**

- A **Download** button next to Like/Share on videos, Shorts, live streams and YouTube Music. It moves under the title, or to the bottom-right corner, when YouTube has no room for it.
- A small arrow next to it with every download type (Video, Phone, Best quality, Editor-friendly, Audio only). The type you last downloaded with gets a ✓ and becomes the default.
- **Clip:** enter a start and end time to save just that part of the video.
- Shortcuts: **Shift+D** downloads with your ✓ option, **Shift+C** opens the clip panel.
- Menu links to open the Video Downloader window or its settings.

**Install it**

1. Install the free [Tampermonkey](https://www.tampermonkey.net) extension for your browser (Chrome, Edge, Firefox, Brave, Opera).
2. Chrome, Edge, Brave and Opera only: right-click the Tampermonkey icon → **Manage extension** → turn on **Allow User Scripts** (or turn on Developer mode on the extensions page).
3. Open [**VideoDownloader.user.js**](https://raw.githubusercontent.com/sleeeeeeeeeeeeeep-cmyl/VideoDownloader/main/VideoDownloader.user.js). Tampermonkey shows its install page: click **Install**.
4. Open any YouTube video (refresh if it was already open). The first time you click Download, your browser asks to open Video Downloader: tick **Always allow** and click **Open**.

The setup guide that opens after installing the app has the same steps with an Install button. Installed this way, Tampermonkey updates the button automatically when a new version is published here.

**What it can and can't do**

- Runs only on `www.youtube.com` and `music.youtube.com`, never inside frames.
- Uses `@grant none`: no special Tampermonkey permissions, no cross-site requests, and it never reads your YouTube account or cookies.
- Makes no network requests of its own and sends nothing anywhere. The only thing it passes on is a `ytdl://` link containing the download type and the 11-character video ID (plus start and end seconds for clips), and only to the app on your own PC.
- Remembers your last download type in your browser's local storage. Nothing else is stored.

## Privacy and security

- Nothing about you is sent anywhere. The app only talks to the video site you download from, winget (to update its helpers) and, once a day, GitHub to see if a new version is out (only the version number is fetched; turn it off in Settings). No analytics.
- Optional YouTube sign-in (for age-restricted videos) is **encrypted with Windows DPAPI**, tied to your Windows account, and only ever used for YouTube links.
- `ytdl://` links from web pages are strictly validated; anything else is refused.
- yt-dlp runs with `--ignore-config --no-plugin-dirs`, so config files or plugins planted elsewhere can't change what it does.
- The data folder (`%LOCALAPPDATA%\VideoDownloader`) is restricted to your Windows account; logs are capped and network reports are deleted after 30 days.

Found a security problem? Please open an issue (without posting any cookies or personal files).

## Files

| File | What it is |
|---|---|
| `Setup.cmd` | Double-click to install |
| `VideoDownloader.ps1` | The app (PowerShell + Windows Forms) |
| `Install.ps1`, `Uninstall.ps1` | Installer / uninstaller |
| `VideoDownloader.user.js` | The YouTube Download button (Tampermonkey userscript) |
| `Guide.html` | Setup guide shown after install |

## Please use responsibly

Only download videos you have the right to save — your own uploads, Creative Commons or public-domain content, or where the creator allows it. Downloading may be against YouTube's Terms of Service, and you are responsible for how you use this tool. This project isn't affiliated with YouTube or Google.

## Credits

Built on [yt-dlp](https://github.com/yt-dlp/yt-dlp) (Unlicense), [FFmpeg](https://ffmpeg.org) and [Deno](https://deno.com). Licensed under the [MIT License](LICENSE).
