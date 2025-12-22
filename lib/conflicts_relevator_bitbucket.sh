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
    log_error "Dependency 'curl' not found. 'curl' is required to call Bitbucket API."
    missing_deps=1
  fi
  if [ $missing_deps -eq 1 ]; then
    log_error "Please install the missing dependencies before proceeding."
    exit 1
  fi
}

# _curl_api_method: Use Bitbucket API via curl to find PRs modifying specified files.
# Params: RESULTS associative array (name), uses FILE_PATHS, REMOTE_URL, LIMIT
_curl_api_method() {
  local -n RESULTS=$1

  log_info "Searching Bitbucket for PRs modifying ${#FILE_PATHS[@]} file(s) via curl..."

  if [ -z "${BITBUCKET_TOKEN:-}" ]; then
    log_error "BITBUCKET_TOKEN environment variable is required for Bitbucket API access."
    log_info "Set it with: export BITBUCKET_TOKEN='your_token_here'"
    exit 1
  fi

  REPO_SLUG=$(common_get_repo_slug "$REMOTE_URL")
  if [ -z "$REPO_SLUG" ]; then
    log_error "Could not determine repository slug from REMOTE_URL='$REMOTE_URL'."
    exit 1
  fi

  # Bitbucket pagination: use pagelen (max 100) and page parameter
  per_page_max=50
  remaining=$LIMIT
  page_offset=1
  all_prs_json='[]'

  while [ "$remaining" -gt 0 ]; do
    page_size=$(( remaining < per_page_max ? remaining : per_page_max ))

    RESP=$(curl -s -H "Authorization: Bearer $BITBUCKET_TOKEN" \
      -w "\nHTTP_STATUS:%{http_code}\n" \
      "https://api.bitbucket.org/2.0/repositories/${REPO_SLUG}/pullrequests?state=OPEN&pagelen=${page_size}&page=${page_offset}"
    )

    HTTP_STATUS=$(grep '^HTTP_STATUS:' <<< "$RESP" | cut -d':' -f2)
    BODY=$(sed '$d' <<< "$RESP")

    if [ "$HTTP_STATUS" -ne 200 ]; then
      log_error "Bitbucket API returned HTTP status $HTTP_STATUS while fetching open PRs (page ${page_offset})."
      log_debug "Response (truncated): $(echo "$BODY" | head -c 1000)"
      exit 1
    fi

    # Remove possible carriage return since jq may introduce them
    page_count=$(echo "$BODY" | jq '.values | length' 2>/dev/null | tr -d '\r' || echo 0)
    if [ "$page_count" -eq 0 ]; then
      break
    fi

    # Extract 'values' array and append
    vals=$(echo "$BODY" | jq '.values')
    all_prs_json=$(echo "$all_prs_json" "$vals" | jq -s 'add')

    if [ "$page_count" -lt "$page_size" ]; then
      break
    fi

    total_fetched=$(echo "$all_prs_json" | jq 'length' | tr -d '\r')
    if [ "$total_fetched" -ge "$LIMIT" ]; then
      all_prs_json=$(echo "$all_prs_json" | jq ".[:$LIMIT]")
      break
    fi

    remaining=$(( LIMIT - total_fetched ))
    page_offset=$(( page_offset + 1 ))
  done

  OPEN_PRS_JSON=$(echo "$all_prs_json" | jq -c '[.[] | {id: .id, branch: .source.branch.name}]')

  if [ -z "$OPEN_PRS_JSON" ] || [ "$OPEN_PRS_JSON" = "[]" ]; then
    log_info "No open PRs found."
  fi

  PR_COUNT=$(echo "$OPEN_PRS_JSON" | jq 'length' | tr -d '\r')
  PR_COUNT=$(( PR_COUNT < LIMIT ? PR_COUNT : LIMIT ))
  log_debug "Analyzing $PR_COUNT open PR(s) in the repository..."

  # Clean target files from leading/trailing whitespace
  mapfile -t CLEANED_TARGET_FILES < <(printf '%s\n' "${FILE_PATHS[@]}" | sed -E 's/^\s+|\s+$//g')


  counter=1
  while IFS= read -r PR_OBJECT; do
    PR_NUMBER=$(echo "$PR_OBJECT" | jq -r '.id' | tr -d '[:space:]')
    PR_BRANCH=$(echo "$PR_OBJECT" | jq -r '.branch' | tr -d '[:space:]')

    log_progress "Processing PR $counter of $PR_COUNT: #${PR_NUMBER} (${PR_BRANCH})..."
    counter=$((counter + 1))

    # Fetch diffstat for the PR to get changed files - the diffstat endpoint is currently returning 302 redirects, so we follow them with -L (curl option for redirects)
    DIFF_RESP=$(curl -s -L -H "Authorization: Bearer $BITBUCKET_TOKEN" \
      -w "\nHTTP_STATUS:%{http_code}\n" \
      "https://api.bitbucket.org/2.0/repositories/${REPO_SLUG}/pullrequests/${PR_NUMBER}/diffstat?pagelen=100"
    )
    HTTP_STATUS_FILES=$(grep '^HTTP_STATUS:' <<< "$DIFF_RESP" | cut -d':' -f2)
    DIFF_BODY=$(sed '$d' <<< "$DIFF_RESP")

    if [ "$HTTP_STATUS_FILES" -ne 200 ]; then
      log_error "Bitbucket API returned HTTP status $HTTP_STATUS_FILES while fetching files for PR #${PR_NUMBER}."
      log_debug "Response (truncated): $(echo "$DIFF_BODY" | head -c 1000)"
      exit 1
    fi

    mapfile -t CHANGED_FILES_NAMES < <(echo "$DIFF_BODY" | jq -r '.values[] | (.new.path // .old.path)' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    for TARGET_FILE in "${CLEANED_TARGET_FILES[@]}"; do
      for CHANGED_FILE in "${CHANGED_FILES_NAMES[@]}"; do
        if [ "$CHANGED_FILE" = "$TARGET_FILE" ]; then
          if [[ ! -v RESULTS["$TARGET_FILE"] ]]; then
            RESULTS["$TARGET_FILE"]="${PR_BRANCH},${PR_NUMBER}"
          else
            RESULTS["$TARGET_FILE"]+=";${PR_BRANCH},${PR_NUMBER}"
          fi
        fi
      done
    done

  done < <(echo "$OPEN_PRS_JSON" | jq -c '.[]')

  log_progress_done
  common_print_results RESULTS
  return 0
}

# get_bitbucket_pr_branches: wrapper selecting method (only curl supported)
get_bitbucket_pr_branches() {
  local -n method_result=$1
  # For Bitbucket we currently support only the API via curl
  _curl_api_method method_result
  return 0
}

relevate_conflicts(){
  local -n bb_results=$1
  shift
  common_parse_args "$@"
  check_dependencies
  get_bitbucket_pr_branches bb_results "$@"
  return 0
}

# --- Main Execution Block ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  declare -A MAIN_RESULTS
  relevate_conflicts MAIN_RESULTS "$@"
fi
