# supabase-worktree

Run an **isolated local Supabase stack** per project — or per `git worktree` — with deterministic ports, a unique `project_id`, and zero config duplication. Your `supabase/` directory is the source of truth; the tool just spins up a parallel stack alongside it.

Originally built to let multiple feature branches of the same project run their own Supabase locally without clobbering each other's databases.

## Install

```sh
brew install yannikw23/tap/supabase-worktree
```

Requires Docker and the Supabase CLI. The CLI is available from two taps — either works:

```sh
brew install supabase          # homebrew/core
# or
brew install supabase/tap/supabase
```

(The formula does **not** declare a dependency on `supabase` because the two taps conflict; install it yourself before using this tool.) `libpq` is pulled in automatically for `psql` / `pg_restore`.

## Quickstart

```sh
cd path/to/your/project        # must contain a supabase/ directory
supabase-worktree up           # init + start (first run takes a while)
supabase-worktree status       # ports, project_id, db url, running state
supabase-worktree psql         # open a psql shell against the isolated db
supabase-worktree down         # stop the stack
```

If you use `git worktree` for feature branches, run the same command in each worktree — each one gets its own stack:

```sh
git worktree add ../myproj-feature-x feature-x
cd ../myproj-feature-x
supabase-worktree up           # separate stack, separate ports, separate db
```

## How it works

When you run `supabase-worktree init` (or `up`), the tool:

1. **Picks an instance name**, in order of precedence:
   1. `$SUPABASE_WORKTREE_NAME` if set.
   2. The current git branch name (slugified) if inside a git work tree.
   3. A deterministic keyword from a built-in list, seeded by `sha1(ROOT)` — stable across runs.
2. **Picks a port offset**, in order of precedence:
   1. `$SUPABASE_WORKTREE_PORT_OFFSET` if set.
   2. The api port of an already-generated `.supabase-worktree/supabase/config.toml` — **existing stacks keep their ports forever**, no matter how the pool or assignments change underneath them.
   3. An explicit pin for this name in `.supabase-worktree.toml` (`[assignments]`, see below).
   4. `sha1(name)` over the reservable pool (50 slots — multiples of 100, `0..4900` — unless the config file or `$SUPABASE_WORKTREE_OFFSETS` shrinks it), linear-probing past slots pinned to other names. The offset is applied to all Supabase service ports (api, db, studio, inbucket, analytics, pooler, shadow, inspector). Because the slot set is finite and known up front, you can whitelist all derived OAuth redirect URIs once (`supabase-worktree ports`) and new worktrees never trigger a console roundtrip.
3. **Detects the base `project_id`** from your `supabase/config.toml` and namespaces it: `${base}-${name}`.
4. **Creates `.supabase-worktree/supabase/`** at the project root with:
   - Symlinks back to `migrations/`, `functions/`, `schemas/`, `seeds/`, `tests/`, `templates/` — so editing those still touches the canonical source.
   - A copied `config.toml` with rewritten ports and project_id.
5. **Writes `.supabase-worktree/.env`** — a snapshot of `$ROOT/.env` (if present) plus per-instance overrides (`SUPABASE_URL`, `SITE_URL`, `SUPABASE_WORKTREE_NEXT_PORT`, etc.). The Supabase CLI reads this file when interpolating `env()` in `config.toml`, so OAuth `client_id`s and a per-worktree `site_url` resolve correctly. Regenerated on every `init` / `up`.
6. **Generates `$ROOT/.env.local`** (only if missing — never clobbers your edits) with `NEXT_PUBLIC_SUPABASE_URL`, `SUPABASE_URL`, `SITE_URL`, `SUPABASE_WORKTREE_PORT_OFFSET`, and `SUPABASE_WORKTREE_NEXT_PORT`. Bun / Next / one-off scripts auto-load this and target the right stack with zero per-command flags.
7. **Runs `supabase --workdir .supabase-worktree start`** so the CLI sees the isolated config.

Everything else (`db reset`, `migration new`, `db diff`, `gen types`, ...) you run via the regular `supabase --workdir .supabase-worktree …` invocation, or just `cd .supabase-worktree` and use `supabase` directly.

## Commands

