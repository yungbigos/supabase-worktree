# Changelog

## v0.1.0 — 2026-05-25

Initial public release.

- Isolated Supabase stack per project / git worktree.
- Deterministic port offset from sha1(name) % 50 * 100.
- Auto-detects base `project_id` from `supabase/config.toml`.
- Instance name precedence: `$SUPABASE_WORKTREE_NAME` → git branch → deterministic keyword.
- Subcommands: `init`, `up`, `down`, `status`, `restore`, `psql`, `version`, `help`.
- Env overrides: `SUPABASE_WORKTREE_NAME`, `SUPABASE_WORKTREE_PROJECT_ID`, `SUPABASE_WORKTREE_PORT_OFFSET`.
