#!/bin/bash
THIS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT_DIR="$(cd "$THIS_SCRIPT_DIR/.." && pwd)"

# Source shared helpers
. "$PROJECT_ROOT_DIR/lib/logging.sh"
. "$PROJECT_ROOT_DIR/lib/common.sh"

# --- Function Definitions ---

check_dependencies() {
  local missing_deps=0
  if ! command -v jq &> /dev/null; then
    log_error "Dependency 'jq' not found. 'jq' is required for JSON processing."
    missing_deps=1
  fi
  if ! command -v curl &> /dev/null; then
    log_error "Dependency 'curl' not found. 'curl' is required to call GitLab API."
    missing_deps=1
  fi
  if [ $missing_deps -eq 1 ]; then
    log_error "Please install the missing dependencies before proceeding."
    exit 1
  fi
}

# _glab_cli_method: Use GitLab CLI (glab) to find MRs modifying specified files
_glab_cli_method() {
    log_debug "Invoked gitlab 'glab' method with parameters:" >&2
    log_debug "  files: ${FILE_PATHS[*]}" >&2
    log_debug "  remote_url: $REMOTE_URL" >&2
    log_debug "  limit: $LIMIT" >&2

  local -n RESULTS=$1

  log_info "Searching GitLab for MRs modifying ${#FILE_PATHS[@]} file(s) via glab..."

  if ! command -v glab &> /dev/null; then
    log_error "'glab' CLI not found. Please install GitLab CLI."
    log_info "Install with: brew install glab (macOS) or winget install glab.glab (Windows)"
    exit 1
  fi

  REPO_SLUG=$(common_get_repo_slug "$REMOTE_URL")
  if [ -z "$REPO_SLUG" ]; then
    log_error "Could not determine repository slug from REMOTE_URL='$REMOTE_URL'."
    exit 1
  fi

  # Fetching open MRs using the GitLab API via glab
  # we use :id to represent the URL-encoded path of the repo
  OPEN_MRS_RESPONSE=$(
    glab api "projects/:id/merge_requests?state=opened" -R "$REPO_SLUG" | jq .
  )

  if [ $? -ne 0 ]; then
    log_error "'glab api' failed. Make sure you are logged in (glab auth login)."
    exit 1
  fi

  MR_COUNT=$(echo "$OPEN_MRS_RESPONSE" | jq 'length')
  log_debug "Analyzing $MR_COUNT open MR(s) in the repository..."

  counter=1
  while IFS= read -r MR_OBJECT; do
    MR_NUMBER=$(echo "$MR_OBJECT" | jq -r '.iid')
    MR_BRANCH=$(echo "$MR_OBJECT" | jq -r '.source_branch')
    MR_TITLE=$(echo "$MR_OBJECT" | jq -r '.title')
    MR_URL=$(echo "$MR_OBJECT" | jq -r '.web_url')

    log_progress "Processing MR $counter of $MR_COUNT: #${MR_NUMBER} (${MR_BRANCH})..."
    counter=$((counter + 1))

    # Get changes for this MR
    CHANGED_FILES_RESPONSE=$(glab api "projects/:id/merge_requests/$MR_NUMBER/changes" -R "$REPO_SLUG" | jq -r '.changes[] | .new_path // .old_path')

    mapfile -t CHANGED_FILES_NAMES < <(echo "$CHANGED_FILES_RESPONSE" | sed -E 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Check if any of the requested FILE_PATHS are present in the MR's changed files
    for TARGET_FILE in "${FILE_PATHS[@]}"; do
      for CHANGED_FILE in "${CHANGED_FILES_NAMES[@]}"; do
        if [ "$CHANGED_FILE" = "$TARGET_FILE" ]; then
          if [[ ! -v RESULTS["$TARGET_FILE"] ]]; then
              RESULTS["$TARGET_FILE"]="${MR_BRANCH},${MR_NUMBER},${MR_TITLE},${MR_URL}"
          else
              RESULTS["$TARGET_FILE"]+=";${MR_BRANCH},${MR_NUMBER},${MR_TITLE},${MR_URL}"
          fi
        fi
      done
    done
  done < <(echo "$OPEN_MRS_RESPONSE" | jq -c '.[]')

  log_progress_done
  common_print_results RESULTS
  return 0
}

# _curl_api_method: Use GitLab REST API via curl to find MRs modifying specified files
_curl_api_method() {
    log_debug "Invoked gitlab 'api' method with parameters:" >&2
    log_debug "  files: ${FILE_PATHS[*]}" >&2
    log_debug "  remote_url: $REMOTE_URL" >&2
    log_debug "  limit: $LIMIT" >&2

  local -n RESULTS=$1

  log_info "Searching GitLab for MRs modifying ${#FILE_PATHS[@]} file(s) via curl..."

  if [ -z "${GITLAB_TOKEN:-}" ]; then
    log_error "GITLAB_TOKEN environment variable is required for GitLab API access."
    log_info "Set it with: export GITLAB_TOKEN='your_token_here'"
    exit 1
  fi

  REPO_SLUG=$(common_get_repo_slug "$REMOTE_URL")
  if [ -z "$REPO_SLUG" ]; then
    log_error "Could not determine repository slug from REMOTE_URL='$REMOTE_URL'."
    exit 1
  fi

  # GitLab pagination: use per_page (max 100) and page parameter
  per_page_max=50
  remaining=$LIMIT
  page_offset=1
  all_mrs_json='[]'

  while [ "$remaining" -gt 0 ]; do
    page_size=$(( remaining < per_page_max ? remaining : per_page_max ))

    # URL encode the repo slug (replace / with %2F)
    ENCODED_REPO_SLUG=$(echo "$REPO_SLUG" | sed 's|/|%2F|g')
    
    RESP=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
      -w "\nHTTP_STATUS:%{http_code}\n" \
      "https://gitlab.com/api/v4/projects/$ENCODED_REPO_SLUG/merge_requests?state=opened&scope=all&per_page=${page_size}&page=${page_offset}"
    )

    HTTP_STATUS=$(grep '^HTTP_STATUS:' <<< "$RESP" | cut -d':' -f2)
    BODY=$(sed '$d' <<< "$RESP")

    if [ "$HTTP_STATUS" -ne 200 ]; then
      log_error "GitLab API returned HTTP status $HTTP_STATUS while fetching open MRs (page ${page_offset})."
      log_debug "Response (truncated): $(echo "$BODY" | head -c 1000)"
      exit 1
    fi

    page_count=$(echo "$BODY" | jq 'length' 2>/dev/null | tr -d '\r' || echo 0)
    if [ "$page_count" -eq 0 ]; then
      break
    fi

    # Concatenate arrays
    all_mrs_json=$(echo "$all_mrs_json" "$BODY" | jq -s 'add')

    if [ "$page_count" -lt "$page_size" ]; then
      break
    fi

    total_fetched=$(echo "$all_mrs_json" | jq 'length' | tr -d '\r')
    if [ "$total_fetched" -ge "$LIMIT" ]; then
      all_mrs_json=$(echo "$all_mrs_json" | jq ".[:$LIMIT]")
      break
    fi

    remaining=$(( LIMIT - total_fetched ))
    page_offset=$(( page_offset + 1 ))
  done

  OPEN_MRS_JSON=$(echo "$all_mrs_json" | jq -c '[.[] | {iid: .iid, source_branch: .source_branch, title: .title, web_url: .web_url}]')

  if [ -z "$OPEN_MRS_JSON" ] || [ "$OPEN_MRS_JSON" = "[]" ]; then
    log_info "No open MRs found."
  fi

  MR_COUNT=$(echo "$OPEN_MRS_JSON" | jq 'length' | tr -d '\r')
  MR_COUNT=$(( MR_COUNT < LIMIT ? MR_COUNT : LIMIT ))
  log_debug "Analyzing $MR_COUNT open MR(s) in the repository..."

  counter=1
  while IFS= read -r MR_OBJECT; do
    MR_NUMBER=$(echo "$MR_OBJECT" | jq -r '.iid' | sed -E 's/^[[:space:]]*//;s/[[:space:]]*$//')
    MR_BRANCH=$(echo "$MR_OBJECT" | jq -r '.source_branch' | sed -E 's/^[[:space:]]*//;s/[[:space:]]*$//')
    MR_TITLE=$(echo "$MR_OBJECT" | jq -r '.title' | sed -E 's/^[[:space:]]*//;s/[[:space:]]*$//')
    MR_URL=$(echo "$MR_OBJECT" | jq -r '.web_url' | sed -E 's/^[[:space:]]*//;s/[[:space:]]*$//')

    log_progress "Processing MR $counter of $MR_COUNT: #${MR_NUMBER} (${MR_BRANCH})..."
    counter=$((counter + 1))

    # Get changes for this MR (URL encode the repo slug)
    ENCODED_REPO_SLUG_CHANGES=$(echo "$REPO_SLUG" | sed 's|/|%2F|g')
    CHANGED_FILES_RESPONSE=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
      "https://gitlab.com/api/v4/projects/$ENCODED_REPO_SLUG_CHANGES/merge_requests/$MR_NUMBER/changes" | \
      jq -r '.changes[].new_path // .changes[].old_path'
    )

    mapfile -t CHANGED_FILES_NAMES < <(echo "$CHANGED_FILES_RESPONSE" | sed -E 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Check if any of the requested FILE_PATHS are present in the MR's changed files
    for TARGET_FILE in "${FILE_PATHS[@]}"; do
      for CHANGED_FILE in "${CHANGED_FILES_NAMES[@]}"; do
        if [ "$CHANGED_FILE" = "$TARGET_FILE" ]; then
          if [[ ! -v RESULTS["$TARGET_FILE"] ]]; then
              RESULTS["$TARGET_FILE"]="${MR_BRANCH},${MR_NUMBER},${MR_TITLE},${MR_URL}"
          else
              RESULTS["$TARGET_FILE"]+=";${MR_BRANCH},${MR_NUMBER},${MR_TITLE},${MR_URL}"
          fi
        fi
      done
    done
  done < <(echo "$OPEN_MRS_JSON" | jq -c '.[]')

  log_progress_done
  common_print_results RESULTS
  return 0
}