| Command                    | What it does                                          |
| -------------------------- | ----------------------------------------------------- |
| `init`                     | Generate `.supabase-worktree/supabase/config.toml` + symlinks |
| `up [supabase args]`       | `supabase start` against the isolated config          |
| `down [supabase args]`     | `supabase stop` against the isolated config           |
| `status`                   | Print root, name, project_id, ports, db url, running state |
| `restore <dump> [--yes]`   | Two-pass `pg_restore` into the isolated DB (app schemas first, then `auth` + `storage` data-only) + reassign `public.*` ownership back to `postgres`. Confirms before wiping; pass `--yes` to skip. |
| `psql [args...]`           | `psql` into the isolated DB                           |
| `ports [--urls\|--table\|--all]` | List every reservable port slot. Default mode prints the Supabase auth redirect URIs to whitelist in OAuth providers (Google, GitHub, …). |
| `hook`                     | Run `$ROOT/.supabase-worktree.hook` on demand (fires automatically after `init` / `up`) |
| `version`                  | Print version                                         |
| `help`                     | Show usage                                            |

## Environment overrides

| Variable                          | Effect                                          |
| --------------------------------- | ----------------------------------------------- |
| `SUPABASE_WORKTREE_NAME`          | Override the instance name                      |
| `SUPABASE_WORKTREE_PROJECT_ID`    | Override the auto-detected base `project_id`    |
| `SUPABASE_WORKTREE_PORT_OFFSET`   | Pin a specific port offset (skips slot derivation) |
| `SUPABASE_WORKTREE_OFFSETS`       | Comma-separated list of reservable offsets (default: 50 slots, multiples of 100, `0..4900`) |

## Derived ports & env vars

Each instance exposes a deterministic Next.js / app dev-server port alongside the Supabase ports — `3000 + (offset / 100)`, range `3000..3049` — so parallel worktrees can each run their own `next dev` without colliding. The value lands in two places:

- `.env.local` → `SUPABASE_WORKTREE_NEXT_PORT=…` (loaded automatically by Bun / Next).
- `.supabase-worktree/.env` → same vars, so `supabase start` sees them too and `env(SITE_URL)` in `config.toml` resolves.

Wire it up in your project's `dev` script:

```jsonc
// package.json
"dev": "next dev -p ${SUPABASE_WORKTREE_NEXT_PORT:-3000}"
```

And in `supabase/config.toml`, swap hard-coded URLs for `env()`:

```toml
[auth]
site_url = "env(SITE_URL)"
additional_redirect_urls = ["env(SITE_URL)"]
```

For OAuth providers (Google, GitHub, …) the redirect-URI list in the provider console must include each derived port. Because the port offsets come from a fixed slot list, you can whitelist all of them once and never touch the console again:

```sh
supabase-worktree ports                # one redirect URI per slot, paste-ready
supabase-worktree ports --table        # full per-slot port breakdown
supabase-worktree ports --all          # both
```

Need fewer slots (cheaper to whitelist) or different ones (avoiding ports another app on your machine grabs)? Override the list:

```sh
export SUPABASE_WORKTREE_OFFSETS="0,100,200,1400,2200,4300"
```

…or better, commit the choice to the repo with a config file (below) so every checkout and teammate resolves the same ports.

## Config file: `.supabase-worktree.toml`

Drop a `.supabase-worktree.toml` at the project root (commit it) to make port assignment fully predictable:

```toml
# Reservable port-offset pool. New worktrees hash into this pool, so the OAuth
# redirect whitelist printed by `supabase-worktree ports` never changes.
offsets = [0, 100, 200, 300, 400, 500, 600, 700, 800, 900]

# Pin worktree names (slugified branch names: feat/foo → feat-foo) to offsets.
# Use this to keep a long-lived stack on its already-whitelisted port, or to
# resolve a hash collision between two simultaneously running worktrees.
[assignments]
main = 1400
"feat-foo" = 100
```

Semantics:

