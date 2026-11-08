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
foreach ($f in 'VideoDownloader.ps1', 'Install.ps1', 'Uninstall.ps1', 'Build-Release.ps1', 'Tests.ps1') {
    Check "$f has no syntax errors" {
        $t = $null; $e = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $f), [ref]$t, [ref]$e)
        if ($e.Count) { throw (($e | ForEach-Object { $_.ToString() }) -join ' | ') }
    }
}
foreach ($f in 'VideoDownloader.ps1', 'Install.ps1', 'Uninstall.ps1', 'Build-Release.ps1', 'Tests.ps1', 'Setup.cmd', 'README.txt') {
    Check "$f is plain ASCII (Windows PowerShell 5.1 and cmd misread other characters)" {
        $b = [System.IO.File]::ReadAllBytes((Join-Path $root $f))
        $n = 0; foreach ($x in $b) { if ($x -gt 127) { $n++ } }
        if ($n) { throw "$n non-ASCII bytes - replace curly quotes, dashes and emoji" }
    }
}
foreach ($f in 'Guide.html', 'VideoDownloader.user.js', 'VideoDownloader.ico', 'extension-manifest.json', 'extension-icon.png', 'README.md', 'LICENSE') {
    Check "$f is present" { Test-Path -LiteralPath (Join-Path $root $f) }
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
    foreach ($f in 'VideoDownloader.ps1', 'Install.ps1', 'Uninstall.ps1', 'Build-Release.ps1', 'Tests.ps1') {
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
