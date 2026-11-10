<#
  Video Downloader 4.5
  Download videos and audio from YouTube (and most other video sites) with yt-dlp.

    No arguments / -App    the Video Downloader window (paste links, watch progress, pause, settings)
    -Uri "ytdl://..."      from the Download button under YouTube videos (adds to the queue, starts downloading)
    -RunQueue              the background downloader (started automatically, no window)
    -Settings              the settings window
    -History               your YouTube watch history, sortable by length (also a button in the window)
    -Menu                  the text-only version, for people who prefer typing
    -UpdateNow             update yt-dlp and Deno now
    -ConnectionCheck       check the connection and Wi-Fi, then open the report (Help > Check my connection)
    -NetCheck              the secure-connection part of that check only (runs by itself when a network intercepts)
    -CheckApp / -UpdateApp look for / install a new Video Downloader from GitHub (used by the window)
    -HistoryTask <task>    a watch-history job running in the background (used by the Watch history window)

  Your settings live in %LOCALAPPDATA%\VideoDownloader\settings.json - change them in the Settings window.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Coloured text for the person watching the console window')]
param([string]$Uri, [switch]$App, [switch]$AutoOpened, [switch]$RunQueue, [switch]$Settings, [switch]$Menu, [switch]$UpdateNow, [switch]$NetCheck,
      [switch]$History, [string]$HistoryTask, [string]$Path, [switch]$CheckApp, [switch]$UpdateApp, [switch]$ConnectionCheck)

$AppVersion = '4.6'
$UpdateRepo = 'sleeeeeeeeeeeeeep-cmyl/VideoDownloader'   # GitHub project: new versions are announced here

# ============================== DEFAULT SETTINGS ==============================
# Windows lets people move Downloads (to another drive, or into OneDrive), so ask Windows where it really is
function Get-DownloadsFolder {
    try {
        $v = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction Stop).'{374DE290-123F-4565-9164-39C4925E467B}'
        if ($v) { $v = [Environment]::ExpandEnvironmentVariables($v); if (Test-Path -LiteralPath $v) { return $v } }
    } catch { Write-Debug $_ }
    return (Join-Path $env:USERPROFILE 'Downloads')
}
$DownloadsDir = Get-DownloadsFolder
$iCloud = Join-Path $env:USERPROFILE 'iCloudDrive'
$Defaults = [ordered]@{
    # general
    NameStyle         = 'title-id'  # title-id | title | channel-title | date-title
    MenuDefault       = 'video'     # the download type picked when the window opens
    OpenAppOnDownload = $true       # show the Video Downloader window when a download starts from the browser
    CloseWhenDone     = $true       # ...and close it again when everything finished fine
    Notify            = $true
    ShowInFolder      = $false
    AutoUpdateDays    = 7           # 0 = never
    CheckAppUpdates   = $true       # look once a day on GitHub for a newer Video Downloader (only asks GitHub for the version number)
    # video
    VideoFolder       = (Join-Path $DownloadsDir 'Videos')
    MaxHeight         = 1080        # Video / Clip / Playlist
    BestHeight        = 0           # Best quality cap, 0 = no limit
    EditHeight        = 1080        # Editor-friendly
    VideoCodec        = 'av1'       # av1 | vp9 | h264
    MaxFps            = 0           # 0 = any | 30 | 60
    Container         = 'mp4'       # mp4 | mkv
    EmbedChapters     = $true
    EmbedThumbnail    = $false
    # phone
    PhoneFolder       = $(if (Test-Path -LiteralPath $iCloud) { Join-Path $iCloud 'Phone Videos' } else { Join-Path $DownloadsDir 'Phone' })
    PhoneHeight       = 720
    PhoneMaxFps       = 0           # 0 = same as the video | 30
    # audio
    AudioFolder       = (Join-Path $DownloadsDir 'Audio')
    AudioFormat       = 'm4a'       # m4a | mp3 | opus | flac | wav
    AudioQuality      = 'best'      # best | 256 | 192 | 128
    AudioCover        = $true
    # extras
    SubtitleMode      = 'off'       # off | embed | file
    SubtitleLangs     = 'en'        # en | all
    AutoSubtitles     = $false
    SponsorBlock      = 'off'       # off | mark | remove
    ClipAccurate      = $true
    ShrinkQuality     = 'balanced'  # smaller | balanced | better
    PlaylistFolders   = $true
    # network
    Fragments         = 4
    SpeedLimit        = 0           # MB/s, 0 = unlimited
    UseCookies        = 'auto'      # auto | always | never
    CookieSource      = 'file'      # file (an exported cookies.txt, kept encrypted) | firefox (read straight from Firefox)
}
# ================================================================================

$ErrorActionPreference = 'Stop'
$script:Interactive = [bool]$Menu                      # only the text version has a console you can see
$Base       = Join-Path $env:LOCALAPPDATA 'VideoDownloader'
$QueueDir   = Join-Path $Base 'queue'
$RunDir     = Join-Path $QueueDir 'running'
$TempDir    = Join-Path $Base 'temp'
$LogFile    = Join-Path $Base 'history.log'
$HistFile   = Join-Path $Base 'history.jsonl'
$StatusFile = Join-Path $Base 'status.json'
$RunnerLog  = Join-Path $Base 'runner.log'
$ErrorLog   = Join-Path $Base 'error.log'
$StampFile  = Join-Path $Base 'last-update.txt'
$SettingsFile = Join-Path $Base 'settings.json'
foreach ($d in $Base, $QueueDir, $RunDir, $TempDir) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

# ---------- the data folder is private to your Windows account ----------
# It holds your sign-in, history and network reports, so only your account (and Windows itself) may open it.
# (4.2 did this with "icacls /T", which also stripped the existing files and locked you out of them; v2 repairs that.)
function Protect-DataFolder {
    if ($env:OS -ne 'Windows_NT') { return }
    $mark = Join-Path $Base '.private-v2'
    if (Test-Path -LiteralPath $mark) { return }
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $icacls = Join-Path $env:WINDIR 'System32\icacls.exe'
        # 1. the folder itself: only you and Windows, passed down to everything inside
        $null = & $icacls $Base '/inheritance:r' '/grant:r' "*${sid}:(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' '/Q' 2>&1
        $ok = ($LASTEXITCODE -eq 0)
        # 2. everything inside simply inherits that (no separate rules of its own)
        $null = & $icacls (Join-Path $Base '*') '/reset' '/T' '/C' '/Q' 2>&1
        # 3. anything still unreadable gets inheritance switched back on directly (you own these files, so this is allowed)
        foreach ($f in Get-ChildItem -LiteralPath $Base -Recurse -Force -ErrorAction SilentlyContinue) {
            try { if (-not $f.PSIsContainer) { [System.IO.File]::OpenRead($f.FullName).Dispose() } }
            catch {
                try {
                    $fs = if ($f.PSIsContainer) { New-Object System.Security.AccessControl.DirectorySecurity } else { New-Object System.Security.AccessControl.FileSecurity }
                    $fs.SetAccessRuleProtection($false, $false)
                    if ($f.PSIsContainer) { [System.IO.Directory]::SetAccessControl($f.FullName, $fs) } else { [System.IO.File]::SetAccessControl($f.FullName, $fs) }
                } catch { $ok = $false }
            }
        }
        if ($ok) { Set-Content -LiteralPath $mark -Value (Get-Date -Format o) }
    } catch { Write-Debug $_ } finally { $ErrorActionPreference = $eap }
}
Protect-DataFolder


function Show-ErrorBox([string]$text, [string]$title = 'Video Downloader', [string]$icon = 'Warning') {
    if ($env:VIDEODOWNLOADER_TEST) { return }   # automatic tests: no pop-ups
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [void][System.Windows.Forms.MessageBox]::Show($text, $title, 'OK', $icon)
    } catch { Write-Debug $_ }
}

trap {
    if ($_.Exception.Message -match 'other end of the pipe|The handle is invalid') { exit 0 }   # the window was simply closed
    $err = "ERROR: $($_.Exception.Message)`r`n$($_.InvocationInfo.PositionMessage)"
    try { Add-Content -LiteralPath $ErrorLog -Value ("{0:yyyy-MM-dd HH:mm:ss}  {1}`r`n" -f (Get-Date), $err) -Encoding UTF8 } catch { Write-Debug $_ }
    try { Close-SignIn } catch { Write-Debug $_ }
    if ($script:Interactive) {
        Write-Host "`n$err" -ForegroundColor Red
        Write-Host "`nSomething went wrong - this was saved to $ErrorLog" -ForegroundColor Yellow
        try { Read-Host 'Press Enter to close' | Out-Null } catch { Start-Sleep 30 }
    } elseif (-not $RunQueue -and -not $UpdateNow -and -not $HistoryTask -and -not $NetCheck -and -not $CheckApp -and -not $UpdateApp -and -not $ConnectionCheck) {
        Show-ErrorBox ("Something went wrong:`n`n{0}`n`nThe details were saved to:`n{1}" -f $_.Exception.Message, $ErrorLog)
    }
    exit 1
}
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { Write-Debug $_ }
try { $Host.UI.RawUI.WindowTitle = 'Video Downloader' } catch { Write-Debug $_ }

# ---------- settings: load / save / apply ----------
function Read-Config {
    $s = [ordered]@{}
    foreach ($k in $Defaults.Keys) { $s[$k] = $Defaults[$k] }
    if (Test-Path -LiteralPath $SettingsFile) {
        try {
            $j = Get-Content -LiteralPath $SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $j.PSObject.Properties) { if ($s.Contains($p.Name) -and $null -ne $p.Value) { $s[$p.Name] = $p.Value } }
            if ($j.Subtitles -eq $true -and -not $j.SubtitleMode) { $s['SubtitleMode'] = 'embed' }   # older settings file
        } catch { Write-Debug $_ }
    }
    return $s
}
function Save-Config { $script:S | ConvertTo-Json | Set-Content -LiteralPath $SettingsFile -Encoding UTF8 }
function Use-Config {
    $script:VideoDir       = [string]$S.VideoFolder
    $script:AudioDir       = [string]$S.AudioFolder
    $script:PhoneDir       = [string]$S.PhoneFolder
    $script:MaxHeight      = [int]$S.MaxHeight
    $script:PhoneHeight    = [int]$S.PhoneHeight
    $script:NameStyle      = [string]$S.NameStyle
    $script:AudioFormat    = [string]$S.AudioFormat
    $script:SponsorBlock   = [string]$S.SponsorBlock
    $script:Notify         = [bool]$S.Notify
    $script:ShowInFolder   = [bool]$S.ShowInFolder
    $script:AutoUpdateDays = [int]$S.AutoUpdateDays
    $script:MenuDefault    = [string]$S.MenuDefault
}
$script:S = Read-Config
Use-Config

$script:Done = New-Object System.Collections.Generic.List[string]
$script:Failed = New-Object System.Collections.Generic.List[string]
$script:UpdatedThisRun = $false
$script:IsRunner = $false
$script:Status = @{}
$script:LastStatusWrite = [datetime]::MinValue
$script:LastErrors = New-Object System.Collections.Generic.List[string]

# Messages: shown in the text version, written to runner.log by the background downloader
function Say([string]$msg, [string]$color = 'Gray') {
    if ($script:Interactive) { Write-Host $msg -ForegroundColor $color }
    else { try { Add-Content -LiteralPath $RunnerLog -Value ("{0:HH:mm:ss}  {1}" -f (Get-Date), $msg) -Encoding UTF8 } catch { Write-Debug $_ } }
}
function Write-DownloadLog([string]$line) {
    try { Add-Content -LiteralPath $LogFile -Value ("{0:yyyy-MM-dd HH:mm}  {1}" -f (Get-Date), $line) -Encoding UTF8 } catch { Write-Debug $_ }
}
function Write-History([hashtable]$h) {
    $h['time'] = (Get-Date).ToString('s')
    try { Add-Content -LiteralPath $HistFile -Value ($h | ConvertTo-Json -Compress) -Encoding UTF8 } catch { Write-Debug $_ }
}

