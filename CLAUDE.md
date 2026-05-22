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

## Test-First Development — MANDATORY

**Write tests BEFORE implementation. Always.**

This is not optional. The workflow is:
1. Write the test that describes the API you want
2. Watch it fail
3. Write the implementation to make it pass
4. Refactor

If you find yourself writing implementation code without a test already waiting for it, stop. Go write the test.

Tests define the contract. The implementation serves the test, not the other way around. When you write tests first, you design better APIs because you're forced to think about what the caller actually wants before you think about how to provide it.

### Test rules

- Use `start_supervised!/1` to start processes
- Never use `Process.sleep/1` — use `Process.monitor/1` + assert on DOWN
- Use `Phoenix.LiveViewTest` and `LazyHTML` for assertions
- Test outcomes, not implementation
- Integration tests first, unit tests as code improves
- Every public function in the functional core gets a test
- `mix test` must pass before every commit — no exceptions

## Storage Constraint

512GB laptop. Max 5 videos downloaded at any time. Process → classify → delete. Short videos first (faster feedback loop).

<!-- deciduous:start -->
## Decision Graph Workflow

**THIS IS MANDATORY. Log decisions IN REAL-TIME, not retroactively.**

### Available Slash Commands

| Command | Purpose |
|---------|---------|
| `/decision` | Manage decision graph - add nodes, link edges, sync |
| `/recover` | Recover context from decision graph on session start |
| `/work` | Start a work transaction - creates goal node before implementation |
| `/document` | Generate comprehensive documentation for a file or directory |
| `/build-test` | Build the project and run the test suite |
| `/serve-ui` | Start the decision graph web viewer |
| `/sync-graph` | Export decision graph to GitHub Pages |
| `/decision-graph` | Build a decision graph from commit history |
| `/sync` | Multi-user sync - pull events, rebuild, push |

### Available Skills

| Skill | Purpose |
|-------|---------|
| `/pulse` | Map current design as decisions (Now mode) |
| `/narratives` | Understand how the system evolved (History mode) |
| `/archaeology` | Transform narratives into queryable graph |

### The Node Flow Rule - CRITICAL

The canonical flow through the decision graph is:

```
goal -> options -> decision -> actions -> outcomes
```

- **Goals** lead to **options** (possible approaches to explore)
- **Options** lead to a **decision** (choosing which option to pursue)
- **Decisions** lead to **actions** (implementing the chosen approach)
- **Actions** lead to **outcomes** (results of the implementation)
- **Observations** attach anywhere relevant
- Goals do NOT lead directly to decisions -- there must be options first
- Options do NOT come after decisions -- options come BEFORE decisions
- Decision nodes should only be created when an option is actually chosen, not prematurely

### The Core Rule

```
BEFORE you do something -> Log what you're ABOUT to do
AFTER it succeeds/fails -> Log the outcome
CONNECT immediately -> Link every node to its parent
AUDIT regularly -> Check for missing connections
```

### Behavioral Triggers - MUST LOG WHEN:

| Trigger | Log Type | Example |
|---------|----------|---------|
| User asks for a new feature | `goal` **with -p** | "Add dark mode" |
| Exploring possible approaches | `option` | "Use Redux for state" |
| Choosing between approaches | `decision` | "Choose state management" |
| About to write/edit code | `action` | "Implementing Redux store" |
| Something worked or failed | `outcome` | "Redux integration successful" |
| Notice something interesting | `observation` | "Existing code uses hooks" |

### What NOT to Log - CRITICAL

**The decision graph records the USER'S project decisions, not your internal process.**

Nodes should capture what the user is building, choosing, and accomplishing. Do NOT create nodes for your own thinking, planning, or tooling steps.

**DO NOT create nodes for:**
- Reading/exploring the codebase ("Analyzing project structure", "Reading config files")
- Your planning process ("Planning implementation approach", "Evaluating options internally")
- Tool usage ("Running tests to check status", "Checking git log")
- Context gathering ("Understanding existing auth code", "Reviewing PR comments")
- Meta-commentary ("Starting work on this task", "Preparing to implement")

**DO create nodes for:**
- What the user asked for (goals)
- Concrete approaches being considered (options)
- Choices made between approaches (decisions)
- Code being written or changed (actions)
- Results of implementation (outcomes)
- Technical findings that affect decisions (observations)

**Rule of thumb:** If a node describes something the user would put on a project timeline or in a PR description, log it. If it describes your internal process of reading and thinking, don't.

### Document Attachments

Attach files (images, PDFs, diagrams, specs, screenshots) to decision graph nodes for rich context.

```bash
# Attach a file to a node
deciduous doc attach <node_id> <file_path>
deciduous doc attach <node_id> <file_path> -d "Architecture diagram"
deciduous doc attach <node_id> <file_path> --ai-describe

# List documents
deciduous doc list              # All documents
deciduous doc list <node_id>    # Documents for a specific node

# Manage documents
deciduous doc show <doc_id>     # Show document details
deciduous doc describe <doc_id> "Updated description"
deciduous doc describe <doc_id> --ai   # AI-generate description
deciduous doc open <doc_id>     # Open in default application
deciduous doc detach <doc_id>   # Soft-delete (recoverable)
deciduous doc gc                # Remove orphaned files from disk
```

**When to suggest document attachment:**

| Situation | Action |
|-----------|--------|
| User shares an image or screenshot | Ask: "Want me to attach this to the current goal/action node?" |
| User references an external document | Ask: "Should I attach a copy to the decision graph?" |
| Architecture diagram is discussed | Suggest attaching it to the relevant goal node |
| Files not in the project are dropped in | Attach to the most relevant active node |

