<#
  Video Downloader - one-line install AND update for Windows.

  Press Windows key + R, paste this line and press Enter (or paste it into PowerShell):

    powershell -c "[Net.ServicePointManager]::SecurityProtocol=3072;irm https://raw.githubusercontent.com/sleeeeeeeeeeeeeep-cmyl/VideoDownloader/main/get.ps1|iex"

  Not installed yet: it downloads the newest release from this project's GitHub page, checks it against the
  release's published SHA-256 checksums, and runs its setup (the same as unzipping it and double-clicking Setup.cmd).
  Already installed (ANY earlier version): it updates Video Downloader to the newest release the same way, keeping
  your settings, queue and history, and brings yt-dlp and Deno up to date. If you already have the newest version,
  only yt-dlp and Deno are updated.
  From version 4.7 on, "video-downloader update" (Run box or any terminal) runs this same file, so the newest update
  steps are always the ones used. Set VD_REINSTALL=1 (or use "video-downloader reinstall") to reinstall anyway.
  Installs for your Windows account only; no administrator rights needed.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Coloured text for the person watching the console window')]
param()

& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'      # (the progress bar makes downloads in Windows PowerShell very slow)
    $repo = 'sleeeeeeeeeeeeeep-cmyl/VideoDownloader'
    $work = $null

    # the version number inside an installed or downloaded VideoDownloader.ps1 ('' if none)
    function Get-ScriptVersion([string]$path) {
        try { if ((Test-Path -LiteralPath $path) -and ([IO.File]::ReadAllText($path) -match "\`$AppVersion = '([0-9.]+)'")) { return $Matches[1] } } catch { Write-Debug $_ }
        return ''
    }
    function ConvertTo-Ver([string]$t) {
        $t = "$t".Trim().TrimStart('v', 'V')
        if ($t -notmatch '^\d+(\.\d+){0,3}$') { return $null }
        if ($t -notmatch '\.') { $t += '.0' }
        return [version]$t
    }
    function Wait-Close([int]$seconds) {
        if ($env:VD_FROM_COMMAND) { return }      # (a terminal window stays open by itself)
        Write-Host ''
        Write-Host "  This window closes by itself in $seconds seconds." -ForegroundColor DarkGray
        Start-Sleep -Seconds $seconds
    }
    function Write-SetupFailure([string]$why) {
        Write-Host ''
        Write-Host "  Video Downloader could not be installed: $why" -ForegroundColor Red
        Write-Host "  You can also install it by hand: https://github.com/$repo/releases/latest" -ForegroundColor DarkGray
        Write-Host '  (download VideoDownloader-x.y.zip, Extract All, double-click Setup.cmd)' -ForegroundColor DarkGray
        try { Read-Host '  Press Enter to close' | Out-Null } catch { Start-Sleep -Seconds 30 }
    }

    try {
        if ($env:OS -ne 'Windows_NT') { Write-SetupFailure "this is the Windows installer. On Linux run: curl -fsSL https://raw.githubusercontent.com/$repo/main/install.sh | sh"; return }
        # GitHub only accepts TLS 1.2 or newer
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        try { $Host.UI.RawUI.WindowTitle = 'Video Downloader Setup' } catch { Write-Debug $_ }
        Write-Host ''
        Write-Host '  Video Downloader - finding the newest version...' -ForegroundColor Cyan
        $headers = @{ 'User-Agent' = 'VideoDownloader-Setup'; 'Accept' = 'application/vnd.github+json' }
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers $headers -UseBasicParsing
        $latest = ([string]$rel.tag_name).TrimStart('v', 'V')
        $installed = Join-Path $env:LOCALAPPDATA 'Programs\VideoDownloader\VideoDownloader.ps1'
        $have = Get-ScriptVersion $installed
        $hv = ConvertTo-Ver $have; $lv = ConvertTo-Ver $latest
        if ($hv -and $lv -and $hv -ge $lv -and -not $env:VD_REINSTALL) {
            # nothing newer to install: bring the parts that talk to YouTube up to date instead
            if ($hv -gt $lv) { Write-Host "  You have Video Downloader $have, which is newer than the newest release ($latest)." -ForegroundColor Green }
            else { Write-Host "  You already have the newest Video Downloader ($have)." -ForegroundColor Green }
            $winget = Get-Command winget -ErrorAction SilentlyContinue
            if ($winget) {
                Write-Host '  Checking yt-dlp and Deno for updates...' -ForegroundColor Cyan
                foreach ($id in 'yt-dlp.yt-dlp', 'DenoLand.Deno') {
                    & $winget.Source upgrade --id $id -e --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity | Out-Host
                }
                try { Set-Content -LiteralPath (Join-Path $env:LOCALAPPDATA 'VideoDownloader\last-update.txt') -Value (Get-Date -Format o) } catch { Write-Debug $_ }
                Write-Host '  Done: yt-dlp and Deno are checked and updated where a newer version was out.' -ForegroundColor Green
            } else {
                Write-Host '  (winget is missing, so yt-dlp and Deno could not be checked. Install "App Installer" from the Microsoft Store.)' -ForegroundColor Yellow
            }
            Write-Host '  To install this version again anyway:  video-downloader reinstall' -ForegroundColor DarkGray
            Wait-Close 10
            return
        }
        if ($have -and $have -eq $latest) { Write-Host "  Reinstalling Video Downloader $latest..." -ForegroundColor Cyan }
        elseif ($have) { Write-Host "  Updating Video Downloader from $have to $latest..." -ForegroundColor Cyan }
        else { Write-Host "  Installing Video Downloader $latest..." -ForegroundColor Cyan }
        $prefix = "https://github.com/$repo/releases/download/"
        $zip = @($rel.assets | Where-Object { $_.name -match '^VideoDownloader-[0-9.]+\.zip$' })[0]
        $sums = @($rel.assets | Where-Object { $_.name -eq 'SHA256SUMS.txt' })[0]
        if (-not $zip -or -not $sums) { Write-SetupFailure 'the newest release has no Windows download yet.'; return }
        foreach ($u in $zip.browser_download_url, $sums.browser_download_url) {
            if (-not ([string]$u).StartsWith($prefix, [StringComparison]::Ordinal)) { Write-SetupFailure 'the release points somewhere unexpected, so nothing was downloaded.'; return }
        }

        $work = Join-Path $env:TEMP ('vd-setup-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $zipPath = Join-Path $work $zip.name
        $sumPath = Join-Path $work 'SHA256SUMS.txt'
        Write-Host "  Downloading $($zip.name)..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $zip.browser_download_url -OutFile $zipPath -Headers $headers -UseBasicParsing
        Invoke-WebRequest -Uri $sums.browser_download_url -OutFile $sumPath -Headers $headers -UseBasicParsing

        # the download must match the checksum published with the release
        $want = ''
        foreach ($line in [IO.File]::ReadAllLines($sumPath)) {
            if ($line -match '^([0-9a-fA-F]{64})\s+\*?(\S+)\s*$' -and [IO.Path]::GetFileName($Matches[2]) -eq $zip.name) { $want = $Matches[1] }
        }
        $got = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
        if (-not $want -or $got -ne $want) { Write-SetupFailure 'the download did not match its published checksum, so nothing was installed.'; return }
        Write-Host '  Checksum OK.' -ForegroundColor Green

        # (.NET refuses ZIP entries that would land outside the folder)
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $x = Join-Path $work 'x'
        [IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $x)
        $installer = @(Get-ChildItem -LiteralPath $x -Filter 'Install.ps1' -File -Recurse)[0]
        if (-not $installer) { Write-SetupFailure 'the download has no installer in it.'; return }

        $ps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        & $ps -NoProfile -ExecutionPolicy Bypass -File $installer.FullName
    } catch {
        Write-SetupFailure $_.Exception.Message
    } finally {
        if ($work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
