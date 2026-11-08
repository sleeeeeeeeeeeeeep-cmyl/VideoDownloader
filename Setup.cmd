@echo off
rem Video Downloader setup - double-click me.
title Video Downloader Setup
if not exist "%~dp0files\Install.ps1" (
  echo.
  echo   The "files" folder is missing.
  echo   Right-click the downloaded ZIP, choose "Extract All...", then run Setup.cmd from the extracted folder.
  echo.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0files\Install.ps1"
