@echo off
rem Double-click to open Video Cruncher, or drag a video onto this file.
start "" powershell -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0VideoCruncher.ps1" "%~1"
