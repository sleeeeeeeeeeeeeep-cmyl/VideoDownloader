<#
  Video Downloader - builds the files attached to a GitHub release:
    dist\VideoDownloader-<version>.zip            the installer (Setup.cmd + files\...)
    dist\VideoDownloader-extension-<version>.zip  the YouTube button as a browser extension (Edge Add-ons / Firefox Add-ons)
    dist\SHA256SUMS.txt                           checksums, so anyone (and the app's "Update now") can check a download
  GitHub runs this automatically when you publish a release (see .github\workflows\ci.yml).
  You can also run it yourself:  powershell -ExecutionPolicy Bypass -File Build-Release.ps1
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Coloured text for the person watching the console window')]
param([string]$Tag)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

$app = [System.IO.File]::ReadAllText((Join-Path $root 'VideoDownloader.ps1'))
if ($app -notmatch "\`$AppVersion = '([0-9.]+)'") { throw 'Could not find $AppVersion in VideoDownloader.ps1' }
$ver = $Matches[1]
if ($Tag -and $Tag.TrimStart('v', 'V') -ne $ver) {
    throw "The release tag '$Tag' doesn't match the app's version '$ver'. Change `$AppVersion in VideoDownloader.ps1 (plus @version in VideoDownloader.user.js and version in extension-manifest.json), or name the release tag $ver."
}

$dist = Join-Path $root 'dist'
if (Test-Path -LiteralPath $dist) { Remove-Item -LiteralPath $dist -Recurse -Force }
$stage = Join-Path $dist 'stage'
$top = Join-Path $stage 'VideoDownloader'
$files = Join-Path $top 'files'
$ext = Join-Path $dist 'extension'
New-Item -ItemType Directory -Path $files, $ext -Force | Out-Null

function Copy-To([string]$name, [string]$dir, [string]$as = '') {
    $from = Join-Path $root $name
    if (-not (Test-Path -LiteralPath $from)) { throw "Missing file in the repository: $name" }
    $to = if ($as) { Join-Path $dir $as } else { $dir }
    Copy-Item -LiteralPath $from -Destination $to -Force
}
# the installer ZIP
'Setup.cmd', 'README.txt' | ForEach-Object { Copy-To $_ $top }
'Install.ps1', 'Uninstall.ps1', 'VideoDownloader.ps1', 'VideoDownloader.user.js', 'VideoDownloader.ico', 'Guide.html' | ForEach-Object { Copy-To $_ $files }
# the browser extension: the same script as the userscript, run as a content script
Copy-To -name 'extension-manifest.json' -dir $ext -as 'manifest.json'
Copy-To -name 'VideoDownloader.user.js' -dir $ext -as 'content.js'
Copy-To -name 'extension-icon.png' -dir $ext -as 'icon-128.png'

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = Join-Path $dist "VideoDownloader-$ver.zip"
$extZip = Join-Path $dist "VideoDownloader-extension-$ver.zip"
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip)
[System.IO.Compression.ZipFile]::CreateFromDirectory($ext, $extZip)
Remove-Item -LiteralPath $stage, $ext -Recurse -Force

$sums = foreach ($z in $zip, $extZip) { '{0}  {1}' -f (Get-FileHash -LiteralPath $z -Algorithm SHA256).Hash.ToLowerInvariant(), (Split-Path -Leaf $z) }
[System.IO.File]::WriteAllLines((Join-Path $dist 'SHA256SUMS.txt'), [string[]]$sums)
Write-Host "Built version $ver in $dist"
$sums | ForEach-Object { Write-Host "  $_" }
