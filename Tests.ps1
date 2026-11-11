<#
  Video Downloader - automatic checks.
  GitHub runs these on Windows (Windows PowerShell 5.1, like most users have) every time files are uploaded,
  so a mistake shows up as a red X on GitHub instead of on someone's PC.
  Run them yourself:  powershell -ExecutionPolicy Bypass -File Tests.ps1
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Coloured text for the person watching the console window')]
param()
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$IsWin = $env:OS -eq 'Windows_NT'
$script:Fails = 0; $script:Passes = 0

function Check([string]$name, [scriptblock]$test) {
    try {
        $r = & $test
        if ($r -is [bool] -and -not $r) { throw 'check returned false' }
        $script:Passes++; Write-Host "  ok    $name" -ForegroundColor Green
    } catch {
        $script:Fails++; Write-Host "  FAIL  $name" -ForegroundColor Red; Write-Host "        $($_.Exception.Message)" -ForegroundColor Red
    }
}
function Expect($got, $want) { if ("$got" -ne "$want") { throw "expected [$want] but got [$got]" } }
function Read-Text([string]$name) { return [System.IO.File]::ReadAllText((Join-Path $root $name), [System.Text.Encoding]::UTF8) }

# ---------------------------------------------------------------- files
Write-Host "`nFiles"
foreach ($f in 'VideoDownloader.ps1', 'Install.ps1', 'Uninstall.ps1', 'Build-Release.ps1', 'Tests.ps1', 'get.ps1') {
    Check "$f has no syntax errors" {
        $t = $null; $e = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $f), [ref]$t, [ref]$e)
        if ($e.Count) { throw (($e | ForEach-Object { $_.ToString() }) -join ' | ') }
    }
}
foreach ($f in 'VideoDownloader.ps1', 'Install.ps1', 'Uninstall.ps1', 'Build-Release.ps1', 'Tests.ps1', 'get.ps1', 'Setup.cmd', 'video-downloader.cmd', 'README.txt') {
    Check "$f is plain ASCII (Windows PowerShell 5.1 and cmd misread other characters)" {
        $b = [System.IO.File]::ReadAllBytes((Join-Path $root $f))
        $n = 0; foreach ($x in $b) { if ($x -gt 127) { $n++ } }
        if ($n) { throw "$n non-ASCII bytes - replace curly quotes, dashes and emoji" }
    }
}
foreach ($f in 'Guide.html', 'VideoDownloader.user.js', 'VideoDownloader.ico', 'extension-manifest.json', 'extension-icon.png', 'README.md', 'LICENSE',
           'video-downloader.py', 'install.sh', 'video-downloader.png', 'README-linux.txt', 'build-linux-release.py', 'get.ps1', 'video-downloader.cmd') {
    Check "$f is present" { Test-Path -LiteralPath (Join-Path $root $f) }
}
foreach ($f in 'Setup.cmd', 'video-downloader.cmd') {
    Check "$f has Windows line endings (with bare LF, cmd can jump to the wrong label)" {
        $b = [System.IO.File]::ReadAllBytes((Join-Path $root $f))
        for ($i = 0; $i -lt $b.Length; $i++) { if ($b[$i] -eq 10 -and ($i -eq 0 -or $b[$i - 1] -ne 13)) { throw "bare LF at byte $i" } }
    }
}