# The background downloader tells the window what it is doing through status.json
function Write-Status([hashtable]$st, [switch]$Force) {
    if (-not $script:IsRunner) { return }
    foreach ($k in $st.Keys) { $script:Status[$k] = $st[$k] }
    $now = Get-Date
    if (-not $Force -and ($now - $script:LastStatusWrite).TotalMilliseconds -lt 400) { return }
    $script:LastStatusWrite = $now
    $script:Status['updated'] = $now.ToString('o')
    $script:Status['runnerPid'] = $PID
    try {
        $tmp = $StatusFile + '.tmp'
        [System.IO.File]::WriteAllText($tmp, ($script:Status | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tmp -Destination $StatusFile -Force
    } catch { Write-Debug $_ }
}

# ---------- running programs ----------
# yt-dlp would also read settings files and plugins from other folders; another program could put commands there
# (for example --exec), so only the options this app gives it are used.
$YtSafeArgs = @('--ignore-config', '--no-plugin-dirs')
function ConvertTo-ArgLine([string[]]$list) {
    ($list | ForEach-Object {
        if ($_ -eq '') { '""' }
        elseif ($_ -notmatch '[\s"]') { $_ }
        else { '"' + (($_ -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"' }
    }) -join ' '
}
function Invoke-Native([string]$exe, [string[]]$argList) {
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo.FileName = $exe
    $p.StartInfo.Arguments = ConvertTo-ArgLine $argList
    $p.StartInfo.UseShellExecute = $false
    if (-not $script:Interactive) { $p.StartInfo.CreateNoWindow = $true }
    [void]$p.Start()
    Write-Status @{ childPid = $p.Id } -Force
    $p.WaitForExit()
    return $p.ExitCode
}

# Start another copy of this script without any window (the background downloader, the window from the browser, ...)
function Invoke-Hidden([string[]]$extra) {
    $argLine = ConvertTo-ArgLine (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath) + $extra)
    if ($env:OS -ne 'Windows_NT') {   # (only used when testing on Linux)
        Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $argLine | Out-Null
        return
    }
    $ps = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -LiteralPath $ps)) { $ps = 'powershell.exe' }
    $conhost = Join-Path $env:WINDIR 'System32\conhost.exe'
    try {
        if (Test-Path -LiteralPath $conhost) {
            Start-Process -FilePath $conhost -ArgumentList ('--headless ' + (ConvertTo-ArgLine @($ps)) + ' ' + $argLine) -WindowStyle Hidden | Out-Null
            return
        }
    } catch { Write-Debug $_ }
    Start-Process -FilePath $ps -ArgumentList ('-WindowStyle Hidden ' + $argLine) -WindowStyle Hidden | Out-Null
}

# ---------- find yt-dlp / ffmpeg / deno even when winget's Links folder isn't on PATH ----------
function Find-Tool([string]$exe, [string]$packagePrefix) {
    $cmd = Get-Command $exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    $roots = @((Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'), (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'))
    $direct = Join-Path $roots[0] "$exe.exe"
    if (Test-Path -LiteralPath $direct) { return $direct }
    if (Test-Path -LiteralPath $roots[1]) {
        foreach ($pkg in Get-ChildItem -LiteralPath $roots[1] -Directory -Filter "$packagePrefix*" -ErrorAction SilentlyContinue) {
            $hit = Get-ChildItem -LiteralPath $pkg.FullName -Filter "$exe.exe" -Recurse -Depth 3 -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }
    return $null
}

function Initialize-Toolset {
    $script:YtDlp  = Find-Tool 'yt-dlp' 'yt-dlp.yt-dlp'
    $script:FFmpeg = Find-Tool 'ffmpeg' 'Gyan.FFmpeg'
    if (-not $script:FFmpeg) { $script:FFmpeg = Find-Tool 'ffmpeg' 'yt-dlp.FFmpeg' }
    $script:Deno   = Find-Tool 'deno' 'DenoLand.Deno'
    $script:FFprobe = $null
    if ($script:FFmpeg) {
        $probe = Join-Path (Split-Path -Parent $script:FFmpeg) ('ffprobe' + [IO.Path]::GetExtension($script:FFmpeg))
        if (Test-Path -LiteralPath $probe) { $script:FFprobe = $probe }
    }
    if (-not $script:FFprobe) { $script:FFprobe = Find-Tool 'ffprobe' 'Gyan.FFmpeg' }
    # put the folders on PATH so yt-dlp finds ffmpeg (merging) and deno (YouTube's JavaScript checks)
    foreach ($t in $script:FFmpeg, $script:Deno) {
        if (-not $t) { continue }
        $dir = Split-Path -Parent $t
        if (($env:PATH -split [regex]::Escape([IO.Path]::PathSeparator)) -notcontains $dir) { $env:PATH = $dir + [IO.Path]::PathSeparator + $env:PATH }
    }
}

function Install-Missing {
    $wgCmd = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $wgCmd) { return }
    $wg = @('-e', '--source', 'winget', '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity')
    if (-not $script:YtDlp)  { Say 'Installing yt-dlp...' Yellow;  $null = Invoke-Native $wgCmd.Source (@('install', '--id', 'yt-dlp.yt-dlp') + $wg) }
    if (-not $script:FFmpeg) { Say 'Installing FFmpeg...' Yellow;  $null = Invoke-Native $wgCmd.Source (@('install', '--id', 'Gyan.FFmpeg') + $wg) }
    if (-not $script:Deno)   { Say 'Installing Deno (YouTube needs it)...' Yellow; $null = Invoke-Native $wgCmd.Source (@('install', '--id', 'DenoLand.Deno') + $wg) }
    Initialize-Toolset
}

function Invoke-ToolUpdate {
    $wgCmd = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $wgCmd) { Say 'winget not found - cannot update yt-dlp.' Red; return }
    Say 'Checking for updates (yt-dlp and Deno)...' Yellow
    Write-Status @{ state = 'updating'; message = 'Checking for updates (yt-dlp and Deno)...' } -Force
    $up = @('-e', '--source', 'winget', '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity')
    $null = Invoke-Native $wgCmd.Source (@('upgrade', '--id', 'yt-dlp.yt-dlp') + $up)
    # Deno solves YouTube's player challenges, so an old copy can break downloads too
    if ("$script:Deno" -match 'DenoLand\.Deno|WinGet\\Links') { $null = Invoke-Native $wgCmd.Source (@('upgrade', '--id', 'DenoLand.Deno') + $up) }
    Set-Content -LiteralPath $StampFile -Value (Get-Date -Format o)
    $script:UpdatedThisRun = $true
    Initialize-Toolset
}

function Test-UpdateDue {
    if ($AutoUpdateDays -le 0) { return $false }
    if (-not (Test-Path -LiteralPath $StampFile)) { return $true }
    try { $last = [datetime]::Parse((Get-Content -LiteralPath $StampFile -Raw).Trim()) } catch { return $true }
    return ((Get-Date) - $last).TotalDays -ge $AutoUpdateDays
}

# ---------- time helpers (clips) ----------
function ConvertFrom-ClockText([string]$t) {
    $t = "$t".Trim()
    if ($t -match '^\d+(\.\d+)?$') { return [double]$t }
    if ($t -match '^(?:(\d+):)?(\d{1,2}):(\d{1,2}(?:\.\d+)?)$') {
        $h = 0; if ($Matches[1]) { $h = [int]$Matches[1] }
        return $h * 3600 + [int]$Matches[2] * 60 + [double]$Matches[3]
    }
    return $null
}
function Format-Clock([double]$s) {
    $s = [int][math]::Floor($s)
    $h = [int][math]::Floor($s / 3600); $m = [int][math]::Floor(($s % 3600) / 60); $sec = $s % 60
    if ($h -gt 0) { return '{0}h{1:00}m{2:00}s' -f $h, $m, $sec }
    return '{0}m{1:00}s' -f $m, $sec
}

# ---------- the queue: one file per download, so nothing is lost when several clicks arrive at once ----------
function Add-Job([hashtable]$job) {
    $name = '{0:yyyyMMddHHmmssfff}-{1}.job' -f (Get-Date), (Get-Random -Maximum 1000000)
    $tmp = Join-Path $QueueDir ($name + '.tmp')
    ($job | ConvertTo-Json -Compress) | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination (Join-Path $QueueDir $name)   # appears atomically
}
function Get-QueueCount { @(Get-ChildItem -LiteralPath $QueueDir -Filter '*.job' -File -ErrorAction SilentlyContinue).Count }
function Read-JobFile([string]$path) {
    try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

# a job file is only run if it looks exactly like one this app writes
function Test-JobSafe($o) {
    $mode = [string]$o.Mode
    if ($mode -in 'netcheck', 'wificheck') { return $true }
    if ($mode -notin 'video', 'best', 'edit', 'audio', 'phone', 'clip', 'playlist', 'shrink') { return $false }
    if ([string]$o.Url -notmatch '^https?://[^\s"<>]+$') { return $false }
    if ($mode -eq 'clip') {
        $a = 0; $b = 0
        if (-not [int]::TryParse([string]$o.Start, [ref]$a) -or -not [int]::TryParse([string]$o.End, [ref]$b) -or $a -lt 0 -or $b -le $a) { return $false }
    }
    return $true
}
function Get-NextJob {
    foreach ($f in Get-ChildItem -LiteralPath $QueueDir -Filter '*.job' -File -ErrorAction SilentlyContinue | Sort-Object Name) {
        $dest = Join-Path $RunDir $f.Name
        try { Move-Item -LiteralPath $f.FullName -Destination $dest -Force -ErrorAction Stop } catch { continue }
        $o = Read-JobFile $dest
        if ($o -and $o.Url -and (Test-JobSafe $o)) {
            $o | Add-Member -NotePropertyName JobFile -NotePropertyValue $dest -Force
            return $o
        }
        Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
    }
    return $null
}
function Complete-Job($job) { Remove-Item -LiteralPath $job.JobFile -Force -ErrorAction SilentlyContinue }
function Restore-Job($job) {   # put it back in the queue for later
    try { Move-Item -LiteralPath $job.JobFile -Destination (Join-Path $QueueDir (Split-Path -Leaf $job.JobFile)) -Force -ErrorAction Stop } catch { Write-Debug $_ }
}
# Anything left "running" belongs to a downloader that was paused, closed or shut down: put it back first in line
function Restore-Interrupted {
    foreach ($f in Get-ChildItem -LiteralPath $RunDir -Filter '*.job' -File -ErrorAction SilentlyContinue) {
        try { Move-Item -LiteralPath $f.FullName -Destination (Join-Path $QueueDir $f.Name) -Force -ErrorAction Stop } catch { Write-Debug $_ }
    }
}
function Clear-OldTemp {
    Get-ChildItem -LiteralPath $TempDir -Directory -Filter 'work-*' -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    Get-ChildItem -LiteralPath $TempDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'done-*.txt' -or $_.LastWriteTime -lt (Get-Date).AddDays(-3) } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
}

# Only one downloader works through the queue at a time
function Test-RunnerActive {
    $m = New-Object System.Threading.Mutex($false, 'Local\VideoDownloaderRunner')
    $got = $false
    try { $got = $m.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $got = $true }
    if ($got) { $m.ReleaseMutex() }
    $m.Dispose()
    return -not $got
}
$PausedFlag = Join-Path $Base 'paused.flag'
function Invoke-Runner {
    Remove-Item -LiteralPath $PausedFlag -Force -ErrorAction SilentlyContinue
    $script:KickAt = Get-Date
    if (-not (Test-RunnerActive)) { Invoke-Hidden @('-RunQueue') }
}
function Suspend-Runner {   # pause: stop the downloader; the half-done file and the queue are kept and resume later
    try { Set-Content -LiteralPath $PausedFlag -Value (Get-Date -Format o) } catch { Write-Debug $_ }
    $st = Read-Status
    foreach ($id in @($st.childPid, $st.runnerPid)) {
        if (-not $id) { continue }
        try {
            if ($env:OS -eq 'Windows_NT') { Start-Process -FilePath 'taskkill.exe' -ArgumentList "/PID $id /T /F" -WindowStyle Hidden -Wait | Out-Null }
            else { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
        } catch { Write-Debug $_ }
    }
}
function Read-Status {
    if (-not (Test-Path -LiteralPath $StatusFile)) { return $null }
    try { return (Get-Content -LiteralPath $StatusFile -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

# ---------- building the yt-dlp command ----------
function Get-NameTemplate([string]$suffix = '') {
    $base = switch ($NameStyle) {
        'title'         { '%(title)s' }
        'channel-title' { '%(uploader|Unknown)s - %(title)s' }
        'date-title'    { '%(upload_date>%Y-%m-%d|undated)s - %(title)s' }
        default         { '%(title)s [%(id)s]' }
    }
    return $base + $suffix + '.%(ext)s'
}

function Get-VideoSort([int]$height, [string]$codec, [int]$fps) {
    $parts = @()
    if ($height -gt 0) { $parts += "res:$height" }
    if ($fps -gt 0) { $parts += "fps:$fps" }
    $parts += @{ av1 = 'vcodec:av01'; vp9 = 'vcodec:vp9'; h264 = 'vcodec:h264' }[$codec]
    $parts += 'acodec:aac'
    return ($parts -join ',')
}

# a frame-rate cap has to be a hard filter (sorting alone lets 1080p60 win over 1080p30)
function Get-VideoFormat([int]$fps) {
    if ($fps -gt 0) { return "bv*[fps<=$fps]+ba/b[fps<=$fps]/bv*+ba/b" }
    return 'bv*+ba/b'
}

function Get-JobArgumentList($job, [string]$listFile, [string]$dirOverride) {
    $mode = [string]$job.Mode
    $isAudio = $mode -eq 'audio'
    $dir = if ($dirOverride) { $dirOverride } elseif ($isAudio) { $AudioDir } elseif ($mode -eq 'phone') { $PhoneDir } else { $VideoDir }
    $out = Get-NameTemplate
    $codec = [string]$S.VideoCodec
    $fps = [int]$S.MaxFps
    $box = [string]$S.Container

    $a = @('--no-playlist', '--windows-filenames', '--trim-filenames', '150', '--no-mtime',
           '--retries', '30', '--fragment-retries', '30', '--retry-sleep', 'http:exp=1:30', '--retry-sleep', 'fragment:exp=1:30',
           '--socket-timeout', '30', '-N', "$([int]$S.Fragments)", '--embed-metadata',
           '-P', $dir, '-P', "temp:$TempDir",
           '--print-to-file', 'after_move:filepath', $listFile)
    if ([double]$S.SpeedLimit -gt 0) { $a += @('-r', ('{0}M' -f $S.SpeedLimit)) }
    if ($script:FFmpeg) { $a += @('--ffmpeg-location', (Split-Path -Parent $script:FFmpeg)) }

    switch ($mode) {
        'video'    { $a += @('-f', (Get-VideoFormat $fps), '-S', (Get-VideoSort -height $MaxHeight -codec $codec -fps $fps), '--merge-output-format', $box) }
        'best'     { $a += @('-f', (Get-VideoFormat $fps), '-S', (Get-VideoSort -height ([int]$S.BestHeight) -codec $codec -fps $fps), '--merge-output-format', $box) }
        'edit'     { $a += @('-f', (Get-VideoFormat $fps), '-S', (Get-VideoSort -height ([int]$S.EditHeight) -codec 'h264' -fps $fps), '--merge-output-format', 'mp4') }
        'phone'    {
            # H.264 + AAC in MP4 plays on every iPhone/Android and in every messaging app; YouTube serves it natively up to 1080p
            $h = $PhoneHeight
            $f = if ([int]$S.PhoneMaxFps -gt 0) { "[fps<=$([int]$S.PhoneMaxFps)]" } else { '' }
            $a += @('-f', "bv*[vcodec^=avc1][height<=$h]$f+ba[ext=m4a]/b[ext=mp4][height<=$h]/bv*[height<=$h]+ba/b[height<=$h]/b",
                    '-S', (Get-VideoSort -height $h -codec 'h264' -fps ([int]$S.PhoneMaxFps)), '--merge-output-format', 'mp4')
        }
        'audio'    {
            $fmt = [string]$AudioFormat
            $a += @('-f', $(if ($fmt -eq 'm4a') { 'ba[ext=m4a]/ba' } else { 'ba' }), '-x', '--audio-format', $fmt)
            $q = [string]$S.AudioQuality
            if ($fmt -in 'mp3', 'opus', 'm4a') { $a += @('--audio-quality', $(if ($q -eq 'best') { '0' } else { "${q}K" })) }
            if ([bool]$S.AudioCover -and $fmt -ne 'wav') { $a += @('--embed-thumbnail', '--convert-thumbnails', 'jpg') }
        }
        'clip'     {
            $a += @('-f', (Get-VideoFormat $fps), '-S', (Get-VideoSort -height $MaxHeight -codec $codec -fps $fps), '--merge-output-format', $box,
                    '--download-sections', ('*{0}-{1}' -f $job.Start, $job.End))
            if ([bool]$S.ClipAccurate) { $a += '--force-keyframes-at-cuts' }
            $out = Get-NameTemplate (' (clip ' + (Format-Clock $job.Start) + '-' + (Format-Clock $job.End) + ')')
        }
        'playlist' {
            $a = $a | Where-Object { $_ -ne '--no-playlist' }
            $a += @('--yes-playlist', '-f', (Get-VideoFormat $fps), '-S', (Get-VideoSort -height $MaxHeight -codec $codec -fps $fps), '--merge-output-format', $box,
                    '--download-archive', (Join-Path $Base 'playlist-archive.txt'), '--ignore-errors')
            $prefix = if ([bool]$S.PlaylistFolders) { '%(playlist_title|Playlist)s\' } else { '' }
            $out = $prefix + '%(playlist_index|0)03d - ' + (Get-NameTemplate)
        }
        'shrink'   {
            # downloads into a private temp folder (dirOverride); Invoke-Shrink writes the small copy to Videos
            $a += @('-f', 'bv*+ba/b', '-S', (Get-VideoSort -height $MaxHeight -codec $codec -fps $fps), '--merge-output-format', 'mp4')
        }
    }
    if (-not $isAudio) {
        if ([bool]$S.EmbedChapters) { $a += '--embed-chapters' }
        if ([bool]$S.EmbedThumbnail -and $mode -ne 'phone') { $a += @('--embed-thumbnail', '--convert-thumbnails', 'jpg') }
        if ($SponsorBlock -eq 'mark')   { $a += @('--sponsorblock-mark', 'all') }
        if ($SponsorBlock -eq 'remove') { $a += @('--sponsorblock-remove', 'sponsor,selfpromo,interaction') }
        $langs = if ([string]$S.SubtitleLangs -eq 'all') { 'all,-live_chat' } else { 'en.*,-live_chat' }
        switch ([string]$S.SubtitleMode) {
            'embed' { $a += @('--embed-subs', '--sub-langs', $langs) }
            'file'  { $a += @('--write-subs', '--sub-langs', $langs, '--convert-subs', 'srt') }
        }
        if ([string]$S.SubtitleMode -ne 'off' -and [bool]$S.AutoSubtitles) { $a += '--write-auto-subs' }
    }
    $a += @('-o', $out)
    return $a
}

# Runs yt-dlp, turning its progress lines into status updates (and a live progress line in the text version)
function Invoke-YtDlp($job, [string]$listFile, [string]$dirOverride, [string]$cookieFile) {
    $argList = @($YtSafeArgs) + @(Get-JobArgumentList -job $job -listFile $listFile -dirOverride $dirOverride)
    if ($cookieFile) { $argList += @(Get-CookieArgumentList $cookieFile) }
    $argList += @('--newline',
                  '--progress-template', 'download:VDLP|%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s|%(info.title)s',
                  '--progress-template', 'postprocess:VDLPP|%(progress.postprocessor)s|%(info.title)s',
                  '--', [string]$job.Url)
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo.FileName = $script:YtDlp
    $p.StartInfo.Arguments = ConvertTo-ArgLine $argList
    $p.StartInfo.UseShellExecute = $false
    $p.StartInfo.CreateNoWindow = $true
    $p.StartInfo.RedirectStandardOutput = $true
    $p.StartInfo.RedirectStandardError = $true
    $p.StartInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $p.StartInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $p.StartInfo.EnvironmentVariables['PYTHONIOENCODING'] = 'utf-8'
    $p.StartInfo.EnvironmentVariables['PYTHONUTF8'] = '1'
    [void]$p.Start()
    Write-Status @{ childPid = $p.Id } -Force
    $errTask = $p.StandardError.ReadToEndAsync()          # read errors in the background so neither stream can block
    $script:LastErrors = New-Object System.Collections.Generic.List[string]
    $onProgressLine = $false
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    while ($null -ne ($line = $p.StandardOutput.ReadLine())) {
        $line = $line -replace "\x1b\[[0-9;]*m", ''
        if ($line.StartsWith('VDLP|')) {
            $f = $line.Split([char]'|', 5)
            $pct = $f[1].Trim(); $spd = $f[2].Trim(); $eta = $f[3].Trim()
            $num = 0.0
            [void][double]::TryParse(($pct -replace '[^0-9.]', ''), [System.Globalization.NumberStyles]::Float, $inv, [ref]$num)
            $st = @{ phase = 'downloading'; percent = $num; speed = $spd; eta = $eta }
            if ($f.Count -ge 5 -and $f[4] -and $f[4] -ne 'NA') { $st['title'] = $f[4].Trim() }
            Write-Status $st
            if ($script:Interactive) { Write-Host ("`r  {0,7}   {1,12}   {2} left      " -f $pct, $spd, $eta) -NoNewline; $onProgressLine = $true }
            continue
        }
        if ($line.StartsWith('VDLPP|')) {
            $f = $line.Split([char]'|', 3)
            $st = @{ phase = 'finishing'; detail = $f[1] }
            if ($f.Count -ge 3 -and $f[2] -and $f[2] -ne 'NA') { $st['title'] = $f[2].Trim() }
            Write-Status $st
            continue
        }
        if ($onProgressLine) { Write-Host ''; $onProgressLine = $false }
        if ($line.Trim()) { Say $line DarkGray }
    }
    if ($onProgressLine) { Write-Host '' }
    $p.WaitForExit()
    foreach ($l in ("$($errTask.Result)" -split "`r?`n")) {
        if (-not $l.Trim()) { continue }
        if ($l -match '^ERROR') { Say $l Red; $script:LastErrors.Add($l) }
        elseif ($l -match '^WARNING') { Say $l Yellow }
        else { Say $l DarkGray }
    }
    return $p.ExitCode
}

# What kind of failure was it? Decides what to try next and what to tell you.
function Get-FailureKind {
    $t = ($script:LastErrors -join ' ')
    if ($t -match "confirm your age|age.restricted|inappropriate for some users") { return 'age' }
    if ($t -match "members.only|Join this channel|available to this channel's members") { return 'members' }
    if ($t -match "not a bot|try again later|HTTP Error 429|Too Many Requests|rate.limit") { return 'blocked' }
    if ($t -match "CERTIFICATE_VERIFY_FAILED|self.signed certificate|certificate verify failed") { return 'intercepted' }
    if ($t -match "getaddrinfo failed|Failed to resolve|Name or service not known|No address associated|timed out|Connection (reset|aborted|refused)|Network is unreachable|No route to host|RemoteDisconnected|Connection broken|IncompleteRead|Read timed out|EOF occurred|SSL:|Unable to connect to proxy|Tunnel connection failed") { return 'offline' }
    if ($t -match "network administrator restrictions|Google Workspace administrator|Restricted Mode") { return 'restricted' }
    if ($t -match "Private video|Video unavailable|video is unavailable|video is not available|no longer available|has been removed|account associated with this video has been terminated|does not exist|Unsupported URL|is not a valid URL") { return 'gone' }
    return 'other'
}
function Get-FailureHint([string]$kind, [bool]$usedCookies) {
    switch ($kind) {
        'gone'    { return 'The video is private, removed, not available, or the link is not a video.' }
        'age'     { if ($usedCookies) { return "Your YouTube account isn't allowed to watch this one, or your saved sign-in is out of date (export a fresh cookies.txt, or sign in again in Firefox)." }
                    return 'It is age-restricted. See Help > "Age-restricted videos" to let the downloader use your YouTube sign-in.' }
        'members' { return "It is members-only: it needs the sign-in of an account that is a member of the channel." }
        'restricted' { return "YouTube Restricted Mode is switched on for this network or account (set by whoever manages the Wi-Fi, a parental filter, or a school/work account), and it hides this video. The downloader can't change that." }
        default   { return 'Try again later. If it keeps failing, click Help > "Check for updates now".' }
    }
}

# ---------- network check: why are secure connections being intercepted? (writes netcheck.txt) ----------
$NetCheckFile = Join-Path $Base 'netcheck.txt'
function Get-TlsCertInfo([string]$ip, [string]$sni) {
    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $tcp.BeginConnect($ip, 443, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne(5000)) { return 'could not connect (timeout)' }
        $tcp.EndConnect($iar)
        $script:ProbeCert = $null; $script:ProbeErr = ''
        # (arguments: sender, certificate, chain, errors) - only looks, never decides: the certificate is reported, not trusted
        $cb = [System.Net.Security.RemoteCertificateValidationCallback] { if ($args[1]) { $script:ProbeCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($args[1]) }; $script:ProbeErr = [string]$args[3]; return $true }
        $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, $cb)
        $ssl.ReadTimeout = 5000; $ssl.WriteTimeout = 5000
        $ssl.AuthenticateAsClient($sni)
        if (-not $script:ProbeCert) { return 'no certificate' }
        $c = $script:ProbeCert
        $ssl.Dispose()
        return ('issued to: {0}  |  issued by: {1}  |  Windows trusts it: {2}' -f $c.Subject, $c.Issuer, $(if ($script:ProbeErr -eq 'None') { 'yes' } else { "no ($($script:ProbeErr))" }))
    } catch { return 'TLS failed: ' + $_.Exception.Message } finally { $tcp.Close() }
}
function Invoke-NetCheck {
    $out = New-Object System.Collections.Generic.List[string]
    $out.Add(('Network check {0:yyyy-MM-dd HH:mm:ss}' -f (Get-Date)))
    try {
        foreach ($p in Get-NetConnectionProfile -ErrorAction Stop) { $out.Add("Connected network: $($p.Name) ($($p.InterfaceAlias), $($p.IPv4Connectivity))") }
        foreach ($c in Get-NetIPConfiguration -ErrorAction Stop | Where-Object { $_.IPv4DefaultGateway }) {
            $out.Add("Adapter: $($c.InterfaceAlias)  IP: $(@($c.IPv4Address.IPAddress) -join ',')  Gateway: $(@($c.IPv4DefaultGateway.NextHop) -join ',')  DNS: $(@($c.DNSServer | Where-Object { $_.AddressFamily -eq 2 } | ForEach-Object { $_.ServerAddresses }) -join ',')")
        }
    } catch { $out.Add('network info failed: ' + $_.Exception.Message) }
    try {
        $is = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        $out.Add("Windows proxy: enabled=$($is.ProxyEnable) server=$($is.ProxyServer) autoconfig=$($is.AutoConfigURL)")
    } catch { Write-Debug $_ }
    $ErrorActionPreference = 'Continue'
    $wh = (& netsh winhttp show proxy 2>$null | Out-String).Trim() -replace '\s+', ' '
    $out.Add("WinHTTP proxy: $wh")
    foreach ($v in 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY') { $x = [Environment]::GetEnvironmentVariable($v); if ($x) { $out.Add("env $v=$x") } }
    try {
        $hosts = @(Get-Content -LiteralPath (Join-Path $env:WINDIR 'System32\drivers\etc\hosts') -ErrorAction Stop | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') })
        $out.Add("hosts file entries: $($hosts.Count)"); foreach ($h in $hosts | Select-Object -First 20) { $out.Add("  $h") }
    } catch { Write-Debug $_ }
    $out.Add('')
    $out.Add('DNS + certificate per site (Wi-Fi DNS vs Cloudflare 1.1.1.1):')
    foreach ($name in 'www.youtube.com', 'youtubei.googleapis.com', 'redirector.googlevideo.com', 'i.ytimg.com', 'www.google.com', 'github.com', 'api.github.com', 'www.cloudflare.com') {
        $sys = @(); $cf = @()
        try { $sys = @(Resolve-DnsName -Name $name -Type A -DnsOnly -QuickTimeout -ErrorAction Stop | Where-Object { $_.Type -eq 'A' } | ForEach-Object { $_.IPAddress }) } catch { $sys = @('lookup failed: ' + $_.Exception.Message) }
        try { $cf = @(Resolve-DnsName -Name $name -Type A -DnsOnly -QuickTimeout -Server 1.1.1.1 -ErrorAction Stop | Where-Object { $_.Type -eq 'A' } | ForEach-Object { $_.IPAddress }) } catch { $cf = @('lookup failed') }
        $out.Add("$name")
        $out.Add("   Wi-Fi DNS : $($sys -join ', ')")
        $out.Add("   Cloudflare: $($cf -join ', ')")
        $ip = $sys | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
        if ($ip) { $out.Add("   cert via Wi-Fi DNS ($ip): " + (Get-TlsCertInfo $ip $name)) }
        $ip2 = $cf | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
        if ($ip2 -and $ip2 -ne $ip) { $out.Add("   cert via Cloudflare DNS ($ip2): " + (Get-TlsCertInfo $ip2 $name)) }
    }
    $out.Add('')
    $out.Add('Trusted root certificates added since 2023 (not from Windows Update):')
    foreach ($store in 'Cert:\LocalMachine\Root', 'Cert:\CurrentUser\Root') {
        try {
            foreach ($c in Get-ChildItem $store -ErrorAction Stop | Where-Object { $_.NotBefore -gt [datetime]'2023-01-01' }) {
                $out.Add(("   {0}: {1}  (from {2:yyyy-MM-dd}, thumbprint {3})" -f $store, $c.Subject, $c.NotBefore, $c.Thumbprint))
            }
        } catch { $out.Add("   $store unreadable") }
    }
    $ErrorActionPreference = 'Stop'
    try { [System.IO.File]::WriteAllLines($NetCheckFile, $out, (New-Object System.Text.UTF8Encoding($false))) } catch { Write-Debug $_ }
}


# ---------- Wi-Fi check: signal, driver, adapter settings, channel crowding, ping and speed (writes wificheck.txt) ----------
$WifiCheckFile = Join-Path $Base 'wificheck.txt'
function Invoke-WifiCheck {
    $o = New-Object System.Collections.Generic.List[string]
    $ErrorActionPreference = 'Continue'
    function Add-Section([string]$title, $text) { $o.Add(''); $o.Add("===== $title ====="); $o.Add(("$text").Trim()) }
    $o.Add(('Wi-Fi check {0:yyyy-MM-dd HH:mm:ss}' -f (Get-Date)))
    Add-Section 'Connection (netsh wlan show interfaces)' (& netsh wlan show interfaces 2>&1 | Out-String)
    Add-Section 'Driver (netsh wlan show drivers)' (& netsh wlan show drivers 2>&1 | Out-String)
    try { Add-Section 'Adapters' (Get-NetAdapter -Physical -ErrorAction Stop | Format-List Name, InterfaceDescription, Status, LinkSpeed, DriverVersionString, DriverDate, DriverProvider | Out-String -Width 200) } catch { Add-Section 'Adapters' $_.Exception.Message }
    $wifi = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.PhysicalMediaType -match '802.11' -or $_.Name -match 'Wi-?Fi|WLAN' } | Select-Object -First 1
    if ($wifi) {
        try { Add-Section "Advanced settings ($($wifi.Name))" (Get-NetAdapterAdvancedProperty -Name $wifi.Name -ErrorAction Stop | Format-Table DisplayName, DisplayValue -AutoSize | Out-String -Width 200) } catch { Add-Section 'Advanced settings' $_.Exception.Message }
        try { Add-Section 'Adapter power management' (Get-NetAdapterPowerManagement -Name $wifi.Name -ErrorAction Stop | Format-List AllowComputerToTurnOffDevice, DeviceSleepOnDisconnect, SelectiveSuspend | Out-String) } catch { Add-Section 'Adapter power management' $_.Exception.Message }
    }
    Add-Section 'Windows power plan: wireless adapter power saving' (& powercfg /query SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 2>&1 | Out-String)
    Add-Section 'Active power plan' (& powercfg /getactivescheme 2>&1 | Out-String)
    # channel crowding: count nearby access points per channel (names left out)
    $nets = & netsh wlan show networks mode=bssid 2>&1
    $chan = @{}; $cur = $null
    foreach ($l in $nets) {
        if ($l -match '^\s*Signal\s*:\s*(\d+)%') { $cur = [int]$Matches[1] }
        elseif ($l -match '^\s*Channel\s*:\s*(\d+)') { $c = [int]$Matches[1]; if (-not $chan.ContainsKey($c)) { $chan[$c] = @() }; $chan[$c] += $cur }
    }
    $lines = foreach ($c in ($chan.Keys | Sort-Object)) { $band = if ($c -le 14) { '2.4 GHz' } else { '5/6 GHz' }; "channel {0,3} ({1}): {2} access point(s), signals {3}" -f $c, $band, $chan[$c].Count, (($chan[$c] | ForEach-Object { "$_%" }) -join ' ') }
    Add-Section 'Nearby Wi-Fi channels' ($lines -join "`r`n")
    $gw = (Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1).IPv4DefaultGateway.NextHop
    if ($gw) { Add-Section "Ping router ($gw), 20 tries" ((& ping -n 20 $gw 2>&1 | Select-Object -Last 4) -join "`r`n") }
    Add-Section 'Ping internet (8.8.8.8), 20 tries' ((& ping -n 20 8.8.8.8 2>&1 | Select-Object -Last 4) -join "`r`n")
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $wc = New-Object System.Net.WebClient
        $data = $wc.DownloadData('https://speed.cloudflare.com/__down?bytes=25000000')
        $sw.Stop()
        Add-Section 'Speed test (25 MB from Cloudflare, discarded)' ('{0:N1} Mbit/s ({1:N1} MB in {2:N1} s)' -f ($data.Length * 8 / 1e6 / $sw.Elapsed.TotalSeconds), ($data.Length / 1MB), $sw.Elapsed.TotalSeconds)
    } catch { Add-Section 'Speed test' ('failed: ' + $_.Exception.Message) }
    $ErrorActionPreference = 'Stop'
    try { [System.IO.File]::WriteAllLines($WifiCheckFile, $o, (New-Object System.Text.UTF8Encoding($false))) } catch { Write-Debug $_ }
}

# ---------- your YouTube sign-in (cookies.txt), kept encrypted ----------
# Only used when a video won't download without it, and only ever for YouTube links.
# It is encrypted with Windows DPAPI, which ties it to your Windows account: a copied file is useless anywhere else.
# yt-dlp needs a plain file while it runs, so a short-lived copy is made in the private temp folder and removed right after.
$CookieVault   = Join-Path $Base 'cookies.dpapi'
$CookieEntropy = [System.Text.Encoding]::UTF8.GetBytes('VideoDownloader.cookies.v1')
$script:CookieTemps = New-Object System.Collections.Generic.List[string]
function Initialize-Dpapi { if (-not $script:DpapiReady) { Add-Type -AssemblyName System.Security; $script:DpapiReady = $true } }
function Write-CookieVault([byte[]]$plain) {
    Initialize-Dpapi
    $enc = [System.Security.Cryptography.ProtectedData]::Protect($plain, $CookieEntropy, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    $tmp = '{0}.{1}.tmp' -f $CookieVault, $PID
    [System.IO.File]::WriteAllBytes($tmp, $enc)
    Move-Item -LiteralPath $tmp -Destination $CookieVault -Force
}
function Get-PlainCookieFile {
    $dirs = @($Base); if ($PSScriptRoot) { $dirs += $PSScriptRoot }   # (empty when the function is loaded on its own, e.g. by Tests.ps1)
    foreach ($c in @($dirs | ForEach-Object { Join-Path $_ 'cookies.txt' })) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}
# a cookies.txt you just exported is moved into the encrypted store (and the plain file deleted)
function Protect-CookieFile {
    if ($env:OS -ne 'Windows_NT') { return }
    $dirs = @($Base); if ($PSScriptRoot) { $dirs += $PSScriptRoot }
    foreach ($c in @($dirs | ForEach-Object { Join-Path $_ 'cookies.txt' })) {
        if (-not (Test-Path -LiteralPath $c)) { continue }
        try {
            $b = [System.IO.File]::ReadAllBytes($c)
            if ($b.Length -gt 0) { Write-CookieVault $b }
            Remove-Item -LiteralPath $c -Force -ErrorAction Stop
            Say 'Your YouTube sign-in (cookies.txt) was moved into encrypted storage.' Green
        } catch { Write-Debug $_ }
    }
}
# Firefox keeps its cookies in a file yt-dlp can read directly (Chrome and Edge encrypt theirs so other programs can't)
$FirefoxCookies = 'browser:firefox'
function Test-FirefoxProfile { return [bool](Get-ChildItem -LiteralPath (Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles') -Filter 'cookies.sqlite' -Recurse -Depth 1 -File -ErrorAction SilentlyContinue | Select-Object -First 1) }
function Test-SignIn {
    if ([string]$S.CookieSource -eq 'firefox') { return (Test-FirefoxProfile) }
    return ((Test-Path -LiteralPath $CookieVault) -or [bool](Get-PlainCookieFile))
}
# the yt-dlp options for a sign-in from Open-SignIn
function Get-CookieArgumentList([string]$c) {
    if (-not $c) { return @() }
    if ($c -eq $FirefoxCookies) { return @('--cookies-from-browser', 'firefox') }
    return @('--cookies', $c)
}
function Test-YouTubeUrl([string]$u) { return $u -match '^https?://([A-Za-z0-9-]+\.)*(youtube\.com|youtu\.be|youtube-nocookie\.com)([/:?#]|$)' }
# a path yt-dlp can use, or $null when there is no saved sign-in
function Open-SignIn {
    if ([string]$S.CookieSource -eq 'firefox') { if (Test-FirefoxProfile) { return $FirefoxCookies } else { return $null } }
    Protect-CookieFile
    if (Test-Path -LiteralPath $CookieVault) {
        try {
            Initialize-Dpapi
            $plain = [System.Security.Cryptography.ProtectedData]::Unprotect([System.IO.File]::ReadAllBytes($CookieVault), $CookieEntropy, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
            $tmp = Join-Path $TempDir ('ck-{0}-{1}.txt' -f $PID, [guid]::NewGuid().ToString('N'))
            [System.IO.File]::WriteAllBytes($tmp, $plain)
            $script:CookieTemps.Add($tmp)
            return $tmp
        } catch { Say "Your saved YouTube sign-in couldn't be unlocked (it only opens on the Windows account that saved it). Export a fresh cookies.txt." Red }
    }
    return Get-PlainCookieFile
}
# yt-dlp refreshes the sign-in as it works, so the newest version is encrypted again before the plain copy is deleted
function Close-SignIn {
    foreach ($t in @($script:CookieTemps)) {
        try {
            if (Test-Path -LiteralPath $t) {
                $b = [System.IO.File]::ReadAllBytes($t)
                if ($b.Length -gt 0) { Write-CookieVault $b }
            }
        } catch { Write-Debug $_ }
        Remove-Item -LiteralPath $t -Force -ErrorAction SilentlyContinue
    }
    $script:CookieTemps.Clear()
}
# plain copies left behind by a downloader that was closed or crashed
function Clear-SignInLeftover {
    foreach ($f in Get-ChildItem -LiteralPath $TempDir -Filter 'ck-*.txt' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime) {
        if ($f.Name -match '^ck-(\d+)-' -and [int]$Matches[1] -ne $PID -and (Get-Process -Id ([int]$Matches[1]) -ErrorAction SilentlyContinue)) { continue }
        try { $b = [System.IO.File]::ReadAllBytes($f.FullName); if ($b.Length -gt 0 -and $env:OS -eq 'Windows_NT') { Write-CookieVault $b } } catch { Write-Debug $_ }
        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
    }
}

# ---------- new versions of Video Downloader itself (yt-dlp updates itself separately) ----------
# Once a day the window asks GitHub for the newest release's version number. Nothing about you or your downloads is sent.
$AppUpdateFile = Join-Path $Base 'app-update.json'
$ReleasesPage  = "https://github.com/$UpdateRepo/releases/latest"
function ConvertTo-Version([string]$t) {
    $t = $t.Trim().TrimStart('v', 'V')
    if ($t -notmatch '^\d+(\.\d+){0,3}$') { return $null }
    if ($t -notmatch '\.') { $t += '.0' }
    return [version]$t
}
function Invoke-AppUpdateCheck {
    $o = [ordered]@{ checked = (Get-Date).ToString('o'); latest = ''; url = $ReleasesPage }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $r = Invoke-RestMethod -Uri "https://api.github.com/repos/$UpdateRepo/releases/latest" -TimeoutSec 20 `
                -Headers @{ 'User-Agent' = 'VideoDownloader'; 'Accept' = 'application/vnd.github+json' }
        if (ConvertTo-Version ([string]$r.tag_name)) { $o.latest = ([string]$r.tag_name).TrimStart('v', 'V') }
        # only ever open this project's own release page
        if ([string]$r.html_url -match ('^https://github\.com/' + [regex]::Escape($UpdateRepo) + '/releases/tag/[A-Za-z0-9._-]+$')) { $o.url = [string]$r.html_url }
    } catch { Write-Debug $_ }
    try { [System.IO.File]::WriteAllText($AppUpdateFile, ($o | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding($false))) } catch { Write-Debug $_ }
}
# "Update now": download the newest release, check it against the release's SHA-256 list, install it quietly, reopen.
# Runs in its own hidden process, because the installer closes the Video Downloader window while it replaces the files.
function Invoke-AppUpdate {
    $work = Join-Path $TempDir ('update-' + [guid]::NewGuid().ToString('N'))
    $page = $ReleasesPage
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $hdr = @{ 'User-Agent' = 'VideoDownloader'; 'Accept' = 'application/vnd.github+json' }
        $r = Invoke-RestMethod -Uri "https://api.github.com/repos/$UpdateRepo/releases/latest" -Headers $hdr -TimeoutSec 30
        if ([string]$r.html_url -match ('^https://github\.com/' + [regex]::Escape($UpdateRepo) + '/releases/tag/[A-Za-z0-9._-]+$')) { $page = [string]$r.html_url }
        $new = ConvertTo-Version ([string]$r.tag_name)
        if (-not $new -or $new -le (ConvertTo-Version $AppVersion)) { Show-ErrorBox "You already have the newest version ($AppVersion)." -icon 'Information'; return }
        $dlPrefix = 'https://github.com/' + $UpdateRepo + '/releases/download/'
        $zipA = @($r.assets | Where-Object { $_.name -match '^VideoDownloader-[0-9.]+\.zip$' }) | Select-Object -First 1
        $sumA = @($r.assets | Where-Object { $_.name -eq 'SHA256SUMS.txt' }) | Select-Object -First 1
        if (-not $zipA -or -not $sumA -or -not ([string]$zipA.browser_download_url).StartsWith($dlPrefix) -or -not ([string]$sumA.browser_download_url).StartsWith($dlPrefix)) {
            throw 'This release has no installer ZIP with a checksum list yet.'
        }
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $zip = Join-Path $work $zipA.name; $sums = Join-Path $work 'SHA256SUMS.txt'
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $zipA.browser_download_url -OutFile $zip -UseBasicParsing -Headers @{ 'User-Agent' = 'VideoDownloader' } -TimeoutSec 300
        Invoke-WebRequest -Uri $sumA.browser_download_url -OutFile $sums -UseBasicParsing -Headers @{ 'User-Agent' = 'VideoDownloader' } -TimeoutSec 60
        $want = ''
        foreach ($l in Get-Content -LiteralPath $sums) { if ($l -match ('^([0-9A-Fa-f]{64})\s+\*?' + [regex]::Escape($zipA.name) + '\s*$')) { $want = $Matches[1] } }
        $got = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
        if (-not $want -or $got -ne $want.ToUpper()) { throw 'The download did not match its published checksum, so it was not installed.' }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, (Join-Path $work 'x'))
        $inst = Get-ChildItem -LiteralPath (Join-Path $work 'x') -Filter 'Install.ps1' -File -Recurse | Select-Object -First 1
        if (-not $inst) { throw 'The download has no Install.ps1.' }
        $ps = Join-Path $PSHOME 'powershell.exe'
        $p = Start-Process -FilePath $ps -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -Quiet' -f $inst.FullName) -WindowStyle Hidden -Wait -PassThru
        if ($p.ExitCode -ne 0) { throw "The installer stopped with code $($p.ExitCode)." }
        Write-DownloadLog ("UPDATE installed version {0}" -f $new)
        Invoke-Hidden @('-App')
    } catch {
        try { Add-Content -LiteralPath $ErrorLog -Value ("{0:yyyy-MM-dd HH:mm:ss}  update failed: {1}" -f (Get-Date), $_.Exception.Message) -Encoding UTF8 } catch { Write-Debug $_ }
        Show-ErrorBox ("Video Downloader couldn't update itself:`n`n{0}`n`nThe download page will open so you can update by hand." -f $_.Exception.Message)
        try { Start-Process $page } catch { Write-Debug $_ }
    } finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
function Test-AppUpdateDue {
    if (-not [bool]$S.CheckAppUpdates -or $env:OS -ne 'Windows_NT') { return $false }
    if (-not (Test-Path -LiteralPath $AppUpdateFile)) { return $true }
    return ((Get-Date) - (Get-Item -LiteralPath $AppUpdateFile).LastWriteTime).TotalHours -ge 24
}
# the newer release the last check found, or $null
function Get-AppUpdate {
    if (-not [bool]$S.CheckAppUpdates -or -not (Test-Path -LiteralPath $AppUpdateFile)) { return $null }
    try {
        $j = Get-Content -LiteralPath $AppUpdateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $new = ConvertTo-Version ([string]$j.latest); $cur = ConvertTo-Version $AppVersion
        if ($new -and $cur -and $new -gt $cur) { return $j }
    } catch { Write-Debug $_ }
    return $null
}

# ---------- privacy: a private data folder, short logs, old reports removed ----------
function Limit-File([string]$path, [long]$max, [int]$keep) {
    try {
        if (-not (Test-Path -LiteralPath $path)) { return }
        if ((Get-Item -LiteralPath $path).Length -le $max) { return }
        $lines = [System.IO.File]::ReadAllLines($path)
        if ($lines.Count -gt $keep) { [System.IO.File]::WriteAllLines($path, [string[]]$lines[($lines.Count - $keep)..($lines.Count - 1)], (New-Object System.Text.UTF8Encoding($false))) }
    } catch { Write-Debug $_ }
}
function Limit-PrivateData {
    Limit-File -path $RunnerLog -max 1MB -keep 3000
    Limit-File -path $LogFile -max 2MB -keep 5000
    Limit-File -path $ErrorLog -max 256KB -keep 500
    Limit-File -path (Join-Path $Base 'runs.log') -max 256KB -keep 1000
    # network/Wi-Fi reports describe your network and PC: they are only kept for 30 days
    Get-ChildItem -LiteralPath $Base -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^(netcheck|wificheck|connection-check).*\.txt$' -and $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
}

# iCloud Drive / OneDrive briefly lock new files while they upload, so move and delete with a few retries
function Move-Safely([string]$from, [string]$to) {
    for ($i = 0; $i -lt 20; $i++) {
        try { Move-Item -LiteralPath $from -Destination $to -Force -ErrorAction Stop; return $true } catch { Start-Sleep -Seconds 1 }
    }
    Say "Couldn't move the file into place (something has it open). It's still here: $from" Red
    return $false
}
function Clear-PathSafely([string]$path) {
    for ($i = 0; $i -lt 10; $i++) {
        try { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -Recurse -ErrorAction Stop }; return } catch { Start-Sleep -Seconds 1 }
    }
}

function Invoke-Shrink([string]$src) {
    $crf = @{ smaller = @(36, 28); balanced = @(30, 24); better = @(25, 21) }[[string]$S.ShrinkQuality]
    if (-not $crf) { $crf = @(30, 24) }
    $enc = @('-c:v', 'libx265', '-crf', "$($crf[1])", '-preset', 'medium', '-tag:v', 'hvc1')
    $ErrorActionPreference = 'Continue'
    $list = & $script:FFmpeg -hide_banner -encoders 2>$null
    $ErrorActionPreference = 'Stop'
    if ($list -match 'libsvtav1') { $enc = @('-c:v', 'libsvtav1', '-preset', '8', '-crf', "$($crf[0])") }
    $dest = Join-Path $VideoDir (([IO.Path]::GetFileNameWithoutExtension($src)) + ' (small).mp4')
    Say 'Shrinking (this can take a while)...' Yellow
    Write-Status @{ phase = 'shrinking' } -Force
    $code = Invoke-Native $script:FFmpeg (@('-hide_banner', '-loglevel', 'error', '-stats', '-n', '-i', $src) + $enc + @('-c:a', 'copy', '-movflags', '+faststart', $dest))
    if ($code -eq 0 -and (Test-Path -LiteralPath $dest)) {
        $before = (Get-Item -LiteralPath $src).Length; $after = (Get-Item -LiteralPath $dest).Length
        Say ("Shrunk {0:N0} MB -> {1:N0} MB" -f ($before / 1MB), ($after / 1MB)) Green
        Clear-PathSafely $src
        return $dest
    }
    Say 'Shrink failed - keeping the original instead.' Red
    $keep = Join-Path $VideoDir (Split-Path -Leaf $src)
    if (Move-Safely $src $keep) { return $keep } else { return $src }
}

# Make sure a phone download really is H.264 video + AAC audio with the index at the front (instant playback);
# YouTube files are just remuxed in seconds, other sites' VP9/AV1/Opus files get re-encoded.
function Get-Codec([string]$file, [string]$kind) {
    if (-not $script:FFprobe) { return '' }
    $sel = $kind + ':0'
    $ErrorActionPreference = 'Continue'   # Windows PowerShell 5.1 turns any stderr text into a fatal error under 'Stop'
    $r = & $script:FFprobe -v error -select_streams $sel -show_entries stream=codec_name -of csv=p=0 $file 2>$null
    return ("$r").Trim()
}
function Convert-ForPhone([string]$src) {
    if (-not $script:FFmpeg -or -not $script:FFprobe) { return $src }
    Write-Status @{ phase = 'converting' } -Force
    $v = Get-Codec $src 'V'; $au = Get-Codec $src 'a'
    $vArgs = @('-c:v', 'copy')
    if ($v -and $v -ne 'h264') {
        $vArgs = @('-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23', '-profile:v', 'high', '-pix_fmt', 'yuv420p', '-vf', "scale=-2:'min($PhoneHeight,ih)'")
    }
    $aArgs = @('-c:a', 'copy')
    if ($au -and $au -ne 'aac') { $aArgs = @('-c:a', 'aac', '-b:a', '160k') }
    if ($vArgs[1] -ne 'copy' -or $aArgs[1] -ne 'copy') { Say "Converting to a phone-friendly format (was $v / $au)..." Yellow }
    if (-not (Test-Path -LiteralPath $PhoneDir)) { New-Item -ItemType Directory -Path $PhoneDir -Force | Out-Null }
    $final = Join-Path $PhoneDir ([IO.Path]::GetFileNameWithoutExtension($src) + '.mp4')
    $tmp = Join-Path (Split-Path -Parent $src) ('phone-{0}.mp4' -f (Get-Random))
    $code = Invoke-Native $script:FFmpeg (@('-hide_banner', '-loglevel', 'error', '-stats', '-y', '-i', $src, '-map', '0:V:0', '-map', '0:a:0?', '-map', '0:s?') + $vArgs + $aArgs + @('-c:s', 'mov_text', '-movflags', '+faststart', $tmp))
    if ($code -eq 0 -and (Test-Path -LiteralPath $tmp)) {
        if (Move-Safely $tmp $final) {
            Say ("Phone-ready: {0:N0} MB, H.264/AAC" -f ((Get-Item -LiteralPath $final).Length / 1MB)) Green
            return $final
        }
        return $tmp
    }
    Say 'Could not make a phone copy - saving the file as downloaded.' Red
    if (Move-Safely $src $final) { return $final }
    return $src
}

$ModeNames = [ordered]@{ video = 'Video'; phone = 'Phone'; best = 'Best quality'; edit = 'Editor-friendly'; audio = 'Audio'; clip = 'Clip'; playlist = 'Playlist'; shrink = 'Shrink' }

function Invoke-Job($job) {
    if ([string]$job.Mode -eq 'wificheck') {
        if ($env:OS -eq 'Windows_NT') { try { Invoke-WifiCheck } catch { Write-Debug $_ } }
        Complete-Job $job
        return
    }
    if ([string]$job.Mode -eq 'netcheck') {   # a network check queued on purpose (not a download)
        if ($env:OS -eq 'Windows_NT') { try { Invoke-NetCheck } catch { Write-Debug $_ } }
        Complete-Job $job
        return
    }
    $label = @{ video = "Video (up to ${MaxHeight}p)"; best = 'Best quality'; edit = 'Editor-friendly (H.264)'; audio = "Audio ($($AudioFormat.ToUpper()))";
                phone = "Phone (${PhoneHeight}p H.264)"; clip = 'Clip'; playlist = 'Whole playlist'; shrink = 'Shrink (re-encode)' }[$job.Mode]
    if ($job.Mode -eq 'clip') { $label += ' ' + (Format-Clock $job.Start) + ' to ' + (Format-Clock $job.End) }
    $left = Get-QueueCount
    try { $Host.UI.RawUI.WindowTitle = 'Video Downloader' + $(if ($left) { " ($left more queued)" } else { '' }) } catch { Write-Debug $_ }
    Say ("`n=== {0} ===" -f $label) Cyan
    Say $job.Url DarkGray
    Write-Status @{ state = 'downloading'; url = [string]$job.Url; mode = [string]$job.Mode; title = ''; percent = 0; speed = ''; eta = ''; phase = 'starting'; message = ''; queued = $left } -Force

    $listFile = Join-Path $TempDir ('done-{0}.txt' -f (Get-Random))
    # shrink and phone jobs download into a private work folder first; only the finished file goes to its final folder
    $workDir = $null
    if ($job.Mode -in 'shrink', 'phone') { $workDir = Join-Path $TempDir ('work-{0}' -f (Get-Random)); New-Item -ItemType Directory -Path $workDir | Out-Null }

    $cookies = if ([string]$S.UseCookies -ne 'never' -and (Test-YouTubeUrl ([string]$job.Url))) { Open-SignIn } else { $null }
    $first = if ([string]$S.UseCookies -eq 'always') { $cookies } else { $null }
    $usedCookies = [bool]$first
    $code = Invoke-YtDlp -job $job -listFile $listFile -dirOverride $workDir -cookieFile $first
    $kind = if ($code -ne 0) { Get-FailureKind } else { '' }
    if ($code -ne 0 -and $kind -eq 'other' -and -not $script:UpdatedThisRun) {
        Say 'Download failed. YouTube changes often - updating yt-dlp and trying once more...' Yellow
        Invoke-ToolUpdate
        Write-Status @{ state = 'downloading'; phase = 'starting'; message = '' } -Force
        $code = Invoke-YtDlp -job $job -listFile $listFile -dirOverride $workDir -cookieFile $first
        $kind = if ($code -ne 0) { Get-FailureKind } else { '' }
    }
    if ($code -ne 0 -and $kind -notin 'gone', 'restricted', 'offline', 'intercepted', 'blocked' -and $cookies -and -not $usedCookies) {
        Say 'Trying again signed in to YouTube...' Yellow
        $usedCookies = $true
        $code = Invoke-YtDlp -job $job -listFile $listFile -dirOverride $workDir -cookieFile $cookies
        $kind = if ($code -ne 0) { Get-FailureKind } else { '' }
    }

    $files = @()
    if (Test-Path -LiteralPath $listFile) {
        $files = @(Get-Content -LiteralPath $listFile -Encoding UTF8 | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
        Remove-Item -LiteralPath $listFile -Force -ErrorAction SilentlyContinue
    }
    if ($job.Mode -eq 'phone') { $files = @($files | ForEach-Object { Convert-ForPhone $_ }) }
    if ($job.Mode -eq 'shrink') { $files = @($files | ForEach-Object { Invoke-Shrink $_ }) }
    if ($workDir) { Clear-PathSafely $workDir }
    $title = [string]$script:Status['title']
    if (-not $title -and $files.Count) { $title = [IO.Path]::GetFileNameWithoutExtension($files[0]) }

    if ($code -eq 0 -or ($job.Mode -eq 'playlist' -and $files.Count)) {
        if ($files.Count -eq 0) { Say 'Already downloaded - nothing new.' Green }
        foreach ($f in $files) { $script:Done.Add($f); Say ('Saved: ' + $f) Green }
        Write-DownloadLog ("OK    {0,-8} {1}  ->  {2}" -f $job.Mode, $job.Url, ($files -join ' | '))
        Write-History @{ ok = $true; url = [string]$job.Url; mode = [string]$job.Mode; title = $title; files = @($files) }
        Complete-Job $job
        return
    }

    $why = ($script:LastErrors | Select-Object -Last 1)
    if (-not $why) { $why = "yt-dlp stopped with exit code $code" }
    Write-DownloadLog ("FAIL  {0,-8} {1}  ({2})" -f $job.Mode, $job.Url, $why)
    if ($kind -in 'offline', 'blocked', 'intercepted') {
        # nothing is wrong with the video: keep it (and everything after it) in the queue for later
        $script:Blocked = $true
        $script:BlockKind = $kind
        Restore-Job $job
        if ($kind -eq 'intercepted') {
            # find out where the fake certificate comes from (at most every 20 minutes)
            if ($env:OS -eq 'Windows_NT' -and (-not (Test-Path -LiteralPath $NetCheckFile) -or (Get-Item -LiteralPath $NetCheckFile).LastWriteTime -lt (Get-Date).AddMinutes(-20))) {
                try { Invoke-NetCheck } catch { Write-Debug $_ }
            }
            $msg = "Your network is intercepting secure connections (it answered with its own self-signed certificate), so YouTube can't be reached safely. This usually comes from a router, ISP or Wi-Fi filter, or security software. Nothing is lost - it carries on when the connection is normal again."
        } elseif ($kind -eq 'offline') {
            $msg = "The internet connection dropped or isn't fully working (Wi-Fi reconnecting, a sign-in page, or a VPN). Nothing is lost - it continues when you press Resume or start another download."
        } else {
            $msg = 'YouTube is temporarily blocking downloads from your connection (too many downloads in a short time, or a VPN). Turn off any VPN, wait about an hour, then press Resume - your queue is saved.'
        }
        Say $msg Red
        Write-Status @{ state = $kind; message = $msg } -Force
        return
    }
    $hint = Get-FailureHint $kind $usedCookies
    $script:Failed.Add($job.Url)
    Write-History @{ ok = $false; url = [string]$job.Url; mode = [string]$job.Mode; title = $title; error = $why; hint = $hint; kind = $kind }
    Complete-Job $job
    Say "FAILED: $why" Red
    Say $hint Yellow
}

# Work through the queue if no other downloader is already doing it. Returns $false if another one owns it.
function Invoke-Queue {
    $script:Blocked = $false
    $script:Mutex = New-Object System.Threading.Mutex($false, 'Local\VideoDownloaderRunner')
    while ($true) {
        $owned = $false
        try { $owned = $script:Mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $owned = $true }
        if (-not $owned) { return $false }
        $script:IsRunner = $true
        try {
            Restore-Interrupted
            Clear-SignInLeftover
            Clear-OldTemp
            if (Test-UpdateDue) { Invoke-ToolUpdate }
            while (-not $script:Blocked -and ($job = Get-NextJob)) { try { Invoke-Job $job } finally { Close-SignIn } }
            if (-not $script:Blocked) { Write-Status @{ state = 'idle'; phase = ''; percent = 0; childPid = 0; message = '' } -Force }
        } finally { $script:Mutex.ReleaseMutex() }
        if ($script:Blocked) {
            $left = Get-QueueCount
            if ($left) { Say ("{0} download(s) are waiting in the queue for later." -f $left) Yellow }
            return $true
        }
        if ((Get-QueueCount) -eq 0) { return $true }   # a job may have arrived while we were finishing
    }
}

function Show-Toast([string]$title, [string]$text) {
    try {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
        $ni = New-Object System.Windows.Forms.NotifyIcon
        $ico = Join-Path $PSScriptRoot 'VideoDownloader.ico'
        $ni.Icon = if (Test-Path -LiteralPath $ico) { New-Object System.Drawing.Icon($ico) } else { [System.Drawing.SystemIcons]::Information }
        $ni.Visible = $true
        $ni.ShowBalloonTip(5000, $title, $text, [System.Windows.Forms.ToolTipIcon]::Info)
        Start-Sleep -Seconds 5
        $ni.Dispose()
    } catch { Write-Debug $_ }
}

function Show-Finished {
    $n = $script:Done.Count
    $nf = $script:Failed.Count
    if ($n -eq 0 -and $nf -eq 0) { return }
    if ($ShowInFolder -and $n) {
        try { Start-Process explorer.exe -ArgumentList ('/select,"{0}"' -f $script:Done[$n - 1]) } catch { Write-Debug $_ }
    }
    if ($Notify -and $env:OS -eq 'Windows_NT') {
        if ($nf) { Show-Toast ("{0} download(s) failed" -f $nf) 'Open Video Downloader to see why.' }
        elseif ($n -eq 1) { Show-Toast 'Download finished' ([IO.Path]::GetFileName($script:Done[0])) }
        else { Show-Toast "$n downloads finished" ([IO.Path]::GetFileName($script:Done[$n - 1])) }
    }
    $script:Done.Clear()
}

function Invoke-QueueHere {   # (text version) download right here in this window
    $ran = Invoke-Queue
    if (-not $ran) {
        Say ("Added - the downloader that is already running will get it ({0} waiting). Open Video Downloader to watch." -f (Get-QueueCount)) Green
        return $false
    }
    Show-Finished
    return $true
}

function Open-Folder([string]$dir) {
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    try { Start-Process explorer.exe $dir } catch { Write-Debug $_ }
}

# ============================== SETTINGS SCREEN ==============================
$SettingTabs = @('General', 'Video', 'Phone', 'Audio', 'Extras', 'Network')
$SettingDefs = @(
    # General
    @{ Tab = 'General'; Key = 'MenuDefault';   Label = 'Default download type';    Kind = 'choice'; Choices = @('video', 'phone', 'best', 'edit', 'audio')
       Names = @{ 'video' = 'Video'; 'phone' = 'Phone'; 'best' = 'Best quality'; 'edit' = 'Editor-friendly'; 'audio' = 'Audio only' } }
    @{ Tab = 'General'; Key = 'NameStyle';     Label = 'File names';               Kind = 'choice'; Choices = @('title-id', 'title', 'channel-title', 'date-title')
       Names = @{ 'title-id' = 'Title [id].mp4'; 'title' = 'Title.mp4'; 'channel-title' = 'Channel - Title.mp4'; 'date-title' = '2026-01-31 - Title.mp4 (upload date)' } }
    @{ Tab = 'General'; Key = 'OpenAppOnDownload'; Label = 'Show this window when a download starts'; Kind = 'bool' }
    @{ Tab = 'General'; Key = 'CloseWhenDone'; Label = '...and close it when all went well'; Kind = 'bool' }
    @{ Tab = 'General'; Key = 'Notify';        Label = 'Notification when done';   Kind = 'bool' }
    @{ Tab = 'General'; Key = 'ShowInFolder';  Label = 'Show file in Explorer when done'; Kind = 'bool' }
    @{ Tab = 'General'; Key = 'AutoUpdateDays'; Label = 'Auto-update yt-dlp';      Kind = 'choice'; Choices = @(7, 30, 0)
       Names = @{ '7' = 'Weekly'; '30' = 'Monthly'; '0' = 'Never' } }
    @{ Tab = 'General'; Key = 'CheckAppUpdates'; Label = 'Tell me about new versions'; Kind = 'bool' }
    # Video
    @{ Tab = 'Video'; Key = 'VideoFolder';     Label = 'Save videos to';           Kind = 'folder' }
    @{ Tab = 'Video'; Key = 'MaxHeight';       Label = 'Video / clip / playlist quality'; Kind = 'choice'; Choices = @(480, 720, 1080, 1440, 2160)
       Names = @{ '480' = '480p'; '720' = '720p'; '1080' = '1080p'; '1440' = '1440p'; '2160' = '4K (2160p)' } }
    @{ Tab = 'Video'; Key = 'BestHeight';      Label = 'Best quality limit';       Kind = 'choice'; Choices = @(0, 2160, 1440)
       Names = @{ '0' = 'No limit (up to 8K)'; '2160' = '4K (2160p)'; '1440' = '1440p' } }
    @{ Tab = 'Video'; Key = 'EditHeight';      Label = 'Editor-friendly quality';  Kind = 'choice'; Choices = @(720, 1080)
       Names = @{ '720' = '720p'; '1080' = '1080p (H.264 tops out here on YouTube)' } }
    @{ Tab = 'Video'; Key = 'VideoCodec';      Label = 'Preferred video format';   Kind = 'choice'; Choices = @('av1', 'vp9', 'h264')
       Names = @{ 'av1' = 'AV1 (smallest files)'; 'vp9' = 'VP9'; 'h264' = 'H.264 (plays on anything, bigger)' } }
    @{ Tab = 'Video'; Key = 'MaxFps';          Label = 'Frame rate';               Kind = 'choice'; Choices = @(0, 60, 30)
       Names = @{ '0' = 'Same as the video'; '60' = 'Up to 60 fps'; '30' = 'Up to 30 fps (smaller)' } }
    @{ Tab = 'Video'; Key = 'Container';       Label = 'File type';                Kind = 'choice'; Choices = @('mp4', 'mkv')
       Names = @{ 'mp4' = 'MP4 (works everywhere)'; 'mkv' = 'MKV' } }
    @{ Tab = 'Video'; Key = 'EmbedChapters';   Label = 'Add chapters';             Kind = 'bool' }
    @{ Tab = 'Video'; Key = 'EmbedThumbnail';  Label = 'Add thumbnail as cover';   Kind = 'bool' }
    # Phone
    @{ Tab = 'Phone'; Key = 'PhoneFolder';     Label = 'Save phone videos to';     Kind = 'folder' }
    @{ Tab = 'Phone'; Key = 'PhoneHeight';     Label = 'Phone quality';            Kind = 'choice'; Choices = @(480, 720, 1080)
       Names = @{ '480' = '480p (smallest files)'; '720' = '720p (recommended)'; '1080' = '1080p (sharpest)' } }
    @{ Tab = 'Phone'; Key = 'PhoneMaxFps';     Label = 'Phone frame rate';         Kind = 'choice'; Choices = @(0, 30)
       Names = @{ '0' = 'Same as the video'; '30' = 'Up to 30 fps (smaller)' } }
    # Audio
    @{ Tab = 'Audio'; Key = 'AudioFolder';     Label = 'Save audio to';            Kind = 'folder' }
    @{ Tab = 'Audio'; Key = 'AudioFormat';     Label = 'Audio format';             Kind = 'choice'; Choices = @('m4a', 'mp3', 'opus', 'flac', 'wav')
       Names = @{ 'm4a' = 'M4A (no quality loss, Apple-friendly)'; 'mp3' = 'MP3 (plays on everything)'; 'opus' = 'Opus (small)'; 'flac' = 'FLAC (lossless copy, big)'; 'wav' = 'WAV (for editing, huge)' } }
    @{ Tab = 'Audio'; Key = 'AudioQuality';    Label = 'MP3 / Opus quality';       Kind = 'choice'; Choices = @('best', '256', '192', '128')
       Names = @{ 'best' = 'Best'; '256' = '256 kbps'; '192' = '192 kbps'; '128' = '128 kbps (smallest)' } }
    @{ Tab = 'Audio'; Key = 'AudioCover';      Label = 'Add cover art';            Kind = 'bool' }
    # Extras
    @{ Tab = 'Extras'; Key = 'SubtitleMode';   Label = 'Subtitles';                Kind = 'choice'; Choices = @('off', 'embed', 'file')
       Names = @{ 'off' = 'None'; 'embed' = 'Inside the video'; 'file' = 'Separate .srt file' } }
    @{ Tab = 'Extras'; Key = 'SubtitleLangs';  Label = 'Subtitle languages';       Kind = 'choice'; Choices = @('en', 'all')
       Names = @{ 'en' = 'English'; 'all' = 'All languages' } }
    @{ Tab = 'Extras'; Key = 'AutoSubtitles';  Label = 'Include auto-generated subtitles'; Kind = 'bool' }
    @{ Tab = 'Extras'; Key = 'SponsorBlock';   Label = 'Sponsor segments';         Kind = 'choice'; Choices = @('off', 'mark', 'remove')
       Names = @{ 'off' = 'Leave alone'; 'mark' = 'Mark them as chapters'; 'remove' = 'Cut them out' } }
    @{ Tab = 'Extras'; Key = 'ClipAccurate';   Label = 'Exact clip start/end (slower)'; Kind = 'bool' }
    @{ Tab = 'Extras'; Key = 'ShrinkQuality';  Label = 'Shrink mode';              Kind = 'choice'; Choices = @('smaller', 'balanced', 'better')
       Names = @{ 'smaller' = 'Smallest file'; 'balanced' = 'Balanced'; 'better' = 'Better quality' } }
    @{ Tab = 'Extras'; Key = 'PlaylistFolders'; Label = 'Playlists get their own folder'; Kind = 'bool' }
    # Network
    @{ Tab = 'Network'; Key = 'Fragments';     Label = 'Parallel download pieces'; Kind = 'choice'; Choices = @(1, 4, 8)
       Names = @{ '1' = '1 (gentlest)'; '4' = '4 (recommended)'; '8' = '8 (fastest)' } }
    @{ Tab = 'Network'; Key = 'SpeedLimit';    Label = 'Speed limit';              Kind = 'choice'; Choices = @(0, 10, 5, 2, 1)
       Names = @{ '0' = 'No limit'; '10' = '10 MB/s'; '5' = '5 MB/s'; '2' = '2 MB/s'; '1' = '1 MB/s' } }
    @{ Tab = 'Network'; Key = 'UseCookies';    Label = 'Use your YouTube sign-in'; Kind = 'choice'; Choices = @('auto', 'always', 'never')
       Names = @{ 'auto' = 'Only when a video needs it (recommended)'; 'always' = 'Always'; 'never' = 'Never' } }
    @{ Tab = 'Network'; Key = 'CookieSource';  Label = 'Where your sign-in comes from'; Kind = 'choice'; Choices = @('file', 'firefox')
       Names = @{ 'file' = 'A cookies.txt file (see Help)'; 'firefox' = 'Firefox (just stay signed in to YouTube there)' } }
)

function Format-Setting($def, $v) {
    if ($def.Kind -eq 'bool') { if ($v) { return 'On' } else { return 'Off' } }
    if ($def.Names -and $def.Names.ContainsKey("$v")) { return $def.Names["$v"] }
    return "$v"
}

function Show-FolderDialog([string]$current, [string]$title, $owner = $null) {
    Add-Type -AssemblyName System.Windows.Forms
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = $title
    $d.ShowNewFolderButton = $true
    if ($current -and (Test-Path -LiteralPath $current)) { $d.SelectedPath = $current }
    if (-not $owner) {   # invisible always-on-top owner, so the picker opens in front of the browser
        $owner = New-Object System.Windows.Forms.Form
        $owner.TopMost = $true; $owner.ShowInTaskbar = $false; $owner.Opacity = 0
        $owner.StartPosition = 'CenterScreen'; $owner.Size = [System.Drawing.Size]::new(1, 1)
        $owner.Show(); $owner.Activate()
        try { $r = $d.ShowDialog($owner) } finally { $owner.Close() }
    } else { $r = $d.ShowDialog($owner) }
    if ($r -eq [System.Windows.Forms.DialogResult]::OK) { return $d.SelectedPath }
    return $null
}
function Select-Folder([string]$current, [string]$title) {
    if ($env:OS -eq 'Windows_NT') { try { return Show-FolderDialog $current $title } catch { Write-Debug $_ } }
    $t = Read-Host 'Type a folder path (Enter = keep the current one)'
    if ($t) { return $t.Trim().Trim('"') }
    return $null
}

function Show-SettingsConsole {
    while ($true) {
        Write-Host "`n================ SETTINGS ================" -ForegroundColor Cyan
        $lastTab = ''
        for ($i = 0; $i -lt $SettingDefs.Count; $i++) {
            $d = $SettingDefs[$i]
            if ($d.Tab -ne $lastTab) { Write-Host ("`n  " + $d.Tab.ToUpper()) -ForegroundColor Cyan; $lastTab = $d.Tab }
            Write-Host ('  {0,2}. ' -f ($i + 1)) -NoNewline -ForegroundColor DarkGray
            Write-Host ('{0,-40}' -f $d.Label) -NoNewline
            Write-Host (Format-Setting $d $S[$d.Key]) -ForegroundColor Yellow
        }
        Write-Host '   R. Reset everything to defaults        Enter = done' -ForegroundColor DarkGray
        $c = "$(Read-Host 'Number to change')".Trim()
        if (-not $c) { return }
        if ($c -match '^[rR]$') {
            if ("$(Read-Host 'Reset all settings? (y/n)')" -match '^[yY]') { $script:S = [ordered]@{}; foreach ($k in $Defaults.Keys) { $script:S[$k] = $Defaults[$k] }; Save-Config; Use-Config }
            continue
        }
        $n = 0
        if (-not [int]::TryParse($c, [ref]$n) -or $n -lt 1 -or $n -gt $SettingDefs.Count) { Write-Host 'Type a number from the list.' -ForegroundColor Red; continue }
        $d = $SettingDefs[$n - 1]
        switch ($d.Kind) {
            'bool'   { $S[$d.Key] = -not [bool]$S[$d.Key] }
            'folder' { $f = Select-Folder ([string]$S[$d.Key]) $d.Label; if ($f) { $S[$d.Key] = $f } }
            'choice' {
                $idx = -1
                for ($k = 0; $k -lt $d.Choices.Count; $k++) { if ("$($d.Choices[$k])" -eq "$($S[$d.Key])") { $idx = $k } }
                $S[$d.Key] = $d.Choices[($idx + 1) % $d.Choices.Count]
            }
        }
        Save-Config; Use-Config
    }
}

function Write-SettingControl($def, $ctl, $value) {
    switch ($def.Kind) {
        'folder' { $ctl.Text = [string]$value }
        'bool'   { $ctl.Checked = [bool]$value }
        'choice' {
            $ctl.SelectedIndex = 0
            for ($k = 0; $k -lt $def.Choices.Count; $k++) { if ("$($def.Choices[$k])" -eq "$value") { $ctl.SelectedIndex = $k } }
        }
    }
}

function Show-SettingsWindow($ownerForm = $null) {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $form = New-Object System.Windows.Forms.Form
    $form.SuspendLayout()
    $form.AutoScaleDimensions = [System.Drawing.SizeF]::new(96, 96)
    $form.AutoScaleMode = 'Dpi'
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9.75)
    $form.Text = 'Video Downloader - Settings'
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false; $form.MinimizeBox = $false
    if (-not $ownerForm) { $form.TopMost = $true }
    $ico = Join-Path $PSScriptRoot 'VideoDownloader.ico'
    if (Test-Path -LiteralPath $ico) { try { $form.Icon = New-Object System.Drawing.Icon($ico) } catch { Write-Debug $_ } }

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Location = [System.Drawing.Point]::new(12, 12)
    $form.Controls.Add($tabs)

    $controls = @{}
    $rowsMax = 0
    foreach ($tabName in $SettingTabs) {
        $page = New-Object System.Windows.Forms.TabPage
        $page.Text = $tabName
        $page.UseVisualStyleBackColor = $true
        [void]$tabs.TabPages.Add($page)
        $y = 14; $rows = 0
        foreach ($d in ($SettingDefs | Where-Object { $_.Tab -eq $tabName })) {
            $lbl = New-Object System.Windows.Forms.Label
            $lbl.Text = $d.Label
            $lbl.Location = [System.Drawing.Point]::new(12, $y + 4)
            $lbl.Size = [System.Drawing.Size]::new(250, 22)
            $page.Controls.Add($lbl)
            switch ($d.Kind) {
                'folder' {
                    $tb = New-Object System.Windows.Forms.TextBox
                    $tb.Location = [System.Drawing.Point]::new(266, $y)
                    $tb.Size = [System.Drawing.Size]::new(290, 26)
                    $page.Controls.Add($tb)
                    $btn = New-Object System.Windows.Forms.Button
                    $btn.Text = 'Browse...'
                    $btn.Location = [System.Drawing.Point]::new(562, $y - 1)
                    $btn.Size = [System.Drawing.Size]::new(90, 28)
                    $btn.Tag = $tb
                    $btn.Add_Click({
                        $box = $this.Tag
                        $picked = Show-FolderDialog -current $box.Text -title 'Choose a folder' -owner $this.FindForm()
                        if ($picked) { $box.Text = $picked }
                    })
                    $page.Controls.Add($btn)
                    $ctl = $tb
                }
                'choice' {
                    $ctl = New-Object System.Windows.Forms.ComboBox
                    $ctl.DropDownStyle = 'DropDownList'
                    $ctl.Location = [System.Drawing.Point]::new(266, $y)
                    $ctl.Size = [System.Drawing.Size]::new(386, 26)
                    foreach ($v in $d.Choices) { [void]$ctl.Items.Add((Format-Setting $d $v)) }
                    $page.Controls.Add($ctl)
                }
                'bool' {
                    $ctl = New-Object System.Windows.Forms.CheckBox
                    $ctl.Text = 'On'
                    $ctl.Location = [System.Drawing.Point]::new(266, $y + 2)
                    $ctl.Size = [System.Drawing.Size]::new(200, 24)
                    $page.Controls.Add($ctl)
                }
            }
            Write-SettingControl -def $d -ctl $ctl -value $S[$d.Key]
            $controls[$d.Key] = $ctl
            $y += 36; $rows++
        }
        $tipText = @{ Phone = 'Tip: a folder inside iCloud Drive (or OneDrive / Google Drive) shows up on your phone in that app.'
                      Network = 'Signing in is only needed for age-restricted or members-only videos. See Help for how to set it up.' }[$tabName]
        if ($tipText) {
            $tip = New-Object System.Windows.Forms.Label
            $tip.Text = $tipText
            $tip.ForeColor = [System.Drawing.Color]::DimGray
            $tip.Location = [System.Drawing.Point]::new(12, $y + 6)
            $tip.Size = [System.Drawing.Size]::new(640, 40)
            $page.Controls.Add($tip)
            $rows += 1
        }
        if ($rows -gt $rowsMax) { $rowsMax = $rows }
    }
    $tabsHeight = 14 + $rowsMax * 36 + 40 + 30
    $tabs.Size = [System.Drawing.Size]::new(678, $tabsHeight)
    $y = 12 + $tabsHeight + 12

    $note = New-Object System.Windows.Forms.Label
    $note.Text = 'Changes apply to the next download.'
    $note.ForeColor = [System.Drawing.Color]::DimGray
    $note.Location = [System.Drawing.Point]::new(176, $y + 7)
    $note.Size = [System.Drawing.Size]::new(270, 22)
    $form.Controls.Add($note)

    $reset = New-Object System.Windows.Forms.Button
    $reset.Text = 'Reset to defaults'
    $reset.Location = [System.Drawing.Point]::new(12, $y)
    $reset.Size = [System.Drawing.Size]::new(150, 32)
    $reset.Add_Click({ foreach ($d in $SettingDefs) { Write-SettingControl -def $d -ctl $controls[$d.Key] -value $Defaults[$d.Key] } })
    $form.Controls.Add($reset)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.DialogResult = 'Cancel'
    $cancel.Location = [System.Drawing.Point]::new(504, $y)
    $cancel.Size = [System.Drawing.Size]::new(90, 32)
    $form.Controls.Add($cancel)

    $save = New-Object System.Windows.Forms.Button
    $save.Text = 'Save'
    $save.DialogResult = 'OK'
    $save.Location = [System.Drawing.Point]::new(600, $y)
    $save.Size = [System.Drawing.Size]::new(90, 32)
    $form.Controls.Add($save)

    $form.AcceptButton = $save
    $form.CancelButton = $cancel
    $form.ClientSize = [System.Drawing.Size]::new(702, $y + 46)
    $form.ResumeLayout($false)
    $form.Add_Shown({ $this.Activate(); $this.TopMost = $false })

    $result = if ($ownerForm) { $form.ShowDialog($ownerForm) } else { $form.ShowDialog() }
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) { $form.Dispose(); return $false }
    foreach ($d in $SettingDefs) {
        $c = $controls[$d.Key]
        switch ($d.Kind) {
            'folder' { $t = $c.Text.Trim().Trim('"'); if ($t) { $S[$d.Key] = $t } }
            'bool'   { $S[$d.Key] = [bool]$c.Checked }
            'choice' { if ($c.SelectedIndex -ge 0) { $S[$d.Key] = $d.Choices[$c.SelectedIndex] } }
        }
    }
    $form.Dispose()
    Save-Config; Use-Config
    return $true
}

# Settings window on Windows; the text version if the window can't open for any reason
function Show-ConfigWindow($ownerForm = $null) {
    if ($env:OS -eq 'Windows_NT') {
        try { [void](Show-SettingsWindow $ownerForm); return }
        catch {
            try { Add-Content -LiteralPath $ErrorLog -Value ("{0:yyyy-MM-dd HH:mm:ss}  settings window: {1}" -f (Get-Date), $_.Exception.Message) } catch { Write-Debug $_ }
            if (-not $script:Interactive) { Show-ErrorBox "The settings window couldn't open: $($_.Exception.Message)"; return }
        }
    }
    Show-SettingsConsole
}

# ============================== WATCH HISTORY ==============================
# Your YouTube watch history: read straight from YouTube (needs your sign-in) or imported from a
# Google Takeout export, with every video's length so you can sort by it. Kept in watch-history.tsv.
$WhFile   = Join-Path $Base 'watch-history.tsv'
$WhStatus = Join-Path $Base 'watch-history-status.json'
$Inv      = [System.Globalization.CultureInfo]::InvariantCulture

function Test-MutexHeld([string]$name) {
    $m = New-Object System.Threading.Mutex($false, $name)
    $got = $false
    try { $got = $m.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $got = $true }
    if ($got) { $m.ReleaseMutex() }
    $m.Dispose()
    return -not $got
}
function Test-HistoryBusy { Test-MutexHeld 'Local\VideoDownloaderHistory' }

function Get-CleanField([string]$s) { if (-not $s) { return '' }; return ($s -replace '[\t\r\n]+', ' ').Trim() }

function Read-WatchHistory {
    $db = @{}
    if (-not (Test-Path -LiteralPath $WhFile)) { return $db }
    foreach ($line in [System.IO.File]::ReadAllLines($WhFile, [System.Text.Encoding]::UTF8)) {
        $f = $line.Split([char]9)
        if ($f.Count -lt 6 -or $f[0] -notmatch $WhKeyRx) { continue }
        $d = $null; $num = 0.0; $n = 0
        if ($f[3] -ne '' -and [double]::TryParse($f[3], [System.Globalization.NumberStyles]::Float, $Inv, [ref]$num)) { $d = $num }
        [void][int]::TryParse($f[5], [ref]$n)
        $db[$f[0]] = @{ id = $f[0]; t = $f[1]; c = $f[2]; d = $d; w = $f[4]; n = $n }
    }
    return $db
}
function Save-WatchHistory($db) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("id`ttitle`tchannel`tseconds`twatched_utc`ttimes`r`n")
    foreach ($e in $db.Values) {
        $d = if ($null -eq $e.d) { '' } else { ([double]$e.d).ToString($Inv) }
        [void]$sb.Append(($e.id, (Get-CleanField $e.t), (Get-CleanField $e.c), $d, [string]$e.w, [int]$e.n) -join "`t").Append("`r`n")
    }
    $tmp = $WhFile + '.tmp'
    [System.IO.File]::WriteAllText($tmp, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $WhFile -Force
}
# one entry per video; titles from YouTube itself ("Authoritative") replace imported ones
function Merge-Watch($db, [string]$id, [string]$title, [string]$channel, $dur, [string]$watched, [int]$count, [switch]$Authoritative) {
    if ($id -notmatch $WhKeyRx) { return }
    $e = $db[$id]
    if (-not $e) { $e = @{ id = $id; t = ''; c = ''; d = $null; w = ''; n = 0 }; $db[$id] = $e }
    if ($title -and ($Authoritative -or -not $e.t)) { $e.t = $title }
    if ($channel -and ($Authoritative -or -not $e.c)) { $e.c = $channel }
    if ($null -ne $dur) { $e.d = $dur }
    if ($watched -and [string]::CompareOrdinal($watched, [string]$e.w) -gt 0) { $e.w = $watched }   # ISO times compare as text
    if ($count -gt $e.n) { $e.n = $count }
}

function Write-WhStatus([hashtable]$h) {
    $h['updated'] = (Get-Date).ToString('o'); $h['pid'] = $PID
    try {
        $tmp = $WhStatus + '.tmp'
        [System.IO.File]::WriteAllText($tmp, ($h | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tmp -Destination $WhStatus -Force
    } catch { Write-Debug $_ }
}
function Read-WhStatus {
    if (-not (Test-Path -LiteralPath $WhStatus)) { return $null }
    try { return (Get-Content -LiteralPath $WhStatus -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function ConvertTo-Utc([string]$text) {
    if (-not $text) { return '' }
    $t = ($text -replace '[\u202f\u00a0]', ' ').Trim()
    $dt = [datetime]::MinValue
    $utc = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
    if ($t -match '^\d{4}-\d\d-\d\dT' -and [datetime]::TryParse($t, $Inv, $utc, [ref]$dt)) { return $dt.ToString('yyyy-MM-ddTHH:mm:ssZ') }
    # Takeout HTML: "Nov 4, 2026, 8:12:33 PM PST" - drop the time zone name
    $t2 = ($t -replace '\s+[A-Z]{2,5}$', '') -replace '(\d{4}),', '$1'
    foreach ($c in [System.Globalization.CultureInfo]::CurrentCulture, $Inv) {
        if ([datetime]::TryParse($t2, $c, [System.Globalization.DateTimeStyles]::AssumeLocal, [ref]$dt)) { return $dt.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
    }
    return ''
}
function ConvertFrom-JsonText([string]$s) { try { return [regex]::Unescape($s) } catch { return $s } }

# A video whose link Takeout left out (newer HTML exports only give title + channel) is kept under a
# key made from its title and channel, until it's found on YouTube and replaced by the real video
$script:Sha = [System.Security.Cryptography.SHA1]::Create()
$WhKeyRx = '^([A-Za-z0-9_-]{11}|~[0-9a-f]{16})$'
function Get-NormText([string]$s) { if (-not $s) { return '' }; return ($s.ToLowerInvariant() -replace '[^\p{L}\p{N}]', '') }
function Get-TitleKey([string]$title, [string]$channel) {
    $bytes = $script:Sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes((Get-NormText $title) + '|' + (Get-NormText $channel)))
    $sb = New-Object System.Text.StringBuilder('~')
    for ($i = 0; $i -lt 8; $i++) { [void]$sb.Append($bytes[$i].ToString('x2')) }
    return $sb.ToString()
}
function Get-PlainHtml([string]$s) { return ([System.Net.WebUtility]::HtmlDecode(($s -replace '<[^>]+>', ''))).Trim() }

function Add-HistoryView($views, [string]$title, [string]$url, [string]$ch, [string]$when) {
    $id = ''
    if ($url -match '(?:[?&]v=|youtu\.be/|/shorts/)([A-Za-z0-9_-]{11})') { $id = $Matches[1] }
    $title = ($title -replace '^Watched\s+', '').Trim()
    if ($title -match '^https?://\S+$') {          # removed videos only keep their link
        if (-not $id -and $title -match '(?:[?&]v=|youtu\.be/|/shorts/)([A-Za-z0-9_-]{11})') { $id = $Matches[1] }
        $title = ''
    }
    if (-not $id -and -not $title) { return $false }
    $key = if ($id) { $id } else { Get-TitleKey $title $ch }
    $v = $views[$key]
    if (-not $v) { $v = @{ n = 0; w = ''; t = ''; c = '' }; $views[$key] = $v }
    $v.n++
    if ($when -and [string]::CompareOrdinal($when, $v.w) -gt 0) { $v.w = $when }
    if ($title -and -not $v.t) { $v.t = $title }
    if ($ch -and -not $v.c) { $v.c = $ch }
    return $true
}

# Reads a Takeout watch-history.json / watch-history.html, or any text with YouTube links. Returns how many views it found.
function Import-HistoryText([string]$text, $db) {
    $views = @{}
    $trim = $text.TrimStart([char]0xFEFF, ' ', "`r", "`n", "`t")
    $total = 0
    if ($trim.StartsWith('[')) {
        $rx = New-Object System.Text.RegularExpressions.Regex('\{\s*"header"\s*:\s*"(?:[^"\\]|\\.)*"(.*?)"time"\s*:\s*"([^"]+)"', 'Singleline')
        foreach ($m in $rx.Matches($trim)) {
            $body = $m.Groups[1].Value
            if ($body -match 'From Google Ads') { continue }
            $title = ''; $url = ''; $ch = ''
            if ($body -match '"title"\s*:\s*"((?:[^"\\]|\\.)*)"') { $title = ConvertFrom-JsonText $Matches[1] }
            if ($body -match '"titleUrl"\s*:\s*"((?:[^"\\]|\\.)*)"') { $url = ConvertFrom-JsonText $Matches[1] }
            if ($body -match '"subtitles"\s*:\s*\[\s*\{\s*"name"\s*:\s*"((?:[^"\\]|\\.)*)"') { $ch = ConvertFrom-JsonText $Matches[1] }
            if (Add-HistoryView -views $views -title $title -url $url -ch $ch -when (ConvertTo-Utc $m.Groups[2].Value)) { $total++ }
        }
    } elseif ($trim -match '(?i)^<(!DOCTYPE html|html)' -and $trim.Contains('content-cell')) {
        $cellRx = New-Object System.Text.RegularExpressions.Regex('content-cell[^"]*mdl-typography--body-1">(.*?)</div>', 'Singleline')
        $chanRx = New-Object System.Text.RegularExpressions.Regex('<a href="https?://(?:www\.)?youtube\.com/(?:channel/|@|c/|user/)[^"]*">(.*?)</a>', 'Singleline')
        foreach ($chunk in $trim.Split(@('<div class="outer-cell'), [StringSplitOptions]::None)) {
            $cm = $cellRx.Match($chunk)
            if (-not $cm.Success) { continue }
            if ($chunk.Contains('From Google Ads')) { continue }
            $parts = [regex]::Split($cm.Groups[1].Value, '<br\s*/?>')
            $first = $parts[0]; $title = ''; $url = ''
            $am = [regex]::Match($first, '<a href="([^"]+)">(.*?)</a>', 'Singleline')
            if ($am.Success -and $am.Groups[1].Value -notmatch '/(channel/|@|c/|user/)') {
                $url = [System.Net.WebUtility]::HtmlDecode($am.Groups[1].Value)
                $title = Get-PlainHtml $am.Groups[2].Value
            } else {
                $plain = Get-PlainHtml $first
                $nb = $plain.IndexOf([char]0x00A0)
                $title = if ($nb -ge 0) { $plain.Substring($nb + 1) } else { $plain }
            }
            $ch = ''; $when = ''
            for ($k = 1; $k -lt $parts.Count; $k++) {
                $chm = $chanRx.Match($parts[$k])
                if ($chm.Success) { if (-not $ch) { $ch = Get-PlainHtml $chm.Groups[1].Value } }
                elseif ($parts[$k].Trim() -and -not $when) { $when = ConvertTo-Utc (Get-PlainHtml $parts[$k]) }
            }
            if (Add-HistoryView -views $views -title $title -url $url -ch $ch -when $when) { $total++ }
        }
    } else {
        # any other file: every YouTube video link in it
        foreach ($m in [regex]::Matches($trim, '(?:[?&]v=|youtu\.be/|/shorts/|/live/|/embed/)([A-Za-z0-9_-]{11})(?![A-Za-z0-9_-])')) {
            if (Add-HistoryView -views $views -title '' -url ('?v=' + $m.Groups[1].Value) -ch '' -when '') { $total++ }
        }
    }
    foreach ($key in $views.Keys) { $v = $views[$key]; Merge-Watch -db $db -id $key -title $v.t -channel $v.c -dur $null -watched $v.w -count $v.n }
    return $total
}

# Fold title-only entries into videos already in the list with the same title and channel
function Join-TitleMatch($db) {
    $index = @{}
    foreach ($e in $db.Values) { if (-not $e.id.StartsWith('~') -and $e.t) { $index[(Get-NormText $e.t) + '|' + (Get-NormText $e.c)] = $e.id } }
    $n = 0
    foreach ($e in @($db.Values | Where-Object { $_.id.StartsWith('~') })) {
        $real = $index[(Get-NormText $e.t) + '|' + (Get-NormText $e.c)]
        if ($real) { Merge-Watch -db $db -id $real -title '' -channel '' -dur $null -watched $e.w -count $e.n; [void]$db.Remove($e.id); $n++ }
    }
    return $n
}

# Hashtags (#shorts #tech ...) make poor search words and are often edited later, so they're left out when comparing titles
function Get-SearchTitle([string]$t) {
    $c = (($t -replace '(^|\s)#[\p{L}\p{N}_]+', ' ') -replace '\s+', ' ').Trim()
    if ($c) { return $c } else { return $t }
}
function Get-TitleSimilarity([string]$a, [string]$b) {
    $a = Get-SearchTitle $a; $b = Get-SearchTitle $b
    $na = Get-NormText $a; $nb = Get-NormText $b
    if (-not $na -or -not $nb) { return 0.0 }
    if ($na -eq $nb) { return 1.0 }
    if ($na.Length -ge 8 -and $nb.Length -ge 8 -and ($na.Contains($nb) -or $nb.Contains($na))) { return 0.8 }
    $wa = @{}; foreach ($w in ($a.ToLowerInvariant() -split '[^\p{L}\p{N}]+')) { if ($w) { $wa[$w] = 1 } }
    $wb = @{}; foreach ($w in ($b.ToLowerInvariant() -split '[^\p{L}\p{N}]+')) { if ($w) { $wb[$w] = 1 } }
    if (-not $wa.Count -or -not $wb.Count) { return 0.0 }
    $common = 0; foreach ($w in $wa.Keys) { if ($wb.ContainsKey($w)) { $common++ } }
    return $common / ($wa.Count + $wb.Count - $common)
}
# The search result that is really this video: same channel and a similar title, or a long identical title
function Select-SearchMatch($cands, [string]$title, [string]$channel) {
    $nc = Get-NormText $channel
    $best = $null; $bestScore = 0.0
    foreach ($c in $cands) {
        if (-not $c -or [string]$c.id -notmatch '^[A-Za-z0-9_-]{11}$') { continue }
        $cc = if ($c.channel) { [string]$c.channel } else { [string]$c.uploader }
        $chanEq = [bool]($nc -and (Get-NormText $cc) -eq $nc)
        $sim = Get-TitleSimilarity $title ([string]$c.title)
        $len = (Get-NormText (Get-SearchTitle $title)).Length
        # same channel and a fair share of the same words (titles get edited), or a long title that is almost the same
        # when the result doesn't say who uploaded it (Shorts results often don't)
        $ok = ($chanEq -and $sim -ge 0.35) -or ($sim -ge 1.0 -and $len -ge 12) -or (-not $cc -and $sim -ge 0.8 -and $len -ge 10)
        if (-not $ok) { continue }
        $score = $sim + [int]$chanEq
        if ($score -gt $bestScore) { $best = $c; $bestScore = $score }
    }
    return $best
}

# Takeout files without links: search YouTube for each title + channel to find the video (and its length)
function Invoke-HistorySearch($db, [string]$doneMsg = '') {
    # titles an older, stricter version gave up on get one more try
    $mk = Join-Path $Base '.history-matcher-v2'
    if (-not (Test-Path -LiteralPath $mk)) {
        foreach ($e in $db.Values) { if ($e.id.StartsWith('~') -and $e.d -eq -1) { $e.d = $null } }
        Save-WatchHistory $db
        try { Set-Content -LiteralPath $mk -Value (Get-Date -Format o) } catch { Write-Debug $_ }
    }
    $todo = @($db.Values | Where-Object { $_.id.StartsWith('~') -and $null -eq $_.d } | Sort-Object { [string]$_.w } -Descending)
    $total = $todo.Count
    if ($total -eq 0) { return $true }
    $batch = 20; $parallel = 2
    $done = 0; $found = 0; $started = Get-Date
    Write-WhStatus @{ state = 'running'; task = 'search'; message = ("{0}Finding your videos on YouTube (the Takeout file has no links): 0 of {1:N0}..." -f $doneMsg, $total); done = 0; total = $total }
    for ($i = 0; $i -lt $total; $i += $batch * $parallel) {
        $jobs = @()
        for ($k = 0; $k -lt $parallel; $k++) {
            $a = $i + $k * $batch
            if ($a -ge $total) { break }
            $b = [math]::Min($total, $a + $batch) - 1
            $map = @{}
            $argList = @('--flat-playlist', '--ignore-errors', '--no-warnings', '--print', 'VDS%(.{id,duration,channel,uploader,title,playlist_id})j', '--')
            foreach ($e in @($todo[$a..$b])) {
                $q = (((Get-SearchTitle (Get-CleanField $e.t)) + ' ' + (Get-CleanField $e.c)) -replace '\s+', ' ').Trim()
                if ($q.Length -gt 200) { $q = $q.Substring(0, 200).Trim() }
                if (-not $q -or $map.ContainsKey($q)) { continue }
                $map[$q] = $e
                $argList += "ytsearch6:$q"
            }
            $p = Invoke-YtDlpCapture $argList
            $jobs += @{ p = $p; map = $map; n = ($b - $a + 1); out = $p.StandardOutput.ReadToEndAsync(); err = $p.StandardError.ReadToEndAsync() }
        }
        $stop = $null
        foreach ($j in $jobs) {
            $j.p.WaitForExit()
            foreach ($l in ("$($j.err.Result)" -split "`r?`n")) {
                if ($l -notmatch '^ERROR') { continue }
                $script:LastErrors = New-Object System.Collections.Generic.List[string]
                $script:LastErrors.Add($l)
                $kind = Get-FailureKind
                if ($kind -in 'offline', 'blocked', 'intercepted') { if (-not $stop) { try { Add-Content -LiteralPath $ErrorLog -Value ("{0:yyyy-MM-dd HH:mm:ss}  history search stopped ({1}): {2}" -f (Get-Date), $kind, $l) -Encoding UTF8 } catch { Write-Debug $_ } }; $stop = $kind }
            }
            $res = @{}
            foreach ($line in ("$($j.out.Result)" -split "`r?`n")) {
                if (-not $line.StartsWith('VDS')) { continue }
                try { $o = $line.Substring(3) | ConvertFrom-Json } catch { continue }
                $q = [string]$o.playlist_id
                if (-not $res.ContainsKey($q)) { $res[$q] = New-Object System.Collections.Generic.List[object] }
                $res[$q].Add($o)
            }
            foreach ($q in @($j.map.Keys)) {
                $e = $j.map[$q]
                if (-not $db.ContainsKey($e.id)) { continue }
                $hit = $null
                if ($res.ContainsKey($q)) { $hit = Select-SearchMatch -cands ($res[$q].ToArray()) -title $e.t -channel $e.c }
                if ($hit) {
                    Merge-Watch -db $db -id ([string]$hit.id) -title $e.t -channel $e.c -dur (ConvertTo-Dur ([string]$hit.duration)) -watched $e.w -count $e.n
                    [void]$db.Remove($e.id)
                    $found++
                } elseif (-not $stop) {
                    $e.d = -1      # not found: removed, private, or renamed since
                }
            }
            $done += $j.n
        }
        Save-WatchHistory $db
        if ($stop) {
            $msg = switch ($stop) { 'offline' { 'Stopped: lost the internet connection.' } 'intercepted' { 'Stopped: your network is intercepting secure connections (a self-signed certificate - usually a router, ISP or Wi-Fi filter, or security software), so YouTube cannot be reached safely.' } default { 'Stopped: YouTube is temporarily limiting searches. Wait an hour, then click "Find missing lengths" to carry on.' } }
            $remain = @($db.Values | Where-Object { $_.id.StartsWith('~') -and $null -eq $_.d }).Count
            Write-WhStatus @{ state = 'error'; message = ('{0} Found {1:N0} so far; {2:N0} still to look for.' -f $msg, $found, $remain) }
            return $false
        }
        $left = ''
        if ($done -lt $total) {
            $per = ((Get-Date) - $started).TotalSeconds / [math]::Max(1, $done)
            $mins = [math]::Ceiling($per * ($total - $done) / 60)
            $left = if ($mins -le 1) { ' - about a minute left' } elseif ($mins -lt 90) { " - about $mins minutes left" } else { (' - about {0:0.#} hours left' -f ($mins / 60)) }
        }
        Write-WhStatus @{ state = 'running'; task = 'search'; message = ("{0}Finding your videos on YouTube (the Takeout file has no links): {1:N0} of {2:N0}, {3:N0} found{4}. You can close this window; it keeps going." -f $doneMsg, [math]::Min($done, $total), $total, $found, $left); done = [math]::Min($done, $total); total = $total }
    }
    Write-DownloadLog ("HISTORY searched {0} titles, found {1}" -f $total, $found)
    return $true
}

function Import-HistoryFile([string]$path, $db) {
    if ($path -match '(?i)\.zip$') {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($path)
        try {
            $all = @($zip.Entries | Where-Object { $_.Length -gt 0 -and $_.Length -lt 512MB })
            $pick = @($all | Where-Object { $_.FullName -match '(?i)watch-history[^/\\]*\.json$' })
            if (-not $pick.Count) { $pick = @($all | Where-Object { $_.FullName -match '(?i)watch-history[^/\\]*\.html?$' }) }
            if (-not $pick.Count) { $pick = @($all | Where-Object { $_.FullName -match '(?i)youtube.*[/\\]history[/\\][^/\\]+\.(json|html?)$' -and $_.FullName -notmatch '(?i)search' }) }
            $n = 0
            foreach ($e in $pick) {
                $sr = New-Object System.IO.StreamReader($e.Open(), [System.Text.Encoding]::UTF8)
                try { $n += Import-HistoryText $sr.ReadToEnd() $db } finally { $sr.Close() }
            }
            return $n
        } finally { $zip.Dispose() }
    }
    return Import-HistoryText ([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)) $db
}

function ConvertTo-Dur([string]$s) {
    $num = 0.0
    if ($s -and $s -ne 'NA' -and [double]::TryParse($s, [System.Globalization.NumberStyles]::Float, $Inv, [ref]$num)) { return $num }
    return $null
}

function Invoke-YtDlpCapture([string[]]$argList) {
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo.FileName = $script:YtDlp
    $p.StartInfo.Arguments = ConvertTo-ArgLine (@($YtSafeArgs) + $argList)
    $p.StartInfo.UseShellExecute = $false
    $p.StartInfo.CreateNoWindow = $true
    $p.StartInfo.RedirectStandardOutput = $true
    $p.StartInfo.RedirectStandardError = $true
    $p.StartInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $p.StartInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $p.StartInfo.EnvironmentVariables['PYTHONIOENCODING'] = 'utf-8'
    $p.StartInfo.EnvironmentVariables['PYTHONUTF8'] = '1'
    [void]$p.Start()
    return $p
}

# Straight from youtube.com/feed/history (the most recent few thousand videos)
function Invoke-HistoryFetch($db) {
    $cookies = Open-SignIn
    if (-not $cookies) {
        Write-WhStatus @{ state = 'error'; message = 'Reading your history needs your YouTube sign-in (a cookies.txt file, or Firefox - Settings > Network). See the guide''s "Age-restricted videos" section for the 1-minute setup, or import a Google Takeout file instead.' }
        return $false
    }
    Write-WhStatus @{ state = 'running'; task = 'fetch'; message = 'Reading your watch history from YouTube...'; done = 0; total = 0 }
    $p = Invoke-YtDlpCapture (@(Get-CookieArgumentList $cookies) + @('--flat-playlist', '--ignore-errors', '--playlist-end', '5000',
                              '--print', 'VDH|%(id)s|%(duration)s|%(channel,uploader|)s|%(title)s', ':ythistory'))
    $errTask = $p.StandardError.ReadToEndAsync()
    $i = 0; $now = (Get-Date).ToUniversalTime()
    while ($null -ne ($line = $p.StandardOutput.ReadLine())) {
        if (-not $line.StartsWith('VDH|')) { continue }
        $f = $line.Split([char]'|', 5)
        if ($f.Count -lt 5) { continue }
        $id = $f[1]
        # the feed has no dates: newest first, so give new entries a time that keeps that order
        $w = ''
        if (-not $db[$id] -or -not $db[$id].w) { $w = $now.AddSeconds(-$i).ToString('yyyy-MM-ddTHH:mm:ssZ') }
        $title = $f[4]; if ($title -eq 'NA') { $title = '' }
        $ch = $f[3]; if ($ch -eq 'NA') { $ch = '' }
        Merge-Watch -db $db -id $id -title $title -channel $ch -dur (ConvertTo-Dur $f[2]) -watched $w -count 1 -Authoritative
        $i++
        if ($i % 50 -eq 0) { Write-WhStatus @{ state = 'running'; task = 'fetch'; message = "Reading your watch history from YouTube... $i videos so far"; done = $i; total = 0 } }
    }
    $p.WaitForExit()
    $script:LastErrors = New-Object System.Collections.Generic.List[string]
    foreach ($l in ("$($errTask.Result)" -split "`r?`n")) { if ($l -match '^ERROR' -or $l -match '(?i)cookies are no longer valid') { $script:LastErrors.Add($l) } }
    if ($i -gt 0) { Save-WatchHistory $db }
    if ($i -eq 0) {
        try { Add-Content -LiteralPath $ErrorLog -Value ("{0:yyyy-MM-dd HH:mm:ss}  history fetch (exit {1}):`r`n{2}" -f (Get-Date), $p.ExitCode, "$($errTask.Result)".Trim()) -Encoding UTF8 } catch { Write-Debug $_ }
        $kind = Get-FailureKind
        $why = ($script:LastErrors | Select-Object -Last 1)
        $msg = switch ($kind) {
            'offline' { 'Could not reach YouTube - check your internet connection (or turn off a VPN) and try again.' }
            'intercepted' { "Your network is intercepting secure connections (it answered with its own self-signed certificate), so YouTube can't be reached safely. This usually comes from a router, ISP or Wi-Fi filter, or security software. Nothing is lost - it carries on when the connection is normal again." }
            'blocked' { 'YouTube is temporarily blocking requests from your connection. Try again in an hour.' }
            default   { if ($why -match '(?i)no longer valid|rotated') { 'Your saved YouTube sign-in (cookies.txt) has expired - YouTube replaces it whenever that browser session is used again. Export a fresh one from a private/incognito window (Help > "Age-restricted videos") and try again.' }
                        elseif ($why -match '(?i)sign in|login|cookies|account') { 'YouTube did not accept your saved sign-in (cookies.txt). Export a fresh one (Help > "Age-restricted videos") and try again.' }
                        elseif ($why) { "YouTube didn't return any history: $why" }
                        else { 'YouTube returned an empty history. Is watch history turned on for your account (youtube.com/feed/history)?' } }
        }
        Write-WhStatus @{ state = 'error'; message = $msg }
        return $false
    }
    Write-DownloadLog ("HISTORY read {0} videos from YouTube" -f $i)
    return $true
}

# Looks up the length (and real title) of every video that doesn't have one yet; a few at a time, saved as it goes
function Invoke-HistoryLengthLookup($db, [string]$doneMsg = '') {
    $todo = @($db.Values | Where-Object { $null -eq $_.d -and -not $_.id.StartsWith('~') } | Sort-Object { [string]$_.w } -Descending | ForEach-Object { $_.id })
    $total = $todo.Count
    if ($total -eq 0) { return $true }
    $cookies = $null
    if ([string]$S.UseCookies -ne 'never') { $cookies = Open-SignIn }
    $batch = 15; $parallel = 3
    $done = 0; $started = Get-Date
    Write-WhStatus @{ state = 'running'; task = 'lengths'; message = ("{0}Looking up video lengths: 0 of {1:N0}..." -f $doneMsg, $total); done = 0; total = $total }
    for ($i = 0; $i -lt $total; $i += $batch * $parallel) {
        $jobs = @()
        for ($k = 0; $k -lt $parallel; $k++) {
            $a = $i + $k * $batch
            if ($a -ge $total) { break }
            $b = [math]::Min($total, $a + $batch) - 1
            $ids = @($todo[$a..$b])
            $argList = @('--skip-download', '--ignore-errors', '--ignore-no-formats-error', '--no-warnings', '--no-playlist',
                         '--extractor-args', 'youtube:skip=hls,dash,translated_subs',
                         '--print', 'VDL|%(id)s|%(duration)s|%(channel,uploader|)s|%(title)s')
            if ($cookies) { $argList += @(Get-CookieArgumentList $cookies) }
            $argList += '--'
            $argList += @($ids | ForEach-Object { "https://www.youtube.com/watch?v=$_" })
            $p = Invoke-YtDlpCapture $argList
            $jobs += @{ p = $p; ids = $ids; out = $p.StandardOutput.ReadToEndAsync(); err = $p.StandardError.ReadToEndAsync() }
        }
        $stop = $null
        foreach ($j in $jobs) {
            $j.p.WaitForExit()
            $seen = @{}
            foreach ($line in ("$($j.out.Result)" -split "`r?`n")) {
                if (-not $line.StartsWith('VDL|')) { continue }
                $f = $line.Split([char]'|', 5)
                if ($f.Count -lt 5) { continue }
                $title = $f[4]; if ($title -eq 'NA') { $title = '' }
                $ch = $f[3]; if ($ch -eq 'NA') { $ch = '' }
                $d = ConvertTo-Dur $f[2]
                if ($null -eq $d) { $d = -1 }          # live streams / premieres without a length
                Merge-Watch -db $db -id $f[1] -title $title -channel $ch -dur $d -watched '' -count 0 -Authoritative
                $seen[$f[1]] = $true
            }
            foreach ($l in ("$($j.err.Result)" -split "`r?`n")) {
                if ($l -notmatch '^ERROR: \[youtube\] ([A-Za-z0-9_-]{11}): (.*)$') { continue }
                $id = $Matches[1]
                $script:LastErrors = New-Object System.Collections.Generic.List[string]
                $script:LastErrors.Add($l)
                $kind = Get-FailureKind
                if ($kind -in 'offline', 'blocked', 'intercepted') { if (-not $stop) { try { Add-Content -LiteralPath $ErrorLog -Value ("{0:yyyy-MM-dd HH:mm:ss}  history lengths stopped ({1}): {2}" -f (Get-Date), $kind, $l) -Encoding UTF8 } catch { Write-Debug $_ } }; $stop = $kind; continue }
                if (-not $seen[$id] -and $db[$id]) { $db[$id].d = -1 }      # removed, private, ...
            }
            $done += $j.ids.Count
        }
        Save-WatchHistory $db
        if ($stop) {
            $msg = switch ($stop) { 'offline' { 'Stopped: lost the internet connection.' } 'intercepted' { 'Stopped: your network is intercepting secure connections (a self-signed certificate - usually a router, ISP or Wi-Fi filter, or security software), so YouTube cannot be reached safely.' } default { 'Stopped: YouTube is temporarily limiting requests. Wait an hour, then click "Find missing lengths".' } }
            $remain = @($db.Values | Where-Object { $null -eq $_.d }).Count
            Write-WhStatus @{ state = 'error'; message = ('{0} {1:N0} videos still need a length.' -f $msg, $remain) }
            return $false
        }
        $left = ''
        if ($done -lt $total) {
            $per = ((Get-Date) - $started).TotalSeconds / [math]::Max(1, $done)
            $mins = [math]::Ceiling($per * ($total - $done) / 60)
            $left = if ($mins -le 1) { ' - about a minute left' } else { " - about $mins minutes left" }
        }
        Write-WhStatus @{ state = 'running'; task = 'lengths'; message = ("{0}Looking up video lengths: {1:N0} of {2:N0}{3}. You can close this window; it keeps going." -f $doneMsg, $done, $total, $left); done = $done; total = $total }
    }
    return $true
}

function Invoke-HistoryTask([string]$task, [string]$file) {
    $m = New-Object System.Threading.Mutex($false, 'Local\VideoDownloaderHistory')
    $owned = $false
    try { $owned = $m.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $owned = $true }
    if (-not $owned) { return }
    try {
        if (-not $script:YtDlp -and $task -ne 'import') { Install-Missing }
        $db = Read-WatchHistory
        $note = ''
        switch ($task) {
            'fetch' {
                if (-not (Invoke-HistoryFetch $db)) { return }
                $note = 'Got your history from YouTube. '
            }
            'import' {
                Write-WhStatus @{ state = 'running'; task = 'import'; message = 'Importing ' + (Split-Path -Leaf $file) + '...' }
                $before = $db.Count
                $views = Import-HistoryFile $file $db
                if ($views -eq 0) {
                    Write-WhStatus @{ state = 'error'; message = "No YouTube videos were found in $(Split-Path -Leaf $file). Pick the Takeout .zip, or watch-history.json / watch-history.html from inside it." }
                    return
                }
                Save-WatchHistory $db
                Write-DownloadLog ("HISTORY imported {0} views ({1} new videos) from {2}" -f $views, ($db.Count - $before), $file)
                $note = ('Imported {0:N0} views ({1:N0} new videos). ' -f $views, ($db.Count - $before))
                Write-WhStatus @{ state = 'running'; task = 'import'; message = $note }
            }
        }
        $joined = Join-TitleMatch $db
        if ($joined) { Save-WatchHistory $db }
        if ($script:YtDlp) {
            if (Invoke-HistoryLengthLookup $db $note) {
                if (Invoke-HistorySearch $db $note) { [void](Invoke-HistoryLengthLookup $db $note) }
            }
        }
        $st = Read-WhStatus
        if (-not $st -or $st.state -ne 'error') {
            $missing = @($db.Values | Where-Object { $null -eq $_.d }).Count
            $notFound = @($db.Values | Where-Object { $_.id.StartsWith('~') -and $_.d -eq -1 }).Count
            $msg = ('{0}Done - {1:N0} videos in your list.' -f $note, $db.Count)
            if ($notFound) { $msg += (' {0:N0} could not be found on YouTube any more (removed, private or renamed).' -f $notFound) }
            if ($missing) { $msg += (' {0:N0} still have no length.' -f $missing) }
            Write-WhStatus @{ state = 'done'; message = $msg }
        }
    } catch {
        Write-WhStatus @{ state = 'error'; message = 'Something went wrong: ' + $_.Exception.Message }
        try { Add-Content -LiteralPath $ErrorLog -Value ("{0:yyyy-MM-dd HH:mm:ss}  history {1}: {2}`r`n{3}" -f (Get-Date), $task, $_.Exception.Message, $_.InvocationInfo.PositionMessage) } catch { Write-Debug $_ }
    } finally {
        Close-SignIn
        $m.ReleaseMutex()
    }
}

function Suspend-HistoryTask {
    $st = Read-WhStatus
    if ($st -and $st.pid) {
        try {
            if ($env:OS -eq 'Windows_NT') { Start-Process -FilePath 'taskkill.exe' -ArgumentList "/PID $($st.pid) /T /F" -WindowStyle Hidden -Wait | Out-Null }
            else { Stop-Process -Id $st.pid -Force -ErrorAction SilentlyContinue }
        } catch { Write-Debug $_ }
    }
    Write-WhStatus @{ state = 'stopped'; message = 'Stopped. Click "Find missing lengths" to carry on later.' }
}

function Format-Length($sec) {
    if ($null -eq $sec) { return '...' }
    if ($sec -lt 0) { return '-' }
    $s = [int][math]::Round([double]$sec)
    $h = [int][math]::Floor($s / 3600); $mi = [int][math]::Floor(($s % 3600) / 60); $se = $s % 60
    if ($h -gt 0) { return '{0}:{1:00}:{2:00}' -f $h, $mi, $se }
    return '{0}:{1:00}' -f $mi, $se
}

# ---------- the Watch history window ----------
$WhFilters = @(
    @('all', 'All videos'), @('10m', 'Longer than 10 minutes'), @('1h', 'Longer than 1 hour'), @('3h', 'Longer than 3 hours'),
    @('shorts', 'Shorts (1 minute or less)'), @('unknown', 'Length not known yet')
)
$WhShowMax = 3000

function Get-WhRowList {
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($e in (Read-WatchHistory).Values) {
        $sec = -2.0
        if ($null -ne $e.d) { $sec = [double]$e.d }
        $w = [datetime]::MinValue
        if ($e.w) { [void][datetime]::TryParse($e.w, $Inv, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$w) }
        $title = if ($e.t) { $e.t } else { "(title not known yet - $($e.id))" }
        $rows.Add([pscustomobject]@{ Id = $e.id; Title = $title; Channel = [string]$e.c; Seconds = $sec; Watched = $w; Times = [int]$e.n })
    }
    return ,$rows
}

function Sync-WhList {
    $q = $script:WhSearch.Text.Trim()
    $flt = $WhFilters[$script:WhFilter.SelectedIndex][0]
    $view = @($script:WhRows | Where-Object {
        $ok = switch ($flt) {
            '10m' { $_.Seconds -gt 600 } '1h' { $_.Seconds -gt 3600 } '3h' { $_.Seconds -gt 10800 }
            'shorts' { $_.Seconds -ge 0 -and $_.Seconds -le 60 } 'unknown' { $_.Seconds -eq -2 } default { $true }
        }
        $ok -and (-not $q -or $_.Title.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or $_.Channel.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0)
    })
    $view = @($view | Sort-Object -Property @{ Expression = $script:WhSortProp; Descending = $script:WhSortDesc }, @{ Expression = 'Watched'; Descending = $true })
    $script:WhView = $view
    $selected = @{}
    foreach ($it in $script:WhList.SelectedItems) { $selected[[string]$it.Tag] = $true }
    $script:WhList.BeginUpdate()
    $script:WhList.Items.Clear()
    $items = New-Object System.Collections.Generic.List[System.Windows.Forms.ListViewItem]
    $n = [math]::Min($view.Count, $WhShowMax)
    for ($i = 0; $i -lt $n; $i++) {
        $r = $view[$i]
        $sec = if ($r.Seconds -eq -2) { $null } else { $r.Seconds }
        $it = New-Object System.Windows.Forms.ListViewItem((Format-Length $sec))
        [void]$it.SubItems.Add($r.Title)
        [void]$it.SubItems.Add($r.Channel)
        [void]$it.SubItems.Add($(if ($r.Watched -gt [datetime]::MinValue) { $r.Watched.ToLocalTime().ToString('yyyy-MM-dd') } else { '' }))
        [void]$it.SubItems.Add($(if ($r.Times -gt 1) { [string]$r.Times } else { '' }))
        $it.Tag = $r.Id
        if ($r.Seconds -eq -1) { $it.ForeColor = [System.Drawing.Color]::Gray }
        if ($selected[$r.Id]) { $it.Selected = $true }
        $items.Add($it)
    }
    $script:WhList.Items.AddRange($items.ToArray())
    $script:WhList.EndUpdate()

    $all = $script:WhRows
    $hours = 0.0; $unknown = 0
    foreach ($r in $all) { if ($r.Seconds -ge 0) { $hours += $r.Seconds } elseif ($r.Seconds -eq -2) { $unknown++ } }
    $txt = '{0:N0} videos  -  {1:N0} hours of video in total' -f $all.Count, ($hours / 3600)
    if ($unknown) { $txt += ('  -  {0:N0} without a length yet' -f $unknown) }
    if ($view.Count -ne $all.Count) { $txt += ('  -  {0:N0} match' -f $view.Count) }
    if ($view.Count -gt $WhShowMax) { $txt += " (showing the first $WhShowMax)" }
    $script:WhSummary.Text = $txt
}

function Sync-WhView([switch]$Force) {
    $busy = Test-HistoryBusy
    $st = Read-WhStatus
    $script:WhGet.Enabled = -not $busy
    $script:WhImport.Enabled = -not $busy
    $script:WhLengths.Enabled = -not $busy
    $script:WhStop.Visible = $busy
    if ($busy) {
        $script:WhBar.Visible = $true
        if ($st -and $st.total -gt 0) {
            $script:WhBar.Style = 'Continuous'; $script:WhBar.Maximum = [int]$st.total; $script:WhBar.Value = [int][math]::Min([double]$st.total, [double]$st.done)
        } else { $script:WhBar.Style = 'Marquee' }
    } else { $script:WhBar.Visible = $false }
    if ($st -and $st.message) {
        $script:WhStatusLine.Text = [string]$st.message
        $script:WhStatusLine.ForeColor = if ($st.state -eq 'error') { [System.Drawing.Color]::Firebrick } elseif ($st.state -eq 'done') { [System.Drawing.Color]::DarkGreen } else { [System.Drawing.Color]::DimGray }
    }
    # reload the list when the saved list changed (at most every 8 seconds while a lookup is running)
    $stamp = if (Test-Path -LiteralPath $WhFile) { (Get-Item -LiteralPath $WhFile).LastWriteTimeUtc } else { [datetime]::MinValue }
    $due = $Force -or ($stamp -ne $script:WhStamp -and (-not $busy -or ((Get-Date) - $script:WhLoadedAt).TotalSeconds -ge 8))
    if ($due) {
        $script:WhStamp = $stamp
        $script:WhLoadedAt = Get-Date
        $script:WhRows = Get-WhRowList
        Sync-WhList
        $script:WhEmpty.Visible = ($script:WhRows.Count -eq 0)
    }
}

function Get-WhSelectedIdList { @($script:WhList.SelectedItems | ForEach-Object { [string]$_.Tag }) }
# a real video opens directly; one only known by title (not found yet) opens a YouTube search for it
function Open-WhVideo([string]$id) {
    if (-not $id.StartsWith('~')) { Start-Process "https://www.youtube.com/watch?v=$id"; return }
    $r = $script:WhRows | Where-Object { $_.Id -eq $id } | Select-Object -First 1
    if ($r) { Start-Process ('https://www.youtube.com/results?search_query=' + [System.Uri]::EscapeDataString(($r.Title + ' ' + $r.Channel).Trim())) }
}
function Open-Guide { $g = Join-Path $PSScriptRoot 'Guide.html'; if (Test-Path -LiteralPath $g) { Start-Process $g } }

function Show-HistoryWindow($ownerForm) {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $f = New-Object System.Windows.Forms.Form
    $script:WhForm = $f
    $f.SuspendLayout()
    $f.AutoScaleDimensions = [System.Drawing.SizeF]::new(96, 96)
    $f.AutoScaleMode = 'Dpi'
    $f.Font = New-Object System.Drawing.Font('Segoe UI', 9.75)
    $f.Text = 'Video Downloader - Watch history'
    $f.StartPosition = if ($ownerForm) { 'CenterParent' } else { 'CenterScreen' }
    $f.ClientSize = [System.Drawing.Size]::new(960, 640)
    $f.MinimumSize = [System.Drawing.Size]::new(780, 480)
    $ico = Join-Path $PSScriptRoot 'VideoDownloader.ico'
    if (Test-Path -LiteralPath $ico) { try { $f.Icon = New-Object System.Drawing.Icon($ico) } catch { Write-Debug $_ } }

    $script:WhGet = Initialize-Control -type Button -x 14 -y 12 -w 180 -h 32 -text 'Get from YouTube'
    $script:WhImport = Initialize-Control -type Button -x 200 -y 12 -w 230 -h 32 -text 'Import Google Takeout file...'
    $script:WhLengths = Initialize-Control -type Button -x 436 -y 12 -w 170 -h 32 -text 'Find missing lengths'
    $script:WhStop = Initialize-Control -type Button -x 612 -y 12 -w 80 -h 32 -text 'Stop'
    $script:WhStop.Visible = $false
    $howTo = New-Object System.Windows.Forms.LinkLabel
    $howTo.Text = 'How do I get my full history?'
    $howTo.Location = [System.Drawing.Point]::new(706, 19); $howTo.Size = [System.Drawing.Size]::new(240, 22)
    $howTo.Anchor = 'Top, Right'; $howTo.TextAlign = 'MiddleRight'
    $f.Controls.AddRange(@($script:WhGet, $script:WhImport, $script:WhLengths, $script:WhStop, $howTo))

    $f.Controls.Add((Initialize-Control -type Label -x 14 -y 60 -w 52 -h 22 -text 'Search:'))
    $script:WhSearch = Initialize-Control -type TextBox -x 68 -y 56 -w 300 -h 27
    $f.Controls.Add($script:WhSearch)
    $f.Controls.Add((Initialize-Control -type Label -x 382 -y 60 -w 44 -h 22 -text 'Show:'))
    $script:WhFilter = Initialize-Control -type ComboBox -x 428 -y 56 -w 230 -h 27
    $script:WhFilter.DropDownStyle = 'DropDownList'
    foreach ($x in $WhFilters) { [void]$script:WhFilter.Items.Add($x[1]) }
    $script:WhFilter.SelectedIndex = 0
    $f.Controls.Add($script:WhFilter)

    $script:WhSummary = Initialize-Control -type Label -x 14 -y 92 -w 932 -h 22 -text '' -anchor 'Top, Left, Right'
    $script:WhSummary.Font = New-Object System.Drawing.Font('Segoe UI', 9.75, [System.Drawing.FontStyle]::Bold)
    $f.Controls.Add($script:WhSummary)

    $script:WhList = Initialize-Control -type ListView -x 14 -y 118 -w 932 -h 400 -text '' -anchor 'Top, Bottom, Left, Right'
    $script:WhList.View = 'Details'; $script:WhList.FullRowSelect = $true; $script:WhList.HideSelection = $false; $script:WhList.MultiSelect = $true
    [void]$script:WhList.Columns.Add('Length', 80, [System.Windows.Forms.HorizontalAlignment]::Right)
    [void]$script:WhList.Columns.Add('Title', 450)
    [void]$script:WhList.Columns.Add('Channel', 190)
    [void]$script:WhList.Columns.Add('Last watched', 110)
    [void]$script:WhList.Columns.Add('Times', 60, [System.Windows.Forms.HorizontalAlignment]::Right)
    $f.Controls.Add($script:WhList)

    $script:WhEmpty = Initialize-Control -type Label -x 40 -y 200 -w 880 -h 120 -text "No history yet.`n`nClick 'Get from YouTube' to read your recent history (needs your YouTube sign-in - see Help),`nor 'Import Google Takeout file...' to load your whole history from a Google Takeout export." -anchor 'Top, Left, Right'
    $script:WhEmpty.TextAlign = 'MiddleCenter'; $script:WhEmpty.ForeColor = [System.Drawing.Color]::DimGray
    $script:WhEmpty.BackColor = [System.Drawing.SystemColors]::Window
    $f.Controls.Add($script:WhEmpty); $script:WhEmpty.BringToFront()

    $script:WhBar = Initialize-Control -type ProgressBar -x 14 -y 526 -w 932 -h 10 -text '' -anchor 'Bottom, Left, Right'
    $script:WhBar.Visible = $false; $script:WhBar.MarqueeAnimationSpeed = 30
    $f.Controls.Add($script:WhBar)
    $script:WhStatusLine = Initialize-Control -type Label -x 14 -y 540 -w 932 -h 40 -text '' -anchor 'Bottom, Left, Right'
    $f.Controls.Add($script:WhStatusLine)

    $f.Controls.Add((Initialize-Control -type Label -x 14 -y 594 -w 132 -h 22 -text 'Download selected as' -anchor 'Bottom, Left'))
    $whMode = Initialize-Control -type ComboBox -x 148 -y 590 -w 150 -h 27 -text '' -anchor 'Bottom, Left'
    $whMode.DropDownStyle = 'DropDownList'
    $script:WhModes = @($AppModes | Where-Object { $_[0] -ne 'playlist' })
    foreach ($m in $script:WhModes) { [void]$whMode.Items.Add($m[1]) }
    $whMode.SelectedIndex = 0
    $script:WhModeBox = $whMode
    $whDl = Initialize-Control -type Button -x 304 -y 588 -w 100 -h 32 -text 'Download' -anchor 'Bottom, Left'
    $whOpen = Initialize-Control -type Button -x 414 -y 588 -w 140 -h 32 -text 'Open on YouTube' -anchor 'Bottom, Left'
    $whCsv = Initialize-Control -type Button -x 560 -y 588 -w 120 -h 32 -text 'Save as CSV...' -anchor 'Bottom, Left'
    $whClear = Initialize-Control -type Button -x 686 -y 588 -w 110 -h 32 -text 'Clear list...' -anchor 'Bottom, Left'
    $whClose = Initialize-Control -type Button -x 846 -y 588 -w 100 -h 32 -text 'Close' -anchor 'Bottom, Right'
    $whClose.DialogResult = 'Cancel'
    $f.CancelButton = $whClose
    $f.Controls.AddRange(@($whMode, $whDl, $whOpen, $whCsv, $whClear, $whClose))

    $script:WhSortProp = 'Seconds'; $script:WhSortDesc = $true
    $script:WhStamp = [datetime]::MinValue; $script:WhLoadedAt = [datetime]::MinValue
    $script:WhRows = New-Object System.Collections.Generic.List[object]
    $script:WhView = @()

    $script:WhGet.Add_Click({
        if (-not (Test-SignIn)) {
            $a = [System.Windows.Forms.MessageBox]::Show("Reading your history straight from YouTube needs your YouTube sign-in (a cookies.txt file, or Firefox - see Settings > Network).`n`nOpen the guide that shows how to set it up (about 1 minute)?`n`n(Or use 'Import Google Takeout file...' instead - no sign-in file needed.)", 'Watch history', 'YesNo', 'Information')
            if ($a -eq 'Yes') { Open-Guide }
            return
        }
        Write-WhStatus @{ state = 'running'; message = 'Starting...' }
        Invoke-Hidden @('-HistoryTask', 'fetch'); Start-Sleep -Milliseconds 400; Sync-WhView
    })
    $script:WhImport.Add_Click({
        $d = New-Object System.Windows.Forms.OpenFileDialog
        $d.Title = 'Choose your Google Takeout export (the .zip) or watch-history.json / .html'
        $d.Filter = 'Takeout export or history file|*.zip;*.json;*.html;*.htm;*.txt;*.csv|All files|*.*'
        $dl = $DownloadsDir
        if (Test-Path -LiteralPath $dl) { $d.InitialDirectory = $dl }
        if ($d.ShowDialog($script:WhForm) -ne [System.Windows.Forms.DialogResult]::OK) { return }
        Write-WhStatus @{ state = 'running'; message = 'Starting the import...' }
        Invoke-Hidden @('-HistoryTask', 'import', '-Path', $d.FileName); Start-Sleep -Milliseconds 400; Sync-WhView
    })
    $script:WhLengths.Add_Click({ Write-WhStatus @{ state = 'running'; message = 'Starting...' }; Invoke-Hidden @('-HistoryTask', 'lengths'); Start-Sleep -Milliseconds 400; Sync-WhView })
    $script:WhStop.Add_Click({ Suspend-HistoryTask; Start-Sleep -Milliseconds 600; Sync-WhView -Force })
    $howTo.Add_LinkClicked({ Open-Guide })
    $script:WhSearchTimer = New-Object System.Windows.Forms.Timer
    $script:WhSearchTimer.Interval = 350
    $script:WhSearchTimer.Add_Tick({ $script:WhSearchTimer.Stop(); Sync-WhList })
    $script:WhSearch.Add_TextChanged({ $script:WhSearchTimer.Stop(); $script:WhSearchTimer.Start() })
    $script:WhFilter.Add_SelectedIndexChanged({ Sync-WhList })
    $script:WhList.Add_ColumnClick({
        $prop = @('Seconds', 'Title', 'Channel', 'Watched', 'Times')[$_.Column]   # ($_ = the click's event arguments)
        if ($prop -eq $script:WhSortProp) { $script:WhSortDesc = -not $script:WhSortDesc }
        else { $script:WhSortProp = $prop; $script:WhSortDesc = $prop -in 'Seconds', 'Watched', 'Times' }
        Sync-WhList
    })
    $script:WhList.Add_DoubleClick({ foreach ($id in (Get-WhSelectedIdList | Select-Object -First 1)) { Open-WhVideo $id } })
    $whOpen.Add_Click({
        $ids = Get-WhSelectedIdList
        if (-not $ids.Count) { [void][System.Windows.Forms.MessageBox]::Show('Select a video in the list first.', 'Watch history'); return }
        foreach ($id in ($ids | Select-Object -First 5)) { Open-WhVideo $id }
    })
    $whDl.Add_Click({
        $all = Get-WhSelectedIdList
        if (-not $all.Count) { [void][System.Windows.Forms.MessageBox]::Show('Select one or more videos first (hold Ctrl or Shift to pick several).', 'Watch history'); return }
        $ids = @($all | Where-Object { -not $_.StartsWith('~') })
        if (-not $ids.Count) { [void][System.Windows.Forms.MessageBox]::Show("These haven't been found on YouTube yet, so there's no link to download. Double-click one to search for it.", 'Watch history'); return }
        $mode = $script:WhModes[$script:WhModeBox.SelectedIndex][0]
        if ($ids.Count -gt 20) {
            $a = [System.Windows.Forms.MessageBox]::Show("Download all $($ids.Count) selected videos?", 'Watch history', 'YesNo', 'Question')
            if ($a -ne 'Yes') { return }
        }
        foreach ($id in $ids) { Add-Job @{ Mode = $mode; Url = "https://www.youtube.com/watch?v=$id" } }
        Invoke-Runner
        $script:WhStatusLine.ForeColor = [System.Drawing.Color]::DarkGreen
        $script:WhStatusLine.Text = "Added $($ids.Count) video(s) to your downloads - the main window shows the progress."
        if ($all.Count -gt $ids.Count) { $script:WhStatusLine.Text += " $($all.Count - $ids.Count) skipped (not found on YouTube yet)." }
    })
    $whCsv.Add_Click({
        $d = New-Object System.Windows.Forms.SaveFileDialog
        $d.Filter = 'CSV (opens in Excel)|*.csv'; $d.FileName = 'YouTube watch history.csv'
        if ($d.ShowDialog($script:WhForm) -ne [System.Windows.Forms.DialogResult]::OK) { return }
        $script:WhView | ForEach-Object {
            [pscustomobject]@{
                Title = $_.Title; Channel = $_.Channel
                Length = $(if ($_.Seconds -ge 0) { Format-Length $_.Seconds } else { '' })
                Seconds = $(if ($_.Seconds -ge 0) { [int]$_.Seconds } else { '' })
                'Last watched' = $(if ($_.Watched -gt [datetime]::MinValue) { $_.Watched.ToLocalTime().ToString('yyyy-MM-dd HH:mm') } else { '' })
                Times = $_.Times; Link = $(if ($_.Id.StartsWith('~')) { '' } else { "https://www.youtube.com/watch?v=$($_.Id)" })
            }
        } | Export-Csv -LiteralPath $d.FileName -NoTypeInformation -Encoding UTF8
        $script:WhStatusLine.ForeColor = [System.Drawing.Color]::DarkGreen
        $script:WhStatusLine.Text = "Saved $($script:WhView.Count) videos to $($d.FileName)"
    })
    $whClear.Add_Click({
        $a = [System.Windows.Forms.MessageBox]::Show("Clear this list?`n`nThis only empties the list in Video Downloader. Your history on YouTube is not touched, and you can get it again any time.", 'Watch history', 'YesNo', 'Question')
        if ($a -ne 'Yes') { return }
        if (Test-HistoryBusy) { Suspend-HistoryTask; Start-Sleep -Milliseconds 800 }
        Remove-Item -LiteralPath $WhFile, $WhStatus -Force -ErrorAction SilentlyContinue
        $script:WhStatusLine.Text = ''
        Sync-WhView -Force
    })

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 1000
    $timer.Add_Tick({ try { Sync-WhView } catch { Write-Debug $_ } })
    $f.Add_Shown({ Sync-WhView -Force; $timer.Start(); $this.Activate() })
    $f.Add_FormClosed({ $timer.Stop() })
    $f.ResumeLayout($false)
    if ($ownerForm) { [void]$f.ShowDialog($ownerForm) } else { [void]$f.ShowDialog() }
    $f.Dispose()
}

# ============================== THE MAIN WINDOW ==============================
$AppModes = @(
    @('video', 'Video'), @('phone', 'Phone'), @('best', 'Best quality'), @('edit', 'Editor-friendly'),
    @('audio', 'Audio only'), @('playlist', 'Whole playlist'), @('shrink', 'Shrink (smaller file)')
)

# Links copied from Google results / YouTube descriptions are redirects: use the real address inside them
function Resolve-Link([string]$u) {
    $u = $u.Trim().Trim('"', "'", '<', '>')
    for ($i = 0; $i -lt 3; $i++) {
        if ($u -match '^https?://(www\.)?(google\.[a-z.]+/url|youtube\.com/redirect|l\.facebook\.com/l\.php|out\.reddit\.com/)[^?]*\?(.*)$') {
            $inner = $null
            foreach ($pair in $Matches[3] -split '&') {
                $kv = $pair -split '=', 2
                if ($kv.Count -eq 2 -and $kv[0] -in 'url', 'q', 'u' -and $kv[1]) {
                    $cand = [System.Uri]::UnescapeDataString($kv[1].Replace('+', ' '))
                    if ($cand -match '^https?://') { $inner = $cand; break }
                }
            }
            if ($inner) { $u = $inner; continue }
        }
        break
    }
    return $u
}
function Get-LinkList([string]$text) {
    @($text -split '\s+' | Where-Object { $_ } | ForEach-Object { Resolve-Link $_ } | Where-Object { $_ -match '^https?://\S+$' })
}

function Get-ShortUrl([string]$u) {
    if ($u -match '[?&]v=([A-Za-z0-9_-]{11})') { return "YouTube video $($Matches[1])" }
    if ($u -match '^https?://(www\.)?([^/]+)(/[^?#]*)?') { return $Matches[2] + $Matches[3] }
    return $u
}

function Read-History([int]$max = 40) {
    if (-not (Test-Path -LiteralPath $HistFile)) { return @() }
    $lines = @(Get-Content -LiteralPath $HistFile -Tail $max -Encoding UTF8 -ErrorAction SilentlyContinue)
    $out = New-Object System.Collections.Generic.List[object]
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if (-not $lines[$i].Trim()) { continue }
        try { $out.Add(($lines[$i] | ConvertFrom-Json)) } catch { Write-Debug $_ }
    }
    return $out
}

function Sync-AppView([switch]$Force) {
    $f = $script:Form
    if ($script:ShowEvent -and $script:ShowEvent.WaitOne(0)) {
        if ($f.WindowState -eq 'Minimized') { $f.WindowState = 'Normal' }
        $f.TopMost = $true; $f.Activate(); $f.TopMost = $false
    }
    if ($script:UpdLink -and (Test-Path -LiteralPath $AppUpdateFile)) {
        $stamp = (Get-Item -LiteralPath $AppUpdateFile).LastWriteTime
        if ($stamp -ne $script:UpdSeen) {
            $script:UpdSeen = $stamp
            $u = Get-AppUpdate
            if ($u) { $script:UpdLink.Text = "Version $($u.latest) is out - update"; $script:UpdLink.Tag = [string]$u.url; $script:UpdLink.Visible = $true }
            else { $script:UpdLink.Visible = $false }
        }
    }
    $active = Test-RunnerActive
    $st = Read-Status
    $running = @(Get-ChildItem -LiteralPath $RunDir -Filter '*.job' -File -ErrorAction SilentlyContinue)
    $queued = @(Get-ChildItem -LiteralPath $QueueDir -Filter '*.job' -File -ErrorAction SilentlyContinue | Sort-Object Name)
    $waiting = $running.Count + $queued.Count

    # waiting downloads start by themselves unless you pressed Pause; after a dropped connection, retry every minute
    if ($active -and $st -and $st.phase -eq 'downloading' -and [double]$st.percent -gt 0) { $script:NetFails = 0 }   # it's working again
    $script:RetryIn = $null
    if (-not $active -and $waiting -gt 0 -and -not (Test-Path -LiteralPath $PausedFlag)) {
        $netProblem = $st -and $st.state -in 'offline', 'intercepted', 'blocked'
        if ($netProblem) {
            # each new failure waits longer before the next automatic try: 1, 2, 5, 10, then every 15 minutes (30 when YouTube is blocking)
            if ([string]$st.updated -ne $script:LastFailSeen) {
                $script:LastFailSeen = [string]$st.updated
                $script:NetFails++
                $mins = @(1, 2, 5, 10, 15)[[math]::Min($script:NetFails, 5) - 1]
                if ($st.state -eq 'blocked') { $mins = 30 }
                $script:NextTry = (Get-Date).AddMinutes($mins)
            }
            if (-not $script:NextTry) { $script:NextTry = Get-Date }
            if ((Get-Date) -ge $script:NextTry) { $script:NextTry = (Get-Date).AddSeconds(20); Invoke-Runner }
            else { $script:RetryIn = $script:NextTry - (Get-Date) }
        } else {
            $sinceKick = if ($script:KickAt) { ((Get-Date) - $script:KickAt).TotalSeconds } else { 1e9 }
            if ($sinceKick -ge 12) { Invoke-Runner }
        }
    }

    # --- "Now downloading" box
    if ($active -and $st -and $st.state -in 'downloading', 'updating') {
        $title = if ($st.title) { [string]$st.title } else { Get-ShortUrl ([string]$st.url) }
        if ($st.state -eq 'updating') { $title = 'Updating yt-dlp...' }
        $script:NowTitle.Text = $title
        $script:PauseBtn.Text = 'Pause'; $script:PauseBtn.Enabled = $true
        if ($st.phase -eq 'downloading') {
            $script:NowBar.Style = 'Continuous'
            $script:NowBar.Value = [int][math]::Max(0, [math]::Min(100, [double]$st.percent))
            $info = '{0:0.0}%' -f [double]$st.percent
            if ($st.speed -and $st.speed -notmatch 'Unknown|NA') { $info += '   -   ' + $st.speed }
            if ($st.eta -and $st.eta -notmatch 'Unknown|NA') { $info += '   -   ' + $st.eta + ' left' }
            $script:NowInfo.Text = $info
        } else {
            $script:NowBar.Style = 'Marquee'
            $script:NowInfo.Text = @{ starting = 'Getting the video ready...'; finishing = 'Finishing up (putting video and sound together)...'
                                      converting = 'Making it phone-friendly...'; shrinking = 'Shrinking the file (this can take a while)...' }[[string]$st.phase]
            if (-not $script:NowInfo.Text) { $script:NowInfo.Text = 'Working...' }
        }
        $script:StatusLine.Text = if ($queued.Count) { "$($queued.Count) more waiting" } else { '' }
        $script:StatusLine.ForeColor = [System.Drawing.Color]::DimGray
    } elseif ($waiting -gt 0 -and $script:KickAt -and ((Get-Date) - $script:KickAt).TotalSeconds -lt 10) {
        $script:NowTitle.Text = 'Starting...'
        $script:NowInfo.Text = 'Getting the downloader ready...'
        $script:NowBar.Style = 'Marquee'
        $script:PauseBtn.Text = 'Pause'; $script:PauseBtn.Enabled = $false
        $script:StatusLine.Text = ''
    } elseif ($waiting -gt 0) {
        $script:NowBar.Style = 'Continuous'; $script:NowBar.Value = 0
        $script:PauseBtn.Text = 'Resume'; $script:PauseBtn.Enabled = $true
        if ($st -and $st.state -in 'offline', 'blocked', 'intercepted' -and $st.message) {
            $script:NowTitle.Text = switch ([string]$st.state) { 'offline' { 'Waiting for the internet' } 'intercepted' { 'Your network is blocking secure connections' } default { 'YouTube is blocking downloads for a while' } }
            $script:NowInfo.Text = if ($script:RetryIn) { "{0} waiting - trying again in {1}:{2:00} (or press Resume to try now)" -f $waiting, [int][math]::Floor($script:RetryIn.TotalMinutes), $script:RetryIn.Seconds } else { "$waiting waiting - trying again now..." }
            $script:StatusLine.Text = [string]$st.message
            $script:StatusLine.ForeColor = [System.Drawing.Color]::Firebrick
        } else {
            $script:NowTitle.Text = 'Paused'
            $script:NowInfo.Text = "$waiting waiting - press Resume to continue (half-done downloads carry on where they stopped)."
            $script:StatusLine.Text = ''
        }
    } else {
        $script:NowTitle.Text = 'Nothing downloading'
        $script:NowInfo.Text = 'Paste a link above, or click Download under any YouTube video.'
        $script:NowBar.Style = 'Continuous'; $script:NowBar.Value = 0
        $script:PauseBtn.Text = 'Pause'; $script:PauseBtn.Enabled = $false
        $script:StatusLine.Text = ''
    }

    # --- the list: downloading, waiting, then finished (newest first)
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($jf in $running) {
        $j = Read-JobFile $jf.FullName; if (-not $j) { continue }
        $t = if ($st -and $st.url -eq $j.Url -and $st.title) { [string]$st.title } else { Get-ShortUrl $j.Url }
        $s = if ($active) { if ($st.phase -eq 'downloading') { 'Downloading {0:0}%' -f [double]$st.percent } else { 'Working...' } } else { 'Paused' }
        $rows.Add(@{ text = $t; mode = $ModeNames[[string]$j.Mode]; status = $s; kind = 'running'; file = $jf.FullName })
    }
    foreach ($jf in $queued) {
        $j = Read-JobFile $jf.FullName; if (-not $j) { continue }
        $rows.Add(@{ text = (Get-ShortUrl $j.Url); mode = $ModeNames[[string]$j.Mode]; status = 'Waiting'; kind = 'waiting'; file = $jf.FullName })
    }
    foreach ($h in (Read-History 40)) {
        $t = if ($h.title) { [string]$h.title } else { Get-ShortUrl ([string]$h.url) }
        if ($h.ok) {
            $path = @($h.files) | Select-Object -Last 1
            $rows.Add(@{ text = $t; mode = $ModeNames[[string]$h.mode]; status = 'Done'; kind = 'done'; file = [string]$path })
        } else {
            $rows.Add(@{ text = $t; mode = $ModeNames[[string]$h.mode]; status = 'Failed - double-click for why'; kind = 'failed'; error = [string]$h.error; hint = [string]$h.hint })
        }
    }
    $sig = ($rows | ForEach-Object { $_.text + '|' + $_.status + '|' + $_.file }) -join "`n"
    if ($Force -or $sig -ne $script:ListSig) {
        $script:ListSig = $sig
        $sel = if ($script:List.SelectedItems.Count) { $script:List.SelectedItems[0].Tag.file } else { $null }
        $script:List.BeginUpdate()
        $script:List.Items.Clear()
        foreach ($r in $rows) {
            $it = New-Object System.Windows.Forms.ListViewItem([string]$r.text)
            [void]$it.SubItems.Add([string]$r.mode)
            [void]$it.SubItems.Add([string]$r.status)
            $it.Tag = $r
            if ($r.kind -eq 'failed') { $it.ForeColor = [System.Drawing.Color]::Firebrick }
            elseif ($r.kind -eq 'done') { $it.ForeColor = [System.Drawing.Color]::DarkGreen }
            elseif ($r.kind -eq 'running') { $it.Font = New-Object System.Drawing.Font($script:List.Font, [System.Drawing.FontStyle]::Bold) }
            if ($sel -and $r.file -eq $sel) { $it.Selected = $true }
            [void]$script:List.Items.Add($it)
        }
        $script:List.EndUpdate()
    }

    # --- opened by a download from the browser: close again when everything went well
    if ($AutoOpened -and [bool]$S.CloseWhenDone -and -not $script:UserTouched) {
        $newFail = @(Read-History 10 | Where-Object { -not $_.ok -and [datetime]$_.time -gt $script:OpenedAt }).Count
        if (-not $active -and $waiting -eq 0 -and $newFail -eq 0) {
            if (-not $script:IdleSince) { $script:IdleSince = Get-Date }
            $left = 6 - [int]((Get-Date) - $script:IdleSince).TotalSeconds
            $script:StatusLine.Text = "All done - closing in $left s (click anywhere in this window to keep it open)"
            $script:StatusLine.ForeColor = [System.Drawing.Color]::DarkGreen
            if ($left -le 0) { $f.Close() }
        } else { $script:IdleSince = $null }
    }
}

function Initialize-Control([string]$type, [int]$x, [int]$y, [int]$w, [int]$h, [string]$text = '', [string]$anchor = 'Top, Left') {
    $c = New-Object "System.Windows.Forms.$type"
    $c.Location = [System.Drawing.Point]::new($x, $y)
    $c.Size = [System.Drawing.Size]::new($w, $h)
    if ($text) { $c.Text = $text }
    $c.Anchor = $anchor
    return $c
}

function Show-App {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    # one window only: a second start just brings the open one to the front
    $script:AppMutex = New-Object System.Threading.Mutex($false, 'Local\VideoDownloaderApp')
    $owned = $false
    try { $owned = $script:AppMutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $owned = $true }
    if (-not $owned) {
        try { [void]([System.Threading.EventWaitHandle]::OpenExisting('Local\VideoDownloaderAppShow')).Set() } catch { Write-Debug $_ }
        return
    }
    $script:ShowEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, 'Local\VideoDownloaderAppShow')
    $script:OpenedAt = Get-Date
    $script:UserTouched = $false
    $script:LastClip = ''
    $script:KickAt = $null
    if ($AutoOpened) { $script:KickAt = Get-Date }
    $script:NetFails = 0; $script:NextTry = $null; $script:LastFailSeen = ''; $script:RetryIn = $null

    $form = New-Object System.Windows.Forms.Form
    $script:Form = $form
    $form.SuspendLayout()
    $form.AutoScaleDimensions = [System.Drawing.SizeF]::new(96, 96)
    $form.AutoScaleMode = 'Dpi'
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9.75)
    $form.Text = "Video Downloader"
    $form.StartPosition = 'CenterScreen'
    $form.ClientSize = [System.Drawing.Size]::new(820, 600)
    $form.MinimumSize = [System.Drawing.Size]::new(660, 480)
    $ico = Join-Path $PSScriptRoot 'VideoDownloader.ico'
    if (Test-Path -LiteralPath $ico) { try { $form.Icon = New-Object System.Drawing.Icon($ico) } catch { Write-Debug $_ } }

    # --- add downloads
    $form.Controls.Add((Initialize-Control -type Label -x 14 -y 12 -w 500 -h 22 -text 'Paste a video link (several at once is fine):'))
    $script:UrlBox = Initialize-Control -type TextBox -x 14 -y 38 -w 506 -h 27 -text '' -anchor 'Top, Left, Right'
    $form.Controls.Add($script:UrlBox)
    $script:ModeBox = Initialize-Control -type ComboBox -x 528 -y 38 -w 178 -h 27 -text '' -anchor 'Top, Right'
    $script:ModeBox.DropDownStyle = 'DropDownList'
    foreach ($m in $AppModes) { [void]$script:ModeBox.Items.Add($m[1]) }
    $script:ModeBox.SelectedIndex = 0
    for ($i = 0; $i -lt $AppModes.Count; $i++) { if ($AppModes[$i][0] -eq $MenuDefault) { $script:ModeBox.SelectedIndex = $i } }
    $form.Controls.Add($script:ModeBox)
    $goBtn = Initialize-Control -type Button -x 712 -y 36 -w 94 -h 31 -text 'Download' -anchor 'Top, Right'
    $form.Controls.Add($goBtn)
    $form.AcceptButton = $goBtn
    $script:UpdLink = New-Object System.Windows.Forms.LinkLabel
    $script:UpdLink.Location = [System.Drawing.Point]::new(520, 12); $script:UpdLink.Size = [System.Drawing.Size]::new(286, 22)
    $script:UpdLink.Anchor = 'Top, Right'; $script:UpdLink.TextAlign = 'MiddleRight'; $script:UpdLink.Visible = $false
    $script:UpdLink.Add_LinkClicked({
        $u = [string]$script:UpdLink.Tag
        if ($u -notmatch ('^https://github\.com/' + [regex]::Escape($UpdateRepo) + '/')) { $u = $ReleasesPage }
        $a = [System.Windows.Forms.MessageBox]::Show(("{0}`n`nYes = update now (this window closes and reopens by itself; your downloads and settings are kept)`nNo = just show me what's new" -f $script:UpdLink.Text),
                'Update Video Downloader', 'YesNoCancel', 'Question')
        if ($a -eq 'Yes') { $script:UpdLink.Text = 'Updating...'; $script:UpdLink.Enabled = $false; Invoke-Hidden @('-UpdateApp') }
        elseif ($a -eq 'No') { Start-Process $u }
    })
    $form.Controls.Add($script:UpdLink)
    $script:UpdSeen = $null
    if (Test-AppUpdateDue) { Invoke-Hidden @('-CheckApp') }

    # --- now downloading
    $grp = Initialize-Control -type GroupBox -x 14 -y 80 -w 792 -h 116 -text 'Now downloading' -anchor 'Top, Left, Right'
    $script:NowTitle = Initialize-Control -type Label -x 12 -y 24 -w 650 -h 24 -text '' -anchor 'Top, Left, Right'
    $script:NowTitle.Font = New-Object System.Drawing.Font('Segoe UI', 10.5, [System.Drawing.FontStyle]::Bold)
    $script:NowTitle.AutoEllipsis = $true
    $script:NowBar = Initialize-Control -type ProgressBar -x 12 -y 52 -w 650 -h 20 -text '' -anchor 'Top, Left, Right'
    $script:NowBar.MarqueeAnimationSpeed = 30
    $script:NowInfo = Initialize-Control -type Label -x 12 -y 80 -w 650 -h 24 -text '' -anchor 'Top, Left, Right'
    $script:NowInfo.AutoEllipsis = $true
    $script:PauseBtn = Initialize-Control -type Button -x 676 -y 46 -w 100 -h 32 -text 'Pause' -anchor 'Top, Right'
    $grp.Controls.AddRange(@($script:NowTitle, $script:NowBar, $script:NowInfo, $script:PauseBtn))
    $form.Controls.Add($grp)

    # --- list
    $script:List = Initialize-Control -type ListView -x 14 -y 208 -w 792 -h 312 -text '' -anchor 'Top, Bottom, Left, Right'
    $script:List.View = 'Details'
    $script:List.FullRowSelect = $true
    $script:List.HideSelection = $false
    $script:List.MultiSelect = $false
    [void]$script:List.Columns.Add('Video', 440)
    [void]$script:List.Columns.Add('Type', 110)
    [void]$script:List.Columns.Add('Status', 220)
    $form.Controls.Add($script:List)

    # --- bottom row
    $openBtn = Initialize-Control -type Button -x 14 -y 530 -w 140 -h 32 -text 'Open videos folder' -anchor 'Bottom, Left'
    $removeBtn = Initialize-Control -type Button -x 160 -y 530 -w 90 -h 32 -text 'Remove' -anchor 'Bottom, Left'
    $clearBtn = Initialize-Control -type Button -x 256 -y 530 -w 120 -h 32 -text 'Clear finished' -anchor 'Bottom, Left'
    $histBtn = Initialize-Control -type Button -x 382 -y 530 -w 130 -h 32 -text 'Watch history' -anchor 'Bottom, Left'
    $helpBtn = Initialize-Control -type Button -x 616 -y 530 -w 90 -h 32 -text 'Help' -anchor 'Bottom, Right'
    $setBtn = Initialize-Control -type Button -x 712 -y 530 -w 94 -h 32 -text 'Settings' -anchor 'Bottom, Right'
    $form.Controls.AddRange(@($openBtn, $removeBtn, $clearBtn, $histBtn, $helpBtn, $setBtn))
    $script:StatusLine = Initialize-Control -type Label -x 14 -y 570 -w 792 -h 22 -text '' -anchor 'Bottom, Left, Right'
    $script:StatusLine.AutoEllipsis = $true
    $form.Controls.Add($script:StatusLine)

    # --- what the buttons do
    $goBtn.Add_Click({
        $script:UserTouched = $true
        $urls = Get-LinkList $script:UrlBox.Text
        if (-not $urls.Count) {
            [void][System.Windows.Forms.MessageBox]::Show('Paste a link that starts with http, for example a YouTube video address.', 'Video Downloader', 'OK', 'Information')
            return
        }
        $mode = $AppModes[$script:ModeBox.SelectedIndex][0]
        foreach ($u in $urls) { Add-Job @{ Mode = $mode; Url = $u } }
        $script:UrlBox.Text = ''
        Invoke-Runner
        Sync-AppView -Force
    })
    $script:ModeBox.Add_SelectedIndexChanged({
        $mode = $AppModes[$script:ModeBox.SelectedIndex][0]
        if ($mode -in 'video', 'phone', 'best', 'edit', 'audio' -and $mode -ne [string]$S.MenuDefault) { $S['MenuDefault'] = $mode; Save-Config; Use-Config }
    })
    $script:PauseBtn.Add_Click({
        $script:UserTouched = $true
        if (Test-RunnerActive) {
            $script:PauseBtn.Enabled = $false
            Suspend-Runner
        } else {
            $script:NextTry = $null
            Invoke-Runner
        }
        Sync-AppView -Force
    })
    $removeBtn.Add_Click({
        $script:UserTouched = $true
        if (-not $script:List.SelectedItems.Count) { return }
        $r = $script:List.SelectedItems[0].Tag
        switch ($r.kind) {
            'waiting' { Remove-Item -LiteralPath $r.file -Force -ErrorAction SilentlyContinue }
            'running' {
                $ans = [System.Windows.Forms.MessageBox]::Show("Stop and remove this download?`n`n$($r.text)", 'Video Downloader', 'YesNo', 'Question')
                if ($ans -eq 'Yes') {
                    if (Test-RunnerActive) { Suspend-Runner; Start-Sleep -Milliseconds 800 }
                    Remove-Item -LiteralPath $r.file -Force -ErrorAction SilentlyContinue
                    if ((Get-QueueCount) -gt 0) { Invoke-Runner }
                }
            }
            default {
                # finished items: just hide them from the list
                $keep = @(Get-Content -LiteralPath $HistFile -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object {
                    try { $h = $_ | ConvertFrom-Json; -not ([string]$h.title -eq $r.text -or (Get-ShortUrl ([string]$h.url)) -eq $r.text) } catch { $true } })
                Set-Content -LiteralPath $HistFile -Value $keep -Encoding UTF8
            }
        }
        Sync-AppView -Force
    })
    $histBtn.Add_Click({ $script:UserTouched = $true; Show-HistoryWindow $script:Form; Sync-AppView -Force })
    $clearBtn.Add_Click({ $script:UserTouched = $true; Set-Content -LiteralPath $HistFile -Value @() -Encoding UTF8; Sync-AppView -Force })
    $openBtn.Add_Click({ $script:UserTouched = $true; Open-Folder $VideoDir })
    $helpMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $miGuide = $helpMenu.Items.Add('Open the guide')
    $miUpdate = $helpMenu.Items.Add('Check for updates now (yt-dlp and Deno)')
    $miCheck = $helpMenu.Items.Add('Check my connection (makes a report)')
    [void]$helpMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $miData = $helpMenu.Items.Add('Open the data folder (settings, logs)')
    $miSite = $helpMenu.Items.Add('Project page, new versions, report a problem')
    $miGuide.Add_Click({ Open-Guide })
    $miUpdate.Add_Click({
        if (Test-RunnerActive) { [void][System.Windows.Forms.MessageBox]::Show('A download is running. Pause it (or let it finish) first, then check for updates.', 'Video Downloader', 'OK', 'Information'); return }
        Invoke-Hidden @('-UpdateNow')
        $script:StatusLine.ForeColor = [System.Drawing.Color]::DimGray
        $script:StatusLine.Text = 'Checking for updates in the background - a notification says when it is done.'
    })
    $miCheck.Add_Click({
        Invoke-Hidden @('-ConnectionCheck')
        $script:StatusLine.ForeColor = [System.Drawing.Color]::DimGray
        $script:StatusLine.Text = 'Checking your connection (about 2 minutes, includes a 25 MB speed test) - the report opens by itself.'
    })
    $miData.Add_Click({ Open-Folder $Base })
    $miSite.Add_Click({ Start-Process "https://github.com/$UpdateRepo" })
    $helpBtn.Add_Click({
        $script:UserTouched = $true
        $helpMenu.Show($helpBtn, (New-Object System.Drawing.Point(0, $helpBtn.Height)))
    })
    $setBtn.Add_Click({
        $script:UserTouched = $true
        Show-ConfigWindow $script:Form
        for ($i = 0; $i -lt $AppModes.Count; $i++) { if ($AppModes[$i][0] -eq $MenuDefault) { $script:ModeBox.SelectedIndex = $i } }
    })
    $script:List.Add_DoubleClick({
        $script:UserTouched = $true
        if (-not $script:List.SelectedItems.Count) { return }
        $r = $script:List.SelectedItems[0].Tag
        if ($r.kind -eq 'done' -and $r.file) {
            if (Test-Path -LiteralPath $r.file) { Start-Process explorer.exe -ArgumentList ('/select,"{0}"' -f $r.file) }
            else { [void][System.Windows.Forms.MessageBox]::Show("The file isn't there any more (moved or deleted):`n$($r.file)", 'Video Downloader') }
        } elseif ($r.kind -eq 'failed') {
            [void][System.Windows.Forms.MessageBox]::Show(("{0}`n`n{1}`n`nYouTube said:`n{2}" -f $r.text, $r.hint, $r.error), 'Why it failed', 'OK', 'Information')
        }
    })
    $script:List.Add_MouseDown({ $script:UserTouched = $true })
    $script:UrlBox.Add_TextChanged({ if ($script:UrlBox.Focused) { $script:UserTouched = $true } })
    $form.Add_Activated({
        # a link on the clipboard is offered automatically
        if ($script:UrlBox.Text) { return }
        try { $clip = [System.Windows.Forms.Clipboard]::GetText().Trim() } catch { $clip = '' }
        if ($clip -match '^https?://\S+$' -and $clip -ne $script:LastClip) {
            $script:LastClip = $clip
            $script:UrlBox.Text = Resolve-Link $clip
            $script:UrlBox.SelectAll()
        }
    })

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 700
    $timer.Add_Tick({ try { Sync-AppView } catch { Write-Debug $_ } })
    $form.Add_Shown({
        # waiting downloads (after a restart, lost Wi-Fi, ...) carry on by themselves unless you pressed Pause
        if ((Get-QueueCount) + @(Get-ChildItem -LiteralPath $RunDir -Filter '*.job' -File -ErrorAction SilentlyContinue).Count -gt 0 -and
            -not (Test-Path -LiteralPath $PausedFlag) -and -not (Test-RunnerActive)) { Invoke-Runner }
        Sync-AppView -Force; $timer.Start(); $this.Activate()
    })
    $form.Add_FormClosed({ $timer.Stop() })
    $form.ResumeLayout($false)
    [void]$form.ShowDialog()
    try { $script:AppMutex.ReleaseMutex() } catch { Write-Debug $_ }
}

# ============================== START ==============================
# A ytdl:// link comes from a web page. If a page crafts one with quotes to sneak in other options
# (-HistoryTask, -Path, ...), refuse it: a link may carry nothing but the link itself.
if ($PSBoundParameters.ContainsKey('Uri')) {
    if ($PSBoundParameters.Count -ne 1 -or $args.Count -gt 0 -or $Uri -notmatch '^ytdl://[A-Za-z0-9/_-]{1,64}$') {
        try { Add-Content -LiteralPath $ErrorLog -Value ("{0:yyyy-MM-dd HH:mm:ss}  refused a malformed ytdl:// link" -f (Get-Date)) -Encoding UTF8 } catch { Write-Debug $_ }
        Show-ErrorBox "A web page sent Video Downloader a link it doesn't accept, so it was ignored."
        exit 1
    }
}
Protect-CookieFile
Limit-PrivateData
try { Add-Content -LiteralPath (Join-Path $Base 'runs.log') -Value ("{0:yyyy-MM-dd HH:mm:ss}  v{1} uri='{2}' app={3} run={4} settings={5} menu={6}" -f (Get-Date), $AppVersion, $Uri, [bool]$App, [bool]$RunQueue, [bool]$Settings, [bool]$Menu) -Encoding UTF8 } catch { Write-Debug $_ }

if ($Settings) { Show-ConfigWindow; exit 0 }
if ($CheckApp) { Invoke-AppUpdateCheck; exit 0 }
if ($UpdateApp) { Invoke-AppUpdate; exit 0 }

Initialize-Toolset

if ($UpdateNow) {
    $script:IsRunner = $false
    Invoke-ToolUpdate
    if (-not $script:Interactive -and $env:OS -eq 'Windows_NT') { Show-Toast 'Video Downloader' 'yt-dlp and Deno are up to date.' }
    exit 0
}
if ($ConnectionCheck) {
    if ($env:OS -eq 'Windows_NT') {
        try { Invoke-WifiCheck } catch { Write-Debug $_ }
        try { Invoke-NetCheck } catch { Write-Debug $_ }
        $both = Join-Path $Base 'connection-check.txt'
        $text = @($WifiCheckFile, $NetCheckFile | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object { [System.IO.File]::ReadAllText($_) }) -join "`r`n`r`n"
        [System.IO.File]::WriteAllText($both, $text, (New-Object System.Text.UTF8Encoding($false)))
        Start-Process -FilePath 'notepad.exe' -ArgumentList ('"{0}"' -f $both)
    }
    exit 0
}
if ($HistoryTask) { Invoke-HistoryTask $HistoryTask $Path; exit 0 }
if ($NetCheck) { Invoke-NetCheck; exit 0 }
if ($History) { Show-HistoryWindow $null; exit 0 }

if ($RunQueue) {
    if (-not $script:YtDlp) { Install-Missing }
    if (-not $script:YtDlp) {
        Write-History @{ ok = $false; url = ''; mode = 'video'; title = 'yt-dlp is missing'; error = 'yt-dlp is not installed'; hint = 'Run Setup again to install yt-dlp, FFmpeg and Deno.' }
        exit 1
    }
    $null = Invoke-Queue
    Show-Finished
    exit 0
}

if ($Uri) {
    # ---- from the Download button in the browser: accept ONLY these exact shapes ----
    if ($Uri -match '^ytdl://settings/?$') { Show-ConfigWindow; exit 0 }
    if ($Uri -match '^ytdl://(app|open)/?$') { Show-App; exit 0 }
    if ($Uri -match '^ytdl://history/?$') { Show-HistoryWindow $null; exit 0 }
    $job = $null
    if ($Uri -match '^ytdl://(video|best|edit|audio|phone)/([A-Za-z0-9_-]{11})/?$') {
        $job = @{ Mode = $Matches[1]; Url = "https://www.youtube.com/watch?v=$($Matches[2])" }
    } elseif ($Uri -match '^ytdl://clip/([A-Za-z0-9_-]{11})/(\d{1,6})-(\d{1,6})/?$' -and [int]$Matches[3] -gt [int]$Matches[2]) {
        $job = @{ Mode = 'clip'; Url = "https://www.youtube.com/watch?v=$($Matches[1])"; Start = [int]$Matches[2]; End = [int]$Matches[3] }
    }
    if (-not $job) { Show-ErrorBox "That download link wasn't understood, so nothing was downloaded:`n$Uri"; exit 1 }
    Add-Job $job
    Invoke-Runner
    if ([bool]$S.OpenAppOnDownload) { Invoke-Hidden @('-App', '-AutoOpened') }   # (if the window is already open it just stays)
    exit 0
}

if (-not $Menu) {
    if (-not $script:YtDlp -and $env:OS -eq 'Windows_NT') {
        Show-ErrorBox "yt-dlp (the part that does the downloading) isn't installed. Run Setup again to install it."
    }
    Show-App
    exit 0
}

# ============================== TEXT VERSION (-Menu) ==============================
if (-not $script:YtDlp) { Install-Missing }
if (-not $script:YtDlp) {
    Say 'yt-dlp is not installed and could not be installed automatically. Run Setup again.' Red
    Read-Host 'Press Enter to close' | Out-Null; exit 1
}
function Get-MenuText {
    @"

  Enter = $($ModeNames[$MenuDefault])   (change this in Settings)
  V     = Video, up to ${MaxHeight}p
  P     = Phone: ${PhoneHeight}p H.264, plays on any phone/app
  4     = Best quality
  E     = Editor-friendly (H.264)
  A     = Audio only ($($AudioFormat.ToUpper()))
  C     = Clip: just part of the video
  L     = Whole playlist (skips ones you already have)
  S     = Shrink: re-encode to a much smaller file
  T     = Settings    U = Update yt-dlp    O = Open Videos folder
"@
}
$waitingNow = Get-QueueCount
if ($waitingNow -gt 0 -and -not (Test-RunnerActive)) {
    Say ("{0} queued download(s) waiting - starting them now." -f $waitingNow) Cyan
    $null = Invoke-QueueHere
}
while ($true) {
    Write-Host ''
    $clip = ''
    try { $clip = "$(Get-Clipboard -Raw -ErrorAction SilentlyContinue)".Trim() } catch { Write-Debug $_ }
    $hasClip = $clip -match '^https?://\S+$'
    if ($hasClip) { Say "Link on your clipboard: $clip" DarkGray; $prompt = 'Paste link(s), press Enter to use the clipboard link, or Q to quit' }
    else { $prompt = 'Paste link(s) - several at once is fine - or press Enter to quit' }
    $raw = Read-Host $prompt
    if (-not $raw) { if ($hasClip) { $raw = $clip } else { break } }
    if ($raw.Trim() -match '^(q|quit|exit)$') { break }
    if ($raw.Trim() -match '^[oO]$') { Open-Folder $VideoDir; continue }
    if ($raw.Trim() -match '^[uU]$') { Invoke-ToolUpdate; continue }
    if ($raw.Trim() -match '^[tT]$') { Show-ConfigWindow; continue }

    $urls = Get-LinkList $raw
    if ($urls.Count -eq 0) { Say "That doesn't look like a link (it should start with http)." Red; continue }

    Write-Host (Get-MenuText)
    $choice = "$(Read-Host 'Choose')".Trim().ToUpper()
    $mode = switch ($choice) {
        ''  { $MenuDefault } 'V' { 'video' } 'P' { 'phone' } '4' { 'best' } 'E' { 'edit' } 'A' { 'audio' } 'C' { 'clip' }
        'L' { 'playlist' } 'S' { 'shrink' } 'T' { 'settings' } 'U' { 'update' } 'O' { 'open' } default { 'unknown' }
    }
    if ($mode -eq 'unknown')  { Say "'$choice' isn't on the list - nothing downloaded." Red; continue }
    if ($mode -eq 'settings') { Show-ConfigWindow; continue }
    if ($mode -eq 'update')   { Invoke-ToolUpdate; continue }
    if ($mode -eq 'open')     { Open-Folder $VideoDir; continue }

    $start = $null; $end = $null
    if ($mode -eq 'clip') {
        $start = ConvertFrom-ClockText (Read-Host 'Start time (e.g. 1:30)')
        $end   = ConvertFrom-ClockText (Read-Host 'End time   (e.g. 2:05)')
        if ($null -eq $start -or $null -eq $end -or $end -le $start) { Say 'Times not understood - use m:ss or h:mm:ss, end after start.' Red; continue }
    }
    foreach ($u in $urls) {
        $j = @{ Mode = $mode; Url = $u }
        if ($mode -eq 'clip') { $j.Start = [int][math]::Floor($start); $j.End = [int][math]::Ceiling($end) }
        Add-Job $j
    }
    if ($urls.Count -gt 1) { Say ("Queued {0} links." -f $urls.Count) Green }
    $null = Invoke-QueueHere
    if ($script:Failed.Count) { Say ("{0} failed this session - see above." -f $script:Failed.Count) Yellow }
}
