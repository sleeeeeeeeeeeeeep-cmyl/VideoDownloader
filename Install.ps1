<#
  Video Downloader - installer.  Run it with Setup.cmd (double-click).
  Installs for the current Windows user only; no administrator rights needed.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Coloured text for the person watching the console window')]
param([switch]$Quiet)
$ErrorActionPreference = 'Stop'
# the version is read from the app itself, so it only has to be changed in one place
$AppVersion = '?'
try { if ((Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VideoDownloader.ps1') -Raw) -match "\`$AppVersion = '([0-9.]+)'") { $AppVersion = $Matches[1] } } catch { Write-Debug $_ }
try { $Host.UI.RawUI.WindowTitle = 'Video Downloader Setup' } catch { Write-Debug $_ }

$Src      = $PSScriptRoot
$Dest     = Join-Path $env:LOCALAPPDATA 'Programs\VideoDownloader'
$Data     = Join-Path $env:LOCALAPPDATA 'VideoDownloader'
$Script   = Join-Path $Dest 'VideoDownloader.ps1'
$Icon     = Join-Path $Dest 'VideoDownloader.ico'
$PsExe    = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$Conhost  = Join-Path $env:WINDIR 'System32\conhost.exe'
$Programs = [Environment]::GetFolderPath('Programs')
$Desktop  = [Environment]::GetFolderPath('Desktop')

function Step([string]$t)  { Write-Host "`n  $t" -ForegroundColor Cyan }
function Good([string]$t)  { Write-Host "    OK  $t" -ForegroundColor Green }
function Note([string]$t)  { Write-Host "        $t" -ForegroundColor DarkGray }
function Bad([string]$t)   { Write-Host "    !!  $t" -ForegroundColor Yellow }
function Finish([int]$code) {
    if (-not $Quiet) {
        Write-Host ''
        if ($code -eq 0) { Write-Host '  This window closes by itself in 15 seconds.' -ForegroundColor DarkGray; Start-Sleep -Seconds 15 }
        else { try { Read-Host '  Press Enter to close' | Out-Null } catch { Start-Sleep -Seconds 60 } }
    }
    exit $code
}

trap {
    Write-Host "`n  Setup stopped because of an error:" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  $($_.InvocationInfo.PositionMessage)" -ForegroundColor DarkGray
    Finish 1
}

Write-Host ''
Write-Host '  ==============================================' -ForegroundColor Red
Write-Host "        VIDEO DOWNLOADER $AppVersion  -  Setup" -ForegroundColor White
Write-Host '  ==============================================' -ForegroundColor Red
Write-Host '  This installs Video Downloader for your Windows account.'
Write-Host '  It also installs three free helper programs if you do not have them:'
Write-Host '    yt-dlp (does the downloading), FFmpeg (joins video + sound), Deno (needed by YouTube).'

$ButtonUrl = 'https://raw.githubusercontent.com/sleeeeeeeeeeeeeep-cmyl/VideoDownloader/main/VideoDownloader.user.js'

# Is Tampermonkey already in the browser that opens links? Then setup can open the button's install page straight away
# (one click on Install) instead of walking through the guide. Only looks for the extension's folder; reads nothing.
function Test-Tampermonkey([string]$progId) {
    if (-not $progId) { try { $progId = [string](Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice' -ErrorAction Stop).ProgId } catch { Write-Debug $_ } }
    if ($progId -like 'FirefoxURL*') {
        $profiles = Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles'
        return [bool](Get-ChildItem -LiteralPath $profiles -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'extensions\firefox@tampermonkey.net.xpi') })
    }
    $root = switch -Wildcard ($progId) {
        'ChromeHTML*'  { Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data' }
        'MSEdgeHTM*'   { Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data' }
        'BraveHTML*'   { Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data' }
        'VivaldiHTM*'  { Join-Path $env:LOCALAPPDATA 'Vivaldi\User Data' }
        'OperaGX*'     { Join-Path $env:APPDATA 'Opera Software\Opera GX Stable' }
        'Opera*'       { Join-Path $env:APPDATA 'Opera Software\Opera Stable' }
        default        { $null }
    }
    if (-not $root -or -not (Test-Path -LiteralPath $root)) { return $false }
    $ids = 'dhdgffkkebhmkfjojejmpbldmpobfkfo', 'iikmkjmpaadaobahmlepeloendndfphd', 'gcalenpjmijncebpfijmoaglllgpjagf'   # Chrome store, Edge store, beta
    $dirs = @($root) + @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' } | ForEach-Object { $_.FullName })
    foreach ($d in $dirs) { foreach ($id in $ids) { if (Test-Path -LiteralPath (Join-Path $d "Extensions\$id")) { return $true } } }
    return $false
}

# The guide in the download is a template: the button script and version number are filled in here
function Write-Guide([string]$template, [string]$out, [string]$userScript, [string]$version) {
    $g = [System.IO.File]::ReadAllText($template, [System.Text.Encoding]::UTF8)
    $js = [System.IO.File]::ReadAllText($userScript, [System.Text.Encoding]::UTF8)
    $g = $g.Replace('{{USERSCRIPT}}', [System.Net.WebUtility]::HtmlEncode($js)).Replace('{{VERSION}}', $version)
    [System.IO.File]::WriteAllText($out, $g, (New-Object System.Text.UTF8Encoding($false)))
}

# ---------- 1. helper programs ----------
function Find-Tool([string]$exe, [string]$packagePrefix) {
    $cmd = Get-Command $exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    $links = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\$exe.exe"
    if (Test-Path -LiteralPath $links) { return $links }
    $pk = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path -LiteralPath $pk) {
        foreach ($p in Get-ChildItem -LiteralPath $pk -Directory -Filter "$packagePrefix*" -ErrorAction SilentlyContinue) {
            $hit = Get-ChildItem -LiteralPath $p.FullName -Filter "$exe.exe" -Recurse -Depth 3 -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }
    return $null
}

Step '1/4  Helper programs'
$winget = Get-Command winget -ErrorAction SilentlyContinue
$tools = @(
    @{ Exe = 'yt-dlp'; Id = 'yt-dlp.yt-dlp';  Name = 'yt-dlp' },
    @{ Exe = 'ffmpeg'; Id = 'Gyan.FFmpeg';    Name = 'FFmpeg' },
    @{ Exe = 'deno';   Id = 'DenoLand.Deno';  Name = 'Deno' }
)
$missing = @()
foreach ($t in $tools) {
    $found = Find-Tool $t.Exe $t.Id
    if ($t.Exe -eq 'ffmpeg' -and -not $found) { $found = Find-Tool 'ffmpeg' 'yt-dlp.FFmpeg' }
    if ($found) { Good "$($t.Name) is already installed" } else { $missing += $t }
}
if ($missing.Count) {
    if (-not $winget) {
        Bad 'Windows Package Manager (winget) was not found, so the helper programs cannot be installed automatically.'
        Note 'Fix: open the Microsoft Store, search for "App Installer", install or update it, then run Setup again.'
        try { Start-Process 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1' } catch { Write-Debug $_ }
        Finish 1
    }
    foreach ($t in $missing) {
        Write-Host "    ..  Installing $($t.Name) (this can take a minute)" -ForegroundColor Yellow
        $ErrorActionPreference = 'Continue'
        & $winget.Source install --id $t.Id -e --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity | Out-Host
        $ErrorActionPreference = 'Stop'
        if (Find-Tool $t.Exe $t.Id) { Good "$($t.Name) installed" }
        else { Bad "$($t.Name) may not have installed. Video Downloader will try again the first time it downloads." }
    }
}

# ---------- 2. copy the app ----------
Step '2/4  Copying Video Downloader'
# stop a running copy first so its files can be replaced
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*VideoDownloader.ps1*' -and $_.CommandLine -like '*-App*' } |
    ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch { Write-Debug $_ } }
New-Item -ItemType Directory -Path $Dest -Force | Out-Null
New-Item -ItemType Directory -Path $Data -Force | Out-Null
foreach ($f in 'VideoDownloader.ps1', 'VideoDownloader.ico', 'VideoDownloader.user.js', 'Guide.html', 'Uninstall.ps1', 'Install.ps1') {
    $from = Join-Path $Src $f
    if (-not (Test-Path -LiteralPath $from)) { throw "Setup is missing a file: $f. Download Video Downloader again and unzip ALL files before running Setup." }
    if ($from -ne (Join-Path $Dest $f)) { Copy-Item -LiteralPath $from -Destination $Dest -Force }
}
Write-Guide -template (Join-Path $Src 'Guide.html') -out (Join-Path $Dest 'Guide.html') -userScript (Join-Path $Src 'VideoDownloader.user.js') -version $AppVersion
Get-ChildItem -LiteralPath $Dest -File | ForEach-Object { try { Unblock-File -LiteralPath $_.FullName } catch { Write-Debug $_ } }
Good "Installed to $Dest"

# ---------- 3. connect the browser button + shortcuts ----------
Step '3/4  Connecting the browser button and adding shortcuts'
$hidden = '"{0}" --headless "{1}" -NoProfile -ExecutionPolicy Bypass -File "{2}"' -f $Conhost, $PsExe, $Script
$cls = 'HKCU:\Software\Classes\ytdl'
New-Item -Path "$cls\shell\open\command" -Force | Out-Null
New-Item -Path "$cls\DefaultIcon" -Force | Out-Null
Set-ItemProperty -Path $cls -Name '(default)' -Value 'URL:Video Downloader'
Set-ItemProperty -Path $cls -Name 'URL Protocol' -Value ''
Set-ItemProperty -Path "$cls\DefaultIcon" -Name '(default)' -Value "`"$Icon`""
Set-ItemProperty -Path "$cls\shell\open\command" -Name '(default)' -Value ($hidden + ' -Uri "%1"')
Good 'Browser button connected (ytdl:// links open Video Downloader)'

$wsh = New-Object -ComObject WScript.Shell
function Add-Shortcut([string]$path, [string]$extra, [string]$desc) {
    $lnk = $wsh.CreateShortcut($path)
    $lnk.TargetPath = $Conhost
    $lnk.Arguments = ('--headless "{0}" -NoProfile -ExecutionPolicy Bypass -File "{1}" {2}' -f $PsExe, $Script, $extra).Trim()
    $lnk.WorkingDirectory = $Dest
    $lnk.IconLocation = "$Icon,0"
    $lnk.Description = $desc
    $lnk.WindowStyle = 7
    $lnk.Save()
}
Add-Shortcut -path (Join-Path $Programs 'Video Downloader.lnk') -extra '-App' -desc 'Download videos and audio'
Good 'Start menu: Video Downloader'
Add-Shortcut -path (Join-Path $Desktop 'Video Downloader.lnk') -extra '-App' -desc 'Download videos and audio'
Good 'Desktop: Video Downloader'

# an entry in Settings > Apps so it can be removed like any other program
$un = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\VideoDownloader'
New-Item -Path $un -Force | Out-Null
$size = [int]((Get-ChildItem -LiteralPath $Dest -File | Measure-Object Length -Sum).Sum / 1KB)
$props = @{
    DisplayName = 'Video Downloader'; DisplayVersion = $AppVersion; Publisher = 'Video Downloader'
    DisplayIcon = $Icon; InstallLocation = $Dest; EstimatedSize = $size; NoModify = 1; NoRepair = 1
    UninstallString = ('"{0}" -NoProfile -ExecutionPolicy Bypass -File "{1}"' -f $PsExe, (Join-Path $Dest 'Uninstall.ps1'))
}
foreach ($k in $props.Keys) {
    $type = if ($props[$k] -is [int]) { 'DWord' } else { 'String' }
    New-ItemProperty -Path $un -Name $k -Value $props[$k] -PropertyType $type -Force | Out-Null
}
Good 'Listed in Settings > Apps (uninstall from there)'

# ---------- 4. the browser part ----------
Step '4/4  The Download button for YouTube'
$haveTm = $false
if (-not $Quiet) { $haveTm = Test-Tampermonkey }
if ($haveTm) {
    Good 'Tampermonkey is in your browser: the button''s install page opens in a moment - click Install there.'
} elseif (-not $Quiet) {   # (an automatic update shouldn't overwrite what you have on the clipboard)
    try {
        Set-Clipboard -Value (Get-Content -LiteralPath (Join-Path $Dest 'VideoDownloader.user.js') -Raw -Encoding UTF8)
        Good 'The button script is copied to your clipboard'
    } catch { Bad 'Could not copy to the clipboard - use the Copy button in the guide instead.' }
}
if (-not $Quiet -and -not $haveTm) { Note 'The guide that just opened shows the 3 quick steps to add the button to your browser.' }

Write-Host ''
Write-Host '  All done!  Video Downloader is in your Start menu.' -ForegroundColor Green
if (-not $Quiet) {
    try { Start-Process (Join-Path $Dest 'Guide.html') } catch { Write-Debug $_ }
    if ($haveTm) { Start-Sleep -Seconds 2; try { Start-Process $ButtonUrl } catch { Write-Debug $_ } }   # (in front of the guide)
    try { Start-Process -FilePath $Conhost -ArgumentList ('--headless "{0}" -NoProfile -ExecutionPolicy Bypass -File "{1}" -App' -f $PsExe, $Script) } catch { Write-Debug $_ }
}
Finish 0