# get_gitlab_mrs: wrapper selecting method (glab or curl)
get_gitlab_mrs() {
  local -n method_result=$1

  # If a method is explicitly specified, use it
  if [ -n "$METHOD" ]; then
    if [ "$METHOD" = "glab" ]; then
      echo "✅ Using the specified 'glab' CLI method." >&2
      _glab_cli_method method_result
    elif [ "$METHOD" = "api" ]; then
      echo "✅ Using the specified 'curl' API method." >&2
      _curl_api_method method_result
    fi
    return 0
  fi

  # Otherwise, auto-detect the best available method
  if command -v glab &> /dev/null; then
    echo "✅ 'glab' CLI found. Using the efficient 'glab api' method." >&2
    _glab_cli_method method_result
  elif command -v curl &> /dev/null; then
    echo "⚠️ 'glab' CLI not found. Falling back to the 'curl' API method." >&2
    _curl_api_method method_result
  else
    echo "❌ Error: Neither 'glab' CLI nor 'curl' is installed. Cannot proceed." >&2
    exit 1
  fi
  return 0
}

# Main function following the same pattern as other providers
relevate_conflicts(){
  local -n gitlab_results=$1
  shift
  check_dependencies
  get_gitlab_mrs gitlab_results "$@"
  return 0
}

# --- Main Execution Block ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  declare -A MAIN_RESULTS

  # common_parse_args will set FILE_PATHS, REMOTE_URL, METHOD, LIMIT
  common_parse_args "$@"

  # if common_parse_args returned exit code 2, it means no files found to analyze (early exit)
  local parse_args_exit_code=$?
  if [ $parse_args_exit_code -eq 2 ]; then
    return 0
  elif [ $parse_args_exit_code -ne 0 ]; then
    log_error "Error parsing arguments in common_parse_args."
    return 1
  fi

  relevate_conflicts MAIN_RESULTS "$@"
fi
