@echo off
rem Video Downloader from the command line.   Type:  video-downloader help
rem Setup copies this file to %LOCALAPPDATA%\Programs\VideoDownloader\bin and adds that folder to your PATH,
rem so the command works in the Run box (Windows key + R), Command Prompt, PowerShell and Windows Terminal.
rem "video-downloader update" always uses the newest update steps published on GitHub (get.ps1), so the same
rem command keeps working for every future version.
setlocal EnableExtensions
set "VD_DIR=%~dp0.."
if exist "%~dp0VideoDownloader.ps1" set "VD_DIR=%~dp0."
set "VD_PS1=%VD_DIR%\VideoDownloader.ps1"
set "VD_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "VD_GET=https://raw.githubusercontent.com/sleeeeeeeeeeeeeep-cmyl/VideoDownloader/main/get.ps1"

set "VD_REINSTALL="
set "VD_CMD=%~1"
if not defined VD_CMD set "VD_CMD=open"
rem (accept "update", "--update", "-update" and "/update" alike)
if "%VD_CMD:~0,2%"=="--" set "VD_CMD=%VD_CMD:~2%"
if "%VD_CMD:~0,1%"=="-" set "VD_CMD=%VD_CMD:~1%"
if "%VD_CMD:~0,1%"=="/" set "VD_CMD=%VD_CMD:~1%"
if "%VD_CMD%"=="?" set "VD_CMD=help"
if /i "%VD_CMD%"=="h" set "VD_CMD=help"
if /i "%VD_CMD%"=="upgrade" set "VD_CMD=update"
if /i "%VD_CMD%"=="v" set "VD_CMD=version"
for %%c in (open update reinstall version settings history menu uninstall help) do if /i "%VD_CMD%"=="%%c" goto cmd_%%c
echo.
echo   "%~1" isn't a Video Downloader command.
goto cmd_help_list

:cmd_reinstall
set "VD_REINSTALL=1"
:cmd_update
echo.
if defined VD_REINSTALL echo   Reinstalling the newest Video Downloader. Your settings, queue and history are kept.
if not defined VD_REINSTALL echo   Updating Video Downloader, yt-dlp and Deno to their newest versions...
set "VD_FROM_COMMAND=1"
rem Started from the Run box or the Start menu, this window would vanish before you could read it.
set "VD_OWNWIN="
echo %cmdcmdline% | find /i "video-downloader.cmd" >nul && set "VD_OWNWIN=1"
rem The update replaces this very file. cmd reads a ( ) block into memory before running it, so everything
rem after the update runs from that block and never from the half-replaced file. (No brackets in text here.)
(
  "%VD_PS%" -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072; irm '%VD_GET%' | iex"
  if errorlevel 1 (
    if defined VD_OWNWIN timeout /t 60
    exit /b 1
  )
  if defined VD_OWNWIN echo.
  if defined VD_OWNWIN timeout /t 20
  exit /b 0
)

:cmd_version
if not exist "%VD_PS1%" goto not_installed
for /f "tokens=2 delims='" %%v in ('findstr /b /c:"$AppVersion = " "%VD_PS1%"') do echo Video Downloader %%v
exit /b 0

:cmd_open
if not exist "%VD_PS1%" goto not_installed
start "" "%SystemRoot%\System32\conhost.exe" --headless "%VD_PS%" -NoProfile -ExecutionPolicy Bypass -File "%VD_PS1%" -App
exit /b 0

:cmd_settings
if not exist "%VD_PS1%" goto not_installed
start "" "%SystemRoot%\System32\conhost.exe" --headless "%VD_PS%" -NoProfile -ExecutionPolicy Bypass -File "%VD_PS1%" -Settings
exit /b 0

:cmd_history
if not exist "%VD_PS1%" goto not_installed
start "" "%SystemRoot%\System32\conhost.exe" --headless "%VD_PS%" -NoProfile -ExecutionPolicy Bypass -File "%VD_PS1%" -History
exit /b 0

:cmd_menu
if not exist "%VD_PS1%" goto not_installed
"%VD_PS%" -NoProfile -ExecutionPolicy Bypass -File "%VD_PS1%" -Menu
exit /b %errorlevel%

:cmd_uninstall
if not exist "%VD_DIR%\Uninstall.ps1" goto not_installed
rem (one block again: the uninstaller deletes the folder this file is in)
(
  "%VD_PS%" -NoProfile -ExecutionPolicy Bypass -File "%VD_DIR%\Uninstall.ps1"
  exit /b 0
)

:not_installed
echo.
echo   Video Downloader isn't installed in "%VD_DIR%".
echo   Install it with:  video-downloader update
exit /b 1

:cmd_help
echo.
echo   Video Downloader
:cmd_help_list
echo.
echo   video-downloader              open the Video Downloader window
echo   video-downloader update       update Video Downloader, yt-dlp and Deno to the newest versions
echo   video-downloader reinstall    install the newest version again (repairs a broken install)
echo   video-downloader version      show which version you have
echo   video-downloader settings     open the settings window
echo   video-downloader history      open your watch history
echo   video-downloader menu         the text version (paste links in this window)
echo   video-downloader uninstall    remove Video Downloader
echo.
if /i "%VD_CMD%"=="help" exit /b 0
exit /b 2