- `offsets` replaces the built-in 50-slot pool (`$SUPABASE_WORKTREE_OFFSETS` still wins over it). A small pool means a short whitelist; collisions only matter for worktrees running *at the same time*, and pins resolve them.
- `[assignments]` pins beat hash derivation. Unpinned names hash into the pool and linear-probe past slots pinned to other names, so a fresh worktree never lands on a reserved offset.
- **Existing stacks are sticky**: once `.supabase-worktree/supabase/config.toml` has been generated, its ports win over pool and assignment edits (a warning tells you when they disagree, and how to re-init onto the pinned slot). `status` shows where the offset came from.
- `supabase-worktree ports` prints the pool **plus** any pinned offsets outside it — the complete set of redirect URIs that can ever be in use. Paste it into Google / GitHub once.

Parsing is deliberately minimal (bash, not a TOML library): `offsets` must be an integer array (multi-line is fine), assignments one `name = offset` per line.

## Post-init hook

Drop an executable script at `$ROOT/.supabase-worktree.hook` and the CLI will run it at the end of every `init` / `up`, right after `.supabase-worktree/.env`, `$ROOT/.env.local`, and the rewritten `config.toml` are in place. Typical use: copy ancillary dotfiles from the main checkout into a fresh `git worktree` (the tool only touches `.env` / `.env.local`), seed local data, or kick off project bootstrap.

The hook receives the full resolved instance state via env vars — same shape as `status`:

| Env var                                | Example value                                       |
| -------------------------------------- | --------------------------------------------------- |
| `SUPABASE_WORKTREE_ROOT`               | `/Users/me/code/myproj`                             |
| `SUPABASE_WORKTREE_NAME`               | `feature-x`                                         |
| `SUPABASE_WORKTREE_PROJECT_ID`         | `myproj-feature-x`                                  |
| `SUPABASE_WORKTREE_BASE_PROJECT_ID`    | `myproj`                                            |
| `SUPABASE_WORKTREE_PORT_OFFSET`        | `1400`                                              |
| `SUPABASE_WORKTREE_DIR`                | `/Users/me/code/myproj/.supabase-worktree`          |
| `SUPABASE_WORKTREE_API_PORT`           | `55721`                                             |
| `SUPABASE_WORKTREE_DB_PORT`            | `55722`                                             |
| `SUPABASE_WORKTREE_STUDIO_PORT`        | `55723`                                             |
| `SUPABASE_WORKTREE_INBUCKET_PORT`      | `55724`                                             |
| `SUPABASE_WORKTREE_ANALYTICS_PORT`     | `55727`                                             |
| `SUPABASE_WORKTREE_POOLER_PORT`        | `55729`                                             |
| `SUPABASE_WORKTREE_SHADOW_PORT`        | `55730`                                             |
| `SUPABASE_WORKTREE_INSPECTOR_PORT`     | `9483`                                              |
| `SUPABASE_WORKTREE_NEXT_PORT`          | `3014`                                              |
| `SUPABASE_WORKTREE_SITE_URL`           | `http://localhost:3014`                             |
| `SUPABASE_WORKTREE_DB_URL`             | `postgresql://postgres:postgres@127.0.0.1:55722/postgres` |

Because it fires on every `init` / `up` (matching how `.env` is regenerated), keep hooks idempotent. Run it on demand with `supabase-worktree hook`.

Minimal example — copy an extra dotfile from a sibling main checkout into a fresh worktree:

```sh
#!/usr/bin/env bash
# $ROOT/.supabase-worktree.hook — chmod +x me, then commit.
set -euo pipefail
main_root="$(dirname "$SUPABASE_WORKTREE_ROOT")/myproj-main"
for f in .env.development.local; do
  if [[ -f "$main_root/$f" && ! -f "$SUPABASE_WORKTREE_ROOT/$f" ]]; then
    cp "$main_root/$f" "$SUPABASE_WORKTREE_ROOT/$f"
    echo "hook: copied $f from $main_root"
  fi
done
```

### Worked example — a git submodule's `.env`, port-adjusted

The tool regenerates the repo-root `.env` / `.env.local` with the worktree's
ports, but it doesn't reach into git submodules. A common setup: edge functions
(or any sub-service) live in a submodule with a **gitignored `.env`** whose
secrets exist only in the primary checkout, and whose Supabase URL must point at
*this* worktree's API port.

