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
2. **Derives a port offset** = `sha1(name) % 50 * 100`, applied to all Supabase service ports (api, db, studio, inbucket, analytics, pooler, shadow, inspector).
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
| `version`                  | Print version                                         |
| `help`                     | Show usage                                            |

## Environment overrides

| Variable                          | Effect                                          |
| --------------------------------- | ----------------------------------------------- |
| `SUPABASE_WORKTREE_NAME`          | Override the instance name                      |
| `SUPABASE_WORKTREE_PROJECT_ID`    | Override the auto-detected base `project_id`    |
| `SUPABASE_WORKTREE_PORT_OFFSET`   | Pin the port offset (skips sha1 derivation)     |

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

For OAuth providers (Google, GitHub, …) the redirect-URI list in the provider console must include each derived port — either add them all up front, or only the ones you'll actually use.

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
- **Port collisions are possible.** The hash space is 50 slots; if you have 7+ worktrees the chance of a collision is non-trivial. `status` shows your chosen ports — set `SUPABASE_WORKTREE_PORT_OFFSET` if you hit one.
- **`config.toml` is copied, not symlinked.** Edits to the source `config.toml` (e.g. enabling a new auth provider) won't propagate to existing isolated stacks. Delete `.supabase-worktree/supabase/config.toml` and re-run `init` to regenerate.
- **`.supabase-worktree/.env` is a snapshot, not a symlink.** Re-run `init` (or just `up`, which always refreshes the env) after editing the repo `.env` so the values reach the supabase CLI. The trade-off vs. a symlink is that per-instance overrides (`SITE_URL`, `SUPABASE_URL`) can live in the same file.

## License

MIT — see [LICENSE](LICENSE).
