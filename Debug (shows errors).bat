@echo off
rem Same as Video Cruncher.bat, but keeps a console window open so you can see any errors.
powershell -NoProfile -STA -ExecutionPolicy Bypass -NoExit -File "%~dp0VideoCruncher.ps1" "%~1"
