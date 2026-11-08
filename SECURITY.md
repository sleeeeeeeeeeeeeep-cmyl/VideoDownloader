# Security

## Reporting a problem

Please report security problems **privately**: on this repository's **Security** tab, click **Report a vulnerability**
([direct link](https://github.com/sleeeeeeeeeeeeeep-cmyl/VideoDownloader/security/advisories/new)).
Don't open a public issue, and never include anyone's cookies.txt.

Only the newest release gets fixes, so please check you're on it first.

## Good examples of what to report

- A web page or link that makes Video Downloader run something, write files outside its folders, or download without you clicking.
- Any way your YouTube sign-in (cookies) could leave your PC or reach a site other than YouTube.
- A way another Windows account on the same PC could read Video Downloader's data folder.
- A problem in "Update now" that could install something other than the official release.

## What Video Downloader does to stay safe

- `ytdl://` links (which any web page can send) only ever carry a download type and a YouTube video ID; anything else is refused.
- Your optional sign-in is encrypted with Windows DPAPI, tied to your Windows account, and only ever used for YouTube addresses.
- yt-dlp runs with `--ignore-config --no-plugin-dirs`, so files planted elsewhere can't change what it does.
- The data folder is private to your Windows account.
- "Update now" only downloads from this repository's releases and checks the file against the release's SHA-256 checksums before installing.
- Every upload is checked automatically on Windows (see `Tests.ps1`).
