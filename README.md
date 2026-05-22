# Archive Classifier

**Live at [archive.bobbby.online](https://archive.bobbby.online)**

Search 1,371 videos from the [markpines Archive.org collection](https://archive.org/details/@markpines) by spoken dialogue, title, or description. The app transcribes audio with Whisper, stores timestamped segments in Postgres with full-text search, and serves a retro Mac OS-styled LiveView UI for browsing and exploring the archive.

The collection is rare Ron Wood footage, rock history, jazz performances, rehearsals, Diamond Head tapes, fashion reels, and party tapes — most of it uncatalogued until now.

## How it works

Videos are imported from an Archive.org metadata dump. A local transcription pipeline downloads each video, extracts audio via Xav NIF, runs Bumblebee Whisper inference, and stores timestamped transcript segments. Postgres tsvector indexes and ILIKE fallback power search across both video metadata and transcript content.

Transcription runs locally (not in production) — the Hetzner VPS serves the UI and search only. The local pipeline processes 2 videos concurrently, bounded by laptop thermals and the 512GB disk.

## Routes

| Path | What it does |
|------|-------------|
| `/` | **Catalog** — browse by collection, search across titles + descriptions + transcripts, sort, trigger classification |
| `/search` | **Transcript search** — full-text search across all spoken words, with timestamps and thumbnails |
| `/videos/:id/transcript` | **Video explorer** — frame scrubbing, timeline slider, play/pause, searchable transcript with click-to-jump |
| `/admin` | **Admin** — filter videos by duration/collection/status, mass-enqueue transcription jobs, live job queue viewer |

All search state is URL-encoded (`?q=...`), so results are shareable.

## Tech stack

- **Elixir 1.20** / **Phoenix 1.8.7** / **LiveView 1.1**
- **Bumblebee + EXLA** — Whisper speech-to-text (openai/whisper-small, `chunk_num_seconds: 30`)
- **Xav** NIF — in-process audio extraction (16kHz mono WAV), replaces FFmpeg CLI
- **FFmpeg** — frame extraction (JPEG every 10s), still CLI, Xav replacement planned
- **Twerker** — GenStage-based persistent job queue backed by Postgres ([github](https://github.com/notactuallytreyanastasio/twerker))
- **ETS** — full catalog cached in memory (1,371 videos loaded on startup)
- **Postgres 17** — videos, transcripts, video frames (JPEG blobs), twerker jobs, tsvector FTS indexes with auto-update triggers
- **Tailwind CSS v4** / **esbuild** / **Bandit**

## Setup

```bash
# 1. Start Postgres
docker compose up -d

# 2. Install deps, create DB, run migrations, build assets
mix setup

# 3. Import video metadata from the archive_tv SQLite database
mix import_archive                          # defaults to ../archive_tv/data/archive-tv.db
mix import_archive /path/to/archive-tv.db   # or specify a path

# 4. Fetch thumbnail images from archive.org
mix fetch_thumbnails

# 5. Start the dev server
mix phx.server        # or: iex -S mix phx.server
```

The app is at [localhost:4000](http://localhost:4000).

To run transcription, enable Whisper in `config/dev.exs` (`start_whisper: true`) and restart. First start downloads the model from Hugging Face (~500MB).

## Architecture

```
lib/archive_classifier/
  application.ex              # OTP supervision tree
  cache.ex                    # ETS — all 1,371 videos in RAM
  archive.ex                  # Query context — list, filter, FTS search
  archive/
    video.ex                  # Video schema (archive_id, title, duration, status, tags, thumbnail)
  classification/
    transcript.ex             # Transcript schema (video_id, start_time, end_time, text, search_vector)
    video_frame.ex            # JPEG frame blobs stored in Postgres
  ml/
    whisper.ex                # Bumblebee Whisper Nx.Serving (conditional startup)
  media/
    audio.ex                  # Xav NIF — 16kHz mono WAV extraction
    frames.ex                 # FFmpeg CLI — JPEG frame extraction every 10s
  pipeline/
    transcribe.ex             # Full pipeline: download → audio → whisper → store → frames → cleanup
    transcription_producer.ex # GenServer queue, max 2 concurrent via Task.Supervisor
    dedup.ex                  # Merges consecutive identical Whisper segments
    supervisor.ex             # Pipeline supervision tree

lib/archive_classifier_web/
  router.ex
  live/
    catalog_live.ex           # Collection-first browsing with search and sort
    search_live.ex            # Cross-video transcript full-text search
    transcript_search_live.ex # Video explorer — frame scrubbing, timeline, captions
    admin_live.ex             # Mass-enqueue dashboard with live job queue viewer
  controllers/
    thumbnail_controller.ex   # Serves thumbnail images from DB
    frame_controller.ex       # Serves video frame images from DB
```

### Transcription pipeline

```
User clicks Classify (or admin mass-enqueue)
  → Twerker.enqueue (persisted to Postgres)
  → Consumer picks up job
    → Req.get from archive.org (exponential backoff, 5 retries)
    → Xav NIF extracts 16kHz mono WAV
    → Whisper Nx.Serving transcribes (chunk_num_seconds: 30)
    → Hallucination filter (non-ASCII ratio, repeated words, nil timestamps)
    → Dedup merges consecutive identical segments
    → Insert transcripts (triggers populate tsvector)
    → FFmpeg extracts JPEG frames every 10s
    → Cleanup temp files, update video status, reload cache
```

Video status: `pending → queued → classifying → classified` (or `failed`).

### Search

Search combines Postgres full-text search (tsvector with English stemming) and ILIKE fallback for terms the stemmer misses (proper nouns, short words). Both video metadata and transcript content are searched. Results are filtered by collection when drilled in, and optionally by classification status ("Transcribed only" checkbox, on by default).

### Video explorer

The transcript viewer at `/videos/:id/transcript` is an interactive explorer with three linked zones:

1. **Frame viewer** — click+drag to scrub through extracted frames
2. **Timeline slider** — drag to any moment, frame and caption follow
3. **Searchable transcript** — click any segment to jump, active segment highlights

All driven by a colocated LiveView JS hook. Play button auto-advances every 3 seconds.

## Deployment

Production runs on a Hetzner VPS as a sidecar in a docker-compose stack. Whisper and Twerker are disabled in prod — the server is UI and search only.

```bash
# Deploy code + assets
./deploy.sh

# Sync local database to production
pg_dump -U postgres -h localhost -p 5432 -Fc archive_classifier_dev -f /tmp/dump.sql
scp /tmp/dump.sql root@5.161.181.91:/tmp/
# Then on server: stop classifier, drop/create DB, pg_restore, start classifier
```

## Development

```bash
mix test                # run tests
mix test --failed       # re-run failures
mix format              # format code
mix credo --strict      # lint
mix precommit           # compile + format + test (all-in-one)
```

### Conventions

- **Test-first.** Write the test before the implementation.
- **`warnings_as_errors: true`.** The compiler is a linter.
- **Functional core, imperative shell.** Pure functions for classification logic. GenServers and LiveViews are thin shells.
- **Type-first.** Define `@type`, `@spec`, and `defstruct` before implementation.
- **LiveView only, minimal JS.** Colocated hooks when needed, nothing else.
- **`mix test` must pass before every commit.**
