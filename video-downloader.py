#!/usr/bin/env python3
"""Video Downloader for Linux.

Download videos and audio from YouTube (and most other video sites) with yt-dlp.
The same YouTube Download button as the Windows version sends ytdl:// links here.

    video-downloader                      the window (paste links, watch progress, pause, settings)
    video-downloader URL [URL...]         download in this terminal (--type video|phone|best|edit|audio|playlist|shrink)
    video-downloader --uri ytdl://...     a link from the Download button (added to the queue)
    video-downloader --settings           the settings window
    video-downloader --resume             continue paused downloads in this terminal
    video-downloader --update-now         update yt-dlp and Deno now
    video-downloader --connection-check   check the connection and open the report
    video-downloader --install            install from an extracted release folder (install.sh runs this)
    video-downloader --uninstall          remove Video Downloader (asks about your settings and history)

Only the Python 3.8+ standard library is used; the window needs Tk (the python3-tk package on most systems).
"""

import argparse
import datetime
import fcntl
import hashlib
import json
import os
import platform
import queue
import random
import re
import shlex
import shutil
import signal
import socket
import ssl
import subprocess
import sys
import tarfile
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

APP_VERSION = '4.6.1'
APP_NAME = 'Video Downloader'
UPDATE_REPO = 'sleeeeeeeeeeeeeep-cmyl/VideoDownloader'
PROJECT_URL = 'https://github.com/' + UPDATE_REPO
README_LINUX_URL = PROJECT_URL + '#linux'
RELEASES_PAGE = PROJECT_URL + '/releases/latest'
USERSCRIPT_URL = 'https://raw.githubusercontent.com/' + UPDATE_REPO + '/main/VideoDownloader.user.js'

# yt-dlp would also read settings files and plugins from other folders; another program could put commands there
# (for example --exec), so only the options this app gives it are used.
YT_SAFE_ARGS = ['--ignore-config', '--no-plugin-dirs']

MODES = ['video', 'phone', 'best', 'edit', 'audio', 'clip', 'playlist', 'shrink']
MODE_NAMES = {
    'video': 'Video', 'phone': 'Phone', 'best': 'Best quality', 'edit': 'Editor-friendly', 'audio': 'Audio only',
    'clip': 'Clip', 'playlist': 'Whole playlist', 'shrink': 'Shrink',
}


# ============================================================ paths
def _xdg(var, default):
    v = os.environ.get(var, '')
    return v if v and os.path.isabs(v) else os.path.join(os.path.expanduser('~'), default)


def downloads_folder():
    """Where the desktop keeps Downloads (it can be renamed or translated), falling back to ~/Downloads."""
    try:
        r = subprocess.run(['xdg-user-dir', 'DOWNLOAD'], capture_output=True, text=True, timeout=5, check=False)
        p = r.stdout.strip()
        if r.returncode == 0 and p and os.path.isdir(p) and p != os.path.expanduser('~'):
            return p
    except (OSError, subprocess.SubprocessError):
        pass
    return os.path.join(os.path.expanduser('~'), 'Downloads')


class Paths:
    def __init__(self):
        self.data = os.environ.get('VIDEODOWNLOADER_DATA') or os.path.join(_xdg('XDG_DATA_HOME', '.local/share'), 'video-downloader')
        self.app_home = os.environ.get('VIDEODOWNLOADER_HOME') or os.path.join(os.path.expanduser('~'), '.local', 'lib', 'video-downloader')
        self.bin = os.path.join(self.app_home, 'bin')
        self.queue = os.path.join(self.data, 'queue')
        self.running = os.path.join(self.queue, 'running')
        self.temp = os.path.join(self.data, 'temp')
        self.settings = os.path.join(self.data, 'settings.json')
        self.status = os.path.join(self.data, 'status.json')
        self.history = os.path.join(self.data, 'history.jsonl')
        self.history_log = os.path.join(self.data, 'history.log')      # (older versions; erased with the history)
        self.runner_log = os.path.join(self.data, 'runner.log')
        self.error_log = os.path.join(self.data, 'error.log')
        self.runner_lock = os.path.join(self.data, 'runner.lock')
        self.window_lock = os.path.join(self.data, 'window.lock')
        self.paused = os.path.join(self.data, 'paused')
        self.cancel = os.path.join(self.data, 'cancel-current')
        self.retry_now = os.path.join(self.data, 'retry-now')
        self.cookies = os.path.join(self.data, 'cookies.txt')
        self.last_update = os.path.join(self.data, 'last-update.txt')
        self.app_update = os.path.join(self.data, 'app-update.json')
        self.archive = os.path.join(self.data, 'playlist-archive.txt')
        self.report = os.path.join(self.data, 'connection-check.txt')

    def ensure(self):
        for d in (self.data, self.queue, self.running, self.temp):
            os.makedirs(d, exist_ok=True)
        # your sign-in, history and network reports live here, so only your account may open it
        try:
            os.chmod(self.data, 0o700)
        except OSError:
            pass
        mark = os.path.join(self.data, '.private-v1')
        if not os.path.exists(mark):      # once: files made before everything was private
            for dirpath, dirs, files in os.walk(self.data):
                for n in dirs:
                    _chmod_quiet(os.path.join(dirpath, n), 0o700)
                for n in files:
                    _chmod_quiet(os.path.join(dirpath, n), 0o600)
            with open(mark, 'w', encoding='utf-8') as f:
                f.write(APP_VERSION)


def _chmod_quiet(path, mode):
    try:
        if not os.path.islink(path):
            os.chmod(path, mode)
    except OSError:
        pass


P = Paths()
# Everything this app creates (settings, history, logs, half-done downloads, and the downloads themselves) is readable
# by your account only. Other accounts on this computer can't open any of it.
os.umask(0o077)


# ============================================================ small helpers
def now_iso():
    return datetime.datetime.now().replace(microsecond=0).isoformat()


def log(path, text):
    try:
        with open(path, 'a', encoding='utf-8') as f:
            f.write('{:%Y-%m-%d %H:%M:%S}  {}\n'.format(datetime.datetime.now(), text))
    except OSError:
        pass


def say(text):
    """Progress text: the terminal in terminal mode, runner.log for the background downloader."""
    if STATE.interactive:
        if STATE.progress_line:
            print()
            STATE.progress_line = False
        print(text, flush=True)
    else:
        try:
            with open(P.runner_log, 'a', encoding='utf-8') as f:
                f.write('{:%H:%M:%S}  {}\n'.format(datetime.datetime.now(), text))
        except OSError:
            pass


class _State:
    interactive = False
    progress_line = False    # a progress line is on screen without its line ending yet


STATE = _State()


def write_json(path, obj, private=False):
    tmp = '{}.{}.tmp'.format(path, os.getpid())
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(obj, f, indent=2)
    if private:
        os.chmod(tmp, 0o600)
    os.replace(tmp, path)


def read_json(path, default=None):
    try:
        with open(path, encoding='utf-8-sig') as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def limit_file(path, max_bytes, keep_lines):
    try:
        if os.path.getsize(path) <= max_bytes:
            return
        with open(path, encoding='utf-8', errors='replace') as f:
            lines = f.readlines()
        with open(path, 'w', encoding='utf-8') as f:
            f.writelines(lines[-keep_lines:])
    except OSError:
        pass


def limit_private_data():
    limit_file(P.runner_log, 1024 * 1024, 3000)
    limit_file(P.error_log, 256 * 1024, 500)
    try:
        os.remove(P.history_log)          # older versions kept a second copy of the history here
    except OSError:
        pass
    days = int(SETTINGS.get('KeepHistoryDays', 0) or 0)
    cutoff = (datetime.datetime.now() - datetime.timedelta(days=days)).replace(microsecond=0).isoformat() if days > 0 else ''
    try:
        if cutoff or os.path.getsize(P.history) > 2 * 1024 * 1024:
            with HistoryLock():
                with open(P.history, encoding='utf-8', errors='replace') as f:
                    lines = f.readlines()
                keep = []
                for line in lines[-3000:]:
                    try:
                        e = json.loads(line)
                    except ValueError:
                        continue
                    if isinstance(e, dict) and (not cutoff or str(e.get('time', '')) >= cutoff):
                        keep.append(line if line.endswith('\n') else line + '\n')
                if len(keep) != len(lines):
                    write_lines(P.history, keep)
    except OSError:
        pass
    try:
        if os.path.getmtime(P.report) < time.time() - 30 * 86400:
            os.remove(P.report)
    except OSError:
        pass


def erase_history():
    """Help > Erase my download history: the list of downloads, the logs, the reports and the playlist memory."""
    gone = 0
    with HistoryLock():
        for path in (P.history, P.history_log, P.runner_log, P.error_log, P.report, P.archive, P.status):
            try:
                os.remove(path)
                gone += 1
            except OSError:
                pass
    return gone


def format_clock(seconds):
    s = int(seconds)
    h, m, sec = s // 3600, (s % 3600) // 60, s % 60
    return '{}h{:02d}m{:02d}s'.format(h, m, sec) if h else '{}m{:02d}s'.format(m, sec)


def parse_clock(text):
    """'90', '1:30' or '1:02:03' -> seconds, or None."""
    t = (text or '').strip()
    if not re.match(r'^\d+(:\d{1,2}){0,2}(\.\d+)?$', t):
        return None
    total = 0.0
    for part in t.split(':'):
        total = total * 60 + float(part)
    return total


def parse_version(tag):
    t = (tag or '').strip().lstrip('vV')
    if not re.match(r'^\d+(\.\d+){0,3}$', t):
        return None
    return tuple(int(x) for x in t.split('.'))


