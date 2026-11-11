<#
  Video Downloader - uninstaller (Settings > Apps > Video Downloader > Uninstall, or "video-downloader uninstall").
  Your downloaded videos are never touched.
#>
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms
$Dest = Join-Path $env:LOCALAPPDATA 'Programs\VideoDownloader'
$Data = Join-Path $env:LOCALAPPDATA 'VideoDownloader'

$ans = [System.Windows.Forms.MessageBox]::Show(
    "Remove Video Downloader from this PC?`n`nYour downloaded videos stay where they are.",
    'Uninstall Video Downloader', 'YesNo', 'Question')
if ($ans -ne 'Yes') { exit 0 }
$deleteData = [System.Windows.Forms.MessageBox]::Show(
    "Also delete your settings, download history, waiting downloads and saved YouTube sign-in?`n`nYes = delete them`nNo = keep them for a future reinstall",
    'Uninstall Video Downloader', 'YesNo', 'Question')

# stop anything that is running
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -in 'powershell.exe', 'yt-dlp.exe', 'ffmpeg.exe' -and $_.CommandLine -like '*VideoDownloader*' -and $_.ProcessId -ne $PID } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Remove-Item -LiteralPath 'HKCU:\Software\Classes\ytdl' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\VideoDownloader' -Recurse -Force -ErrorAction SilentlyContinue
foreach ($lnk in (Join-Path ([Environment]::GetFolderPath('Programs')) 'Video Downloader.lnk'),
                 (Join-Path ([Environment]::GetFolderPath('Programs')) 'Update Video Downloader.lnk'),
                 (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Video Downloader.lnk')) {
    Remove-Item -LiteralPath $lnk -Force -ErrorAction SilentlyContinue
}
# take the "video-downloader" command's folder back out of your PATH (other entries are left exactly as they were)
try {
    $bin = Join-Path $Dest 'bin'
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    if ($key) {
        try {
            $cur = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $keep = @($cur -split ';' | Where-Object { $_ -ne '' -and [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') -ine $bin.TrimEnd('\') })
            if ($keep.Count -ne @($cur -split ';' | Where-Object { $_ -ne '' }).Count) { $key.SetValue('Path', ($keep -join ';'), $key.GetValueKind('Path')) }
        } finally { $key.Close() }
        [Environment]::SetEnvironmentVariable('VideoDownloaderSetup', '1', 'User')     # (announces the change)
        [Environment]::SetEnvironmentVariable('VideoDownloaderSetup', $null, 'User')
    }
} catch { Write-Debug $_ }
if ($deleteData -eq 'Yes') { Remove-Item -LiteralPath $Data -Recurse -Force -ErrorAction SilentlyContinue }

# this script lives in the folder being removed, so the folder is deleted a moment after it exits
Start-Process -FilePath "$env:WINDIR\System32\cmd.exe" -ArgumentList ('/c timeout /t 2 /nobreak >nul & rmdir /s /q "{0}"' -f $Dest) -WindowStyle Hidden

[void][System.Windows.Forms.MessageBox]::Show(
    "Video Downloader was removed.`n`nTwo last things you can do yourself if you like:`n- Remove the Download button: open Tampermonkey's dashboard and delete 'Video Downloader - YouTube button' (or remove the 'Video Downloader - YouTube button' extension if you used that instead).`n- The helper programs yt-dlp, FFmpeg and Deno are still installed (other apps may use them). Remove them in Settings > Apps if you don't need them.",
    'Uninstall Video Downloader', 'OK', 'Information')
