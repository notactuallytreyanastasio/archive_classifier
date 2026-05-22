# Archive Classifier

Classifies 1,371 videos from the [markpines Archive.org collection](https://archive.org/details/@markpines) -- rare Ron Wood footage, rock history, jazz, rehearsals, party tapes. Imports metadata from a SQLite database, downloads videos with bounded concurrency, transcribes audio with Bumblebee Whisper, and provides a LiveView UI for browsing, searching, and triggering classification.

## Tech Stack

- **Elixir 1.20** / **Phoenix 1.8.7** / **Phoenix LiveView 1.1**
- **Bumblebee + EXLA** for Whisper speech-to-text (openai/whisper-small)
- **Xav** NIF bindings for audio extraction (replaces FFmpeg CLI)
- **Nx** numerical computing backend
- **GenStage** pipeline with Task.Supervisor for bounded-concurrency transcription
- **ETS** in-memory cache for the full video catalog
- **Ecto + Postgres** (pgvector/pgvector:pg17 image via Docker)
- **Exqlite** for one-time SQLite import of archive metadata
- **Tailwind CSS v4** / **esbuild** / **Bandit** HTTP server

## Prerequisites

- Erlang/OTP and Elixir 1.20+ (install via `asdf` or `mise`)
- FFmpeg 7 (required by Xav NIF for audio decoding) -- `brew install ffmpeg`
- Docker (for Postgres)
- The `archive_tv` SQLite database (source of video metadata)

## Setup

```bash
# 1. Start Postgres
docker compose up -d

# 2. Install deps, create DB, run migrations, build assets
mix setup

# 3. Import video metadata from the archive_tv SQLite database
mix import_archive                          # defaults to ../archive_tv/data/archive-tv.db
mix import_archive /path/to/archive-tv.db   # or specify a path

# 4. Fetch thumbnail images from archive.org (concurrent, ~10 at a time)
mix fetch_thumbnails

# 5. Start the dev server
mix phx.server        # or: iex -S mix phx.server
```

The app is at [http://localhost:4000](http://localhost:4000).

## Routes

| Path | Description |
|------|-------------|
| `/` | Catalog -- browse videos grouped by collection, search, sort, trigger classification |
| `/search` | Transcript search -- full-text search across all transcribed audio, with timestamps |
| `/videos/:id/transcript` | Per-video transcript viewer with in-transcript search |
| `/thumbnails/:id` | Serves thumbnail images from the database |

All search state is URL-encoded (`?q=...`), so results are shareable.

## Architecture

```
lib/archive_classifier/
  application.ex          # OTP supervision tree
  cache.ex                # ETS cache -- all 1,371 videos in RAM
  archive/
    video.ex              # Video schema (archive_id, title, duration, status, tags, thumbnail)
  classification/
    transcript.ex         # Transcript schema (video_id, start_time, end_time, text)
  ml/
    whisper.ex            # Bumblebee Whisper Nx.Serving (model download + batched inference)
  media/
    audio.ex              # Xav-based audio extraction (16kHz mono WAV for Whisper)
  pipeline/
    supervisor.ex         # Supervisor for TaskSupervisor + TranscriptionProducer
    transcription_producer.ex  # GenServer queue -- max 2 concurrent transcriptions
    transcribe.ex         # Single-video pipeline: download -> extract audio -> whisper -> store

lib/archive_classifier_web/
  router.ex
  live/
    catalog_live.ex          # Collection-first browsing with search and sort
    search_live.ex           # Cross-video transcript full-text search
    transcript_search_live.ex  # Per-video transcript viewer with filtering
```

### Supervision Tree

```
ArchiveClassifier.Supervisor (one_for_one)
  +-- Telemetry
  +-- Repo (Ecto/Postgres)
  +-- Cache (ETS -- loads all videos on startup)
  +-- ML.Whisper (conditional -- only when start_whisper: true)
  +-- Pipeline.Supervisor (one_for_one)
  |     +-- Task.Supervisor (for transcription tasks)
  |     +-- TranscriptionProducer (queue + bounded dispatch)
  +-- PubSub
  +-- Endpoint
```

### ETS Cache

The full catalog fits in memory. `ArchiveClassifier.Cache` is a GenServer that owns a public named ETS table. It loads all videos on startup, serves reads without hitting Postgres, and exposes `reload/1` for single-video cache invalidation after classification status changes.

### Transcription Pipeline

1. User clicks "Classify" in the catalog UI
2. `TranscriptionProducer.enqueue/1` adds the video ID to a `:queue`
3. The producer dispatches up to 2 concurrent tasks via `Task.Supervisor.async_nolink/2`
4. Each task runs `Transcribe.run/1`: download video -> extract 16kHz mono WAV via Xav -> run Whisper inference -> insert transcript segments -> clean up files
5. Video status progresses: `pending -> queued -> classifying -> classified` (or `failed`)
6. Cache is reloaded after each status change

### Bumblebee Whisper Serving

`ML.Whisper` downloads `openai/whisper-small` from Hugging Face on first start, compiles it with EXLA, and registers an `Nx.Serving` under the module name. Transcription requests go through `Nx.Serving.batched_run/2`. The serving is conditionally started based on the `start_whisper` config flag (enabled in dev, can be disabled for faster startup when not doing ML work).

### Storage Constraint

This runs on a 512GB laptop. Max 5 videos downloaded at any time. The pipeline downloads, transcribes, then deletes media files. Short videos are processed first for faster feedback.

## Running Classification

From the catalog UI at `/`, drill into a collection and click "Classify" on any pending video. The pipeline handles the rest. Monitor progress via the status badges in the UI (pending / queued / classifying / classified / failed).

Programmatically:

```elixir
# In an IEx session
ArchiveClassifier.Pipeline.TranscriptionProducer.enqueue(video_id)
ArchiveClassifier.Pipeline.TranscriptionProducer.status()
# => %{queued: 3, active: 2}
```

## Development

```bash
mix test                # run tests (creates DB, runs migrations automatically)
mix test --failed       # re-run failures
mix format              # format code
mix credo --strict      # lint
```

### Conventions

- **Test-first development.** Write the test before the implementation. No exceptions.
- **`warnings_as_errors: true`** in `mix.exs`. The compiler is a linter.
- **Functional core, imperative shell.** Pure functions for classification logic and data transforms. GenServers and LiveViews are thin orchestration shells.
- **Type-first design.** Define `@type`, `@spec`, and `defstruct` before writing implementation.
- **LiveView only, minimal JS.** No JavaScript unless required for client-side interop.
- **Streams for collections** in LiveView. Never assign raw lists.
- **No `.new()` constructors.** Build structs with `%Module{field: value}`.
- **`{:ok, result}` / `{:error, reason}`** tuples for all fallible operations.
- **`mix test` must pass before every commit.**

### Pre-commit

The project uses a `precommit` Mix alias that runs compile (with warnings-as-errors), unlocks unused deps, formats, and runs the test suite:

```bash
mix precommit
```