**Do NOT aggressively prompt for documents.** Only suggest when files are directly relevant to a decision node. Files are stored in `.deciduous/documents/` with content-hash naming for deduplication.

### CRITICAL: Capture VERBATIM User Prompts

**Prompts must be the EXACT user message, not a summary.** When a user request triggers new work, capture their full message word-for-word.

**BAD - summaries are useless for context recovery:**
```bash
# DON'T DO THIS - this is a summary, not a prompt
deciduous add goal "Add auth" -p "User asked: add login to the app"
```

**GOOD - verbatim prompts enable full context recovery:**
```bash
# Use --prompt-stdin for multi-line prompts
deciduous add goal "Add auth" -c 90 --prompt-stdin << 'EOF'
I need to add user authentication to the app. Users should be able to sign up
with email/password, and we need OAuth support for Google and GitHub. The auth
should use JWT tokens with refresh token rotation.
EOF

# Or use the prompt command to update existing nodes
deciduous prompt 42 << 'EOF'
The full verbatim user message goes here...
EOF
```

**When to capture prompts:**
- Root `goal` nodes: YES - the FULL original request
- Major direction changes: YES - when user redirects the work
- Routine downstream nodes: NO - they inherit context via edges

**Updating prompts on existing nodes:**
```bash
deciduous prompt <node_id> "full verbatim prompt here"
cat prompt.txt | deciduous prompt <node_id>  # Multi-line from stdin
```

Prompts are viewable in the web viewer.

### CRITICAL: Maintain Connections

**The graph's value is in its CONNECTIONS, not just nodes.**

| When you create... | IMMEDIATELY link to... |
|-------------------|------------------------|
| `outcome` | The action that produced it |
| `action` | The decision that spawned it |
| `decision` | The option(s) it chose between |
| `option` | Its parent goal |
| `observation` | Related goal/action |
| `revisit` | The decision/outcome being reconsidered |

**Root `goal` nodes are the ONLY valid orphans.**

### Quick Commands

```bash
deciduous add goal "Title" -c 90 -p "User's original request"
deciduous add action "Title" -c 85
deciduous link FROM TO -r "reason"  # DO THIS IMMEDIATELY!
deciduous serve   # View live (auto-refreshes every 30s)
deciduous sync    # Export for static hosting

# Metadata flags
# -c, --confidence 0-100   Confidence level
# -p, --prompt "..."       Store the user prompt (use when semantically meaningful)
# -f, --files "a.rs,b.rs"  Associate files
# -b, --branch <name>      Git branch (auto-detected)
# --commit <hash|HEAD>     Link to git commit (use HEAD for current commit)
# --date "YYYY-MM-DD"      Backdate node (for archaeology)

# Branch filtering
deciduous nodes --branch main
deciduous nodes -b feature-auth
```

### CRITICAL: Link Commits to Actions/Outcomes

**After every git commit, link it to the decision graph!**

```bash
git commit -m "feat: add auth"
deciduous add action "Implemented auth" -c 90 --commit HEAD
deciduous link <goal_id> <action_id> -r "Implementation"
```

The `--commit HEAD` flag captures the commit hash and links it to the node. The web viewer will show commit messages, authors, and dates.

### Git History & Deployment

```bash
# Export graph AND git history for web viewer
deciduous sync

# This creates:
# - docs/graph-data.json (decision graph)
# - docs/git-history.json (commit info for linked nodes)
```

To deploy to GitHub Pages:
1. `deciduous sync` to export
2. Push to GitHub
3. Settings > Pages > Deploy from branch > /docs folder

Your graph will be live at `https://<user>.github.io/<repo>/`

### Branch-Based Grouping

Nodes are auto-tagged with the current git branch. Configure in `.deciduous/config.toml`:
```toml
[branch]
main_branches = ["main", "master"]
auto_detect = true
```

### Audit Checklist (Before Every Sync)

1. Does every **outcome** link back to what caused it?
2. Does every **action** link to why you did it?
3. Any **dangling outcomes** without parents?

### Git Staging Rules - CRITICAL

**NEVER use broad git add commands that stage everything:**
- ❌ `git add -A` - stages ALL changes including untracked files
- ❌ `git add .` - stages everything in current directory
- ❌ `git add -a` or `git commit -am` - auto-stages all tracked changes
- ❌ `git add *` - glob patterns can catch unintended files

**ALWAYS stage files explicitly by name:**
- ✅ `git add src/main.rs src/lib.rs`
- ✅ `git add Cargo.toml Cargo.lock`
- ✅ `git add .claude/commands/decision.md`

**Why this matters:**
- Prevents accidentally committing sensitive files (.env, credentials)
- Prevents committing large binaries or build artifacts
- Forces you to review exactly what you're committing
- Catches unintended changes before they enter git history

### Session Start Checklist

```bash
deciduous check-update    # Update needed? Run 'deciduous update' if yes
                          # (auto-checked every 24h if auto-update is on)
deciduous nodes           # What decisions exist?
deciduous edges           # How are they connected? Any gaps?
deciduous doc list        # Any attached documents to review?
git status                # Current state
```

### Multi-User Sync

Sync decisions with teammates via event logs:

```bash
# Check sync status
deciduous events status

# Apply teammate events (after git pull)
deciduous events rebuild

# Compact old events periodically
deciduous events checkpoint --clear-events
```

Events auto-emit on add/link/status commands. Git merges event files automatically.
<!-- deciduous:end -->
