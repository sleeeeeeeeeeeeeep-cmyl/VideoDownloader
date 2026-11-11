# Changelog

## 4.6.2

Easier to install.

- **Windows in one line:** press Windows key + R, paste the line from the README's Quick install, press Enter. It
  downloads the newest release, checks it against the published SHA-256 checksums and runs Setup: no ZIP to extract,
  no "Windows protected your PC" warning (`get.ps1`).
- **The button in one click:** if Tampermonkey is already in your default browser (Chrome, Edge, Brave, Vivaldi,
  Opera or Firefox), Setup opens the button's install page for you on Windows and Linux; just click Install.
- The README starts with a Quick install section for both systems.
- **Settings > Update now:** gets the newest Video Downloader if there is one, otherwise updates yt-dlp and Deno.
- **The version is shown** in the bottom-right corner of the main window (click it for what's new) and in Settings.

## 4.6.1

A full check of every file for anything that could stop downloads, or let someone else get at what you download.

Downloads

- Audio-only now works on sites that only offer video and sound in one file (it failed with "Requested format is not
  available").
- Phone and Shrink downloads are never lost: if FFmpeg is missing or a file can't be moved (OneDrive or iCloud busy),
  the video is saved as downloaded instead of being deleted with the work folder.
- Linux: a playlist where a few videos are unavailable now counts as done (like on Windows); "already downloaded" is
  no longer reported as a failure; a download that can't start, or any unexpected error, fails that one download
  instead of stopping the downloader; a failed helper download during setup no longer stops setup; file names are the
  same as on Windows, so they copy to USB sticks and phones.

Privacy and security

- New: Help > Erase my download history (the list, all logs, connection reports and playlist memory, in one go), and
  Settings > General > Forget finished downloads after (1, 7, 30 or 90 days).
- Clear finished and Remove really delete the entries, and Clear finished also clears the log that names them.
- No log records the links you click any more, and notifications no longer show video names (they appear on the lock
  screen).
- Each download keeps its half-done pieces in its own private folder, deleted when it finishes or is removed.
- Pause and Stop only ever stop Video Downloader's own programs (an old process number in a status file could belong
  to another program), and a sign-in copy the stopped downloader had open is encrypted again straight away.
- A hand-edited or damaged settings file can't slip unexpected values into downloads: choices must be listed ones and
  folders full paths.
- Linux: everything the app creates, downloads included, is readable by your account only; the connection report no
  longer lists the names of nearby Wi-Fi networks; downloads during setup and updates are https-only, also after
  redirects; Python runs isolated (`-I`) so files in the current folder can't change it; install.sh only runs once it
  has downloaded completely; desktop menu entries are quoted correctly whatever your folder names are.
- The guide has a Content Security Policy and a new "Privacy" section.

## 4.6

- **New: Video Downloader for Linux.** The same downloads (all eight types, every setting), the same queue that waits
  out dropped connections, pause and resume, failure explanations and the signed-in retry, in a window or from the
  terminal (`video-downloader --type audio LINK`). The YouTube Download button works with it unchanged. Install with
  `sh install.sh` from `VideoDownloader-linux-4.6.tar.gz`, or one line with curl; no sudo needed. Helper programs are
  checked against their published SHA-256 checksums, and "Update now" works the same way as on Windows.
- Releases now include the Linux download, and its checksum is in `SHA256SUMS.txt`.
- GitHub now also checks the Linux app on every upload: ruff, vermin (Python 3.8 compatibility), shellcheck and 32
  tests on Python 3.8 and the current Ubuntu Python, including opening the window on a virtual display.
- Windows: version 4.6 so both apps match; the README has a Linux section and a Windows/Linux comparison.

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
