# Changelog

## v0.3.0 — 2026-06-10

- `restore` is now a real two-pass restore instead of a single `pg_restore` call. Pass 1 restores DDL + data for app schemas while excluding `auth`, `storage`, `realtime`, `_analytics`, `_supabase`, and `supabase_functions` — those keep the local-version DDL so local GoTrue / Storage binaries stay compatible with a prod dump. Pass 2 then loads `auth` and `storage` data-only into the local-version tables. After both passes, ownership of `public.*` / `cron.*` / `supabase_migrations.*` objects is reassigned back to the `postgres` role so `supabase migration up` can ALTER them. The old single-pass behavior silently broke local sign-in.
- `restore` now prompts for confirmation (use `--yes` / `-y` to skip), validates that the dump is a valid custom-format `pg_dump`, and validates that the worktree DB is reachable as `supabase_admin` before touching anything.
- `restore` connects as `supabase_admin` (not `postgres`) since the pass-2 writes into `auth` / `storage` require it. The reassignment block at the end flips ownership back to `postgres` so subsequent `supabase migration up` works.

## v0.2.3 — 2026-06-02

- Emit `PORT=${WT_NEXT_PORT}` in `.env.local` and `$WT_ENV`. Bun loads `.env.local` into `process.env` and child processes inherit it, so the spawned dev server picks up the worktree port automatically. Previously, package.json scripts using `${SUPABASE_WORKTREE_NEXT_PORT:-3000}` always fell back to 3000 because bun does **not** expose `.env`-loaded vars to script subshells (the variable is in `process.env` but not in the shell scope that expands `${VAR}`). Drop the `-p` flag from your `dev`/`start` scripts and let Next read `PORT` directly.

## v0.2.2 — 2026-06-02

- `$ROOT/.env.local` is now a merged file — a snapshot of `$ROOT/.env` with the supabase-worktree-managed keys stripped, followed by the per-instance overrides. Previously it contained only the overrides, so Next / Bun / scripts that auto-load `.env.local` lost access to the repo `.env` (Langdock keys, OAuth secrets, etc.) when running against a worktree.
- `.env.local` is regenerated on every `init` / `up` (the previous "don't clobber" guard is gone) so repo `.env` edits propagate. If you had local edits in `.env.local`, move them to `$ROOT/.env`.
- `cmd_up` now refreshes both `$WT_ENV` and `$ROOT/.env.local`.
- The override key list is factored into one `OVERRIDE_KEYS` array so the two emitters and the snapshot filter can't drift apart.
- Added `NEXT_PUBLIC_APP_URL` to the override set so OAuth callbacks built from this env var land on the worktree port. For this to actually route through Supabase auth, the project's `supabase/config.toml` should set `site_url = "env(SITE_URL)"`. (Remember to register the worktree port in your OAuth provider consoles — Google, Webex, etc. — otherwise providers will reject the new redirect URI.)
- `SITE_URL` (and the new `NEXT_PUBLIC_APP_URL`) now use `localhost` instead of `127.0.0.1` to match what OAuth providers typically have registered. `SUPABASE_URL` still uses `127.0.0.1` since that's how the app talks to the API container.
- Same symlink-loop guard from v0.2.1 now also applied to `.env.local`.

## v0.2.1 — 2026-06-02

- Fix: `write_wt_env` no longer destroys `$ROOT/.env` when `.supabase-worktree/.env` is (or has become) a symlink back to it. Previously, `{ cat $ROOT/.env; ... } > $WT_ENV` could self-concatenate the source file under racy conditions, producing multi-GB env files. The function now (1) detects the dangerous symlink and removes it before writing, and (2) writes via a temp file + atomic `mv`, so the read source and the write target are always distinct inodes.

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
