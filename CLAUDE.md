# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Plamus is an offline-first, professional Windows desktop music player built with Flutter. It features local library management, yt-dlp/ffmpeg media ingestion, and a minimalist UI with glass morphism design.

## Development Commands

### Running the app
```bash
flutter run -d windows
```

### Testing
```bash
flutter test
```

### Building
```bash
flutter build windows --release
```

### Code analysis
```bash
flutter analyze
```

### Dependency management
```bash
flutter pub get
flutter pub upgrade
```

## Architecture

### Audio Backend (Windows-specific)
- `just_audio` has no native Windows plugin — **media_kit backend is required**
- `JustAudioMediaKit.ensureInitialized(windows: true)` must run before audio playback
- After changing audio dependencies, perform a **full cold restart** (not hot reload)
- Audio continues when the window is minimized (desktop OS audio mix)

### Database Layer
- SQLite via `sqflite_common_ffi` for Windows desktop
- Must initialize FFI in `main()`: `sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;`
- Schema: `tracks`, `playlists`, `playlist_tracks`, `history`
- Database file: `plamus.db` in application support directory

### State Management
- Provider pattern for reactive state
- Three main providers:
  - `LibraryService`: tracks, playlists, SQLite coordination
  - `AudioPlayerService`: playback queue, shuffle, repeat, volume
  - `ThemeController`: light/dark theme toggle

### Media Ingestion Pipeline
1. **Local files**: `MediaIngestService` copies audio or extracts from video via ffmpeg
2. **YouTube/URLs**: `DownloadService` runs yt-dlp to download MP3 (VBR q0)
3. **Registration**: `LibraryService.registerTrackFile()` indexes the file path in SQLite
4. Audio formats: MP3, WAV, FLAC, M4A, AAC, OGG (copied as-is)
5. Video formats: MP4, MKV, WEBM, MOV, AVI (audio extracted to MP3)

### Binary Dependencies
- `BinaryService` extracts bundled `yt-dlp.exe` and `ffmpeg.exe` from `assets/bin/` to application support on first launch
- **Before release builds**: place real Windows binaries in `assets/bin/` (see `assets/bin/README.txt`)
- Binaries are NOT in git; developers must download separately
- yt-dlp flags: `--no-playlist -x --audio-format mp3 --audio-quality 0`
- ffmpeg flags: `-vn -codec:a libmp3lame -q:a 0` (VBR quality 0)

### UI Structure
- `PlamusShell`: root layout with sidebar navigation + animated content + glass player bar
- Sections: Home (library), Search/Import, Liked Songs, History, Playlist Detail
- `GlassPlayerBar`: bottom player with blur backdrop, progress slider, playback controls
- Theme: custom `PlamusTheme` with light/dark variants, glass morphism effects

### File Paths
- Library directory: `%AppData%/Plamus/library/` (or platform equivalent via `path_provider`)
- Database: `%AppData%/Plamus/plamus.db`
- Binaries: `%AppData%/Plamus/bin/yt-dlp.exe`, `ffmpeg.exe`

## Key Services

### AudioPlayerService
- Wraps `just_audio` with queue management, shuffle, repeat modes
- Shuffle uses back-stack for predictable "previous" behavior
- Repeat modes: off, all (loop queue), one (loop single track)
- Records play history to SQLite on track load
- Updates track duration in DB after first play if unknown

### LibraryService
- CRUD for tracks and playlists
- Smart lists: liked tracks, recent history (last 50 plays)
- Track operations: rename (updates file + DB), export, reveal in Explorer, delete
- Playlist operations: create, rename, delete, add/remove tracks

### DownloadService
- Runs yt-dlp as child process with 45-minute timeout
- Parses `[download] X%` from stderr for progress UI
- Returns path to downloaded MP3 in library directory
- Throws `TimeoutException`, `ProcessException`, or `StateError` on failure

### MediaIngestService
- Copies audio files or transcodes video to MP3
- Ensures unique filenames with `_1`, `_2` suffixes if collision
- Validates file existence before ingest

## Windows-Specific Notes
- Shell integration: `WindowsShell.showInFolder()` uses `explorer.exe /select,<path>`
- File paths use forward slashes internally (cross-platform `path` package)
- Bash shell syntax in development (Git Bash / WSL)

## Testing Notes
- Widget tests in `test/widget_test.dart`
- No integration tests currently
- Manual testing: run dev build and test import, playback, playlist CRUD

## Common Pitfalls
- **Audio not working**: ensure `JustAudioMediaKit.ensureInitialized()` ran and media_kit libs are in pubspec
- **yt-dlp/ffmpeg missing**: check `BinaryService.lastResolution.errors` for extraction issues
- **File in use errors**: Windows locks open files; stop playback before renaming/deleting
- **Hot reload issues**: audio backend changes require full restart
