# Changelog

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