# ---------------------------------------------------------------- the update command
Write-Host "`nThe video-downloader command and the one-line install/update"
$vdc = Read-Text 'video-downloader.cmd'
Check '"video-downloader update" runs the newest get.ps1 from this project (so it works for every future version)' {
    if (-not $vdc.Contains("set `"VD_GET=https://raw.githubusercontent.com/sleeeeeeeeeeeeeep-cmyl/VideoDownloader/main/get.ps1`"")) { throw 'wrong or missing get.ps1 address' }
    if ($vdc -notmatch "irm '%VD_GET%' \| iex") { throw 'get.ps1 is not run' }
}
Check 'the update runs from one ( ) block, so replacing the .cmd mid-update is harmless' {
    $i = $vdc.IndexOf(':cmd_update'); $blk = $vdc.Substring($i)
    $open = $blk.IndexOf("`n(") ; $ps = $blk.IndexOf('"%VD_PS%"'); $close = $blk.IndexOf("`n)")
    if ($open -lt 0 -or -not ($open -lt $ps -and $ps -lt $close)) { throw 'the PowerShell call is not inside the block' }
    if ($blk.Substring($open, $close - $open) -match 'goto |call :') { throw 'the block jumps back into the file' }
}
Check 'every command the help lists has a label' {
    foreach ($w in 'open', 'update', 'reinstall', 'version', 'settings', 'history', 'menu', 'uninstall', 'help') {
        if ($vdc -notmatch "(?m)^:cmd_$w\s*$") { throw "no :cmd_$w label" }
    }
}
Check 'the release ZIP and the installer include the command' {
    if ((Read-Text 'Build-Release.ps1') -notmatch "'video-downloader\.cmd'") { throw 'not in the release ZIP' }
    $inst = Read-Text 'Install.ps1'
    if ($inst -notmatch 'video-downloader\.cmd' -or $inst -notmatch 'Add-UserPath') { throw 'the installer does not install it' }
    if ((Read-Text 'Uninstall.ps1') -notmatch "Update Video Downloader\.lnk") { throw 'the uninstaller leaves the Update shortcut' }
}
Check 'get.ps1 reads installed versions and compares them like the app does' {
    $t = $null; $e = $null
    $ga = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'get.ps1'), [ref]$t, [ref]$e)
    foreach ($fn in 'ConvertTo-Ver', 'Get-ScriptVersion') {
        . ([scriptblock]::Create(($ga.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq $fn }, $true) | Select-Object -First 1).Extent.Text))
    }
    $want = if ((Read-Text 'VideoDownloader.ps1') -match "\`$AppVersion = '([0-9.]+)'") { $Matches[1] } else { 'missing' }
    Expect (Get-ScriptVersion (Join-Path $root 'VideoDownloader.ps1')) $want
    Expect (Get-ScriptVersion (Join-Path $root 'no-such-file.ps1')) ''
    if (-not ((ConvertTo-Ver '4.10') -gt (ConvertTo-Ver '4.9'))) { throw '4.10 should be newer than 4.9' }
    if (-not ((ConvertTo-Ver 'v4.7') -gt (ConvertTo-Ver '4.6.2'))) { throw '4.7 should be newer than 4.6.2' }
    if (-not ((ConvertTo-Ver '5') -gt (ConvertTo-Ver '4.7'))) { throw '5 should be newer than 4.7' }
    if ($null -ne (ConvertTo-Ver '?')) { throw 'an unreadable version must not count as a version' }
}

# ---------------------------------------------------------------- versions
Write-Host "`nVersion numbers"
$app = Read-Text 'VideoDownloader.ps1'
$ver = if ($app -match "\`$AppVersion = '([0-9.]+)'") { $Matches[1] } else { '' }
Check "the app has a version number ($ver)" { [bool]$ver }
Check 'the YouTube button script has the same version (Tampermonkey only updates when it goes up)' {
    $js = Read-Text 'VideoDownloader.user.js'
    if ($js -notmatch '@version\s+([0-9.]+)') { throw 'no @version line' }
    Expect $Matches[1] $ver
}
Check 'the browser extension has the same version' { Expect ((Read-Text 'extension-manifest.json') | ConvertFrom-Json).version $ver }
Check 'the Linux app has the same version' {
    if ((Read-Text 'video-downloader.py') -notmatch "(?m)^APP_VERSION = '([0-9.]+)'") { throw 'no APP_VERSION line' }
    Expect $Matches[1] $ver
}
Check 'CHANGELOG.md describes this version' { (Read-Text 'CHANGELOG.md') -match ('(?m)^## ' + [regex]::Escape($ver) + '\s*$') }

