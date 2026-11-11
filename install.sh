#!/bin/sh
# Video Downloader for Linux - setup AND update.
#
#   From the extracted download:   sh install.sh
#   Or straight from GitHub:       curl -fsSL https://raw.githubusercontent.com/sleeeeeeeeeeeeeep-cmyl/VideoDownloader/main/install.sh | sh
#   Already installed (4.7+):      video-downloader update      (runs this same file, fetched fresh from GitHub)
#
# Installs for your account only (no sudo). The second way downloads the newest Linux release first and checks it
# against the release's SHA-256 checksums before running anything from it. Run over ANY earlier version it updates
# it (settings, queue and history are kept) and updates yt-dlp and Deno; if you already have the newest version, only
# yt-dlp and Deno are updated (VD_REINSTALL=1 installs it again anyway).
# Remove it again with:  video-downloader --uninstall
#
# Everything is inside main(), which is only called on the very last line: if the download of this script is cut
# off half-way, nothing at all runs.
set -eu

REPO="sleeeeeeeeeeeeeep-cmyl/VideoDownloader"

say() { printf '%s\n' "$*"; }
fail() { printf 'Setup stopped: %s\n' "$*" >&2; exit 1; }

main() {
    # ---- Python 3.8 or newer (every current Linux has it)
    PY=""
    for candidate in python3 python; do
        if command -v "$candidate" >/dev/null 2>&1 &&
            "$candidate" -I -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>/dev/null; then
            PY=$candidate
            break
        fi
    done
    if [ -z "$PY" ]; then
        fail "Video Downloader needs Python 3.8 or newer. Install it with your package manager (for example: sudo apt install python3), then run this again."
    fi

    # ---- next to the app (the extracted download)? Then install from here.
    here=""
    case "$0" in
        */*) here=$(cd "$(dirname "$0")" && pwd) ;;
    esac
    if [ -n "$here" ] && [ -f "$here/video-downloader.py" ]; then
        exec "$PY" "$here/video-downloader.py" --install "$@"
    fi

    # ---- otherwise download the newest Linux release and check it first
    if command -v curl >/dev/null 2>&1; then
        fetch() { curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 -o "$2" "$1"; }
    elif command -v wget >/dev/null 2>&1; then
        fetch() { wget -q --https-only -O "$2" "$1"; }
    else
        fail "curl or wget is needed to download Video Downloader."
    fi
    # (python3 -I: ignore the current folder and environment, so nothing lying around can change what runs)
    if command -v sha256sum >/dev/null 2>&1; then
        hash_of() { sha256sum "$1" | cut -d ' ' -f 1; }
    else
        hash_of() { "$PY" -I -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"; }
    fi

    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    trap 'exit 130' INT TERM
    say "Finding the newest version of Video Downloader..."
    fetch "https://api.github.com/repos/$REPO/releases/latest" "$work/release.json"
    tarball=$("$PY" -I -c '
import json, re, sys
names = [a["name"] for a in json.load(open(sys.argv[1])).get("assets", [])]
print(next((n for n in names if re.match(r"^VideoDownloader-linux-[0-9.]+\.tar\.gz$", n)), ""))
' "$work/release.json")
    [ -n "$tarball" ] || fail "the newest release has no Linux download yet. See https://github.com/$REPO/releases"

    # ---- already installed? (any earlier version is simply updated; the newest one only needs its helpers updated)
    installed="${VIDEODOWNLOADER_HOME:-$HOME/.local/lib/video-downloader}/video-downloader.py"
    latest=$("$PY" -I -c 'import json, sys; print(str(json.load(open(sys.argv[1])).get("tag_name", "")).lstrip("vV"))' "$work/release.json")
    have=""
    if [ -f "$installed" ]; then
        have=$("$PY" -I -c '
import re, sys
m = re.search(r"^APP_VERSION = .([0-9.]+).", open(sys.argv[1], encoding="utf-8").read(), re.M)
print(m.group(1) if m else "?")
' "$installed" 2>/dev/null || echo "?")
    fi
    current=$("$PY" -I -c '
import re, sys
def v(t):
    return tuple(int(x) for x in t.split(".")) if re.match(r"^[0-9]+(\.[0-9]+)*$", t) else None
a, b = v(sys.argv[1]), v(sys.argv[2])
print(1 if a and b and a >= b else 0)
' "$have" "$latest")
    if [ "$current" = 1 ] && [ -z "${VD_REINSTALL:-}" ]; then
        say "You already have the newest Video Downloader ($have). Checking yt-dlp and Deno for updates..."
        "$PY" -I "$installed" --update-now || true
        say "Everything is up to date. (To install this version again anyway: video-downloader reinstall)"
        return 0
    fi
    if [ -n "$have" ] && [ "$have" = "$latest" ]; then say "Reinstalling Video Downloader $latest..."
    elif [ -n "$have" ]; then say "Updating Video Downloader from $have to $latest..."
    else say "Installing Video Downloader $latest..."; fi
    base="https://github.com/$REPO/releases/latest/download"
    say "Downloading $tarball..."
    fetch "$base/$tarball" "$work/$tarball"
    fetch "$base/SHA256SUMS.txt" "$work/SHA256SUMS.txt"
    want=$(grep -E "^[0-9a-fA-F]{64} [ *]?$tarball\$" "$work/SHA256SUMS.txt" | cut -d ' ' -f 1 | tr 'A-F' 'a-f' || true)
    got=$(hash_of "$work/$tarball")
    if [ -z "$want" ] || [ "$want" != "$got" ]; then
        fail "the download did not match its published checksum, so nothing was installed."
    fi
    say "Checksum OK."
    mkdir "$work/x"
    "$PY" -I -c '
import os, sys, tarfile
dest = os.path.realpath(sys.argv[2])
with tarfile.open(sys.argv[1]) as t:
    for m in t.getmembers():
        target = os.path.realpath(os.path.join(dest, m.name))
        if not (target == dest or target.startswith(dest + os.sep)) or not (m.isfile() or m.isdir()):
            sys.exit("unsafe entry in the download: " + m.name)
    if hasattr(tarfile, "data_filter"):
        t.extractall(dest, filter="data")
    else:
        t.extractall(dest)
' "$work/$tarball" "$work/x"
    app=$(find "$work/x" -name video-downloader.py -type f | head -n 1)
    [ -n "$app" ] || fail "the download has no video-downloader.py."
    "$PY" -I "$app" --install "$@"
}

main "$@"