def open_path(path):
    """Open a file, folder or web address with the desktop's default app."""
    try:
        subprocess.Popen(['xdg-open', path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        return True
    except OSError:
        return False


def show_in_folder(path):
    """Show a file selected in the file manager (GNOME, KDE and others support this), or just open its folder."""
    uri = 'file://' + urllib.parse.quote(os.path.abspath(path))
    try:
        r = subprocess.run(['gdbus', 'call', '--session', '--dest', 'org.freedesktop.FileManager1',
                            '--object-path', '/org/freedesktop/FileManager1', '--method',
                            'org.freedesktop.FileManager1.ShowItems', "['{}']".format(uri), ''],
                           capture_output=True, timeout=5, check=False)
        if r.returncode == 0:
            return
    except (OSError, subprocess.SubprocessError):
        pass
    open_path(os.path.dirname(path) or '.')


def notify(title, body):
    if not SETTINGS.get('Notify', True) or not shutil.which('notify-send'):
        return
    icon = os.path.join(P.app_home, 'video-downloader.png')
    cmd = ['notify-send', '-a', APP_NAME, title, body]
    if os.path.exists(icon):
        cmd[1:1] = ['-i', icon]
    try:
        subprocess.run(cmd, timeout=5, capture_output=True, check=False)
    except (OSError, subprocess.SubprocessError):
        pass


def process_alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except (OSError, ValueError, TypeError):
        return False


class FileLock:
    """An exclusive lock that the system releases if the process dies (so a crash never leaves it stuck)."""

    def __init__(self, path):
        self.path = path
        self.f = None

    def acquire(self):
        self.f = open(self.path, 'a+')
        try:
            fcntl.flock(self.f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            self.f.close()
            self.f = None
            return False
        self.f.seek(0)
        self.f.truncate()
        self.f.write(str(os.getpid()))
        self.f.flush()
        return True

    def held_by_other(self):
        if self.acquire():
            self.release()
            return False
        return True

    def release(self):
        if self.f:
            try:
                fcntl.flock(self.f, fcntl.LOCK_UN)
            finally:
                self.f.close()
                self.f = None


class HistoryLock:
    """The window (hiding lines) and the downloader (adding lines) never write history.jsonl at the same moment."""

    def __enter__(self):
        self.f = open(P.history + '.lock', 'a')
        fcntl.flock(self.f, fcntl.LOCK_EX)
        return self

    def __exit__(self, *exc):
        fcntl.flock(self.f, fcntl.LOCK_UN)
        self.f.close()
        return False


def history_key(e):
    return hashlib.sha1((str(e.get('time', '')) + '|' + str(e.get('url', ''))).encode('utf-8')).hexdigest()[:16]  # noqa: S324 - an id, not security


def write_lines(path, lines):
    tmp = '{}.{}.tmp'.format(path, os.getpid())
    with open(tmp, 'w', encoding='utf-8') as f:
        f.writelines(lines)
    os.replace(tmp, path)


# ============================================================ settings
def default_settings():
    dl = downloads_folder()
    return {
        'NameStyle': 'title-id', 'MenuDefault': 'video', 'OpenAppOnDownload': True, 'CloseWhenDone': True,
        'Notify': True, 'ShowInFolder': False, 'AutoUpdateDays': 7, 'CheckAppUpdates': True,
        'VideoFolder': os.path.join(dl, 'Videos'), 'MaxHeight': 1080, 'BestHeight': 0, 'EditHeight': 1080,
        'VideoCodec': 'av1', 'MaxFps': 0, 'Container': 'mp4', 'EmbedChapters': True, 'EmbedThumbnail': False,
        'PhoneFolder': os.path.join(dl, 'Phone'), 'PhoneHeight': 720, 'PhoneMaxFps': 0,
        'AudioFolder': os.path.join(dl, 'Audio'), 'AudioFormat': 'm4a', 'AudioQuality': 'best', 'AudioCover': True,
        'SubtitleMode': 'off', 'SubtitleLangs': 'en', 'AutoSubtitles': False, 'SponsorBlock': 'off',
        'ClipAccurate': True, 'ShrinkQuality': 'balanced', 'PlaylistFolders': True,
        'Fragments': 4, 'SpeedLimit': 0, 'UseCookies': 'auto', 'CookieSource': 'firefox', 'KeepHistoryDays': 0,
    }


SETTING_DEFS = [
    ('General', 'MenuDefault', 'Default download type', 'choice', [('video', 'Video'), ('phone', 'Phone'), ('best', 'Best quality'), ('edit', 'Editor-friendly'), ('audio', 'Audio only')]),
    ('General', 'NameStyle', 'File names', 'choice', [('title-id', 'Title [id].mp4'), ('title', 'Title.mp4'), ('channel-title', 'Channel - Title.mp4'), ('date-title', '2026-01-31 - Title.mp4 (upload date)')]),
    ('General', 'OpenAppOnDownload', 'Show this window when a download starts', 'bool', None),
    ('General', 'CloseWhenDone', '...and close it when all went well', 'bool', None),
    ('General', 'Notify', 'Notification when done', 'bool', None),
    ('General', 'ShowInFolder', 'Show the file in the file manager when done', 'bool', None),
    ('General', 'AutoUpdateDays', 'Auto-update yt-dlp', 'choice', [(7, 'Weekly'), (30, 'Monthly'), (0, 'Never')]),
    ('General', 'CheckAppUpdates', 'Tell me about new versions', 'bool', None),
    ('General', 'KeepHistoryDays', 'Forget finished downloads after', 'choice', [(0, 'Never (keep the list)'), (90, '90 days'), (30, '30 days'), (7, '7 days'), (1, '1 day')]),
    ('Video', 'VideoFolder', 'Save videos to', 'folder', None),
    ('Video', 'MaxHeight', 'Video / clip / playlist quality', 'choice', [(480, '480p'), (720, '720p'), (1080, '1080p'), (1440, '1440p'), (2160, '4K (2160p)')]),
    ('Video', 'BestHeight', 'Best quality limit', 'choice', [(0, 'No limit (up to 8K)'), (2160, '4K (2160p)'), (1440, '1440p')]),
    ('Video', 'EditHeight', 'Editor-friendly quality', 'choice', [(720, '720p'), (1080, '1080p (H.264 tops out here on YouTube)')]),
    ('Video', 'VideoCodec', 'Preferred video format', 'choice', [('av1', 'AV1 (smallest files)'), ('vp9', 'VP9'), ('h264', 'H.264 (plays on anything, bigger)')]),
    ('Video', 'MaxFps', 'Frame rate', 'choice', [(0, 'Same as the video'), (60, 'Up to 60 fps'), (30, 'Up to 30 fps (smaller)')]),
    ('Video', 'Container', 'File type', 'choice', [('mp4', 'MP4 (works everywhere)'), ('mkv', 'MKV')]),
    ('Video', 'EmbedChapters', 'Add chapters', 'bool', None),
    ('Video', 'EmbedThumbnail', 'Add thumbnail as cover', 'bool', None),
    ('Phone', 'PhoneFolder', 'Save phone videos to', 'folder', None),
    ('Phone', 'PhoneHeight', 'Phone quality', 'choice', [(480, '480p (smallest files)'), (720, '720p (recommended)'), (1080, '1080p (sharpest)')]),
    ('Phone', 'PhoneMaxFps', 'Phone frame rate', 'choice', [(0, 'Same as the video'), (30, 'Up to 30 fps (smaller)')]),
    ('Audio', 'AudioFolder', 'Save audio to', 'folder', None),
    ('Audio', 'AudioFormat', 'Audio format', 'choice', [('m4a', 'M4A (no quality loss)'), ('mp3', 'MP3 (plays on everything)'), ('opus', 'Opus (small)'), ('flac', 'FLAC (lossless copy, big)'), ('wav', 'WAV (for editing, huge)')]),
    ('Audio', 'AudioQuality', 'MP3 / Opus quality', 'choice', [('best', 'Best'), ('256', '256 kbps'), ('192', '192 kbps'), ('128', '128 kbps (smallest)')]),
    ('Audio', 'AudioCover', 'Add cover art', 'bool', None),
    ('Extras', 'SubtitleMode', 'Subtitles', 'choice', [('off', 'None'), ('embed', 'Inside the video'), ('file', 'Separate .srt file')]),
    ('Extras', 'SubtitleLangs', 'Subtitle languages', 'choice', [('en', 'English'), ('all', 'All languages')]),
    ('Extras', 'AutoSubtitles', 'Include auto-generated subtitles', 'bool', None),
    ('Extras', 'SponsorBlock', 'Sponsor segments', 'choice', [('off', 'Leave alone'), ('mark', 'Mark them as chapters'), ('remove', 'Cut them out')]),
    ('Extras', 'ClipAccurate', 'Exact clip start/end (slower)', 'bool', None),
    ('Extras', 'ShrinkQuality', 'Shrink mode', 'choice', [('smaller', 'Smallest file'), ('balanced', 'Balanced'), ('better', 'Better quality')]),
    ('Extras', 'PlaylistFolders', 'Playlists get their own folder', 'bool', None),
    ('Network', 'Fragments', 'Parallel download pieces', 'choice', [(1, '1 (gentlest)'), (4, '4 (recommended)'), (8, '8 (fastest)')]),
    ('Network', 'SpeedLimit', 'Speed limit', 'choice', [(0, 'No limit'), (10, '10 MB/s'), (5, '5 MB/s'), (2, '2 MB/s'), (1, '1 MB/s')]),
    ('Network', 'UseCookies', 'Use your YouTube sign-in', 'choice', [('auto', 'Only when a video needs it (recommended)'), ('always', 'Always'), ('never', 'Never')]),
    ('Network', 'CookieSource', 'Where your sign-in comes from', 'choice', [('firefox', 'Firefox'), ('chrome', 'Google Chrome'), ('chromium', 'Chromium'), ('brave', 'Brave'), ('edge', 'Microsoft Edge'), ('opera', 'Opera'), ('vivaldi', 'Vivaldi'), ('file', 'A cookies.txt file (see the README)')]),
]


def clean_folder(value):
    """A folder setting: a full path (~ allowed), or None if it isn't one."""
    if not isinstance(value, str):
        return None
    v = os.path.expanduser(value.strip())
    if not v or not os.path.isabs(v) or any(ord(ch) < 32 for ch in v):
        return None
    return os.path.normpath(v)


def load_settings():
    s = default_settings()
    saved = read_json(P.settings, {}) or {}
    if not isinstance(saved, dict):
        saved = {}
    defs = {d[1]: d for d in SETTING_DEFS}
    for k, v in saved.items():
        d = defs.get(k)
        if k not in s or not d:
            continue
        if d[3] == 'choice' and v not in [c[0] for c in d[4]]:
            continue           # an unknown value (hand-edited, or from another version): keep the default
        if d[3] == 'bool':
            v = bool(v)
        if d[3] == 'folder':
            v = clean_folder(v)
            if not v:
                continue
        s[k] = v
    return s


def save_settings(s):
    write_json(P.settings, s, private=True)


SETTINGS = {}


# ============================================================ links and jobs
YOUTUBE_RE = re.compile(r'^https?://([A-Za-z0-9-]+\.)*(youtube\.com|youtu\.be|youtube-nocookie\.com)([/:?#]|$)')
URI_RE = re.compile(r'^ytdl://(video|phone|best|edit|audio)/([A-Za-z0-9_-]{11})/?$')
URI_CLIP_RE = re.compile(r'^ytdl://clip/([A-Za-z0-9_-]{11})/(\d{1,6})-(\d{1,6})/?$')
URI_OPEN_RE = re.compile(r'^ytdl://(app|settings|history)/?$')


def is_youtube(url):
    return bool(YOUTUBE_RE.match(url or ''))


def resolve_link(u):
    """Unwrap Google/YouTube/Facebook/Reddit redirect links."""
    u = u.strip().strip('"\'<>')
    for _ in range(3):
        m = re.match(r'^https?://(www\.)?(google\.[a-z.]+/url|youtube\.com/redirect|l\.facebook\.com/l\.php|out\.reddit\.com/)[^?]*\?(.*)$', u)
        if not m:
            break
        inner = None
        for k, v in urllib.parse.parse_qsl(m.group(3)):
            if k in ('url', 'q', 'u') and re.match(r'^https?://', v):
                inner = v
                break
        if not inner:
            break
        u = inner
    return u


def get_links(text):
    return [u for u in (resolve_link(t) for t in (text or '').split()) if re.match(r'^https?://\S+$', u)]


def job_safe(job):
    """A job file is only run if it looks exactly like one this app writes."""
    if not isinstance(job, dict):
        return False
    mode = str(job.get('Mode', ''))
    if mode not in MODES:
        return False
    if not re.match(r'^https?://[^\s"<>]+$', str(job.get('Url', ''))):
        return False
    if mode == 'clip':
        try:
            a, b = int(job.get('Start')), int(job.get('End'))
        except (TypeError, ValueError):
            return False
        if a < 0 or b <= a:
            return False
    return True


def add_job(url, mode, start=None, end=None, source='app'):
    P.ensure()
    job = {'Url': url, 'Mode': mode, 'Added': now_iso(), 'Source': source}
    if mode == 'clip':
        job['Start'], job['End'] = int(start), int(end)
    if not job_safe(job):
        raise ValueError('not a valid download: {} {}'.format(mode, url))
    name = '{:%Y%m%d%H%M%S%f}-{}.job'.format(datetime.datetime.now(), random.randint(100000, 999999))
    write_json(os.path.join(P.queue, name), job)
    return name


def list_jobs(folder):
    try:
        names = sorted(n for n in os.listdir(folder) if n.endswith('.job'))
    except OSError:
        return []
    out = []
    for n in names:
        j = read_json(os.path.join(folder, n))
        if isinstance(j, dict):
            j['_file'] = n
            out.append(j)
    return out


def next_job():
    for name in sorted(n for n in os.listdir(P.queue) if n.endswith('.job')):
        src, dest = os.path.join(P.queue, name), os.path.join(P.running, name)
        try:
            os.replace(src, dest)
        except OSError:
            continue
        job = read_json(dest)
        if job_safe(job):
            job['_file'] = name
            return job
        os.remove(dest)
        log(P.error_log, 'discarded an invalid job file: ' + name)
    return None


def requeue(job):
    try:
        os.replace(os.path.join(P.running, job['_file']), os.path.join(P.queue, job['_file']))
    except OSError:
        pass


def finish_job(job):
    try:
        os.remove(os.path.join(P.running, job['_file']))
    except OSError:
        pass
    shutil.rmtree(job_temp(job), ignore_errors=True)     # half-done pieces of this download


def job_temp(job):
    """Each download keeps its half-done pieces in its own folder, so removing a download removes them too."""
    return os.path.join(P.temp, 'job-' + os.path.splitext(job.get('_file') or 'job')[0])


def restore_interrupted():
    for j in list_jobs(P.running):
        requeue(j)


def parse_uri(uri):
    """A ytdl:// link from the button. Returns ('open', what), ('job', mode, url, start, end) or None if refused."""
    uri = (uri or '').strip()
    if len(uri) > 80:
        return None
    m = URI_OPEN_RE.match(uri)
    if m:
        return ('open', m.group(1))
    m = URI_RE.match(uri)
    if m:
        return ('job', m.group(1), 'https://www.youtube.com/watch?v=' + m.group(2), None, None)
    m = URI_CLIP_RE.match(uri)
    if m and int(m.group(3)) > int(m.group(2)):
        return ('job', 'clip', 'https://www.youtube.com/watch?v=' + m.group(1), int(m.group(2)), int(m.group(3)))
    return None


# ============================================================ tools
class Tools:
    ytdlp = None
    ffmpeg = None
    ffprobe = None
    deno = None


TOOLS = Tools()


def find_tool(name):
    own = os.path.join(P.bin, name)
    if os.access(own, os.X_OK):
        return own
    extra = [os.path.join(os.path.expanduser('~'), '.local', 'bin'), os.path.join(os.path.expanduser('~'), '.deno', 'bin')]
    path = os.pathsep.join([os.environ.get('PATH', '')] + extra)
    return shutil.which(name, path=path)


def init_tools():
    TOOLS.ytdlp = find_tool('yt-dlp')
    TOOLS.ffmpeg = find_tool('ffmpeg')
    TOOLS.ffprobe = find_tool('ffprobe')
    TOOLS.deno = find_tool('deno')
    # yt-dlp finds Deno (YouTube's player challenges) and FFmpeg through PATH
    dirs = os.environ.get('PATH', '').split(os.pathsep)
    for t in (TOOLS.deno, TOOLS.ffmpeg):
        if t and os.path.dirname(t) not in dirs:
            dirs.insert(0, os.path.dirname(t))
    os.environ['PATH'] = os.pathsep.join(dirs)


def is_own(tool):
    return bool(tool) and os.path.dirname(tool) == P.bin


def update_tools(force=False):
    """yt-dlp and Deno change with YouTube, so keep them current (only the copies this app installed)."""
    days = int(SETTINGS.get('AutoUpdateDays', 7))
    if not force:
        if days <= 0:
            return
        try:
            if time.time() - os.path.getmtime(P.last_update) < days * 86400:
                return
        except OSError:
            pass
    say('Checking for updates (yt-dlp and Deno)...')
    if is_own(TOOLS.ytdlp):
        run_quiet([TOOLS.ytdlp, '-U'], 300)
    elif TOOLS.ytdlp:
        say('yt-dlp came from somewhere else ({}), so update it the way you installed it.'.format(TOOLS.ytdlp))
    if is_own(TOOLS.deno):
        run_quiet([TOOLS.deno, 'upgrade'], 300)
    with open(P.last_update, 'w', encoding='utf-8') as f:
        f.write(now_iso())


def run_quiet(cmd, timeout):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, check=False)
        for line in (r.stdout + r.stderr).splitlines():
            if line.strip():
                say(line.strip())
        return r.returncode
    except (OSError, subprocess.SubprocessError) as e:
        say('Could not run {}: {}'.format(os.path.basename(cmd[0]), e))
        return -1


# ============================================================ what yt-dlp is asked to do
def name_template(suffix=''):
    base = {
        'title': '%(title)s',
        'channel-title': '%(uploader|Unknown)s - %(title)s',
        'date-title': '%(upload_date>%Y-%m-%d|undated)s - %(title)s',
    }.get(SETTINGS.get('NameStyle'), '%(title)s [%(id)s]')
    return base + suffix + '.%(ext)s'


def video_format(fps):
    # a frame-rate cap has to be a hard filter (sorting alone lets 1080p60 win over 1080p30)
    if fps > 0:
        return 'bv*[fps<={0}]+ba/b[fps<={0}]/bv*+ba/b'.format(fps)
    return 'bv*+ba/b'


def video_sort(height, codec, fps):
    parts = []
    if height > 0:
        parts.append('res:{}'.format(height))
    if fps > 0:
        parts.append('fps:{}'.format(fps))
    parts.append({'av1': 'vcodec:av01', 'vp9': 'vcodec:vp9', 'h264': 'vcodec:h264'}.get(codec, 'vcodec:av01'))
    parts.append('acodec:aac')
    return ','.join(parts)


def folder_for(mode):
    s = SETTINGS
    return s['AudioFolder'] if mode == 'audio' else s['PhoneFolder'] if mode == 'phone' else s['VideoFolder']


def job_args(job, list_file, dir_override=None):
    s = SETTINGS
    mode = job['Mode']
    out_dir = dir_override or folder_for(mode)
    codec, fps, box, height = s['VideoCodec'], int(s['MaxFps']), s['Container'], int(s['MaxHeight'])
    out = name_template()
    a = ['--no-playlist', '--windows-filenames', '--trim-filenames', '150', '--no-mtime',
         '--retries', '30', '--fragment-retries', '30', '--retry-sleep', 'http:exp=1:30', '--retry-sleep', 'fragment:exp=1:30',
         '--socket-timeout', '30', '-N', str(int(s['Fragments'])), '--embed-metadata',
         '-P', out_dir, '-P', 'temp:' + job_temp(job), '--print-to-file', 'after_move:filepath', list_file]
    if float(s['SpeedLimit']) > 0:
        a += ['-r', '{}M'.format(s['SpeedLimit'])]
    if TOOLS.ffmpeg:
        a += ['--ffmpeg-location', os.path.dirname(TOOLS.ffmpeg)]
    if mode == 'video':
        a += ['-f', video_format(fps), '-S', video_sort(height, codec, fps), '--merge-output-format', box]
    elif mode == 'best':
        a += ['-f', video_format(fps), '-S', video_sort(int(s['BestHeight']), codec, fps), '--merge-output-format', box]
    elif mode == 'edit':
        a += ['-f', video_format(fps), '-S', video_sort(int(s['EditHeight']), 'h264', fps), '--merge-output-format', 'mp4']
    elif mode == 'phone':
        # H.264 + AAC in MP4 plays on every iPhone/Android and in every messaging app
        h, pf = int(s['PhoneHeight']), int(s['PhoneMaxFps'])
        cap = '[fps<={}]'.format(pf) if pf > 0 else ''
        a += ['-f', 'bv*[vcodec^=avc1][height<={h}]{c}+ba[ext=m4a]/b[ext=mp4][height<={h}]/bv*[height<={h}]+ba/b[height<={h}]/b'.format(h=h, c=cap),
              '-S', video_sort(h, 'h264', pf), '--merge-output-format', 'mp4']
    elif mode == 'audio':
        fmt = s['AudioFormat']
        # (/b: sites that only offer video with sound in one file still give their audio)
        a += ['-f', 'ba[ext=m4a]/ba/b' if fmt == 'm4a' else 'ba/b', '-x', '--audio-format', fmt]
        if fmt in ('mp3', 'opus', 'm4a'):
            a += ['--audio-quality', '0' if s['AudioQuality'] == 'best' else '{}K'.format(s['AudioQuality'])]
        if s['AudioCover'] and fmt != 'wav':
            a += ['--embed-thumbnail', '--convert-thumbnails', 'jpg']
    elif mode == 'clip':
        a += ['-f', video_format(fps), '-S', video_sort(height, codec, fps), '--merge-output-format', box,
              '--download-sections', '*{}-{}'.format(job['Start'], job['End'])]
        if s['ClipAccurate']:
            a.append('--force-keyframes-at-cuts')
        out = name_template(' (clip {}-{})'.format(format_clock(job['Start']), format_clock(job['End'])))
    elif mode == 'playlist':
        a.remove('--no-playlist')
        a += ['--yes-playlist', '-f', video_format(fps), '-S', video_sort(height, codec, fps), '--merge-output-format', box,
              '--download-archive', P.archive, '--ignore-errors']
        out = ('%(playlist_title|Playlist)s/' if s['PlaylistFolders'] else '') + '%(playlist_index|0)03d - ' + name_template()
    elif mode == 'shrink':
        # downloads into a private temp folder (dir_override); shrink() writes the small copy to Videos
        a += ['-f', 'bv*+ba/b', '-S', video_sort(height, codec, fps), '--merge-output-format', 'mp4']
    if mode != 'audio':
        if s['EmbedChapters']:
            a.append('--embed-chapters')
        if s['EmbedThumbnail'] and mode != 'phone':
            a += ['--embed-thumbnail', '--convert-thumbnails', 'jpg']
        if s['SponsorBlock'] == 'mark':
            a += ['--sponsorblock-mark', 'all']
        elif s['SponsorBlock'] == 'remove':
            a += ['--sponsorblock-remove', 'sponsor,selfpromo,interaction']
        langs = 'all,-live_chat' if s['SubtitleLangs'] == 'all' else 'en.*,-live_chat'
        if s['SubtitleMode'] == 'embed':
            a += ['--embed-subs', '--sub-langs', langs]
        elif s['SubtitleMode'] == 'file':
            a += ['--write-subs', '--sub-langs', langs, '--convert-subs', 'srt']
        if s['SubtitleMode'] != 'off' and s['AutoSubtitles']:
            a.append('--write-auto-subs')
    a += ['-o', out]
    return a


def cookie_args(source):
    if not source:
        return []
    if source == 'file':
        return ['--cookies', P.cookies]
    return ['--cookies-from-browser', source]


def sign_in_source():
    """Where yt-dlp can get your YouTube sign-in from, or None."""
    src = SETTINGS.get('CookieSource', 'firefox')
    if src == 'file':
        if os.path.exists(P.cookies):
            try:
                os.chmod(P.cookies, 0o600)    # it works like a password: readable by you only
            except OSError:
                pass
            return 'file'
        return None
    return src


# ============================================================ failures
def failure_kind(text):
    t = text or ''
    checks = [
        ('age', r'confirm your age|age.restricted|inappropriate for some users'),
        ('members', r"members.only|Join this channel|available to this channel's members"),
        ('blocked', r'not a bot|try again later|HTTP Error 429|Too Many Requests|rate.limit'),
        ('intercepted', r'CERTIFICATE_VERIFY_FAILED|self.signed certificate|certificate verify failed'),
        ('offline', r'getaddrinfo failed|Failed to resolve|Name or service not known|Temporary failure in name resolution|No address associated|timed out|Connection (reset|aborted|refused)|Network is unreachable|No route to host|RemoteDisconnected|Connection broken|IncompleteRead|Read timed out|EOF occurred|SSL:|Unable to connect to proxy|Tunnel connection failed'),
        ('restricted', r'network administrator restrictions|Google Workspace administrator|Restricted Mode'),
        ('gone', r'Private video|Video unavailable|video is unavailable|video is not available|no longer available|has been removed|account associated with this video has been terminated|does not exist|Unsupported URL|is not a valid URL'),
    ]
    for kind, pattern in checks:
        if re.search(pattern, t, re.I):
            return kind
    return 'other'


def failure_hint(kind, used_sign_in):
    if kind == 'gone':
        return 'The video is private, removed, not available, or the link is not a video.'
    if kind == 'age':
        if used_sign_in:
            return "Your YouTube account isn't allowed to watch this one, or your sign-in is out of date (sign in to YouTube again in your browser)."
        return 'It is age-restricted. In Settings > Network, choose the browser you are signed in to YouTube with.'
    if kind == 'members':
        return 'It is members-only: it needs the sign-in of an account that is a member of the channel.'
    if kind == 'restricted':
        return "YouTube Restricted Mode is switched on for this network or account, and it hides this video. The downloader can't change that."
    return 'Try again later. If it keeps failing, click Help > "Check for updates now".'


# ============================================================ status (read by the window)
STATUS = {}
_last_status_write = [0.0]
_status_lock = threading.Lock()


def write_status(force=False, **kw):
    with _status_lock:
        STATUS.update(kw)
        STATUS['updated'] = now_iso()
        STATUS['runnerPid'] = os.getpid()
        if force or time.time() - _last_status_write[0] > 0.4:
            _last_status_write[0] = time.time()
            try:
                write_json(P.status, STATUS)
            except OSError:
                pass


def read_status():
    st = read_json(P.status, {}) or {}
    if st.get('state') not in (None, 'idle') and not process_alive(st.get('runnerPid')):
        st['state'] = 'idle'
    return st


def runner_active():
    return FileLock(P.runner_lock).held_by_other()


def start_runner():
    """Start the background downloader unless it's already running or paused."""
    if os.path.exists(P.paused) or runner_active():
        return
    subprocess.Popen([sys.executable, '-I', os.path.abspath(__file__), '--run-queue'], stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


# ============================================================ running yt-dlp
def run_ytdlp(job, extra, dir_override=None):
    """Runs yt-dlp for a job. Returns (exit code, error text, files, was_stopped)."""
    list_file = os.path.join(P.temp, 'done-{}.txt'.format(random.randint(10 ** 8, 10 ** 9)))
    cmd = [TOOLS.ytdlp] + YT_SAFE_ARGS + [
        '--newline', '--progress-template',
        'download:VDLP|%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s|%(info.title)s',
        '--progress-template', 'postprocess:VDLPP|%(progress.postprocessor)s|%(info.title)s',
    ] + job_args(job, list_file, dir_override) + extra + ['--', job['Url']]
    env = dict(os.environ, PYTHONIOENCODING='utf-8', PYTHONUTF8='1')
    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                                env=env, start_new_session=True, text=True, encoding='utf-8', errors='replace', bufsize=1)
    except OSError as e:
        return 127, 'ERROR: yt-dlp could not be started: {}'.format(e), [], False
    write_status(force=True, childPid=proc.pid)
    errors = []

    def reader():
        for raw in proc.stdout:
            line = raw.rstrip('\n')
            if line.startswith('VDLP|'):
                p = (line.split('|', 4) + ['', '', '', '', ''])[:5]
                try:
                    pct = float(p[1].strip().rstrip('%'))
                except ValueError:
                    pct = STATUS.get('percent', 0)
                write_status(percent=pct, speed=p[2].strip(), eta=p[3].strip(), title=p[4].strip() or STATUS.get('title', ''), phase='downloading')
                if STATE.interactive:
                    print('\r  {:5.1f}%  {:>11}  ETA {:>8}'.format(pct, p[2].strip(), p[3].strip()), end='', flush=True)
                    STATE.progress_line = True
                continue
            if line.startswith('VDLPP|'):
                p = (line.split('|', 2) + ['', '', ''])[:3]
                write_status(phase='finishing', detail=p[1], title=p[2].strip() or STATUS.get('title', ''))
                continue
            say(line)
            if line.startswith('ERROR') or 'WARNING' in line[:10]:
                errors.append(line)

    t = threading.Thread(target=reader, daemon=True)
    t.start()
    stopped = False
    try:
        while proc.poll() is None:
            if os.path.exists(P.paused) or os.path.exists(P.cancel):
                stopped = True
                stop_process(proc)
                break
            time.sleep(0.4)
    except KeyboardInterrupt:
        stop_process(proc)
        raise
    proc.wait()
    t.join(timeout=5)
    files = []
    try:
        with open(list_file, encoding='utf-8') as f:
            files = [ln.strip() for ln in f if ln.strip() and os.path.exists(ln.strip())]
        os.remove(list_file)
    except OSError:
        pass
    write_status(force=True, childPid=0)
    return proc.returncode, '\n'.join(errors), files, stopped


def stop_process(proc):
    try:
        os.killpg(proc.pid, signal.SIGINT)     # yt-dlp stops cleanly and keeps the half-done .part file
        proc.wait(timeout=15)
    except (OSError, subprocess.TimeoutExpired):
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except OSError:
            pass


def codec_of(path, kind):
    if not TOOLS.ffprobe:
        return ''
    try:
        r = subprocess.run([TOOLS.ffprobe, '-v', 'error', '-select_streams', kind + ':0', '-show_entries', 'stream=codec_name',
                            '-of', 'csv=p=0', path], capture_output=True, text=True, timeout=60, check=False)
        return r.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ''


def unique_path(path):
    if not os.path.exists(path):
        return path
    stem, ext = os.path.splitext(path)
    n = 2
    while os.path.exists('{} ({}){}'.format(stem, n, ext)):
        n += 1
    return '{} ({}){}'.format(stem, n, ext)


def convert_for_phone(src):
    """Make sure a phone download really is H.264 + AAC with the index at the front (instant playback)."""
    if not TOOLS.ffmpeg or not TOOLS.ffprobe:
        return src
    write_status(force=True, phase='converting')
    v, au = codec_of(src, 'V'), codec_of(src, 'a')
    vargs = ['-c:v', 'copy']
    if v and v != 'h264':
        h = int(SETTINGS['PhoneHeight'])
        vargs = ['-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23', '-profile:v', 'high', '-pix_fmt', 'yuv420p',
                 '-vf', "scale=-2:'min({},ih)'".format(h)]
    aargs = ['-c:a', 'copy'] if (not au or au == 'aac') else ['-c:a', 'aac', '-b:a', '160k']
    if vargs[1] != 'copy' or aargs[1] != 'copy':
        say('Converting to a phone-friendly format (was {} / {})...'.format(v, au))
    tmp = os.path.join(os.path.dirname(src), 'phone-{}.mp4'.format(random.randint(10 ** 6, 10 ** 7)))
    r = subprocess.run([TOOLS.ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', '-i', src, '-map', '0:V:0', '-map', '0:a:0?',
                        '-map', '0:s?'] + vargs + aargs + ['-c:s', 'mov_text', '-movflags', '+faststart', tmp], capture_output=True, check=False)
    if r.returncode == 0 and os.path.exists(tmp):
        final = os.path.splitext(src)[0] + '.mp4'
        if final != src:
            final = unique_path(final)
        os.replace(tmp, final)
        if final != src:
            os.remove(src)
        return final
    say('Could not make a phone copy - keeping the file as downloaded.')
    try:
        os.remove(tmp)
    except OSError:
        pass
    return src


def keep_original(src):
    """Shrink couldn't run: put the downloaded file in Videos as it is."""
    os.makedirs(SETTINGS['VideoFolder'], exist_ok=True)
    keep = unique_path(os.path.join(SETTINGS['VideoFolder'], os.path.basename(src)))
    shutil.move(src, keep)
    return keep


def shrink(src):
    if not TOOLS.ffmpeg:
        say('FFmpeg is missing, so the video was saved without shrinking it.')
        return keep_original(src)
    crf = {'smaller': (36, 28), 'balanced': (30, 24), 'better': (25, 21)}.get(SETTINGS['ShrinkQuality'], (30, 24))
    enc = ['-c:v', 'libx265', '-crf', str(crf[1]), '-preset', 'medium', '-tag:v', 'hvc1']
    try:
        encoders = subprocess.run([TOOLS.ffmpeg, '-hide_banner', '-encoders'], capture_output=True, text=True, timeout=30, check=False).stdout
        if 'libsvtav1' in encoders:
            enc = ['-c:v', 'libsvtav1', '-preset', '8', '-crf', str(crf[0])]
    except (OSError, subprocess.SubprocessError):
        pass
    os.makedirs(SETTINGS['VideoFolder'], exist_ok=True)
    dest = unique_path(os.path.join(SETTINGS['VideoFolder'], os.path.splitext(os.path.basename(src))[0] + ' (small).mp4'))
    say('Shrinking (this can take a while)...')
    write_status(force=True, phase='shrinking')
    r = subprocess.run([TOOLS.ffmpeg, '-hide_banner', '-loglevel', 'error', '-n', '-i', src] + enc +
                       ['-c:a', 'copy', '-movflags', '+faststart', dest], capture_output=True, check=False)
    if r.returncode == 0 and os.path.exists(dest):
        say('Shrunk {:.0f} MB -> {:.0f} MB'.format(os.path.getsize(src) / 1e6, os.path.getsize(dest) / 1e6))
        os.remove(src)
        return dest
    say('Shrink failed - keeping the original instead.')
    try:
        os.remove(dest)
    except OSError:
        pass
    return keep_original(src)


def add_history(entry):
    entry['time'] = now_iso()
    try:
        with HistoryLock(), open(P.history, 'a', encoding='utf-8') as f:
            f.write(json.dumps(entry) + '\n')
    except OSError:
        pass


def process_job(job):
    """Downloads one job. Returns 'ok', 'fail', 'network', 'blocked', 'paused' or 'cancelled'."""
    mode = job['Mode']
    say('')
    say('=== {} ==='.format(MODE_NAMES.get(mode, mode) + (' {} to {}'.format(format_clock(job['Start']), format_clock(job['End'])) if mode == 'clip' else '')))
    say(job['Url'])
    write_status(force=True, state='downloading', phase='starting', percent=0, speed='', eta='', title='',
                 url=job['Url'], mode=mode, message='', job=job['_file'])
    if not TOOLS.ytdlp:
        add_history({'mode': mode, 'url': job['Url'], 'ok': False, 'title': '',
                     'error': 'yt-dlp is not installed.', 'hint': 'Run the installer again (install.sh) to install it.', 'kind': 'other'})
        finish_job(job)
        return 'fail'
    for d in (folder_for(mode), P.temp):
        os.makedirs(d, exist_ok=True)
    work = tempfile.mkdtemp(prefix='work-', dir=P.temp) if mode == 'shrink' else None
    youtube = is_youtube(job['Url'])
    source = sign_in_source() if (youtube and SETTINGS['UseCookies'] != 'never') else None
    use = source if SETTINGS['UseCookies'] == 'always' else None
    code, err, files, stopped = run_ytdlp(job, cookie_args(use), work)
    updated = False
    while code != 0 and not stopped:
        kind = failure_kind(err)
        if kind in ('offline', 'intercepted', 'blocked'):
            break
        if source and not use and kind in ('age', 'members', 'other'):
            say('Trying again signed in to YouTube...')
            use = source
        elif kind == 'other' and not updated:
            updated = True
            update_tools(force=True)
            init_tools()
        else:
            break
        write_status(force=True, phase='starting', percent=0)
        code, err, files, stopped = run_ytdlp(job, cookie_args(use), work)
    if stopped:
        if os.path.exists(P.cancel):
            try:
                os.remove(P.cancel)
            except OSError:
                pass
            finish_job(job)
            say('Removed.')
            return 'cancelled'
        requeue(job)
        say('Paused.')
        return 'paused'
    title = STATUS.get('title', '')
    if code == 0 or (mode == 'playlist' and files):     # (a playlist with a few unavailable videos still counts)
        if not files:
            say('Already downloaded - nothing new.')
        if mode == 'phone':
            files = [convert_for_phone(f) for f in files]
        elif mode == 'shrink':
            files = [shrink(f) for f in files]
        if work:
            shutil.rmtree(work, ignore_errors=True)
        add_history({'mode': mode, 'url': job['Url'], 'ok': True, 'title': title, 'files': files})
        finish_job(job)
        say('Done: ' + ', '.join(files))
        if SETTINGS['ShowInFolder'] and files:
            show_in_folder(files[0])
        return 'ok'
    if work:
        shutil.rmtree(work, ignore_errors=True)
    kind = failure_kind(err) if code != 0 else 'other'
    if kind in ('offline', 'intercepted', 'blocked'):
        requeue(job)
        return 'blocked' if kind == 'blocked' else 'network'
    add_history({'mode': mode, 'url': job['Url'], 'ok': False, 'title': title, 'error': err.strip()[-1500:] or 'yt-dlp stopped with code {}'.format(code),
                 'hint': failure_hint(kind, bool(use)), 'kind': kind})
    finish_job(job)
    return 'fail'


def clear_old_temp():
    cutoff = time.time() - 3 * 86400
    for n in os.listdir(P.temp):
        p = os.path.join(P.temp, n)
        try:
            if os.path.getmtime(p) < cutoff or n.startswith(('done-', 'update-')):
                if os.path.isdir(p):
                    shutil.rmtree(p, ignore_errors=True)
                else:
                    os.remove(p)
        except OSError:
            pass


def wait_or_stop(seconds):
    """Sleep, but stop early for Pause or Resume. Returns False if paused."""
    end = time.time() + seconds
    while time.time() < end:
        if os.path.exists(P.paused):
            return False
        if os.path.exists(P.retry_now):
            try:
                os.remove(P.retry_now)
            except OSError:
                pass
            return True
        time.sleep(1)
    return True


def run_queue():
    """The background downloader: works through the queue one job at a time."""
    P.ensure()
    lock = FileLock(P.runner_lock)
    if not lock.acquire():
        return 0
    try:
        for flag in (P.cancel, P.retry_now):     # left over from an earlier run
            try:
                os.remove(flag)
            except OSError:
                pass
        if not STATE.interactive:
            try:
                os.remove(P.runner_log)          # the log only describes the latest run (it names what you downloaded)
            except OSError:
                pass
        restore_interrupted()
        clear_old_temp()
        limit_private_data()
        init_tools()
        try:
            update_tools()
        except OSError as e:
            say('Update check failed: {}'.format(e))
        init_tools()
        done = failed = net_fails = 0
        while not os.path.exists(P.paused):
            job = next_job()
            if not job:
                break
            write_status(force=True, queued=len(list_jobs(P.queue)))
            try:
                result = process_job(job)
            except (OSError, ValueError, KeyError, RuntimeError) as e:
                log(P.error_log, 'download failed unexpectedly: {}: {}'.format(type(e).__name__, e))
                add_history({'mode': job.get('Mode', ''), 'url': job.get('Url', ''), 'ok': False, 'title': '',
                             'error': '{}: {}'.format(type(e).__name__, e), 'hint': failure_hint('other', False), 'kind': 'other'})
                finish_job(job)
                result = 'fail'
            if result == 'ok':
                done += 1
                net_fails = 0
            elif result == 'fail':
                failed += 1
                net_fails = 0
            elif result in ('network', 'blocked'):
                net_fails += 1
                minutes = 30 if result == 'blocked' else [1, 2, 5, 10, 15][min(net_fails, 5) - 1]
                msg = ('YouTube is blocking downloads for a while' if result == 'blocked'
                       else 'Waiting for the internet (or a network that isn\'t intercepting secure connections)')
                say('{} - trying again in {} min.'.format(msg, minutes))
                write_status(force=True, state='waiting', message=msg, nextTry=(datetime.datetime.now() + datetime.timedelta(minutes=minutes)).replace(microsecond=0).isoformat())
                if not wait_or_stop(minutes * 60):
                    break
            elif result == 'paused':
                break
        write_status(force=True, state='paused' if os.path.exists(P.paused) else 'idle', message='', percent=0)
        if done or failed:
            notify(APP_NAME, '{} download(s) finished{}'.format(done, ', {} failed'.format(failed) if failed else ''))
    finally:
        lock.release()
    return 0


# ============================================================ terminal mode
def terminal_download(urls, mode):
    STATE.interactive = True
    P.ensure()
    init_tools()
    if not TOOLS.ytdlp:
        print('yt-dlp is not installed. Run install.sh from the Video Downloader download, or install yt-dlp yourself.')
        return 1
    for u in urls:
        add_job(u, mode, source='terminal')
    if runner_active():
        print('Added to the queue: the background downloader is already running (open the window to watch it).')
        return 0
    try:
        os.remove(P.paused)
    except OSError:
        pass
    try:
        return run_queue()
    except KeyboardInterrupt:
        # Ctrl+C works like Pause: nothing is lost, and Resume (or running this again) continues
        open(P.paused, 'w').close()
        restore_interrupted()
        write_status(force=True, state='paused', percent=0)
        print('\nPaused. To continue: video-downloader --resume  (or press Resume in the window)')
        return 130


# ============================================================ GitHub: new versions
def github_json(url):
    req = urllib.request.Request(url, headers={'User-Agent': 'VideoDownloader', 'Accept': 'application/vnd.github+json'})
    with _OPENER.open(req, timeout=20) as r:
        return json.load(r)


def check_app_update():
    info = {'checked': now_iso(), 'latest': '', 'url': RELEASES_PAGE}
    try:
        r = github_json('https://api.github.com/repos/{}/releases/latest'.format(UPDATE_REPO))
        if parse_version(r.get('tag_name')):
            info['latest'] = r['tag_name'].lstrip('vV')
        if re.match(r'^https://github\.com/' + re.escape(UPDATE_REPO) + r'/releases/tag/[A-Za-z0-9._-]+$', str(r.get('html_url', ''))):
            info['url'] = r['html_url']
    except (OSError, ValueError):
        pass
    try:
        write_json(P.app_update, info)
    except OSError:
        pass
    return info


def app_update_available():
    if not SETTINGS.get('CheckAppUpdates', True):
        return None
    info = read_json(P.app_update, {}) or {}
    new, cur = parse_version(info.get('latest')), parse_version(APP_VERSION)
    return info if (new and cur and new > cur) else None


def app_update_due():
    if not SETTINGS.get('CheckAppUpdates', True):
        return False
    try:
        return time.time() - os.path.getmtime(P.app_update) > 86400
    except OSError:
        return True


class _HttpsOnlyRedirects(urllib.request.HTTPRedirectHandler):
    """Follow a redirect only to another https:// address (never a plain-http one that could be tampered with)."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: PLR0917 - urllib's own signature
        if not newurl.lower().startswith('https://'):
            raise urllib.error.HTTPError(newurl, code, 'refused a redirect away from https', headers, fp)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


_OPENER = urllib.request.build_opener(_HttpsOnlyRedirects())


def download(url, dest, progress=None):
    if not url.lower().startswith('https://'):
        raise ValueError('only https:// downloads are allowed: ' + url)
    req = urllib.request.Request(url, headers={'User-Agent': 'VideoDownloader'})
    with _OPENER.open(req, timeout=60) as r, open(dest, 'wb') as f:
        total = int(r.headers.get('Content-Length') or 0)
        got = 0
        while True:
            chunk = r.read(1 << 16)
            if not chunk:
                break
            f.write(chunk)
            got += len(chunk)
            if progress and total:
                progress(got, total)


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def expected_hash(sums_text, name):
    for line in sums_text.splitlines():
        m = re.match(r'^([0-9a-fA-F]{64})\s+\*?(\S+)\s*$', line.strip())
        if m and os.path.basename(m.group(2)) == name:
            return m.group(1).lower()
    return ''


def safe_extract_tar(tar_path, dest):
    """Extract a .tar.* without letting any entry escape the folder (or be a link or device)."""
    root = os.path.realpath(dest)
    with tarfile.open(tar_path) as t:
        members = []
        for m in t.getmembers():
            target = os.path.realpath(os.path.join(dest, m.name))
            if not (target == root or target.startswith(root + os.sep)) or not (m.isfile() or m.isdir()):
                raise ValueError('unsafe entry in archive: ' + m.name)
            members.append(m)
        if hasattr(tarfile, 'data_filter'):
            t.extractall(dest, members=members, filter='data')
        else:
            t.extractall(dest, members=members)  # noqa: S202 - every entry was checked above


def install_app_update():
    """'Update now': download this project's newest Linux release, check its SHA-256, install it."""
    r = github_json('https://api.github.com/repos/{}/releases/latest'.format(UPDATE_REPO))
    new = parse_version(r.get('tag_name'))
    if not new or new <= parse_version(APP_VERSION):
        return 'You already have the newest version ({}).'.format(APP_VERSION)
    prefix = 'https://github.com/{}/releases/download/'.format(UPDATE_REPO)
    assets = {a.get('name'): a.get('browser_download_url', '') for a in r.get('assets', [])}
    tar_name = next((n for n in assets if re.match(r'^VideoDownloader-linux-[0-9.]+\.tar\.gz$', n or '')), None)
    if not tar_name or 'SHA256SUMS.txt' not in assets or not assets[tar_name].startswith(prefix) or not assets['SHA256SUMS.txt'].startswith(prefix):
        raise RuntimeError('This release has no Linux download with a checksum list yet.')
    work = tempfile.mkdtemp(prefix='update-', dir=P.temp)
    try:
        tar_path, sums_path = os.path.join(work, tar_name), os.path.join(work, 'SHA256SUMS.txt')
        download(assets[tar_name], tar_path)
        download(assets['SHA256SUMS.txt'], sums_path)
        with open(sums_path, encoding='utf-8') as f:
            want = expected_hash(f.read(), tar_name)
        if not want or sha256_of(tar_path) != want:
            raise RuntimeError('The download did not match its published checksum, so it was not installed.')
        safe_extract_tar(tar_path, os.path.join(work, 'x'))
        found = None
        for dirpath, _, names in os.walk(os.path.join(work, 'x')):
            if 'video-downloader.py' in names:
                found = os.path.join(dirpath, 'video-downloader.py')
                break
        if not found:
            raise RuntimeError('The download has no video-downloader.py.')
        rc = subprocess.run([sys.executable, '-I', found, '--install', '--quiet'], check=False).returncode
        if rc != 0:
            raise RuntimeError('The installer stopped with code {}.'.format(rc))
        return None
    finally:
        shutil.rmtree(work, ignore_errors=True)


# ============================================================ connection check
def connection_check():
    out = ['Video Downloader {} - connection check, {:%Y-%m-%d %H:%M}'.format(APP_VERSION, datetime.datetime.now()),
           '{} / Python {}'.format(platform.platform(), platform.python_version()), '']

    def cmd(c, timeout=20):
        try:
            r = subprocess.run(c, capture_output=True, text=True, timeout=timeout, check=False)
            return (r.stdout + r.stderr).strip()
        except (OSError, subprocess.SubprocessError) as e:
            return '(could not run {}: {})'.format(c[0], e)

    out.append('== Network')
    gw = ''
    if shutil.which('ip'):
        route = cmd(['ip', 'route', 'show', 'default'])
        out.append(route or '(no default route: not connected?)')
        m = re.search(r'default via (\S+)', route)
        gw = m.group(1) if m else ''
    if shutil.which('nmcli'):
        wifi = cmd(['nmcli', '-t', '-f', 'IN-USE,CHAN,FREQ,RATE,SIGNAL,SECURITY', 'dev', 'wifi', 'list', '--rescan', 'no']).splitlines()
        mine = [ln[2:] for ln in wifi if ln.startswith('*:')]
        chans = [ln.split(':')[1] for ln in wifi if ln.count(':') >= 2]
        out.append('Wi-Fi in use (channel:frequency:rate:signal:security): ' + (', '.join(mine) or 'none'))
        out.append('Nearby access points per channel (names left out): ' +
                   ', '.join('{} on ch {}'.format(chans.count(c), c) for c in sorted(set(chans), key=lambda x: int(x) if x.isdigit() else 0)))
    out.append('')
    out.append('== Name lookups (DNS)')
    for host in ('www.youtube.com', 'redirector.googlevideo.com', 'github.com'):
        try:
            addrs = sorted({a[4][0] for a in socket.getaddrinfo(host, 443, proto=socket.IPPROTO_TCP)})
            out.append('{:<30} {}'.format(host, ', '.join(addrs[:4])))
        except OSError as e:
            out.append('{:<30} FAILED: {}'.format(host, e))
    out.append('')
    out.append('== Secure connections (who answers for the site)')
    for host in ('www.youtube.com', 'redirector.googlevideo.com', 'github.com'):
        try:
            ctx = ssl.create_default_context()
            with socket.create_connection((host, 443), timeout=10) as sock, ctx.wrap_socket(sock, server_hostname=host) as s:
                issuer = dict(x[0] for x in s.getpeercert().get('issuer', ()))
                out.append('{:<30} OK, certificate from {}'.format(host, issuer.get('organizationName', '?')))
        except ssl.SSLCertVerificationError as e:
            out.append('{:<30} INTERCEPTED: {} - something on this network answers with its own certificate'.format(host, e.verify_message))
        except OSError as e:
            out.append('{:<30} FAILED: {}'.format(host, e))
    out.append('')
    if shutil.which('ping'):
        out.append('== Ping')
        for target in [t for t in (gw, '1.1.1.1') if t]:
            res = cmd(['ping', '-c', '10', '-i', '0.3', '-W', '2', target], 30).splitlines()
            out.append('{}: {}'.format(target, ' | '.join(res[-2:])))
        out.append('')
    out.append('== Speed test (25 MB from Cloudflare)')
    try:
        t0 = time.time()
        req = urllib.request.Request('https://speed.cloudflare.com/__down?bytes=25000000', headers={'User-Agent': 'VideoDownloader'})
        n = 0
        with urllib.request.urlopen(req, timeout=60) as r:
            while True:
                chunk = r.read(1 << 16)
                if not chunk:
                    break
                n += len(chunk)
        secs = max(time.time() - t0, 0.001)
        out.append('{:.1f} MB in {:.1f} s = {:.1f} Mbit/s'.format(n / 1e6, secs, n * 8 / secs / 1e6))
    except OSError as e:
        out.append('FAILED: {}'.format(e))
    P.ensure()
    with open(P.report, 'w', encoding='utf-8') as f:
        f.write('\n'.join(out) + '\n')
    return P.report


# ============================================================ install / uninstall
APPS_DIR = os.path.join(_xdg('XDG_DATA_HOME', '.local/share'), 'applications')
LAUNCHER = os.path.join(os.path.expanduser('~'), '.local', 'bin', 'video-downloader')


def _arch():
    m = platform.machine().lower()
    return 'arm64' if m in ('aarch64', 'arm64') else 'x64' if m in ('x86_64', 'amd64') else m


def _fetch_verified(url, dest, sums_url, name, label, *, size_note=''):
    """Download a helper program and check it against the checksum its makers publish."""
    print('    ..  Downloading {}{}'.format(label, size_note), flush=True)

    def bar(got, total):
        print('\r        {:5.1f}%  of {:.0f} MB'.format(got * 100 / total, total / 1e6), end='', flush=True)

    download(url, dest, bar)
    print()
    sums = os.path.join(os.path.dirname(dest), 'sums.txt')
    download(sums_url, sums)
    with open(sums, encoding='utf-8') as f:
        want = expected_hash(f.read(), name)
    os.remove(sums)
    if not want or sha256_of(dest) != want:
        os.remove(dest)
        raise RuntimeError('{} did not match its published checksum, so it was not installed.'.format(label))
    print('    OK  {} (checksum verified)'.format(label))


def install_tools():
    arch = _arch()
    os.makedirs(P.bin, exist_ok=True)
    work = tempfile.mkdtemp(prefix='vd-install-')
    for step in (_install_ytdlp, _install_deno, _install_ffmpeg):
        try:
            step(arch, work)
        except (OSError, RuntimeError, ValueError, zipfile.BadZipFile, tarfile.TarError, KeyError) as e:
            print('\n    !!  {}'.format(e))
            print('        Setup carries on; run it again later (sh install.sh) to retry this part.')
    shutil.rmtree(work, ignore_errors=True)


def _put_tool(src_file, name):
    """Move a checked helper program into place in one step (a half-copied program is never left behind)."""
    dest = os.path.join(P.bin, name)
    os.chmod(src_file, 0o700)
    os.replace(src_file, dest)


def _install_ytdlp(arch, work):
    # its own self-contained build, so it can update itself whatever Python the system has
    if is_own(find_tool('yt-dlp')):
        print('    OK  yt-dlp is already installed')
        return
    name = {'x64': 'yt-dlp_linux', 'arm64': 'yt-dlp_linux_aarch64'}.get(arch)
    if not name:
        print('    !!  No ready-made yt-dlp for this processor ({}); install it with: python3 -m pip install --user yt-dlp'.format(arch))
        return
    base = 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/'
    tmp = os.path.join(work, name)
    _fetch_verified(base + name, tmp, base + 'SHA2-256SUMS', name, 'yt-dlp')
    staged = os.path.join(P.bin, '.yt-dlp.new')
    shutil.move(tmp, staged)
    _put_tool(staged, 'yt-dlp')


def _install_deno(arch, work):
    # YouTube's player challenges need a JavaScript runtime
    if find_tool('deno'):
        print('    OK  Deno is already installed')
        return
    name = {'x64': 'deno-x86_64-unknown-linux-gnu.zip', 'arm64': 'deno-aarch64-unknown-linux-gnu.zip'}.get(arch)
    if not name:
        print('    !!  No ready-made Deno for this processor ({}); see https://deno.com'.format(arch))
        return
    base = 'https://github.com/denoland/deno/releases/latest/download/'
    tmp = os.path.join(work, name)
    _fetch_verified(base + name, tmp, base + name + '.sha256sum', name, 'Deno')
    staged = os.path.join(P.bin, '.deno.new')
    with zipfile.ZipFile(tmp) as z, z.open('deno') as src, open(staged, 'wb') as dst:
        shutil.copyfileobj(src, dst)
    _put_tool(staged, 'deno')


def _install_ffmpeg(arch, work):
    # the system's copy if there is one (it's usually installed); otherwise a static build
    if find_tool('ffmpeg') and find_tool('ffprobe'):
        print('    OK  FFmpeg is already installed')
        return
    name = {'x64': 'ffmpeg-master-latest-linux64-gpl.tar.xz', 'arm64': 'ffmpeg-master-latest-linuxarm64-gpl.tar.xz'}.get(arch)
    if not name:
        print('    !!  Install FFmpeg with your package manager (for example: sudo apt install ffmpeg)')
        return
    base = 'https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/'
    tmp = os.path.join(work, name)
    _fetch_verified(base + name, tmp, base + 'checksums.sha256', name, 'FFmpeg', size_note=' (about 100 MB)')
    with tarfile.open(tmp) as t:
        for member in t.getmembers():
            tool = os.path.basename(member.name)
            if member.isfile() and tool in ('ffmpeg', 'ffprobe') and '/bin/' in member.name:
                staged = os.path.join(P.bin, '.' + tool + '.new')
                with t.extractfile(member) as src, open(staged, 'wb') as dst:
                    shutil.copyfileobj(src, dst)
                _put_tool(staged, tool)


def _desktop_quote(path):
    """A path as one quoted Exec= argument of a .desktop file (the format has two escaping layers)."""
    arg = re.sub(r'(["`$\\])', r'\\\1', path)      # quoting rule: \ before " ` $ and \
    return '"' + arg.replace('\\', '\\\\').replace('%', '%%') + '"'     # then the string rule doubles each \


def _desktop_entry(name, comment, exec_args, extra=''):
    exe = LAUNCHER
    return ('[Desktop Entry]\nType=Application\nName={}\nComment={}\nExec={} {}\nIcon={}\nTerminal=false\n{}'
            .format(name, comment, _desktop_quote(exe), exec_args, os.path.join(P.app_home, 'video-downloader.png'), extra))


def tk_missing_hint():
    for tool, pkg in (('apt-get', 'sudo apt install python3-tk'), ('dnf', 'sudo dnf install python3-tkinter'),
                      ('pacman', 'sudo pacman -S tk'), ('zypper', 'sudo zypper install python3-tk')):
        if shutil.which(tool):
            return pkg
    return 'install the Tk package for Python 3 (often called python3-tk)'


def install(quiet=False):
    src_dir = os.path.dirname(os.path.abspath(__file__))
    print('\n  ==============================================')
    print('        VIDEO DOWNLOADER {}  -  Setup (Linux)'.format(APP_VERSION))
    print('  ==============================================')
    print('  This installs Video Downloader for your account only (no administrator password needed).\n')
    print('  1/4  Helper programs (yt-dlp, Deno, FFmpeg)')
    install_tools()
    print('\n  2/4  Copying Video Downloader')
    os.makedirs(P.app_home, exist_ok=True)
    stop_window()
    for name in ('video-downloader.py', 'VideoDownloader.user.js', 'video-downloader.png', 'README-linux.txt', 'LICENSE'):
        s = os.path.join(src_dir, name)
        if os.path.exists(s) and os.path.abspath(s) != os.path.join(P.app_home, name):
            shutil.copy2(s, os.path.join(P.app_home, name))
    os.chmod(os.path.join(P.app_home, 'video-downloader.py'), 0o700)
    os.makedirs(os.path.dirname(LAUNCHER), exist_ok=True)
    with open(LAUNCHER, 'w', encoding='utf-8') as f:
        f.write('#!/bin/sh\nexec {} -I {} "$@"\n'.format(shlex.quote(sys.executable), shlex.quote(os.path.join(P.app_home, 'video-downloader.py'))))
    os.chmod(LAUNCHER, 0o700)
    print('    OK  Installed to ' + P.app_home)
    print('\n  3/4  Menu entry and the browser button')
    os.makedirs(APPS_DIR, exist_ok=True)
    with open(os.path.join(APPS_DIR, 'video-downloader.desktop'), 'w', encoding='utf-8') as f:
        f.write(_desktop_entry(APP_NAME, 'Download videos and audio', '--app', 'Categories=AudioVideo;Network;\nStartupWMClass=video-downloader\n'))
    with open(os.path.join(APPS_DIR, 'video-downloader-link.desktop'), 'w', encoding='utf-8') as f:
        f.write(_desktop_entry(APP_NAME + ' link', 'Opens ytdl:// links from the YouTube Download button', '--uri %u',
                               'NoDisplay=true\nMimeType=x-scheme-handler/ytdl;\n'))
    if shutil.which('xdg-mime'):
        subprocess.run(['xdg-mime', 'default', 'video-downloader-link.desktop', 'x-scheme-handler/ytdl'], capture_output=True, check=False)
    if shutil.which('update-desktop-database'):
        subprocess.run(['update-desktop-database', APPS_DIR], capture_output=True, check=False)
    print('    OK  "Video Downloader" is in your applications menu, and ytdl:// links open it')
    print('\n  4/4  The Download button for YouTube')
    print('    Install Tampermonkey in your browser, then open this link and click Install:')
    print('    ' + USERSCRIPT_URL)
    P.ensure()
    try:
        import tkinter  # noqa: F401  (only checking that it's there)
    except ImportError:
        print('\n    !!  The window needs Tk, which isn\'t installed. Install it with:  ' + tk_missing_hint())
        print('        (Downloading from the terminal works without it:  video-downloader LINK)')
    if os.environ.get('PATH', '').split(os.pathsep).count(os.path.dirname(LAUNCHER)) == 0:
        print('\n    Note: {} is not on your PATH yet; it usually is after you log out and back in.'.format(os.path.dirname(LAUNCHER)))
    print('\n  All done! Open "Video Downloader" from your applications menu.\n')
    if not quiet:
        if sys.stdout.isatty():
            open_path(README_LINUX_URL)
    else:
        subprocess.Popen([sys.executable, '-I', os.path.join(P.app_home, 'video-downloader.py'), '--app'], stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    return 0


def stop_window():
    """Close a running Video Downloader window (before its files are replaced)."""
    try:
        with open(P.window_lock, encoding='utf-8') as f:
            pid = int(f.read().strip() or 0)
        if pid and pid != os.getpid() and FileLock(P.window_lock).held_by_other():
            os.kill(pid, signal.SIGTERM)
    except (OSError, ValueError):
        pass


def uninstall(delete_data=None):
    print('Removing Video Downloader...')
    stop_window()
    for p in (LAUNCHER, os.path.join(APPS_DIR, 'video-downloader.desktop'), os.path.join(APPS_DIR, 'video-downloader-link.desktop')):
        try:
            os.remove(p)
        except OSError:
            pass
    shutil.rmtree(P.app_home, ignore_errors=True)
    if shutil.which('update-desktop-database'):
        subprocess.run(['update-desktop-database', APPS_DIR], capture_output=True, check=False)
    if delete_data is None and sys.stdin.isatty():
        ans = input('Also delete your settings, download history and waiting downloads? [y/N] ').strip().lower()
        delete_data = ans in ('y', 'yes')
    if delete_data:
        shutil.rmtree(P.data, ignore_errors=True)
    print('Video Downloader was removed. Your downloaded videos are untouched.')
    print('The Download button stays in Tampermonkey until you delete it there.')
    return 0


# ============================================================ the window (Tk)
def run_window(auto_opened=False, open_settings=False):
    try:
        import tkinter as tk
        from tkinter import ttk, messagebox, filedialog
    except ImportError:
        print('The Video Downloader window needs Tk. Install it with:  ' + tk_missing_hint())
        print('You can still download from the terminal:  video-downloader LINK')
        return 1
    P.ensure()
    lock = FileLock(P.window_lock)
    for _ in range(10):               # a window that is just closing (for example during an update) gets 3 seconds
        if lock.acquire():
            break
        time.sleep(0.3)
    else:
        return 0          # already open: it shows new downloads by itself
    init_tools()
    root = tk.Tk(className='video-downloader')
    root.title(APP_NAME)
    root.geometry('860x600')
    root.minsize(700, 480)
    try:
        root.iconphoto(True, tk.PhotoImage(file=os.path.join(P.app_home, 'video-downloader.png')))
    except tk.TclError:
        pass
    style = ttk.Style(root)
    if 'clam' in style.theme_names():
        style.theme_use('clam')
    style.configure('Big.TButton', padding=(14, 6))
    ui = {'touched': False, 'closing_at': None, 'rows': {}, 'kicked': 0.0}
    calls = queue.Queue()     # work finished in the background hands its screen update to the window this way

    def touch(_e=None):
        ui['touched'] = True

    root.bind('<Button-1>', touch, add='+')
    root.bind('<Key>', touch, add='+')

    top = ttk.Frame(root, padding=(12, 10, 12, 4))
    top.pack(fill='x')
    ttk.Label(top, text='Paste a video link (or several):').grid(row=0, column=0, sticky='w')
    upd = ttk.Button(top, text='')      # shown only when a new version is out
    link = ttk.Entry(top)
    link.grid(row=1, column=0, sticky='ew', pady=(4, 0))
    mode_names = [MODE_NAMES[m] for m in MODES if m != 'clip']
    mode_box = ttk.Combobox(top, values=mode_names, state='readonly', width=16)
    mode_box.set(MODE_NAMES.get(SETTINGS['MenuDefault'], 'Video'))
    mode_box.grid(row=1, column=1, padx=8, pady=(4, 0))
    go = ttk.Button(top, text='Download', style='Big.TButton')
    go.grid(row=1, column=2, pady=(4, 0))
    top.columnconfigure(0, weight=1)

    now = ttk.LabelFrame(root, text='Now downloading', padding=10)
    now.pack(fill='x', padx=12, pady=6)
    now_title = ttk.Label(now, text='Nothing right now', font=('TkDefaultFont', 11, 'bold'))
    now_title.grid(row=0, column=0, columnspan=2, sticky='w')
    bar = ttk.Progressbar(now, maximum=100)
    bar.grid(row=1, column=0, sticky='ew', pady=6)
    pause = ttk.Button(now, text='Pause', width=10)
    pause.grid(row=1, column=1, padx=(8, 0))
    now_line = ttk.Label(now, text='')
    now_line.grid(row=2, column=0, columnspan=2, sticky='w')
    now.columnconfigure(0, weight=1)

    mid = ttk.Frame(root, padding=(12, 0))
    mid.pack(fill='both', expand=True)
    cols = ('status', 'title', 'type', 'when')
    tree = ttk.Treeview(mid, columns=cols, show='headings', selectmode='extended')
    for c, label, w in (('status', 'Status', 150), ('title', 'Video', 420), ('type', 'Type', 100), ('when', 'When', 100)):
        tree.heading(c, text=label)
        tree.column(c, width=w, stretch=(c == 'title'))
    tree.tag_configure('fail', foreground='#c01c28')
    tree.tag_configure('ok', foreground='#26734d')
    sb = ttk.Scrollbar(mid, orient='vertical', command=tree.yview)
    tree.configure(yscrollcommand=sb.set)
    tree.pack(side='left', fill='both', expand=True)
    sb.pack(side='left', fill='y')

    bottom = ttk.Frame(root, padding=12)
    bottom.pack(fill='x')
    status_line = ttk.Label(bottom, text='', foreground='#555')
    status_line.pack(side='top', fill='x', pady=(0, 6))
    remove_btn = ttk.Button(bottom, text='Remove')
    clear_btn = ttk.Button(bottom, text='Clear finished')
    folder_btn = ttk.Button(bottom, text='Open videos folder')
    help_btn = ttk.Button(bottom, text='Help')
    settings_btn = ttk.Button(bottom, text='Settings')
    for b in (remove_btn, clear_btn, folder_btn):
        b.pack(side='left', padx=(0, 6))
    for b in (settings_btn, help_btn):
        b.pack(side='right', padx=(6, 0))

    def set_status(text, color='#555'):
        status_line.configure(text=text, foreground=color)

    def history_entries():
        out = []
        try:
            with open(P.history, encoding='utf-8') as f:
                for line in f.readlines()[-300:]:
                    try:
                        e = json.loads(line)
                        if isinstance(e, dict) and not e.get('hidden'):
                            out.append(e)
                    except ValueError:
                        pass
        except OSError:
            pass
        return list(reversed(out))

    def start_downloads(_e=None):
        touch()
        links = get_links(link.get())
        if not links:
            set_status('Paste a link that starts with https:// first.', '#c01c28')
            return
        mode = next(m for m in MODES if MODE_NAMES[m] == mode_box.get())
        for u in links:
            add_job(u, mode)
        link.delete(0, 'end')
        try:
            os.remove(P.paused)
        except OSError:
            pass
        start_runner()
        set_status('Added {} download(s).'.format(len(links)))
        refresh()

    go.configure(command=start_downloads)
    link.bind('<Return>', start_downloads)

    def toggle_pause():
        touch()
        if os.path.exists(P.paused):
            try:
                os.remove(P.paused)
            except OSError:
                pass
            open(P.retry_now, 'w').close()
            start_runner()
            set_status('Resuming...')
        else:
            open(P.paused, 'w').close()
            set_status('Pausing - the half-done download is kept and continues when you press Resume.')
        refresh()

    pause.configure(command=toggle_pause)

    def remove_selected():
        touch()
        sel = tree.selection()
        if not sel:
            set_status('Select a line first.')
            return
        for iid in sel:
            kind, key = iid.split(':', 1)
            if kind == 'queued':
                try:
                    os.remove(os.path.join(P.queue, key))
                except OSError:
                    pass
            elif kind == 'current' and runner_active():
                if messagebox.askyesno(APP_NAME, 'Stop and remove the download that is running now?', parent=root):
                    open(P.cancel, 'w').close()
            elif kind == 'done' and iid in ui['rows']:
                forget_history({history_key(ui['rows'][iid])})
        refresh()

    def forget_history(keys):
        """Removes finished downloads from the list - really deleted from the history file, not just hidden."""
        try:
            with HistoryLock():
                with open(P.history, encoding='utf-8') as f:
                    lines = f.readlines()
                out = []
                for line in lines:
                    try:
                        e = json.loads(line)
                    except ValueError:
                        continue
                    if isinstance(e, dict) and history_key(e) not in keys and not e.get('hidden'):
                        out.append(json.dumps(e) + '\n')
                write_lines(P.history, out)
        except OSError:
            pass
        refresh()

    def clear_finished():
        touch()
        forget_history({history_key(e) for e in history_entries()})
        if not runner_active():
            try:
                os.remove(P.runner_log)     # it names the downloads too
            except OSError:
                pass
        set_status('Finished downloads cleared from the list (your files are untouched).')

    remove_btn.configure(command=remove_selected)
    clear_btn.configure(command=clear_finished)
    folder_btn.configure(command=lambda: (os.makedirs(SETTINGS['VideoFolder'], exist_ok=True), open_path(SETTINGS['VideoFolder'])))

    def on_double(_e):
        touch()
        sel = tree.focus()
        if not sel or not sel.startswith('done:'):
            return
        e = ui['rows'].get(sel)
        if not e:
            return
        if e.get('ok') and e.get('files'):
            f = e['files'][0]
            if os.path.exists(f):
                show_in_folder(f)
            else:
                messagebox.showinfo(APP_NAME, 'That file has been moved or deleted:\n' + f, parent=root)
        elif not e.get('ok'):
            messagebox.showwarning(APP_NAME, '{}\n\n{}\n\nDetails:\n{}'.format(e.get('url', ''), e.get('hint', ''), (e.get('error') or '')[-800:]), parent=root)

    tree.bind('<Double-1>', on_double)

    # ---------- Help menu
    def run_bg(fn, done_msg):
        def work():
            try:
                fn()
                calls.put(lambda: set_status(done_msg))
            except Exception as e:  # noqa: BLE001 - shown to the person instead of crashing the window
                msg = str(e)
                calls.put(lambda: set_status('Failed: ' + msg, '#c01c28'))
        threading.Thread(target=work, daemon=True).start()

    def help_update_tools():
        if runner_active():
            messagebox.showinfo(APP_NAME, 'A download is running. Pause it (or let it finish) first, then check for updates.', parent=root)
            return
        set_status('Checking for updates (yt-dlp and Deno)...')
        run_bg(lambda: (update_tools(force=True), init_tools()), 'yt-dlp and Deno are up to date.')

    def help_connection():
        set_status('Checking your connection (about a minute, includes a 25 MB speed test) - the report opens by itself.')
        run_bg(lambda: open_path(connection_check()), 'Connection report opened (it is also in the data folder).')

    def erase_all():
        touch()
        if runner_active():
            messagebox.showinfo(APP_NAME, 'A download is running. Pause it (or let it finish) first.', parent=root)
            return
        if not messagebox.askyesno(APP_NAME, 'Erase your download history?\n\nThis deletes the list of finished downloads, the logs, '
                                   'connection reports and the list of playlist videos already downloaded.\n\nYour downloaded files, '
                                   'settings and waiting downloads are kept.', parent=root):
            return
        erase_history()
        set_status('Your download history and logs were erased.')
        refresh()

    help_menu = tk.Menu(root, tearoff=False)
    help_menu.add_command(label='Open the guide (README)', command=lambda: open_path(README_LINUX_URL))
    help_menu.add_command(label='Install the YouTube Download button', command=lambda: open_path(USERSCRIPT_URL))
    help_menu.add_command(label='Check for updates now (yt-dlp and Deno)', command=help_update_tools)
    help_menu.add_command(label='Check my connection (makes a report)', command=help_connection)
    help_menu.add_separator()
    help_menu.add_command(label='Erase my download history...', command=erase_all)
    help_menu.add_command(label='Open the data folder (settings, logs)', command=lambda: open_path(P.data))
    help_menu.add_command(label='Project page, new versions, report a problem', command=lambda: open_path(PROJECT_URL))
    help_btn.configure(command=lambda: help_menu.tk_popup(help_btn.winfo_rootx(), help_btn.winfo_rooty() + help_btn.winfo_height()))

    # ---------- settings window
    def open_settings_window():
        win = tk.Toplevel(root)
        win.title('Video Downloader settings')
        win.transient(root)
        nb = ttk.Notebook(win)
        nb.pack(fill='both', expand=True, padx=10, pady=10)
        tabs, vars_ = {}, {}
        for tab, key, label, kind, choices in SETTING_DEFS:
            if tab not in tabs:
                tabs[tab] = ttk.Frame(nb, padding=12)
                nb.add(tabs[tab], text=tab)
            fr = tabs[tab]
            r = fr.grid_size()[1]
            if kind == 'bool':
                v = tk.BooleanVar(value=bool(SETTINGS[key]))
                ttk.Checkbutton(fr, text=label, variable=v).grid(row=r, column=0, columnspan=3, sticky='w', pady=3)
            elif kind == 'choice':
                names = [n for _, n in choices]
                current = next((n for val, n in choices if val == SETTINGS[key]), names[0])
                v = tk.StringVar(value=current)
                ttk.Label(fr, text=label).grid(row=r, column=0, sticky='w', pady=3, padx=(0, 10))
                ttk.Combobox(fr, values=names, textvariable=v, state='readonly', width=42).grid(row=r, column=1, sticky='w')
            else:
                v = tk.StringVar(value=SETTINGS[key])
                ttk.Label(fr, text=label).grid(row=r, column=0, sticky='w', pady=3, padx=(0, 10))
                ttk.Entry(fr, textvariable=v, width=44).grid(row=r, column=1, sticky='w')

                def pick(var=v):
                    d = filedialog.askdirectory(parent=win, initialdir=var.get() or os.path.expanduser('~'))
                    if d:
                        var.set(d)
                ttk.Button(fr, text='Change...', command=pick).grid(row=r, column=2, padx=6)
            vars_[key] = (v, kind, choices)

        def save():
            for key, (v, kind, _choices) in vars_.items():
                if kind == 'folder' and v.get().strip() and not clean_folder(v.get()):
                    messagebox.showwarning(APP_NAME, 'Folders need a full path, for example {}'.format(default_settings()[key]), parent=win)
                    return
            for key, (v, kind, choices) in vars_.items():
                if kind == 'bool':
                    SETTINGS[key] = bool(v.get())
                elif kind == 'choice':
                    SETTINGS[key] = next(val for val, n in choices if n == v.get())
                else:
                    SETTINGS[key] = clean_folder(v.get()) or default_settings()[key]
            save_settings(SETTINGS)
            win.destroy()
            set_status('Settings saved - they apply to the next download.')

        def reset():
            if messagebox.askyesno(APP_NAME, 'Put every setting back to its default?', parent=win):
                SETTINGS.clear()
                SETTINGS.update(default_settings())
                save_settings(SETTINGS)
                win.destroy()
                open_settings_window()

        btns = ttk.Frame(win, padding=(10, 0, 10, 10))
        btns.pack(fill='x')
        ttk.Button(btns, text='Reset to defaults', command=reset).pack(side='left')
        ttk.Button(btns, text='Cancel', command=win.destroy).pack(side='right')
        ttk.Button(btns, text='Save', command=save).pack(side='right', padx=6)

    settings_btn.configure(command=open_settings_window)

    # ---------- app updates
    def update_link():
        info = app_update_available()
        if info:
            upd.configure(text='Version {} is out - update'.format(info['latest']), state='normal')
            upd.grid(row=0, column=1, columnspan=2, sticky='e')
        else:
            upd.grid_remove()

    def on_update_click():
        info = app_update_available()
        if not info:
            return
        a = messagebox.askyesnocancel(APP_NAME, 'Version {} is out.\n\nYes = update now (this window closes and reopens by itself; your downloads and settings are kept)\nNo = just show me what\'s new'.format(info['latest']), parent=root)
        if a is None:
            return
        if not a:
            open_path(info.get('url') or RELEASES_PAGE)
            return
        upd.configure(text='Updating...', state='disabled')

        def work():
            try:
                msg = install_app_update()
            except Exception as e:  # noqa: BLE001 - shown to the person
                msg = "Video Downloader couldn't update itself:\n\n{}\n\nThe download page will open so you can update by hand.".format(e)
                calls.put(lambda: (messagebox.showwarning(APP_NAME, msg, parent=root), open_path(RELEASES_PAGE), update_link()))
                return
            if msg:
                calls.put(lambda: (messagebox.showinfo(APP_NAME, msg, parent=root), update_link()))
            else:
                ui['close'] = True     # the installer opens the new version
        threading.Thread(target=work, daemon=True).start()

    upd.configure(command=on_update_click)
    if app_update_due():
        threading.Thread(target=lambda: (check_app_update(), calls.put(update_link)), daemon=True).start()
    update_link()

    # ---------- clipboard: offer a copied link
    def offer_clipboard(_e=None):
        if link.get().strip():
            return
        try:
            clip = root.clipboard_get()
        except tk.TclError:
            return
        found = get_links(clip)
        if found and len(clip) < 4000:
            link.insert(0, ' '.join(found))
    root.bind('<FocusIn>', offer_clipboard, add='+')

    # ---------- refresh every 0.7 s
    def refresh():
        st = read_status()
        active = runner_active()
        paused = os.path.exists(P.paused)
        queued = list_jobs(P.queue)
        running = list_jobs(P.running)
        rows = []
        if active and running:
            j = running[0]
            rows.append(('current:' + j['_file'], ('Downloading', st.get('title') or j['Url'], MODE_NAMES.get(j['Mode'], j['Mode']), 'now'), ()))
        for j in queued:
            rows.append(('queued:' + j['_file'], ('Paused' if paused else 'Waiting', j['Url'], MODE_NAMES.get(j['Mode'], j['Mode']), j.get('Added', '')[11:16]), ()))
        ui['rows'] = {}
        for e in history_entries():
            iid = 'done:' + history_key(e)
            if iid in ui['rows']:
                continue
            ui['rows'][iid] = e
            rows.append((iid, ('Done' if e.get('ok') else 'Failed (double-click)', e.get('title') or e.get('url', ''),
                               MODE_NAMES.get(e.get('mode'), e.get('mode', '')), e.get('time', '')[5:16].replace('T', ' ')),
                         ('ok' if e.get('ok') else 'fail',)))
        # update in place, so the selection and scroll position survive the refresh
        if list(tree.get_children()) == [r[0] for r in rows]:
            for iid, values, tags in rows:
                tree.item(iid, values=values, tags=tags)
        else:
            keep = [i for i in tree.selection() if i in {r[0] for r in rows}]
            tree.delete(*tree.get_children())
            for iid, values, tags in rows:
                tree.insert('', 'end', iid=iid, values=values, tags=tags)
            if keep:
                tree.selection_set(keep)
        if active and st.get('state') == 'downloading':
            now_title.configure(text=st.get('title') or 'Starting...')
            bar.configure(value=float(st.get('percent') or 0))
            phase = st.get('phase', '')
            line = {'starting': 'Starting...', 'converting': 'Making it phone-friendly...', 'shrinking': 'Shrinking (this can take a while)...',
                    'finishing': 'Finishing ({})...'.format(st.get('detail', ''))}.get(phase)
            now_line.configure(text=line or '{}   {}   {} left   ({} waiting)'.format(
                '{:.1f}%'.format(float(st.get('percent') or 0)), st.get('speed', ''), st.get('eta', ''), len(queued)))
        elif active and st.get('state') == 'waiting':
            now_title.configure(text=st.get('message', 'Waiting'))
            bar.configure(value=0)
            nt = st.get('nextTry', '')
            now_line.configure(text='Trying again at {} - or press Resume to try now.'.format(nt[11:16]) if nt else '')
        elif paused:
            now_title.configure(text='Paused')
            bar.configure(value=0)
            now_line.configure(text='{} download(s) waiting. Press Resume to continue.'.format(len(queued)))
        else:
            now_title.configure(text='Nothing right now')
            bar.configure(value=0)
            now_line.configure(text='Paste a link above, or click Download under a YouTube video.')
        pause.configure(text='Resume' if (paused or (active and st.get('state') == 'waiting')) else 'Pause',
                        state='normal' if (active or paused or queued) else 'disabled')
        if queued and not active and not paused and time.time() - ui['kicked'] > 10:
            ui['kicked'] = time.time()      # (at most every 10 s, so a downloader that can't start isn't restarted non-stop)
            start_runner()
        # auto-close after downloads that came from the browser, once all went well
        if auto_opened and SETTINGS['CloseWhenDone'] and not ui['touched']:
            recent = [e for e in history_entries() if e.get('time', '') >= ui.get('opened', '')]
            if not active and not queued and recent and all(e.get('ok') for e in recent):
                if ui['closing_at'] is None:
                    ui['closing_at'] = time.time() + 6
                left = int(ui['closing_at'] - time.time())
                set_status('All done - closing in {} s (click anywhere in this window to keep it open)'.format(max(left, 0)))
                if left <= 0:
                    ui['close'] = True
        elif ui['closing_at'] is not None:
            ui['closing_at'] = None
            set_status('Staying open.')

    def tick():
        while not calls.empty():
            try:
                calls.get_nowait()()
            except (queue.Empty, tk.TclError):
                break
        try:
            refresh()
        except (OSError, ValueError, tk.TclError) as e:
            log(P.error_log, 'window refresh: {}'.format(e))
        if ui.get('close'):
            root.destroy()
            return
        root.after(700, tick)

    ui['opened'] = now_iso()
    if open_settings:
        root.after(200, open_settings_window)
    tick()
    root.protocol('WM_DELETE_WINDOW', root.destroy)
    signal.signal(signal.SIGTERM, lambda *_: ui.update(close=True))
    if os.environ.get('VIDEODOWNLOADER_SELFTEST'):
        root.after(int(os.environ['VIDEODOWNLOADER_SELFTEST']), root.destroy)
    root.mainloop()
    lock.release()
    return 0


def open_window_detached(*extra):
    subprocess.Popen([sys.executable, '-I', os.path.abspath(__file__), '--app'] + list(extra), stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


# ============================================================ start
def handle_uri(uri):
    parsed = parse_uri(uri)
    if not parsed:
        P.ensure()
        log(P.error_log, 'refused a malformed ytdl:// link')
        return 1
    if parsed[0] == 'open':
        if parsed[1] == 'settings':
            open_window_detached('--settings')
        else:
            open_window_detached()
        return 0
    _, mode, url, start, end = parsed
    add_job(url, mode, start, end, source='button')
    try:
        os.remove(P.paused)
    except OSError:
        pass
    start_runner()
    if SETTINGS.get('OpenAppOnDownload', True):
        open_window_detached('--auto-opened')
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(prog='video-downloader', description='Download videos and audio with yt-dlp.', allow_abbrev=False)
    ap.add_argument('urls', nargs='*', help='links to download in this terminal')
    ap.add_argument('--type', default='video', choices=[m for m in MODES if m != 'clip'], help='download type for links given here')
    ap.add_argument('--uri', help='a ytdl:// link from the YouTube Download button')
    ap.add_argument('--app', action='store_true', help='open the window (the default)')
    ap.add_argument('--auto-opened', action='store_true', help=argparse.SUPPRESS)
    ap.add_argument('--settings', action='store_true', help='open the settings window')
    ap.add_argument('--run-queue', action='store_true', help=argparse.SUPPRESS)
    ap.add_argument('--resume', action='store_true', help='continue paused or waiting downloads in this terminal')
    ap.add_argument('--update-now', action='store_true', help='update yt-dlp and Deno now')
    ap.add_argument('--connection-check', action='store_true', help='check the connection and open the report')
    ap.add_argument('--install', action='store_true', help='install from an extracted release folder')
    ap.add_argument('--quiet', action='store_true', help=argparse.SUPPRESS)
    ap.add_argument('--uninstall', action='store_true', help='remove Video Downloader')
    ap.add_argument('--delete-data', action='store_true', help='with --uninstall: also delete settings and history')
    ap.add_argument('--version', action='version', version=APP_NAME + ' ' + APP_VERSION)
    raw = list(sys.argv[1:] if argv is None else argv)
    # a ytdl:// link comes from a web page: it may carry nothing but the link itself
    is_link = any(x == '--uri' or x.startswith('--uri=') for x in raw)
    if is_link and not ((len(raw) == 2 and raw[0] == '--uri') or (len(raw) == 1 and raw[0].startswith('--uri='))):
        P.ensure()
        log(P.error_log, 'refused a ytdl:// link with extra options')
        return 1
    a = ap.parse_args(raw)
    SETTINGS.clear()
    SETTINGS.update(load_settings())
    if a.install:
        return install(quiet=a.quiet)
    if a.uninstall:
        return uninstall(True if a.delete_data else None)
    if a.uri is not None:
        return handle_uri(a.uri)
    if a.run_queue:
        return run_queue()
    if a.update_now:
        STATE.interactive = True
        P.ensure()
        init_tools()
        update_tools(force=True)
        return 0
    if a.connection_check:
        print('Checking your connection (about a minute)...')
        path = connection_check()
        print(open(path, encoding='utf-8').read())
        open_path(path)
        return 0
    if a.resume:
        return terminal_download([], 'video')
    if a.urls:
        links = [u for u in (resolve_link(x) for x in a.urls) if re.match(r'^https?://\S+$', u)]
        if not links:
            print('Those are not links. Give links that start with https://')
            return 2
        return terminal_download(links, a.type)
    return run_window(auto_opened=a.auto_opened, open_settings=a.settings)


if __name__ == '__main__':
    sys.exit(main())