# ---------------------------------------------------------------- the button script
Write-Host "`nYouTube button script"
$js = Read-Text 'VideoDownloader.user.js'
Check 'only runs on YouTube and YouTube Music' {
    $m = @([regex]::Matches($js, '(?m)^// @match\s+(\S+)') | ForEach-Object { $_.Groups[1].Value })
    Expect ($m -join ' ') 'https://www.youtube.com/* https://music.youtube.com/*'
}
Check 'asks Tampermonkey for no special permissions (@grant none)' { $js -match '(?m)^// @grant\s+none\s*$' -and $js -notmatch '(?m)^// @grant\s+(?!none)\S' }
Check 'makes no network requests of its own' { $js -notmatch '\bfetch\(|XMLHttpRequest|sendBeacon|GM_xmlhttpRequest|new WebSocket' }
Check 'updates from this project on GitHub' { $js -match '(?m)^// @updateURL\s+https://raw\.githubusercontent\.com/sleeeeeeeeeeeeeep-cmyl/VideoDownloader/main/VideoDownloader\.user\.js\s*$' }
Check 'the extension only runs on YouTube and asks for no permissions' {
    $mf = (Read-Text 'extension-manifest.json') | ConvertFrom-Json
    if ($mf.permissions -or $mf.host_permissions) { throw 'the manifest asks for permissions' }
    Expect (@($mf.content_scripts[0].matches) -join ' ') 'https://www.youtube.com/* https://music.youtube.com/*'
}

# ---------------------------------------------------------------- code analysis
Write-Host "`nCode analysis (PSScriptAnalyzer: every rule, errors, warnings and information)"
$psa = Get-Module -ListAvailable PSScriptAnalyzer | Sort-Object Version -Descending | Select-Object -First 1
if (-not $psa -and $env:GITHUB_ACTIONS) {
    try { Install-Module PSScriptAnalyzer -Scope CurrentUser -Force -ErrorAction Stop; $psa = Get-Module -ListAvailable PSScriptAnalyzer | Select-Object -First 1 } catch { Write-Debug $_ }
}
if ($psa) {
    Import-Module $psa
    foreach ($f in 'VideoDownloader.ps1', 'Install.ps1', 'Uninstall.ps1', 'Build-Release.ps1', 'Tests.ps1', 'get.ps1') {
        Check "$f has no analyzer findings" {
            $found = @(Invoke-ScriptAnalyzer -Path (Join-Path $root $f) -Severity Error, Warning, Information)
            if ($found.Count) { throw (($found | ForEach-Object { 'line {0}: {1} ({2})' -f $_.Line, $_.Message, $_.RuleName }) -join ' | ') }
        }
    }
} elseif ($env:GITHUB_ACTIONS) {
    Check 'PSScriptAnalyzer is available' { $false }
} else {
    Write-Host '  (PSScriptAnalyzer is not installed here, so this part is skipped. GitHub always runs it.)' -ForegroundColor Yellow
}

# ---------------------------------------------------------------- the app's own functions
Write-Host "`nApp logic"
$t = $null; $e = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'VideoDownloader.ps1'), [ref]$t, [ref]$e)
foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    if ($fn.Name -ne 'Say') { . ([scriptblock]::Create($fn.Extent.Text)) }
}
function Say([string]$msg, [string]$color) { }
$script:UpdateRepo = 'sleeeeeeeeeeeeeep-cmyl/VideoDownloader'   # (read by the app's functions)
$script:S = @{ UseCookies = 'auto'; CookieSource = 'file'; CheckAppUpdates = $true }

