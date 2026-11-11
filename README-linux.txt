VIDEO DOWNLOADER FOR LINUX
==========================

Download videos and audio from YouTube (and most other video sites) with a
simple window, or from the terminal. Works on Ubuntu, Debian, Mint, Fedora,
Arch, openSUSE, Pop!_OS, ChromeOS Linux and others. No sudo needed.

INSTALL
  1. Open a terminal in this folder: right-click an empty spot in the folder
     and choose "Open in Terminal". (If your file manager has no such entry,
     open a terminal and type:  cd ~/Downloads/VideoDownloader-linux-4.7
     using the name of this folder.)
  2. Type:   sh install.sh   and press Enter.
  It downloads yt-dlp, Deno and (only if your system has none) FFmpeg into
  ~/.local/lib/video-downloader, checking each one against the checksum its
  makers publish. Then "Video Downloader" is in your applications menu.

  The window needs Tk. If setup says it is missing, install it:
    Ubuntu/Debian/Mint:  sudo apt install python3-tk
    Fedora:              sudo dnf install python3-tkinter
    Arch:                sudo pacman -S tk
    openSUSE:            sudo zypper install python3-tk

UPDATE (keeps your settings, queue and history)
  video-downloader update       newest Video Downloader + yt-dlp + Deno
  video-downloader reinstall    install the newest version again (repairs it)
  The same command works for every future version. Before 4.7 there was no
  "update" command; update those once with:
    curl -fsSL https://raw.githubusercontent.com/sleeeeeeeeeeeeeep-cmyl/VideoDownloader/main/install.sh | sh
  If the terminal says "command not found", log out and back in once, or use
  ~/.local/bin/video-downloader update

THE DOWNLOAD BUTTON ON YOUTUBE
  1. Install the Tampermonkey extension in your browser (tampermonkey.net).
  2. Chrome, Brave, Edge, Opera: on the browser's Extensions page, open
     Tampermonkey's details and turn on "Allow User Scripts".
  3. Open this link and click Install on the page Tampermonkey shows:
     https://raw.githubusercontent.com/sleeeeeeeeeeeeeep-cmyl/VideoDownloader/main/VideoDownloader.user.js
  The first time you click Download on YouTube, the browser asks whether to
  open "Video Downloader link": tick "always" and allow it.

FROM THE TERMINAL
  video-downloader                          open the window
  video-downloader LINK [LINK...]           download as video
  video-downloader --type audio LINK        audio only (also: phone, best,
                                            edit, playlist, shrink)
  video-downloader --resume                 continue paused downloads
  video-downloader update                   update everything (see UPDATE)
  video-downloader --update-now             update only yt-dlp and Deno
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

PRIVACY
  Everything the app makes (settings, history, logs, half-done and finished
  downloads) is readable by your account only. Clear finished removes finished
  downloads from the list; Help > Erase my download history deletes the list,
  logs and reports; Settings > General > Forget finished downloads after does it
  automatically. Notifications never show video names.

HELP
  The full guide, troubleshooting and new versions:
  https://github.com/sleeeeeeeeeeeeeep-cmyl/VideoDownloader#linux
  Please only download videos you have the right to download.
