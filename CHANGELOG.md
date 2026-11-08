# Changelog

## 4.5

- **New Help menu** in the window: open the guide, check for updates now, check your connection (Wi-Fi, ping, speed
  and secure-connection report), open the data folder, and the project page. Error messages already pointed to
  "Check for updates", which didn't exist until now.
- **Fixed:** when your sign-in was set to "Always", the automatic retry after updating yt-dlp ran without it.
- **Fixed:** the Wi-Fi check was defined twice; the older copy was dead code and is gone.
- **Fixed:** the cleanup routine deleted the whole download log once it passed 2 MB. Logs are now only trimmed.
- **Fixed:** the tools folder was added to PATH again every time the app looked for its tools.
- The network check only looks at the sites Video Downloader uses.
- Messages about your sign-in no longer assume a cookies.txt file (Firefox works too).
- Code quality: every script has zero PSScriptAnalyzer findings (errors, warnings and information); clear function
  names; every error that is deliberately ignored is passed to PowerShell's debug output instead of vanishing. GitHub
  now runs the analyzer on every upload.
- The setup guide passes an HTML validator; the workflow passes `actionlint` and uses `actions/checkout@v5` (no more
  Node.js 20 warning).
- A much more complete README: every download type and setting, troubleshooting, privacy, and how to build a release.

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
