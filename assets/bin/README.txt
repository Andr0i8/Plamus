Plamus binary bundle (Windows)
==============================

Before building a release, copy into this folder:

  - yt-dlp.exe   (official Windows build from https://github.com/yt-dlp/yt-dlp/releases)
  - ffmpeg.exe   (static build, e.g. from https://www.gyan.dev/ffmpeg/builds/ or your trusted source)

The app extracts these from the asset bundle to the user's AppData on first run.
If they are missing, URL download and video-to-audio conversion will report a clear error
but the rest of the player (local MP3/WAV) still works.

This README is bundled as a small asset so the assets/bin/ directory is tracked by Flutter.
