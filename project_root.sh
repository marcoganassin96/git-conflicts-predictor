#!/usr/bin/env bash
# project_root.sh - determines PROJECT_ROOT for the repository
# Usage: source this file and call compute_project_root <start_dir>

compute_project_root() {
  local start_dir="$1"
  # Resolve symlink for start_dir
  local SOURCE="$start_dir"
  while [ -L "$SOURCE" ]; do
    local DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
  done
  local dir="$(cd -P "$SOURCE" >/dev/null 2>&1 && pwd)"

  # 1) Try git top-level
  if git_root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)"; then
    PROJECT_ROOT="$git_root"
    export PROJECT_ROOT
    return 0
  fi

  # 2) Walk up searching for marker files
  while [ "$dir" != "/" ] && [ -n "$dir" ]; do
    if [ -e "$dir/.project-root" ] || [ -d "$dir/.git" ] || [ -e "$dir/README.md" ]; then
      PROJECT_ROOT="$dir"
      export PROJECT_ROOT
      return 0
    fi
    dir=$(dirname "$dir")
  done

  # 3) Fallback to start_dir
  PROJECT_ROOT="$start_dir"
  export PROJECT_ROOT
  return 0
}
