# Video Cruncher

A small Windows app that **super-compresses videos, GIFs and MP3s** for comedic effect, so they look and sound like they've been re-uploaded 400 times.

Pick a crunch level from 1 ("Slightly potato") to 10 ("ATOMIZED"), then add fun settings: deep-fried colours, glitch/datamosh, chipmunk speed, bass boost, slowed + reverb, nightcore, vinyl crackle, meme captions, endless "re-uploads" and more.

It's a single PowerShell script with a Frutiger Aero–style window. Everything runs on [ffmpeg](https://ffmpeg.org/).

## Getting started

1. Download this repo (**Code → Download ZIP**) and unzip it anywhere.
2. Double-click **`Video Cruncher.bat`**, or drag a file onto it.
3. Pick a mode (**Video**, **MP3** or **GIF**), choose a file, set the crunch level, and hit **CRUNCH IT**.

The result is saved next to the original as `name_crunched.mp4` / `.mp3` / `.gif`. Your original file is never changed.

**ffmpeg:** the app looks for an existing copy automatically, checking PATH, `C:\ffmpeg`, Program Files, WinGet/Scoop/Chocolatey, Downloads and Desktop. If it can't find one, it offers to download ffmpeg (~100 MB, once) or lets you point to `ffmpeg.exe`.

## Modes

### Video
- **Crunch level 1–10**, from "Slightly potato" to "ATOMIZED"
- **Deep fry colours:** oversaturated, over-sharpened, noisy
- **Pixelate only:** clean, chunky pixels without the compression mess
- **Glitch / datamosh:** smeared, corrupted, melting frames
- **Distorted audio** and **bass boost**
- **Speed:** 0.25x to 3x, with or without the chipmunk / deep-voice pitch change
- **Stretch:** wide, super wide, tall, super tall
- **Re-uploads:** re-crunches the result 5–50 times, like a meme reposted forever
- **Random seeking:** skips back and forth through the video at random, like someone frantically scrubbing the timeline
- **Auto YTP:** random YouTube Poop edits everywhere: stutter loops, reverses, chipmunk / slow-mo, pitch shifts, inverted colours, mirroring, rainbow, zoom, loud bursts and echo. It's different every time.
- **Save as GIF**

### MP3
Crunchy distortion, bass boost, phone call, underwater, slowed + reverb, nightcore, phone in a bathroom, vinyl crackle, radio static. You can also give it a video and it rips out the crunched sound.

### GIF
Fewer colours the higher the level, plus deep fry, grainy dither, boomerang, and **top/bottom meme captions in Impact font**.
You can paste a GIF link (Tenor, Giphy, Klipy…). Links are hit-and-miss, though, so saving the GIF to your PC first works best.

## Buttons
- **Preview (3 sec):** crunches just the first 3 seconds and plays it
- **Crunch a folder:** batch-crunches every matching file into a `crunched` subfolder
- **Random!:** picks surprise settings

## Made with Claude
This app was built by [Claude](https://claude.ai), Anthropic's AI assistant, through a back-and-forth conversation. Every feature here was asked for, tried out and refined along the way. I (heccfluffin) came up with the idea and the features, and tested it on Windows, where it runs well.

If you hit a bug, open an issue with a screenshot from `Debug (shows errors).bat`.

## Troubleshooting
- Run **`Debug (shows errors).bat`** to see error messages in a console window.
- If Windows shows "Windows protected your PC", click **More info → Run anyway**. It's a plain script, so you can read `VideoCruncher.ps1` in Notepad first.
