# supabase-worktree

Run an **isolated local Supabase stack** per project — or per `git worktree` — with deterministic ports, a unique `project_id`, and zero config duplication. Your `supabase/` directory is the source of truth; the tool just spins up a parallel stack alongside it.

Originally built to let multiple feature branches of the same project run their own Supabase locally without clobbering each other's databases.

## Install

```sh
brew install yannikw23/tap/supabase-worktree
```

Requires the Supabase CLI (`brew install supabase/tap/supabase`), Docker, and a `libpq` install (provides `psql` / `pg_restore`).

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
5. **Runs `supabase --workdir .supabase-worktree start`** so the CLI sees the isolated config.

Everything else (`db reset`, `migration new`, `db diff`, `gen types`, ...) you run via the regular `supabase --workdir .supabase-worktree …` invocation, or just `cd .supabase-worktree` and use `supabase` directly.

## Commands

| Command                    | What it does                                          |
| -------------------------- | ----------------------------------------------------- |
| `init`                     | Generate `.supabase-worktree/supabase/config.toml` + symlinks |
| `up [supabase args]`       | `supabase start` against the isolated config          |
| `down [supabase args]`     | `supabase stop` against the isolated config           |
| `status`                   | Print root, name, project_id, ports, db url, running state |
| `restore <dump-file>`      | `pg_restore` a dump into the isolated DB              |
| `psql [args...]`           | `psql` into the isolated DB                           |
| `version`                  | Print version                                         |
| `help`                     | Show usage                                            |

## Environment overrides

| Variable                          | Effect                                          |
| --------------------------------- | ----------------------------------------------- |
| `SUPABASE_WORKTREE_NAME`          | Override the instance name                      |
| `SUPABASE_WORKTREE_PROJECT_ID`    | Override the auto-detected base `project_id`    |
| `SUPABASE_WORKTREE_PORT_OFFSET`   | Pin the port offset (skips sha1 derivation)     |

## Limitations

- **Port rewrite assumes Supabase defaults.** If you've customized ports in `supabase/config.toml`, the literal `port = 54321` replacements won't match. A TOML-aware rewrite is planned for v0.2.
- **Port collisions are possible.** The hash space is 50 slots; if you have 7+ worktrees the chance of a collision is non-trivial. `status` shows your chosen ports — set `SUPABASE_WORKTREE_PORT_OFFSET` if you hit one.
- **`config.toml` is copied, not symlinked.** Edits to the source `config.toml` (e.g. enabling a new auth provider) won't propagate to existing isolated stacks. Delete `.supabase-worktree/supabase/config.toml` and re-run `init` to regenerate.

## License

MIT — see [LICENSE](LICENSE).
