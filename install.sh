#!/bin/sh
# Video Downloader for Linux - setup.
#
#   From the extracted download:   sh install.sh
#   Or straight from GitHub:       curl -fsSL https://raw.githubusercontent.com/sleeeeeeeeeeeeeep-cmyl/VideoDownloader/main/install.sh | sh
#
# Installs for your account only (no sudo). The second way downloads the newest Linux release first and checks it
# against the release's SHA-256 checksums before running anything from it.
# Remove it again with:  video-downloader --uninstall
set -eu

REPO="sleeeeeeeeeeeeeep-cmyl/VideoDownloader"

say() { printf '%s\n' "$*"; }
fail() { printf 'Setup stopped: %s\n' "$*" >&2; exit 1; }

# ---- Python 3.8 or newer (every current Linux has it)
PY=""
for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 &&
        "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>/dev/null; then
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
    fetch() { curl -fsSL --proto '=https' --tlsv1.2 -o "$2" "$1"; }
elif command -v wget >/dev/null 2>&1; then
    fetch() { wget -q --https-only -O "$2" "$1"; }
else
    fail "curl or wget is needed to download Video Downloader."
fi
if command -v sha256sum >/dev/null 2>&1; then
    hash_of() { sha256sum "$1" | cut -d ' ' -f 1; }
else
    hash_of() { "$PY" -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"; }
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
say "Finding the newest version of Video Downloader..."
fetch "https://api.github.com/repos/$REPO/releases/latest" "$work/release.json"
tarball=$("$PY" -c '
import json, re, sys
names = [a["name"] for a in json.load(open(sys.argv[1])).get("assets", [])]
print(next((n for n in names if re.match(r"^VideoDownloader-linux-[0-9.]+\.tar\.gz$", n)), ""))
' "$work/release.json")
[ -n "$tarball" ] || fail "the newest release has no Linux download yet. See https://github.com/$REPO/releases"
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
"$PY" -c '
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
"$PY" "$app" --install "$@"