This hook resolves the primary checkout via `git rev-parse --git-common-dir`
(no hardcoded sibling path), populates the submodule, copies its `.env` from the
primary, and rewrites just the port-bearing URLs to `SUPABASE_WORKTREE_API_PORT`.
It's idempotent and a no-op in the primary checkout (which *is* the source):

```sh
#!/usr/bin/env bash
# $ROOT/.supabase-worktree.hook — chmod +x me, then commit.
set -euo pipefail

root="$SUPABASE_WORKTREE_ROOT"
submodule="supabase/functions"   # adjust to your submodule path

# The primary checkout holds the source-of-truth .env. git-common-dir points at
# <primary>/.git for every linked worktree; its parent is the primary checkout.
main="$(dirname "$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)")"
[[ "$root" == "$main" ]] && exit 0   # nothing to do in the primary itself

git -C "$root" submodule update --init "$submodule" >/dev/null 2>&1 || true

src="$main/$submodule/.env"
dst="$root/$submodule/.env"
[[ -f "$src" ]] || { echo "hook: no $src to copy — skipping" >&2; exit 0; }

api_url="http://127.0.0.1:${SUPABASE_WORKTREE_API_PORT}"
# Copy verbatim (keeps secrets), then repoint only the Supabase URLs.
sed -E \
  -e "s|^(SUPABASE_URL=).*|\1${api_url}|" \
  -e "s|^(FUNCTIONS_URL=).*|\1${api_url}|" \
  "$src" > "$dst"
echo "hook: wrote $submodule/.env (Supabase URL -> ${api_url})"
```

Shared, single-instance side-services (a queue, a mailer) are the mirror case:
because only one worktree's stack can own them at a time, repoint those with an
**explicit** command you run from the active worktree — not from the hook, which
fires on every `init` (even for a worktree you haven't started) and would
silently steal the service from a running stack.

## Enforcing usage from agent rules (CLAUDE.md / AGENTS.md)

If you work with Claude Code, Cursor, or any other agent that reads project rules, add a section like this so the agent doesn't `supabase start` against the shared root stack from inside a worktree:

```md
## Worktree-isolated Supabase

This project uses [`supabase-worktree`](https://github.com/yungbigos/supabase-worktree) so each git worktree has its own Supabase stack + Next.js port. Rules:

- **Never** run `supabase start`, `supabase db reset`, or `supabase db diff` from the repo root in a worktree. Always go through `supabase-worktree …`, or pass `--workdir .supabase-worktree` to the supabase CLI directly.
- Bring a worktree up with `supabase-worktree up` (idempotent; safe to re-run).
- `.env.local` and `.supabase-worktree/.env` are generated — don't commit them. Edit the repo `.env` for shared secrets, then re-run `supabase-worktree init` (or `up`) to refresh the snapshot.
- The Next.js dev server reads `SUPABASE_WORKTREE_NEXT_PORT` from `.env.local`. Use `bun run dev` (or whatever script honours it) — don't hard-code `-p 3000`.
- New worktrees created via `gtr new` auto-run `supabase-worktree init` via `.gtrconfig`. For worktrees made any other way, run it manually once.
```

## Limitations

- **Port rewrite assumes Supabase defaults.** If you've customized ports in `supabase/config.toml`, the literal `port = 54321` replacements won't match. A TOML-aware rewrite is planned for v0.2.
- **Port collisions are possible.** Two names can hash to the same slot; the chance grows with worktree count and shrinks the pool. Collisions only bite when both stacks run simultaneously — pin one of them in `.supabase-worktree.toml` `[assignments]` (or set `SUPABASE_WORKTREE_PORT_OFFSET`) to resolve. `status` shows your chosen ports and where the offset came from.
- **`config.toml` is copied, not symlinked.** Edits to the source `config.toml` (e.g. enabling a new auth provider) won't propagate to existing isolated stacks. Delete `.supabase-worktree/supabase/config.toml` and re-run `init` to regenerate.
- **`.supabase-worktree/.env` is a snapshot, not a symlink.** Re-run `init` (or just `up`, which always refreshes the env) after editing the repo `.env` so the values reach the supabase CLI. The trade-off vs. a symlink is that per-instance overrides (`SITE_URL`, `SUPABASE_URL`) can live in the same file.

## License

MIT — see [LICENSE](LICENSE).
