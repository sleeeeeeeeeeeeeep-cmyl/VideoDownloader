# Video Downloader

A free Windows app that adds a **Download** button under YouTube videos and saves them to your PC or phone. No ads, no account, no server — everything runs on your own computer using [yt-dlp](https://github.com/yt-dlp/yt-dlp).

## Features

- **Download button on YouTube** (videos, Shorts, Live, YouTube Music) via a small Tampermonkey userscript
- **Modes:** Video · Phone (H.264, plays anywhere) · Best quality · Editor-friendly · Audio only · Clip (just part of a video) · Whole playlist · Shrink
- **Queue** that survives restarts, with pause/resume and automatic retry when the connection drops
- **Watch history:** import your Google Takeout history and sort what you've watched by length
- **Keeps itself working:** updates yt-dlp and Deno automatically, since YouTube changes often

## Install

1. Go to [**Releases**](../../releases) and download `VideoDownloader-x.y.zip`.
2. Right-click the ZIP → **Extract All…** (Setup doesn't run from inside a ZIP).
3. Double-click **`Setup.cmd`**. If Windows shows "Windows protected your PC", click **More info → Run anyway** (the app isn't code-signed).
4. Follow the guide that opens to add the Download button (about 2 minutes).

**Needs:** Windows 10 or 11. Setup installs the free helpers [yt-dlp](https://github.com/yt-dlp/yt-dlp), [FFmpeg](https://ffmpeg.org) and [Deno](https://deno.com) with winget if they're missing. No administrator rights needed; it installs for your Windows account only.

**Uninstall:** Settings → Apps → Installed apps → Video Downloader → Uninstall. Downloaded videos are never touched.

## Privacy and security

- Nothing is sent anywhere except to the video site you download from (and winget for updates). No analytics.
- Optional YouTube sign-in (for age-restricted videos) is **encrypted with Windows DPAPI**, tied to your Windows account, and only ever used for YouTube links.
- `ytdl://` links from web pages are strictly validated; anything else is refused.
- yt-dlp runs with `--ignore-config --no-plugin-dirs`, so config files or plugins planted elsewhere can't change what it does.
- The data folder (`%LOCALAPPDATA%\VideoDownloader`) is restricted to your Windows account; logs are capped and network reports are deleted after 30 days.

Found a security problem? Please open an issue (without posting any cookies or personal files).

## Files

| File | What it is |
|---|---|
| `Setup.cmd` | Double-click to install |
| `files/VideoDownloader.ps1` | The app (PowerShell + Windows Forms) |
| `files/Install.ps1`, `files/Uninstall.ps1` | Installer / uninstaller |
| `files/VideoDownloader.user.js` | The YouTube Download button (Tampermonkey userscript) |
| `files/Guide.html` | Setup guide shown after install |

## Please use responsibly

Only download videos you have the right to save — your own uploads, Creative Commons or public-domain content, or where the creator allows it. Downloading may be against YouTube's Terms of Service, and you are responsible for how you use this tool. This project isn't affiliated with YouTube or Google.

## Credits

Built on [yt-dlp](https://github.com/yt-dlp/yt-dlp) (Unlicense), [FFmpeg](https://ffmpeg.org) and [Deno](https://deno.com). Licensed under the [MIT License](LICENSE).
