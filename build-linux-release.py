#!/usr/bin/env python3
"""Builds dist/VideoDownloader-linux-<version>.tar.gz and adds its SHA-256 to dist/SHA256SUMS.txt.

GitHub runs this after Build-Release.ps1 when a release is published (see .github/workflows/ci.yml).
Run it yourself with:  python3 build-linux-release.py [--tag 4.6]
"""
import argparse
import hashlib
import io
import os
import re
import sys
import tarfile
import time

ROOT = os.path.dirname(os.path.abspath(__file__))
FILES = [  # (name in the repository, permissions in the download)
    ('install.sh', 0o755), ('video-downloader.py', 0o755), ('VideoDownloader.user.js', 0o644),
    ('video-downloader.png', 0o644), ('README-linux.txt', 0o644), ('LICENSE', 0o644),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--tag', default='')
    tag = ap.parse_args().tag
    with open(os.path.join(ROOT, 'video-downloader.py'), encoding='utf-8') as f:
        m = re.search(r"^APP_VERSION = '([0-9.]+)'$", f.read(), re.M)
    if not m:
        sys.exit('Could not find APP_VERSION in video-downloader.py')
    ver = m.group(1)
    if tag and tag.lstrip('vV') != ver:
        sys.exit("The release tag '{}' doesn't match the Linux app's version '{}' (APP_VERSION in video-downloader.py).".format(tag, ver))
    dist = os.path.join(ROOT, 'dist')
    os.makedirs(dist, exist_ok=True)
    name = 'VideoDownloader-linux-{}.tar.gz'.format(ver)
    out = os.path.join(dist, name)
    top = 'VideoDownloader-linux-{}'.format(ver)
    stamp = int(time.time())
    with tarfile.open(out, 'w:gz', format=tarfile.PAX_FORMAT) as t:
        d = tarfile.TarInfo(top)
        d.type, d.mode, d.mtime = tarfile.DIRTYPE, 0o755, stamp
        t.addfile(d)
        for fname, mode in FILES:
            with open(os.path.join(ROOT, fname), 'rb') as f:
                data = f.read()
            if fname.endswith(('.sh', '.py', '.txt', '.js')):
                data = data.replace(b'\r\n', b'\n')     # in case the files went through Windows
            info = tarfile.TarInfo('{}/{}'.format(top, fname))
            info.size, info.mode, info.mtime = len(data), mode, stamp
            t.addfile(info, io.BytesIO(data))
    with open(out, 'rb') as f:
        digest = hashlib.sha256(f.read()).hexdigest()
    sums = os.path.join(dist, 'SHA256SUMS.txt')
    lines = []
    if os.path.exists(sums):
        with open(sums, encoding='utf-8-sig') as f:
            lines = [ln.rstrip('\r\n') for ln in f if ln.strip() and not ln.rstrip().endswith(' ' + name)]
    lines.append('{}  {}'.format(digest, name))
    with open(sums, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')
    print('Built {}\n  {}  {}'.format(out, digest, name))


if __name__ == '__main__':
    main()
