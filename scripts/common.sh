#!/usr/bin/env bash
# common.sh - shared utilities for git-conflicts-predictor scripts
# Requires: bash 4+ (associative arrays), jq

# Assume the remote URL is passed via a flag for clarity, e.g., --url
usage() {
  echo "Usage: $0 --file <path/to/file1> [--file <path/to/file2> ...] [--url <remote_url>] [--method <gh|api>] [--limit <number>]" >&2
  echo "       Or: $0 --file <path/to/file1,path/to/file2,...> [--url <remote_url>] [--method <gh|api>] [--limit <number>]" >&2
  echo "" >&2
  echo "Options:" >&2
  echo "  --file     Path to file(s) to analyze (required)" >&2
  echo "  --url      Remote repository URL (optional)" >&2
  echo "  --method   Method to use: 'gh' (GitHub CLI) or 'api' (REST API) (optional)" >&2
  echo "  --limit    Maximum number of PRs to analyze (default: $PR_FETCH_LIMIT)" >&2
  exit 1
}

##
# @Function: common_parse_args
# @Description: Parse, clean, validate and set defaults for common script arguments
#
# @Params: All script arguments ($@)
#   Example:
#
# @Output: 
#   FILE_PATHS (array) - List of file paths to analyze
#   REMOTE_URL (string) - Remote repository URL
#   METHOD (string) - Method to use: 'gh' or 'api'
#   LIMIT (integer) - Maximum number of PRs to analyze
#
# @Returns (Integer): Exit code.
#   0 if the extraction is successful.
#   1 on error.
##
common_parse_args() {
  PR_FETCH_LIMIT_DEFAULT=200
  FILE_PATHS=()
  REMOTE_URL=""
  METHOD=""
  LIMIT="$PR_FETCH_LIMIT_DEFAULT"

  # --- Parsing Arguments ---

  while [[ $# -gt 0 ]]; do
      case "$1" in
          --help|-h)
              usage
              ;;
          --file)
              # Ensure the value exists for --file
              if [[ -z "$2" || "$2" == --* ]]; then
                  echo "Error: Argument expected for $1." >&2
                  usage
              fi
              
              # Split comma-separated values and add to the FILES array
              IFS=',' read -r -a NEW_FILES <<< "$2"
              FILE_PATHS+=( "${NEW_FILES[@]}" )
              
              shift 2 # Consume the flag and its value
              ;;
          --url|--remote-url)
              # Ensure the value exists for the URL
              if [[ -z "$2" || "$2" == --* ]]; then
                  echo "Error: Argument expected for $1." >&2
                  usage
              fi
              
              REMOTE_URL="$2"
              shift 2 # Consume the flag and its value
              ;;
        
          --method)
              # Ensure the value exists for --method
              if [[ -z "$2" || "$2" == --* ]]; then
                  echo "Error: Argument expected for $1." >&2
                  usage
              fi
              METHOD="$2"

              # Allowed methods are 'gh' and 'api'
              declare -a ALLOWED_METHODS=("gh" "api")

              if [[ ! " ${ALLOWED_METHODS[*]} " =~ " ${METHOD} " ]]; then
                  last_idx=$((${#ALLOWED_METHODS[@]} - 1))
                  printf -v csv "'%s', " "${ALLOWED_METHODS[@]:0:$last_idx}"
                  formatted_methods="${csv%, } and '${ALLOWED_METHODS[$last_idx]}'"
                  echo "Error: Invalid method '$METHOD'. Allowed methods are $formatted_methods" >&2
                  exit 1
              fi

              shift 2 # Consume the flag and its value
              ;;

          --limit)
              # Ensure the value exists for --limit
              if [[ -z "$2" || "$2" == --* ]]; then
                  echo "Error: Argument expected for $1." >&2
                  usage
              fi
              
              # Validate that the limit is a positive integer
              if ! [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
                  echo "Error: --limit must be a positive integer, got '$2'" >&2
                  exit 1
              fi
              
              LIMIT="$2"
              shift 2 # Consume the flag and its value
              ;;
          *)
              # Handle any unknown positional arguments or flags
              echo "Error: Unknown argument '$1'" >&2
              usage
              ;;
      esac
  done

  # --- Validation and Defaults ---

  # 1. Validate if --file was provided
  if [ ${#FILE_PATHS[@]} -eq 0 ]; then
      echo "Error: The --file parameter is required." >&2
      usage
  fi

  # 2. Set default for REMOTE_URL if not provided via flag
  if [ -z "$REMOTE_URL" ]; then
      # Use the original git command as the default
      REMOTE_URL=$(git remote -v | head -n 1 | awk '{print $2}')
      
      # Optional: Add error handling if git fails
      if [ $? -ne 0 ] || [ -z "$REMOTE_URL" ]; then
          echo "Warning: Could not determine REMOTE_URL using 'git remote -v'. Execution will be interrupted." >&2
          exit 1
      fi
  fi
  return 0
}

##
# @Function: common_get_repo_slug
# @Description: Extracts the full repository name ('owner/repo') from a Git remote URL.
#
# @Param 1 (String) REMOTE_URL: The remote URL of the Git repository.
#   Example: https://github.com/owner/repo.git or git@github.com:owner/repo.git
#
# @Output (String): Prints the 'owner/repo' string to standard output (stdout).
#
# @Returns (Integer): Exit code. 0 if the extraction is successful.
##
common_get_repo_slug() {
  # Extract the repository path by removing the protocol/host prefix and any trailing .git
  # Examples handled:
  # - git@github.com:owner/repo.git -> owner/repo
  # - https://github.com/owner/repo.git -> owner/repo
  # - https://gitlab.com/group/subgroup/repo.git -> subgroup/repo (last two path components)
  local url="$1"
  local path
  path=$(printf "%s" "$url" | sed -E 's#^(git@[^:]+:|https?://[^/]+/)##; s#\.git$##')

  # If nothing left after trimming, return empty
  if [ -z "$path" ]; then
    echo "" >&2
    echo "" 
    return 0
  fi

  # If the remaining path does not contain a slash, it's not a valid owner/repo form
  if [[ "$path" != */* ]]; then
    echo "" >&2
    echo "" 
    return 0
  fi

  # Split into components and return the last two (owner/repo)
  IFS='/' read -r -a parts <<< "$path"
  local n=${#parts[@]}
  if [ "$n" -ge 2 ]; then
    REPO_SLUG="${parts[$((n-2))]}/${parts[$((n-1))]}"
  else
    REPO_SLUG="$path"
  fi

  echo "Debug: Parsed repository slug from REMOTE_URL: $REPO_SLUG" >&2
  echo "$REPO_SLUG"
  return 0
}
