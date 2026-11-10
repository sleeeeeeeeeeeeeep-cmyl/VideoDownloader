VIDEO DOWNLOADER FOR LINUX
==========================

Download videos and audio from YouTube (and most other video sites) with a
simple window, or from the terminal. Works on Ubuntu, Debian, Mint, Fedora,
Arch, openSUSE, Pop!_OS, ChromeOS Linux and others. No sudo needed.

INSTALL
  1. Open a terminal in this folder (right-click > Open in Terminal).
  2. Run:   sh install.sh
  It downloads yt-dlp, Deno and (only if your system has none) FFmpeg into
  ~/.local/lib/video-downloader, checking each one against the checksum its
  makers publish. Then "Video Downloader" is in your applications menu.

  The window needs Tk. If setup says it is missing, install it:
    Ubuntu/Debian/Mint:  sudo apt install python3-tk
    Fedora:              sudo dnf install python3-tkinter
    Arch:                sudo pacman -S tk
    openSUSE:            sudo zypper install python3-tk

THE DOWNLOAD BUTTON ON YOUTUBE
  Install the Tampermonkey extension in your browser, then open
  https://raw.githubusercontent.com/sleeeeeeeeeeeeeep-cmyl/VideoDownloader/main/VideoDownloader.user.js
  and click Install. The first time you click Download, the browser asks
  whether to open "Video Downloader link" - allow it (tick "always").

FROM THE TERMINAL
  video-downloader                          open the window
  video-downloader LINK [LINK...]           download as video
  video-downloader --type audio LINK        audio only (also: phone, best,
                                            edit, playlist, shrink)
  video-downloader --resume                 continue paused downloads
  video-downloader --update-now             update yt-dlp and Deno
  video-downloader --connection-check       check your connection
  video-downloader --uninstall              remove it
  Ctrl+C pauses (nothing is lost); --resume or the window's Resume continues.

WHERE THINGS GO
  Videos: ~/Downloads/Videos   Phone: ~/Downloads/Phone   Audio: ~/Downloads/Audio
  (change them in Settings). Settings, history and logs are in
  ~/.local/share/video-downloader (only your account can open it).

SIGN-IN (age-restricted or members-only videos)
  Settings > Network > "Where your sign-in comes from": pick the browser you
  are signed in to YouTube with (Firefox, Chrome, Chromium, Brave, Edge, Opera
  or Vivaldi). It is only used for YouTube links, and by default only when a
  video needs it.

HELP
  The full guide, troubleshooting and new versions:
  https://github.com/sleeeeeeeeeeeeeep-cmyl/VideoDownloader#linux
  Please only download videos you have the right to download.
