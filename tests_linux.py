#!/usr/bin/env python3
"""Checks for the Linux app (video-downloader.py). Run:  python3 tests_linux.py

Nothing is downloaded: a stand-in yt-dlp writes small files instead, and everything happens in a temporary home folder.
The window test needs a display (CI runs it under xvfb-run); it is skipped without one.
"""

import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import textwrap
import time
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.join(HERE, 'video-downloader.py')

spec = importlib.util.spec_from_file_location('vd', APP)
vd = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vd)

# A stand-in for yt-dlp: understands the options this app uses and writes a small file (or a real 1-second video).
FAKE_YTDLP = textwrap.dedent(r'''
    #!/usr/bin/env python3
    import os, shutil, subprocess, sys, time
    a = sys.argv[1:]
    if a == ['-U']:
        print('yt-dlp is up to date (fake)'); sys.exit(0)
    with open(os.environ['FAKE_LOG'], 'a') as f:
        f.write(' '.join(a) + '\n')
    url = a[-1]
    assert a[-2] == '--', 'the link must come after --'
    assert '--ignore-config' in a and '--no-plugin-dirs' in a
    out_dir = next(v.split(':', 1)[1] if v.startswith('home:') else v for k, v in zip(a, a[1:]) if k == '-P' and not v.startswith('temp:'))
    listing = a[a.index('--print-to-file') + 2]
    temp_dir = next(v[5:] for k, v in zip(a, a[1:]) if k == '-P' and v.startswith('temp:'))
    os.makedirs(temp_dir, exist_ok=True)
    with open(os.path.join(temp_dir, 'Fake title [abc].mp4.part'), 'w') as f:
        f.write('half')
    signed_in = '--cookies-from-browser' in a or '--cookies' in a
    if 'private' in url:
        print('ERROR: [youtube] abc: Private video. Sign in if you have been granted access'); sys.exit(1)
    if 'offline' in url:
        print('ERROR: Unable to download: <urlopen error [Errno -3] Temporary failure in name resolution>'); sys.exit(1)
    if 'agegate' in url and not signed_in:
        print('ERROR: [youtube] abc: Sign in to confirm your age. This video may be inappropriate for some users.'); sys.exit(1)
    steps = 40 if 'slow' in url else 3
    for i in range(1, steps + 1):
        print('VDLP|{:5.1f}%|  1.00MiB/s|00:0{}|Fake title'.format(i * 100 / steps, 1), flush=True)
        time.sleep(0.25 if 'slow' in url else 0.01)
    if '-x' in a:
        ext = a[a.index('--audio-format') + 1]
    else:
        ext = 'webm' if os.environ.get('FAKE_REAL_MEDIA') else 'mp4'
    name = 'Fake title [abc]'
    if '--download-sections' in a:
        name = 'Fake title [abc] (clip 0m10s-0m20s)'
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, name + '.' + ext)
    if os.environ.get('FAKE_REAL_MEDIA') and shutil.which('ffmpeg') and '-x' not in a:
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc=size=320x240:rate=25:duration=1',
                        '-f', 'lavfi', '-i', 'sine=duration=1', '-c:v', 'libvpx-vp9', '-c:a', 'libopus', '-shortest', path], check=True)
    else:
        with open(path, 'wb') as f:
            f.write(b'fake media ' + url.encode())
    print('VDLPP|Merger|Fake title', flush=True)
    with open(listing, 'a') as f:
        f.write(path + '\n')
''').lstrip()


def make_env(home):
    env = dict(os.environ)
    env.update({
        'HOME': home, 'XDG_DATA_HOME': os.path.join(home, '.local', 'share'),
        'VIDEODOWNLOADER_DATA': os.path.join(home, 'data'), 'VIDEODOWNLOADER_HOME': os.path.join(home, 'app'),
        'FAKE_LOG': os.path.join(home, 'ytdlp-calls.txt'), 'PATH': '/usr/local/bin:/usr/bin:/bin',
    })
    env.pop('FAKE_REAL_MEDIA', None)
    return env


