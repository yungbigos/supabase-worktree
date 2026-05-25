_supabase_worktree() {
  local cur cmds
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  cmds="init up down status restore psql version help"
  if [[ $COMP_CWORD -eq 1 ]]; then
    COMPREPLY=( $(compgen -W "$cmds" -- "$cur") )
    return 0
  fi
  if [[ "${COMP_WORDS[1]}" == "restore" && $COMP_CWORD -eq 2 ]]; then
    COMPREPLY=( $(compgen -f -- "$cur") )
  fi
}
complete -F _supabase_worktree supabase-worktree