Check 'download links from web pages: only well-formed jobs run' {
    $cases = @(
        @{ j = @{ Mode = 'video'; Url = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ' }; ok = $true },
        @{ j = @{ Mode = 'clip'; Url = 'https://youtu.be/dQw4w9WgXcQ'; Start = 5; End = 9 }; ok = $true },
        @{ j = @{ Mode = 'clip'; Url = 'https://youtu.be/dQw4w9WgXcQ'; Start = 9; End = 5 }; ok = $false },
        @{ j = @{ Mode = 'evil'; Url = 'https://example.com/' }; ok = $false },
        @{ j = @{ Mode = 'video'; Url = '--exec calc' }; ok = $false },
        @{ j = @{ Mode = 'video'; Url = 'file:///C:/Windows/win.ini' }; ok = $false },
        @{ j = @{ Mode = 'video'; Url = 'https://a.com/x" --exec "calc' }; ok = $false })
    foreach ($c in $cases) { if ((Test-JobSafe ([pscustomobject]$c.j)) -ne $c.ok) { throw "wrong answer for $($c.j.Mode) $($c.j.Url)" } }
}
Check 'your YouTube sign-in is only used for YouTube addresses' {
    foreach ($u in 'https://www.youtube.com/watch?v=x', 'https://youtu.be/x', 'https://music.youtube.com/x', 'https://m.youtube.com/x') { if (-not (Test-YouTubeUrl $u)) { throw "should be YouTube: $u" } }
    foreach ($u in 'https://youtube.com.evil.com/x', 'https://evilyoutube.com/x', 'https://vimeo.com/1', 'http://example.com/?youtube.com') { if (Test-YouTubeUrl $u) { throw "should not be YouTube: $u" } }
}
Check 'program arguments are quoted safely' { Expect (ConvertTo-ArgLine @('a b', 'c"d', '', 'plain', 'end\')) '"a b" "c\"d" "" plain end\' }
Check 'version numbers compare correctly (4.10 is newer than 4.9)' {
    if (-not ((ConvertTo-Version '4.10') -gt (ConvertTo-Version 'v4.9'))) { throw '4.10 should be newer' }
    if ($null -ne (ConvertTo-Version '4.2-beta')) { throw 'odd tags should be ignored' }
    Expect (ConvertTo-Version '4') '4.0'
}
Check 'clip times are understood' { Expect (ConvertFrom-ClockText '1:02:03') 3723; Expect (ConvertFrom-ClockText '90') 90; if ($null -ne (ConvertFrom-ClockText 'abc')) { throw 'abc is not a time' } }
Check 'watch history: hashtags are left out of searches' { Expect (Get-SearchTitle 'Tariffs be like #shorts #rap') 'Tariffs be like'; Expect (Get-SearchTitle '#shorts') '#shorts' }
Check 'watch history: search results are matched to the right video' {
    function C($id, $title, $ch) { [pscustomobject]@{ id = $id; title = $title; channel = $ch; uploader = $null } }
    Expect (Select-SearchMatch -cands @((C -id 'aaaaaaaaaaa' -title 'Which AI do I trust the most?? (Top 5 List)' -ch 'CarterPCs')) -title 'Which AI do I trust the most?? (Top 5 List) #tech #ai' -channel 'CarterPCs').id 'aaaaaaaaaaa'
    Expect (Select-SearchMatch -cands @((C -id 'bbbbbbbbbbb' -title 'Minecraft but ice is op' -ch 'Someone Else')) -title 'brittle ice is op' -channel 'camman18') ''
    Expect (Select-SearchMatch -cands @((C -id 'ccccccccccc' -title 'Painting then vs now' -ch 'Yahya'), (C -id 'ddddddddddd' -title 'Painting now vs back then' -ch 'Yahya')) -title 'Painting now vs back then' -channel 'Yahya').id 'ddddddddddd'
}

Check 'folder settings must be full paths' {
    if ($IsWin) {
        foreach ($p in 'C:\Users\me\Videos', 'D:\', '\\nas\share\videos') { if (-not (Test-FolderSetting $p)) { throw "should be allowed: $p" } }
        foreach ($p in 'Videos', '..\x', 'C:x', 'C:\a"b', "C:\a`nb", '') { if (Test-FolderSetting $p) { throw "should be refused: $p" } }
    } else {
        if (-not (Test-FolderSetting '/home/me/Videos')) { throw 'a full path is fine' }
        if (Test-FolderSetting 'Videos') { throw 'a relative path is not' }
    }
}
Check 'a hand-edited settings file cannot slip in unexpected values' {
    $script:SettingDefs = @(@{ Key = 'AudioFormat'; Kind = 'choice'; Choices = @('m4a', 'mp3') }, @{ Key = 'MaxHeight'; Kind = 'choice'; Choices = @(720, 1080) },
                     @{ Key = 'Notify'; Kind = 'bool' }, @{ Key = 'VideoFolder'; Kind = 'folder' })
    $Defaults = @{ AudioFormat = 'm4a'; MaxHeight = 1080; Notify = $true; VideoFolder = $(if ($IsWin) { 'C:\Videos' } else { '/videos' }) }
    $script:S = @{ AudioFormat = 'mp3 --exec calc'; MaxHeight = 720; Notify = 'yes'; VideoFolder = '..\..\Windows' }
    Repair-Config
    Expect $S.AudioFormat 'm4a'; Expect $S.MaxHeight 720; Expect $S.Notify $true; Expect $S.VideoFolder $Defaults.VideoFolder
}
Check 'audio from sites that only have video+sound files, and each download has its own temp folder' {
    $script:S = @{ VideoCodec = 'av1'; MaxFps = 0; Container = 'mp4'; Fragments = 4; SpeedLimit = 0; AudioQuality = 'best'; AudioCover = $true }
    $script:AudioFormat = 'm4a'; $script:TempDir = 'T'
    $a = @(Get-JobArgumentList -job @{ Mode = 'audio'; Url = 'https://x'; JobFile = (Join-Path 'q' '20260101-5.job') } -listFile 'l' -dirOverride '')
    Expect $a[[array]::IndexOf($a, '-f') + 1] 'ba[ext=m4a]/ba/b'
    Expect $a[[array]::IndexOf($a, '--audio-format') + 1] 'm4a'
    Expect (@($a | Where-Object { $_ -like 'temp:*' })[0]) ('temp:' + (Join-Path 'T' 'job-20260101-5'))
}
Check 'setup spots Tampermonkey in the browser that opens links' {
    $t = $null; $e = $null
    $ia = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Install.ps1'), [ref]$t, [ref]$e)
    . ([scriptblock]::Create(($ia.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Test-Tampermonkey' }, $true) | Select-Object -First 1).Extent.Text))
    $fake = Join-Path ([System.IO.Path]::GetTempPath()) ('vd-tm-' + [guid]::NewGuid().ToString('N'))
    $saved = $env:LOCALAPPDATA, $env:APPDATA
    try {
        $env:LOCALAPPDATA = Join-Path $fake 'Local'; $env:APPDATA = Join-Path $fake 'Roaming'
        if (Test-Tampermonkey 'ChromeHTML') { throw 'nothing is installed yet' }
        New-Item -ItemType Directory -Force -Path (Join-Path $env:LOCALAPPDATA (Join-Path 'Google' (Join-Path 'Chrome' (Join-Path 'User Data' (Join-Path 'Profile 2' (Join-Path 'Extensions' 'dhdgffkkebhmkfjojejmpbldmpobfkfo')))))) | Out-Null
        if (-not (Test-Tampermonkey 'ChromeHTML')) { throw 'Chrome: not found' }
        if (Test-Tampermonkey 'MSEdgeHTM') { throw 'Edge has no Tampermonkey here' }
        New-Item -ItemType Directory -Force -Path (Join-Path $env:APPDATA (Join-Path 'Mozilla' (Join-Path 'Firefox' (Join-Path 'Profiles' (Join-Path 'ab12.default-release' 'extensions'))))) | Out-Null
        if (Test-Tampermonkey 'FirefoxURL-308046B0AF4A39CB') { throw 'Firefox has no Tampermonkey yet' }
        Set-Content -LiteralPath (Join-Path $env:APPDATA (Join-Path 'Mozilla' (Join-Path 'Firefox' (Join-Path 'Profiles' (Join-Path 'ab12.default-release' (Join-Path 'extensions' 'firefox@tampermonkey.net.xpi')))))) -Value 'x'
        if (-not (Test-Tampermonkey 'FirefoxURL-308046B0AF4A39CB')) { throw 'Firefox: not found' }
    } finally {
        $env:LOCALAPPDATA, $env:APPDATA = $saved
        Remove-Item -LiteralPath $fake -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Check 'Pause only ever stops Video Downloader''s own programs' {
    $other = if ($IsWin) { Start-Process -FilePath (Join-Path $env:WINDIR 'System32\PING.EXE') -ArgumentList '-n 30 127.0.0.1' -WindowStyle Hidden -PassThru }
             else { Start-Process -FilePath 'sleep' -ArgumentList '30' -PassThru }
    try {
        Suspend-OwnProcess $other.Id
        Start-Sleep -Milliseconds 500
        if ($other.HasExited) { throw 'another program was stopped' }
        Suspend-OwnProcess $PID      # (and never itself)
    } finally { try { $other.Kill() } catch { Write-Debug $_ } }
}
Check 'finished downloads are forgotten after the chosen number of days, and Erase removes everything it names' {
    $Base = Join-Path ([System.IO.Path]::GetTempPath()) ('vd-hist-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $Base | Out-Null
    try {
        $HistFile = Join-Path $Base 'history.jsonl'; $LogFile = Join-Path $Base 'history.log'
        $script:RunnerLog = Join-Path $Base 'runner.log'; $script:ErrorLog = Join-Path $Base 'error.log'
        $old = (Get-Date).AddDays(-40).ToString('s'); $new = (Get-Date).AddDays(-2).ToString('s')
        [System.IO.File]::WriteAllLines($HistFile, [string[]]@("{""ok"":true,""url"":""https://old"",""time"":""$old""}", "{""ok"":true,""url"":""https://new"",""time"":""$new""}"))
        [System.IO.File]::WriteAllLines($LogFile, [string[]]@(($old.Substring(0, 10) + ' 10:00  OK https://old'), ($new.Substring(0, 10) + ' 10:00  OK https://new')))
        $script:S = @{ KeepHistoryDays = 30 }
        Limit-PrivateData
        $h = [System.IO.File]::ReadAllText($HistFile); $l = [System.IO.File]::ReadAllText($LogFile)
        if ($h -match 'old' -or $h -notmatch 'new' -or $l -match 'old' -or $l -notmatch 'new') { throw "kept: $h / $l" }
        foreach ($n in 'settings.json', 'runs.log', 'playlist-archive.txt', 'netcheck.txt') { Set-Content -LiteralPath (Join-Path $Base $n) -Value 'x' }
        Clear-DownloadHistory
        $left = @(Get-ChildItem -LiteralPath $Base -File | ForEach-Object { $_.Name })
        Expect ($left -join ',') 'settings.json'
    } finally { Remove-Item -LiteralPath $Base -Recurse -Force -ErrorAction SilentlyContinue }
}

# ---------------------------------------------------------------- Windows-only: privacy and security features
if ($IsWin) {
    Write-Host "`nPrivacy and security (Windows)"
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('vd-test-' + [guid]::NewGuid().ToString('N'))
    $Base = Join-Path $tmp 'VideoDownloader'; $TempDir = Join-Path $Base 'temp'
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
    $CookieVault = Join-Path $Base 'cookies.dpapi'
    $script:CookieEntropy = [System.Text.Encoding]::UTF8.GetBytes('VideoDownloader.cookies.v1')
    $script:CookieTemps = New-Object System.Collections.Generic.List[string]
    $FirefoxCookies = 'browser:firefox'
    $secret = "# Netscape HTTP Cookie File`n.youtube.com`tTRUE`t/`tTRUE`t0`tSID`tsecret-value-123"

    Check 'a cookies.txt you add is encrypted, and the plain file deleted' {
        [System.IO.File]::WriteAllText((Join-Path $Base 'cookies.txt'), $secret)
        Protect-CookieFile
        if (Test-Path -LiteralPath (Join-Path $Base 'cookies.txt')) { throw 'the plain cookies.txt is still there' }
        if (-not (Test-Path -LiteralPath $CookieVault)) { throw 'no encrypted copy' }
        if ([System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($CookieVault)).Contains('secret-value-123')) { throw 'the encrypted copy contains the plain text' }
    }
    Check 'the sign-in can be unlocked for a download, and the plain copy is removed afterwards' {
        $p = Open-SignIn
        Expect ([System.IO.File]::ReadAllText($p)) $secret
        [System.IO.File]::AppendAllText($p, "`nrefreshed")      # yt-dlp updates the file while it works
        Close-SignIn
        if (Test-Path -LiteralPath $p) { throw 'the plain copy was not removed' }
        $p2 = Open-SignIn
        if (-not ([System.IO.File]::ReadAllText($p2)).EndsWith('refreshed')) { throw "yt-dlp's refreshed sign-in was not kept" }
        Close-SignIn
    }
    Check 'the sign-in is only passed to yt-dlp the right way' {
        Expect ((Get-CookieArgumentList 'C:\x\ck.txt') -join ' ') '--cookies C:\x\ck.txt'
        Expect ((Get-CookieArgumentList $FirefoxCookies) -join ' ') '--cookies-from-browser firefox'
        Expect (@(Get-CookieArgumentList '').Count) 0
    }

    Check 'the data folder becomes private, and files locked by the 4.2 bug are repaired' {
        foreach ($n in 'settings.json', 'history.log') { Set-Content -LiteralPath (Join-Path $Base $n) -Value 'x' }
        $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $icacls = Join-Path $env:WINDIR 'System32\icacls.exe'
        # what 4.2 did
        $null = & $icacls $Base '/inheritance:r' '/grant:r' "*${sid}:(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' '/T' '/C' '/Q' 2>&1
        Protect-DataFolder
        foreach ($n in 'settings.json', 'history.log') { [void][System.IO.File]::ReadAllText((Join-Path $Base $n)) }
        $acl = Get-Acl -LiteralPath $Base
        if (-not $acl.AreAccessRulesProtected) { throw 'the folder still inherits access from its parent' }
        $who = @($acl.Access | ForEach-Object { $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value } | Sort-Object -Unique)
        # you and Windows must be there; the Administrators group may be too (it can take over any folder anyway,
        # and Windows adds it when an administrator account creates the folder); nobody else may be
        foreach ($must in $sid, 'S-1-5-18') { if ($who -notcontains $must) { throw "missing access for $must (got $($who -join ', '))" } }
        $others = @($who | Where-Object { $_ -notin @($sid, 'S-1-5-18', 'S-1-5-32-544') })
        if ($others.Count) { throw "other accounts can open the folder: $($others -join ', ')" }
        $f = Get-Acl -LiteralPath (Join-Path $Base 'settings.json')
        if ($f.AreAccessRulesProtected) { throw 'files should simply inherit from the folder' }
        if (-not (Test-Path -LiteralPath (Join-Path $Base '.private-v2'))) { throw 'not marked as done' }
    }
    Check 'new files in the private folder can be read and written' {
        $n = Join-Path $Base 'new.txt'; Set-Content -LiteralPath $n -Value 'ok'; Expect ((Get-Content -LiteralPath $n).Trim()) 'ok'
    }
    Check 'your real Downloads folder is found' { Test-Path -LiteralPath (Get-DownloadsFolder) }

    Check 'a ytdl:// link carrying extra options is refused' {
        $old = $env:LOCALAPPDATA; $env:LOCALAPPDATA = $tmp; $env:VIDEODOWNLOADER_TEST = '1'
        try {
            $ps = Join-Path $PSHOME 'powershell.exe'
            & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'VideoDownloader.ps1') -Uri 'ytdl://video/dQw4w9WgXcQ' -HistoryTask import -Path 'C:\Windows\win.ini' | Out-Null
            Expect $LASTEXITCODE 1
            & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'VideoDownloader.ps1') -Uri 'ytdl://video/dQw4w9WgXcQ" -Path x' | Out-Null
            Expect $LASTEXITCODE 1
            if ((Get-Content -LiteralPath (Join-Path $Base 'error.log') -Raw) -notmatch 'refused a malformed ytdl:// link') { throw 'the refusal was not logged' }
            if (@(Get-ChildItem -LiteralPath (Join-Path $Base 'queue') -Filter '*.job' -ErrorAction SilentlyContinue).Count) { throw 'a download was queued anyway' }
        } finally { $env:LOCALAPPDATA = $old; Remove-Item Env:\VIDEODOWNLOADER_TEST -ErrorAction SilentlyContinue }
    }

    Check 'the installer fills in the guide (button script and version)' {
        $ia = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Install.ps1'), [ref]$t, [ref]$e)
        $ng = $ia.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Write-Guide' }, $true) | Select-Object -First 1
        . ([scriptblock]::Create($ng.Extent.Text))
        $out = Join-Path $tmp 'Guide.html'
        Write-Guide -template (Join-Path $root 'Guide.html') -out $out -userScript (Join-Path $root 'VideoDownloader.user.js') -version $ver
        $g = [System.IO.File]::ReadAllText($out)
        if ($g.Contains('{{')) { throw 'a {{placeholder}} was left in the guide' }
        if (-not $g.Contains("Video Downloader $ver")) { throw 'the version is missing' }
        if (-not $g.Contains('// ==UserScript==')) { throw 'the button script is missing' }
    }
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "`n(Skipping the Windows-only checks: encryption, folder privacy, link handling, installer.)" -ForegroundColor Yellow
}

Write-Host ''
if ($script:Fails) { Write-Host "$($script:Fails) check(s) FAILED, $($script:Passes) passed." -ForegroundColor Red; exit 1 }
Write-Host "All $($script:Passes) checks passed." -ForegroundColor Green
exit 0
