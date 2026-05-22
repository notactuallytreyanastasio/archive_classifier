# Archive Classifier

## What this is

A Phoenix app that classifies 1,371 videos from the markpines Archive.org collection (rare Ron Wood footage, rock history, jazz, rehearsals, party tapes). It reads metadata from the `archive_tv` SQLite database, downloads videos in controlled batches (max 5 at a time), and runs classification pipelines: audio transcription → segment classification, frame sampling → visual classification.

## Commands

```bash
mix setup              # deps.get + ecto.create + ecto.migrate
mix phx.server         # start dev server (localhost:4000)
iex -S mix phx.server  # with IEx shell
mix test               # run tests
mix test --failed      # re-run failed tests
mix format             # format code
mix credo --strict     # lint
```

## Infrastructure

- **Elixir app runs on the host** (not Docker — Docker is slow for Elixir hot reload)
- **Postgres runs in Docker** — `docker compose up -d`
- **llama-server** for vision models — runs as separate process when needed
- **FFmpeg** for audio extraction and frame sampling — installed via Homebrew

## Architecture

Functional core, imperative shell. Pure functions for all classification logic, data transformations, taxonomy rules. GenServers/LiveViews are the thin imperative shell that orchestrates side effects.

```
lib/archive_classifier/
├── archive/           # Reading from archive_tv SQLite (source of truth for video metadata)
├── classification/    # Ecto schemas + pure classification logic
├── pipeline/          # GenStage producer/consumers, download manager
├── ml/                # Bumblebee serving (whisper, CLIP) + HTTP client for llama-server
└── media/             # FFmpeg wrappers, storage lifecycle
```

## Design Philosophy

### Functional core, imperative shell

- **Functional core**: Pure functions that take data in, return data out. No side effects, no process state, no I/O. All classification logic, taxonomy rules, data transformations live here. Trivially testable.
- **Imperative shell**: LiveViews, GenServers, Ecto operations, model inference calls. Orchestrates side effects and calls into the functional core. Keep it thin.

### Type-first design

Before writing implementation, define `@type`, `@typedoc`, `defstruct`, and `@spec`. Types are the contract between modules.

### No OO constructors

Do NOT create `.new()` functions. Construct structs directly with `%Module{field: value}`.

### LiveView only, minimal JS

Use LiveView for everything. No JavaScript unless absolutely required for client-side interop (canvas, audio playback, etc). Use colocated JS hooks when needed.

## Elixir Guidelines

- Pattern match over conditionals. Match on function heads.
- `{:ok, result}` / `{:error, reason}` tuples for fallible operations.
- Use `with` for chaining ok/error tuples.
- Guards: `when is_binary(name) and byte_size(name) > 0`
- Predicates end with `?`, don't start with `is_`
- Prepend to lists: `[new | list]`, not `list ++ [new]`
- One module per file. Never nest modules.
- Never use map access syntax on structs. Use dot access.
- Don't use `String.to_atom/1` on user input.
- Each alias gets its own line. Alphabetical. No compound aliases.
- Pipe chains start with data, not function calls.
- Use `Req` for HTTP. Never HTTPoison, Tesla, or :httpc.
- Standard library for dates/times. No extra deps.
- `Task.async_stream/3` for concurrent work with backpressure.

## Phoenix 1.8 Guidelines

- LiveView templates start with `<Layouts.app flash={@flash} ...>`
- Use `<.icon name="hero-x-mark" class="w-5 h-5"/>` for icons
- Use `<.input>` for form inputs
- Tailwind CSS v4: no tailwind.config.js, uses import syntax in app.css
- Never use `@apply` in raw CSS
- Only `app.js` and `app.css` bundles. No external scripts in layouts.
- Always use streams for collections. Never assign raw lists.
- Always use `to_form/2` for forms. Never pass changesets to templates.
- Avoid LiveComponents unless strongly justified.
- Name LiveViews with `Live` suffix: `ArchiveClassifierWeb.DashboardLive`

## Ecto Guidelines

- Always preload associations when needed in templates
- `field :name, :string` even for text columns
- Use `Ecto.Changeset.get_field/2` to access changeset fields
- Fields set programmatically (like foreign keys) must NOT be in `cast`
- Always use `mix ecto.gen.migration` for migrations

## Test Guidelines

- Use `start_supervised!/1` to start processes
- Never use `Process.sleep/1` — use `Process.monitor/1` + assert on DOWN
- Use `Phoenix.LiveViewTest` and `LazyHTML` for assertions
- Test outcomes, not implementation
- Integration tests first, unit tests as code improves

## Storage Constraint

512GB laptop. Max 5 videos downloaded at any time. Process → classify → delete. Short videos first (faster feedback loop).