class TempHome(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp(prefix='vd-test-')
        self.env = make_env(self.home)
        self.bin = os.path.join(self.home, 'app', 'bin')
        os.makedirs(self.bin)
        fake = os.path.join(self.bin, 'yt-dlp')
        with open(fake, 'w') as f:
            f.write(FAKE_YTDLP)
        os.chmod(fake, 0o700)
        self.data = self.env['VIDEODOWNLOADER_DATA']
        os.makedirs(self.data)
        with open(os.path.join(self.data, 'settings.json'), 'w') as f:
            json.dump({'VideoFolder': os.path.join(self.home, 'Videos'), 'AudioFolder': os.path.join(self.home, 'Audio'),
                       'PhoneFolder': os.path.join(self.home, 'Phone'), 'AutoUpdateDays': 0, 'Notify': False,
                       'CheckAppUpdates': False}, f)

    def tearDown(self):
        shutil.rmtree(self.home, ignore_errors=True)

    def run_app(self, *args, timeout=60, env=None):
        return subprocess.run([sys.executable, APP] + list(args), env=env or self.env, capture_output=True, text=True,
                              timeout=timeout, check=False, stdin=subprocess.DEVNULL)

    def history(self):
        try:
            with open(os.path.join(self.data, 'history.jsonl')) as f:
                return [json.loads(x) for x in f if x.strip()]
        except OSError:
            return []

    def calls(self):
        try:
            with open(self.env['FAKE_LOG']) as f:
                return f.read().splitlines()
        except OSError:
            return []


class Links(unittest.TestCase):
    def test_button_links(self):
        self.assertEqual(vd.parse_uri('ytdl://video/dQw4w9WgXcQ'), ('job', 'video', 'https://www.youtube.com/watch?v=dQw4w9WgXcQ', None, None))
        self.assertEqual(vd.parse_uri('ytdl://audio/dQw4w9WgXcQ/'), ('job', 'audio', 'https://www.youtube.com/watch?v=dQw4w9WgXcQ', None, None))
        self.assertEqual(vd.parse_uri('ytdl://clip/dQw4w9WgXcQ/10-20'), ('job', 'clip', 'https://www.youtube.com/watch?v=dQw4w9WgXcQ', 10, 20))
        self.assertEqual(vd.parse_uri('ytdl://settings'), ('open', 'settings'))

    def test_refused_links(self):
        for bad in ('ytdl://clip/dQw4w9WgXcQ/20-10', 'ytdl://video/short', 'ytdl://video/dQw4w9WgXcQ?x=--exec',
                    'ytdl://video/dQw4w9WgXcQ --exec x', 'ytdl://shrink/dQw4w9WgXcQ', 'ytdl://video/' + 'a' * 100,
                    'https://www.youtube.com/watch?v=dQw4w9WgXcQ', 'ytdl://video/dQw4w9WgXc"', ''):
            self.assertIsNone(vd.parse_uri(bad), bad)

    def test_job_check(self):
        self.assertTrue(vd.job_safe({'Mode': 'video', 'Url': 'https://youtu.be/x'}))
        self.assertTrue(vd.job_safe({'Mode': 'clip', 'Url': 'https://youtu.be/x', 'Start': 1, 'End': 5}))
        for bad in ({'Mode': 'exec', 'Url': 'https://youtu.be/x'}, {'Mode': 'video', 'Url': '--exec=rm'},
                    {'Mode': 'video', 'Url': 'file:///etc/passwd'}, {'Mode': 'video', 'Url': 'https://a b'},
                    {'Mode': 'clip', 'Url': 'https://youtu.be/x', 'Start': 5, 'End': 5}, [], None):
            self.assertFalse(vd.job_safe(bad), bad)

    def test_unwrap(self):
        self.assertEqual(vd.resolve_link('https://www.google.com/url?q=https%3A%2F%2Fyoutu.be%2Fabc&sa=D'), 'https://youtu.be/abc')
        self.assertEqual(vd.resolve_link('https://www.youtube.com/redirect?event=x&q=https%3A%2F%2Fexample.com%2Fv'), 'https://example.com/v')
        self.assertEqual(vd.get_links('see <https://youtu.be/a> and https://youtu.be/b, ftp://x'), ['https://youtu.be/a', 'https://youtu.be/b,'])
        self.assertTrue(vd.is_youtube('https://music.youtube.com/watch?v=x'))
        self.assertFalse(vd.is_youtube('https://youtube.com.evil.example/watch'))

    def test_clock_and_versions(self):
        self.assertEqual(vd.parse_clock('1:02:03'), 3723)
        self.assertEqual(vd.parse_clock('90'), 90)
        self.assertIsNone(vd.parse_clock('1:2x'))
        self.assertEqual(vd.format_clock(75), '1m15s')
        self.assertEqual(vd.format_clock(3725), '1h02m05s')
        self.assertGreater(vd.parse_version('v4.10'), vd.parse_version('4.9'))
        self.assertIsNone(vd.parse_version('4.6-beta'))


class Arguments(unittest.TestCase):
    def setUp(self):
        vd.SETTINGS.clear()
        vd.SETTINGS.update(vd.default_settings())
        vd.TOOLS.ffmpeg = None

    def args(self, mode, **extra):
        job = {'Mode': mode, 'Url': 'https://youtu.be/abc', 'Start': 10, 'End': 20}
        vd.SETTINGS.update(extra)
        return vd.job_args(job, '/tmp/list.txt')

    def test_video(self):
        a = self.args('video')
        self.assertIn('--no-playlist', a)
        self.assertEqual(a[a.index('-f') + 1], 'bv*+ba/b')
        self.assertEqual(a[a.index('-S') + 1], 'res:1080,vcodec:av01,acodec:aac')
        self.assertEqual(a[-1], '%(title)s [%(id)s].%(ext)s')

    def test_fps_cap_is_a_filter(self):
        a = self.args('video', MaxFps=30)
        self.assertEqual(a[a.index('-f') + 1], 'bv*[fps<=30]+ba/b[fps<=30]/bv*+ba/b')
        self.assertIn('fps:30', a[a.index('-S') + 1])

    def test_phone(self):
        a = self.args('phone')
        self.assertTrue(a[a.index('-f') + 1].startswith('bv*[vcodec^=avc1][height<=720]+ba[ext=m4a]'))
        self.assertEqual(a[a.index('--merge-output-format') + 1], 'mp4')

    def test_audio(self):
        a = self.args('audio', AudioFormat='mp3', AudioQuality='192')
        self.assertEqual(a[a.index('--audio-format') + 1], 'mp3')
        self.assertEqual(a[a.index('--audio-quality') + 1], '192K')
        self.assertIn('--embed-thumbnail', a)
        self.assertNotIn('--embed-chapters', a)

    def test_clip(self):
        a = self.args('clip')
        self.assertEqual(a[a.index('--download-sections') + 1], '*10-20')
        self.assertIn('--force-keyframes-at-cuts', a)
        self.assertEqual(a[-1], '%(title)s [%(id)s] (clip 0m10s-0m20s).%(ext)s')

    def test_playlist(self):
        a = self.args('playlist')
        self.assertNotIn('--no-playlist', a)
        self.assertIn('--yes-playlist', a)
        self.assertTrue(a[-1].startswith('%(playlist_title|Playlist)s/%(playlist_index|0)03d - '))

    def test_extras(self):
        a = self.args('video', SponsorBlock='remove', SubtitleMode='file', SubtitleLangs='all', AutoSubtitles=True, NameStyle='date-title', SpeedLimit=5)
        self.assertEqual(a[a.index('--sponsorblock-remove') + 1], 'sponsor,selfpromo,interaction')
        self.assertEqual(a[a.index('--sub-langs') + 1], 'all,-live_chat')
        self.assertIn('--write-auto-subs', a)
        self.assertEqual(a[a.index('-r') + 1], '5M')
        self.assertEqual(a[-1], '%(upload_date>%Y-%m-%d|undated)s - %(title)s.%(ext)s')

    def test_names_work_on_any_drive_and_each_download_has_its_own_temp_folder(self):
        a = vd.job_args({'Mode': 'video', 'Url': 'https://youtu.be/abc', '_file': '20260101-5.job'}, '/tmp/l')
        self.assertIn('--windows-filenames', a)
        self.assertEqual(a[a.index('-P', a.index('-P') + 1) + 1], 'temp:' + os.path.join(vd.P.temp, 'job-20260101-5'))

    def test_audio_works_on_sites_without_separate_audio(self):
        a = self.args('audio')
        self.assertEqual(a[a.index('-f') + 1], 'ba[ext=m4a]/ba/b')
        a = self.args('audio', AudioFormat='mp3')
        self.assertEqual(a[a.index('-f') + 1], 'ba/b')

    def test_every_setting_choice_is_valid(self):
        defaults = vd.default_settings()
        for _tab, key, _label, kind, choices in vd.SETTING_DEFS:
            self.assertIn(key, defaults)
            if kind == 'choice':
                self.assertIn(defaults[key], [c[0] for c in choices], key)


class Failures(unittest.TestCase):
    def test_kinds(self):
        self.assertEqual(vd.failure_kind('Sign in to confirm your age'), 'age')
        self.assertEqual(vd.failure_kind("Sign in to confirm you're not a bot"), 'blocked')
        self.assertEqual(vd.failure_kind('HTTP Error 429: Too Many Requests'), 'blocked')
        self.assertEqual(vd.failure_kind('[SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed'), 'intercepted')
        self.assertEqual(vd.failure_kind('Temporary failure in name resolution'), 'offline')
        self.assertEqual(vd.failure_kind('Private video'), 'gone')
        self.assertEqual(vd.failure_kind('Join this channel to get access to members-only content'), 'members')
        self.assertEqual(vd.failure_kind('something new'), 'other')


class SafeSettings(unittest.TestCase):
    def test_folders_must_be_full_paths(self):
        self.assertEqual(vd.clean_folder('/home/me/Videos/'), '/home/me/Videos')
        self.assertEqual(vd.clean_folder('~/Videos'), os.path.join(os.path.expanduser('~'), 'Videos'))
        for bad in ('Videos', '../x', '', '/a\nb', None, 5, ['x']):
            self.assertIsNone(vd.clean_folder(bad), bad)

    def test_hand_edited_settings_are_ignored(self):
        d = tempfile.mkdtemp()
        old = vd.P.settings
        try:
            vd.P.settings = os.path.join(d, 'settings.json')
            with open(vd.P.settings, 'w') as f:
                json.dump({'AudioFormat': 'mp3 --exec x', 'VideoFolder': 'relative', 'MaxHeight': 720, 'Notify': 0, 'Unknown': 1}, f)
            s = vd.load_settings()
            self.assertEqual(s['AudioFormat'], 'm4a')
            self.assertEqual(s['VideoFolder'], vd.default_settings()['VideoFolder'])
            self.assertEqual(s['MaxHeight'], 720)
            self.assertIs(s['Notify'], False)
            self.assertNotIn('Unknown', s)
            with open(vd.P.settings, 'w') as f:
                f.write('[1, 2]')
            self.assertEqual(vd.load_settings()['AudioFormat'], 'm4a')
        finally:
            vd.P.settings = old
            shutil.rmtree(d)

    def test_desktop_entries_quote_odd_folder_names(self):
        self.assertEqual(vd._desktop_quote('/home/a b/x'), '"/home/a b/x"')
        self.assertEqual(vd._desktop_quote('/h/$x"y%u'), '"/h/\\\\$x\\\\"y%%u"')

    def test_only_https_downloads(self):
        with self.assertRaises(ValueError):
            vd.download('http://github.com/x', os.devnull)


class SpotsTampermonkey(unittest.TestCase):
    def test_finds_it_only_in_the_default_browser(self):
        home = tempfile.mkdtemp()
        old = dict(os.environ)
        try:
            os.environ['HOME'] = home
            os.environ.pop('XDG_CONFIG_HOME', None)
            self.assertFalse(vd.has_tampermonkey('google-chrome.desktop'))
            os.makedirs(os.path.join(home, '.config', 'google-chrome', 'Profile 1', 'Extensions', 'dhdgffkkebhmkfjojejmpbldmpobfkfo'))
            self.assertTrue(vd.has_tampermonkey('google-chrome.desktop'))
            self.assertFalse(vd.has_tampermonkey('brave-browser.desktop'))
            self.assertFalse(vd.has_tampermonkey('firefox_firefox.desktop'))
            ext = os.path.join(home, 'snap', 'firefox', 'common', '.mozilla', 'firefox', 'x1.default', 'extensions')
            os.makedirs(ext)
            open(os.path.join(ext, 'firefox@tampermonkey.net.xpi'), 'w').close()
            self.assertTrue(vd.has_tampermonkey('firefox_firefox.desktop'))
            self.assertFalse(vd.has_tampermonkey(''))
        finally:
            os.environ.clear()
            os.environ.update(old)
            shutil.rmtree(home)


class Downloads(unittest.TestCase):
    def test_checksums(self):
        sums = 'a' * 64 + '  VideoDownloader-linux-4.6.tar.gz\n' + 'b' * 64 + ' *dist/other.zip\n'
        self.assertEqual(vd.expected_hash(sums, 'VideoDownloader-linux-4.6.tar.gz'), 'a' * 64)
        self.assertEqual(vd.expected_hash(sums, 'other.zip'), 'b' * 64)
        self.assertEqual(vd.expected_hash(sums, 'missing.zip'), '')

    def test_unsafe_archives_are_refused(self):
        d = tempfile.mkdtemp()
        try:
            for name, kind in (('../escape.txt', tarfile.REGTYPE), ('/abs.txt', tarfile.REGTYPE), ('link', tarfile.SYMTYPE)):
                path = os.path.join(d, 'bad.tar.gz')
                with tarfile.open(path, 'w:gz') as t:
                    info = tarfile.TarInfo(name)
                    info.type = kind
                    if kind == tarfile.SYMTYPE:
                        info.linkname = '/etc/passwd'
                        t.addfile(info)
                    else:
                        info.size = 2
                        t.addfile(info, io.BytesIO(b'hi'))
                with self.assertRaises(ValueError):
                    vd.safe_extract_tar(path, os.path.join(d, 'out'))
            good = os.path.join(d, 'good.tar.gz')
            with tarfile.open(good, 'w:gz') as t:
                info = tarfile.TarInfo('VideoDownloader/video-downloader.py')
                info.size = 2
                t.addfile(info, io.BytesIO(b'hi'))
            vd.safe_extract_tar(good, os.path.join(d, 'out'))
            self.assertTrue(os.path.exists(os.path.join(d, 'out', 'VideoDownloader', 'video-downloader.py')))
        finally:
            shutil.rmtree(d)


class EndToEnd(TempHome):
    def test_terminal_download_audio(self):
        r = self.run_app('--type', 'audio', 'https://www.youtube.com/watch?v=abc')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        h = self.history()
        self.assertEqual(len(h), 1)
        self.assertTrue(h[0]['ok'], h)
        self.assertTrue(os.path.exists(os.path.join(self.home, 'Audio', 'Fake title [abc].m4a')))
        self.assertEqual(oct(os.stat(self.data).st_mode & 0o777), '0o700')
        self.assertEqual(os.listdir(os.path.join(self.data, 'queue', 'running')), [])
        # only your account can read what it made, and nothing is left in the temp folder
        for path in (os.path.join(self.data, 'history.jsonl'), os.path.join(self.home, 'Audio', 'Fake title [abc].m4a')):
            self.assertEqual(os.stat(path).st_mode & 0o077, 0, path)
        self.assertEqual(os.listdir(os.path.join(self.data, 'temp')), [])
        self.assertFalse(os.path.exists(os.path.join(self.data, 'history.log')))

    def test_failure_is_explained(self):
        r = self.run_app('https://www.youtube.com/watch?v=private')
        self.assertEqual(r.returncode, 0, r.stderr)
        h = self.history()
        self.assertFalse(h[0]['ok'])
        self.assertEqual(h[0]['kind'], 'gone')
        self.assertIn('private', h[0]['hint'])

    def test_age_gate_retries_signed_in(self):
        r = self.run_app('https://www.youtube.com/watch?v=agegate')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(self.history()[0]['ok'], self.history())
        calls = self.calls()
        self.assertEqual(len(calls), 2)
        self.assertNotIn('--cookies-from-browser', calls[0])
        self.assertIn('--cookies-from-browser firefox', calls[1])

    def test_sign_in_is_youtube_only(self):
        with open(os.path.join(self.data, 'settings.json')) as f:
            s = json.load(f)
        s['UseCookies'] = 'always'
        with open(os.path.join(self.data, 'settings.json'), 'w') as f:
            json.dump(s, f)
        self.run_app('https://vimeo.com/123')
        self.run_app('https://youtu.be/abc')
        calls = self.calls()
        self.assertNotIn('--cookies', calls[0])
        self.assertIn('--cookies-from-browser firefox', calls[1])

    def test_offline_waits_and_keeps_the_job(self):
        p = subprocess.Popen([sys.executable, APP, 'https://youtu.be/offline'], env=self.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            for _ in range(100):
                st = vd.read_json(os.path.join(self.data, 'status.json'), {}) or {}
                if st.get('state') == 'waiting':
                    break
                time.sleep(0.1)
            self.assertEqual(st.get('state'), 'waiting')
            self.assertEqual(len(os.listdir(os.path.join(self.data, 'queue'))), 2)   # the job file + running/
            open(os.path.join(self.data, 'paused'), 'w').close()
            p.wait(timeout=10)
        finally:
            p.kill()
        self.assertEqual(self.history(), [])

    def test_pause_keeps_the_job(self):
        p = subprocess.Popen([sys.executable, APP, 'https://youtu.be/slow'], env=self.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            time.sleep(2)
            open(os.path.join(self.data, 'paused'), 'w').close()
            p.wait(timeout=20)
        finally:
            p.kill()
        jobs = [n for n in os.listdir(os.path.join(self.data, 'queue')) if n.endswith('.job')]
        self.assertEqual(len(jobs), 1)
        self.assertEqual(self.history(), [])
        part = os.path.join(self.data, 'temp', 'job-' + jobs[0][:-4], 'Fake title [abc].mp4.part')
        self.assertTrue(os.path.exists(part), 'the half-done download is kept for Resume')
        r = self.run_app('--resume')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertTrue(self.history()[0]['ok'])
        self.assertFalse(os.path.exists(os.path.join(self.data, 'paused')))

    def test_removing_a_running_download_deletes_its_pieces(self):
        p = subprocess.Popen([sys.executable, APP, 'https://youtu.be/slow'], env=self.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            time.sleep(2)
            self.assertEqual(len(os.listdir(os.path.join(self.data, 'temp'))), 1)
            open(os.path.join(self.data, 'cancel-current'), 'w').close()
            p.wait(timeout=20)
        finally:
            p.kill()
        self.assertEqual(os.listdir(os.path.join(self.data, 'temp')), [])
        self.assertEqual([n for n in os.listdir(os.path.join(self.data, 'queue')) if n.endswith('.job')], [])
        self.assertEqual(self.history(), [])

    def test_history_is_forgotten_after_the_chosen_days_and_erase_removes_it_all(self):
        old = (vd.datetime.datetime.now() - vd.datetime.timedelta(days=40)).replace(microsecond=0).isoformat()
        with open(os.path.join(self.data, 'history.jsonl'), 'w') as f:
            f.write(json.dumps({'ok': True, 'url': 'https://old', 'time': old}) + '\n')
        with open(os.path.join(self.data, 'settings.json')) as f:
            s = json.load(f)
        s['KeepHistoryDays'] = 30
        with open(os.path.join(self.data, 'settings.json'), 'w') as f:
            json.dump(s, f)
        self.run_app('https://youtu.be/abc')
        urls = [e['url'] for e in self.history()]
        self.assertEqual(urls, ['https://youtu.be/abc'])
        for n in ('runner.log', 'error.log', 'connection-check.txt', 'playlist-archive.txt'):
            open(os.path.join(self.data, n), 'w').close()
        os.environ['VIDEODOWNLOADER_DATA'] = self.data
        old_p = vd.P
        try:
            vd.P = vd.Paths()
            vd.erase_history()
        finally:
            vd.P = old_p
            os.environ.pop('VIDEODOWNLOADER_DATA')
        left = os.listdir(self.data)
        for gone in ('history.jsonl', 'runner.log', 'error.log', 'connection-check.txt', 'playlist-archive.txt', 'status.json'):
            self.assertNotIn(gone, left)
        self.assertIn('settings.json', left)

    def test_shrink_without_ffmpeg_keeps_the_video(self):
        only_python = os.path.join(self.home, 'only-python')      # a PATH with Python (for the stand-in) but no FFmpeg
        os.makedirs(only_python)
        os.symlink(sys.executable, os.path.join(only_python, 'python3'))
        r = self.run_app('--type', 'shrink', 'https://youtu.be/abc', env=dict(self.env, PATH=only_python))
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertTrue(os.path.exists(os.path.join(self.home, 'Videos', 'Fake title [abc].mp4')), r.stdout)
        self.assertTrue(self.history()[0]['ok'])

    def test_button_link_adds_a_job(self):
        r = self.run_app('--uri', 'ytdl://clip/dQw4w9WgXcQ/10-20', env=dict(self.env, DISPLAY=''))
        self.assertEqual(r.returncode, 0, r.stderr)
        for _ in range(100):
            if self.history():
                break
            time.sleep(0.1)
        h = self.history()
        self.assertTrue(h and h[0]['ok'], h)
        self.assertEqual(h[0]['mode'], 'clip')
        self.assertIn('--download-sections *10-20', self.calls()[0])

    def test_button_link_with_extra_options_is_refused(self):
        r = self.run_app('--uri', 'ytdl://video/dQw4w9WgXcQ', '--update-now')
        self.assertEqual(r.returncode, 1)
        r = self.run_app('--uri', 'ytdl://video/dQw4w9WgXcQ', 'https://evil.example/x')
        self.assertEqual(r.returncode, 1)
        r = self.run_app('--uri', 'ytdl://video/dQw4w9WgXcQ";--exec=x')
        self.assertEqual(r.returncode, 1)
        r = self.run_app('--ur', 'ytdl://video/dQw4w9WgXcQ')          # no abbreviations
        self.assertNotEqual(r.returncode, 0)
        r = self.run_app('--uri=ytdl://video/dQw4w9WgXcQ', '--uri=ytdl://audio/dQw4w9WgXcQ')
        self.assertEqual(r.returncode, 1)
        self.assertEqual(self.calls(), [])

    def test_bad_job_files_are_discarded(self):
        q = os.path.join(self.data, 'queue')
        os.makedirs(q, exist_ok=True)
        with open(os.path.join(q, '0-evil.job'), 'w') as f:
            json.dump({'Mode': 'video', 'Url': '--exec=touch /tmp/pwned'}, f)
        self.run_app('--run-queue')
        self.assertEqual(self.calls(), [])
        self.assertEqual([n for n in os.listdir(q) if n.endswith('.job')], [])

    @unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'), 'needs FFmpeg')
    def test_phone_converts_to_h264(self):
        env = dict(self.env, FAKE_REAL_MEDIA='1')
        r = self.run_app('--type', 'phone', 'https://youtu.be/abc', env=env, timeout=120)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        out = os.path.join(self.home, 'Phone', 'Fake title [abc].mp4')
        self.assertTrue(os.path.exists(out), os.listdir(os.path.join(self.home, 'Phone')))
        codecs = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'stream=codec_name', '-of', 'csv=p=0', out],
                                capture_output=True, text=True, check=True).stdout.split()
        self.assertIn('h264', codecs)
        self.assertIn('aac', codecs)


class AppUpdate(TempHome):
    """'Update now': only this project's Linux download, only with a matching checksum."""

    def setUp(self):
        super().setUp()
        self.old_p = vd.P
        os.environ['VIDEODOWNLOADER_DATA'] = self.data
        vd.P = vd.Paths()
        vd.P.ensure()
        self.addCleanup(os.environ.pop, 'VIDEODOWNLOADER_DATA', None)
        # a release tarball with an installer that just records that it ran
        self.files = {}
        tar = os.path.join(self.home, 'VideoDownloader-linux-9.9.tar.gz')
        with tarfile.open(tar, 'w:gz') as t:
            data = b'print("installed")\n'
            info = tarfile.TarInfo('VideoDownloader-linux-9.9/video-downloader.py')
            info.size = len(data)
            t.addfile(info, io.BytesIO(data))
        self.files['VideoDownloader-linux-9.9.tar.gz'] = tar
        with open(tar, 'rb') as f:
            self.digest = vd.hashlib.sha256(f.read()).hexdigest()

    def tearDown(self):
        vd.P = self.old_p
        super().tearDown()

    def release(self, sums_text, prefix='https://github.com/' + vd.UPDATE_REPO + '/releases/download/9.9/'):
        sums = os.path.join(self.home, 'SHA256SUMS.txt')
        with open(sums, 'w') as f:
            f.write(sums_text)
        self.files['SHA256SUMS.txt'] = sums
        return {'tag_name': '9.9', 'assets': [{'name': n, 'browser_download_url': prefix + n} for n in self.files]}

    def run_update(self, rel):
        ran = []

        def fake_download(url, dest, progress=None):
            shutil.copy(self.files[url.rsplit('/', 1)[1]], dest)

        def fake_run(cmd, **_kw):
            ran.append(cmd)
            return subprocess.CompletedProcess(cmd, 0)

        with mock.patch.object(vd, 'github_json', return_value=rel), mock.patch.object(vd, 'download', fake_download), \
                mock.patch.object(vd.subprocess, 'run', fake_run):
            return vd.install_app_update(), ran

    def test_good_update_runs_the_new_installer(self):
        msg, ran = self.run_update(self.release(self.digest + '  VideoDownloader-linux-9.9.tar.gz\n'))
        self.assertIsNone(msg)
        self.assertEqual(len(ran), 1)
        self.assertEqual(ran[0][1], '-I')
        self.assertEqual(ran[0][3:], ['--install', '--quiet'])

    def test_wrong_checksum_is_refused(self):
        with self.assertRaises(RuntimeError):
            self.run_update(self.release('0' * 64 + '  VideoDownloader-linux-9.9.tar.gz\n'))

    def test_other_sites_are_refused(self):
        with self.assertRaises(RuntimeError):
            self.run_update(self.release(self.digest + '  VideoDownloader-linux-9.9.tar.gz\n', prefix='https://evil.example/'))

    def test_same_version_does_nothing(self):
        with mock.patch.object(vd, 'github_json', return_value={'tag_name': vd.APP_VERSION, 'assets': []}):
            self.assertIn('newest version', vd.install_app_update())


class InstallAndRemove(TempHome):
    def test_install_and_uninstall(self):
        # helper programs are already in place, so nothing is downloaded
        for t in ('deno', 'ffmpeg', 'ffprobe'):
            p = os.path.join(self.bin, t)
            with open(p, 'w') as f:
                f.write('#!/bin/sh\nexit 0\n')
            os.chmod(p, 0o700)
        src = tempfile.mkdtemp(prefix='vd-src-')
        try:
            for name in ('video-downloader.py', 'VideoDownloader.user.js', 'video-downloader.png', 'README-linux.txt', 'LICENSE'):
                if os.path.exists(os.path.join(HERE, name)):
                    shutil.copy(os.path.join(HERE, name), src)
            env = dict(self.env, DISPLAY='')
            env.pop('VIDEODOWNLOADER_HOME')
            env['HOME'] = self.home
            # the real app folder is ~/.local/lib/video-downloader; put the fake tools there
            real_bin = os.path.join(self.home, '.local', 'lib', 'video-downloader', 'bin')
            shutil.copytree(self.bin, real_bin)
            r = subprocess.run([sys.executable, os.path.join(src, 'video-downloader.py'), '--install'], env=env,
                               capture_output=True, text=True, timeout=60, check=False)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            launcher = os.path.join(self.home, '.local', 'bin', 'video-downloader')
            desktop = os.path.join(self.home, '.local', 'share', 'applications', 'video-downloader-link.desktop')
            self.assertTrue(os.access(launcher, os.X_OK))
            with open(desktop) as f:
                text = f.read()
            self.assertIn('MimeType=x-scheme-handler/ytdl;', text)
            self.assertIn('--uri %u', text)
            r = subprocess.run([launcher, '--version'], env=env, capture_output=True, text=True, check=False)
            self.assertIn(vd.APP_VERSION, r.stdout)
            r = subprocess.run([launcher, '--uninstall', '--delete-data'], env=env, capture_output=True, text=True, check=False)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertFalse(os.path.exists(launcher))
            self.assertFalse(os.path.exists(desktop))
            self.assertFalse(os.path.exists(os.path.join(self.home, '.local', 'lib', 'video-downloader')))
            self.assertFalse(os.path.exists(self.data))
        finally:
            shutil.rmtree(src, ignore_errors=True)


class Window(TempHome):
    @unittest.skipUnless(os.environ.get('DISPLAY'), 'needs a display (run under xvfb-run)')
    def test_window_opens_and_closes(self):
        try:
            import tkinter  # noqa: F401
        except ImportError:
            self.skipTest('Tk is not installed')
        env = dict(self.env, VIDEODOWNLOADER_SELFTEST='2500', DISPLAY=os.environ['DISPLAY'])
        with open(os.path.join(self.data, 'paused'), 'w'):
            pass
        os.makedirs(os.path.join(self.data, 'queue'), exist_ok=True)
        with open(os.path.join(self.data, 'queue', '1.job'), 'w') as f:
            json.dump({'Mode': 'audio', 'Url': 'https://youtu.be/abc', 'Added': '2026-01-01T10:00:00'}, f)
        with open(os.path.join(self.data, 'history.jsonl'), 'w') as f:
            f.write(json.dumps({'mode': 'video', 'url': 'https://youtu.be/x', 'ok': False, 'title': 'Broken', 'time': '2026-01-01T09:00:00', 'hint': 'h'}) + '\n')
        r = self.run_app('--app', env=env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stderr.strip(), '')
        self.assertFalse(os.path.exists(os.path.join(self.data, 'error.log')), 'the window logged an error')


if __name__ == '__main__':
    unittest.main(verbosity=2)
