# Changelog

## v0.2.0 — 2026-05-29

- `init` now writes `.supabase-worktree/.env` — a snapshot of the repo `.env` plus per-instance overrides (`SUPABASE_URL`, `SITE_URL`, `SUPABASE_WORKTREE_NEXT_PORT`, `SUPABASE_WORKTREE_PORT_OFFSET`, `SUPABASE_WORKTREE_NAME`). The Supabase CLI reads this for `env()` interpolation in `config.toml`, so OAuth credentials and per-worktree `site_url` resolve correctly.
- `init` now generates `$ROOT/.env.local` (only if it doesn't already exist) so Bun / Next / one-off scripts auto-target the worktree stack without per-command flags.
- New derived value: `WT_NEXT_PORT = 3000 + offset/100` (range `3000..3049`). Wire it into your project's `dev` script (e.g. `next dev -p ${SUPABASE_WORKTREE_NEXT_PORT:-3000}`) so parallel worktrees can each run their own dev server.
- `up` re-writes `.supabase-worktree/.env` every invocation, so edits to the repo `.env` propagate without an explicit re-init.
- `status` and `help` now also print the derived Next port and site URL.

## v0.1.0 — 2026-05-25

Initial public release.

- Isolated Supabase stack per project / git worktree.
- Deterministic port offset from sha1(name) % 50 * 100.
- Auto-detects base `project_id` from `supabase/config.toml`.
- Instance name precedence: `$SUPABASE_WORKTREE_NAME` → git branch → deterministic keyword.
- Subcommands: `init`, `up`, `down`, `status`, `restore`, `psql`, `version`, `help`.
- Env overrides: `SUPABASE_WORKTREE_NAME`, `SUPABASE_WORKTREE_PROJECT_ID`, `SUPABASE_WORKTREE_PORT_OFFSET`.
