@echo off
rem Video Downloader setup - double-click me.
title Video Downloader Setup
set "VDSRC=%~dp0"
if exist "%~dp0files\Install.ps1" set "VDSRC=%~dp0files\"
if not exist "%VDSRC%Install.ps1" (
  echo.
  echo   Setup can't find Install.ps1.
  echo   Right-click the downloaded ZIP, choose "Extract All...", then run Setup.cmd from the extracted folder.
  echo.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%VDSRC%Install.ps1"
