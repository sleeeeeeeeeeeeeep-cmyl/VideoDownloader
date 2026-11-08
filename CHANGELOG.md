# Changelog

## 4.4
- **Update now:** when a new version is out, one click downloads it, checks it against the release's SHA-256 checksums, installs it and reopens the window.
- **Fixed:** 4.2's "private data folder" step could lock you out of your own settings and history ("Access to the path ... is denied"). 4.4 repairs this automatically the first time it opens.
- **Watch history:** hashtags are left out of searches, matching is less strict when the channel is the same, and titles an older version gave up on are searched again.
- **Sign in through Firefox:** if you use Firefox, Video Downloader can read your YouTube sign-in from it (Settings > Network) instead of an exported cookies.txt.
- The YouTube button is also available as a browser extension (for Edge Add-ons and Firefox Add-ons).
- Every release now comes with SHA-256 checksums, built automatically by GitHub after the automatic checks pass.

## 4.3
- The window tells you when a new version is out (checks GitHub once a day; turn it off in Settings > General).
- The YouTube button can be installed in one click from the guide, and then keeps itself up to date through Tampermonkey.
- Videos and audio are saved to your real Downloads folder, even if you moved it to another drive or into OneDrive.

## 4.2
- Security: `ytdl://` links from web pages are strictly checked; links that try to sneak in extra options are refused.
- Security: your optional YouTube sign-in is encrypted with Windows (DPAPI) and only ever used for YouTube links.
- Security: yt-dlp ignores config files and plugins from other folders.
- Privacy: the data folder is private to your Windows account; logs are capped and network reports are deleted after 30 days.
- Clear message when a network's YouTube Restricted Mode hides a video.
- Deno is updated together with yt-dlp.
- Error messages show special characters correctly.

## 4.0
- First public release: installer, Video Downloader window, YouTube Download button, queue with pause/resume, phone mode, clips, playlists, watch history import.
