#!/usr/bin/env bash
set -euo pipefail

THIS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT_DIR="$(cd "$THIS_SCRIPT_DIR/../.." && pwd)"
TEST_DIR="$PROJECT_ROOT_DIR/tests"

# Source shared helpers
. "$TEST_DIR/utils.sh"
. "$PROJECT_ROOT_DIR/bin/git-overlap.sh"
. "$PROJECT_ROOT_DIR/lib/logging.sh"

# Macro
GITHUB_TEST_REPO_URL="https://github.com/marcoganassin96/git-conflicts-predictor-tester-github.git"
BITBUCKET_TEST_REPO_URL="https://bitbucket.org/MarcoGanassin/git-conflicts-predictor-tester-bitbucket"

FILES_TO_TEST="README.md,sparkling_water/ai_engine/ai.py"
declare -A EXPECTED_RESULTS=(
  ["sparkling_water/ai_engine/ai.py"]="feat/improve_sparkling_water_with_ai,2"
  ["README.md"]="feat/improve_sparkling_water_with_ai,2;feat/nanowarofsteel/zen_of_python,1"
)

# --- Helper Function ---
# Arguments: $1=Repo URL, $2=Mode Flag (optional), $3=Test Function Name (for logging)
_current_repo_files_test_logic() {
  local url="$1"
  local mode="$2"
  local test_name="$3"

  # 1. Check if we are inside a git repository
  if ! git rev-parse --is-inside-work-tree &> /dev/null; then
    log_warn "Skipping $test_name: Not inside a git repository."
    return 0
  fi

  # 2. Initialize associative array
  declare -A relevate_conflicts_result=()

  # 3. Run method (Shift allows us to handle the optional mode flag correctly)
  if [[ -n "$mode" ]]; then
    manage_conflicts_relevation relevate_conflicts_result "$mode" --url "$url"
  else
    manage_conflicts_relevation relevate_conflicts_result --url "$url"
  fi

  # 4. Assert exit code
  local display_mode="${mode:--no-file}"
  assertEquals "Expected exit code 0 for $test_name ($display_mode mode)" 0 $?
}

# Define individual test functions (must start with 'test')

# ==============================================================================
# GITHUB TESTS
# ==============================================================================

# -- Files from current repo ----------------------------------------------------------------------

test_relevate_conflicts_github_local() {
    _current_repo_files_test_logic "$GITHUB_TEST_REPO_URL" "--local" "$FUNCNAME"
}

test_relevate_conflicts_github_branch() {
    _current_repo_files_test_logic "$GITHUB_TEST_REPO_URL" "--branch" "$FUNCNAME"
}

test_relevate_conflicts_github_no_file() {
    _current_repo_files_test_logic "$GITHUB_TEST_REPO_URL" "" "$FUNCNAME"
}

# -- Custom files ----------------------------------------------------------------------

test_relevate_conflicts_github_api() {
  declare -A relevate_conflicts_result
  manage_conflicts_relevation relevate_conflicts_result --file "$FILES_TO_TEST" --url "$GITHUB_TEST_REPO_URL" --method api --limit 5
  assertArrayEquals EXPECTED_RESULTS relevate_conflicts_result "API method results mismatch"
}

test_relevate_conflicts_github_gh() {
  declare -A relevate_conflicts_result
  manage_conflicts_relevation relevate_conflicts_result --file "$FILES_TO_TEST" --url "$GITHUB_TEST_REPO_URL" --method gh --limit 5
  assertArrayEquals EXPECTED_RESULTS relevate_conflicts_result "GH method results mismatch"
}

test_relevate_conflicts_github_auto() {
  declare -A relevate_conflicts_result
  manage_conflicts_relevation relevate_conflicts_result --file "$FILES_TO_TEST" --url "$GITHUB_TEST_REPO_URL" --limit 5
  assertArrayEquals EXPECTED_RESULTS relevate_conflicts_result "Auto method results mismatch"
}


# ==============================================================================
# BITBUCKET TESTS
# ==============================================================================

# -- Files from current repo ----------------------------------------------------------------------

test_relevate_conflicts_bitbucket_local() {
    _current_repo_files_test_logic "$BITBUCKET_TEST_REPO_URL" "--local" "$FUNCNAME"
}

test_relevate_conflicts_bitbucket_branch() {
    _current_repo_files_test_logic "$BITBUCKET_TEST_REPO_URL" "--branch" "$FUNCNAME"
}

test_relevate_conflicts_bitbucket_no_file() {
    _current_repo_files_test_logic "$BITBUCKET_TEST_REPO_URL" "" "$FUNCNAME"
}

# -- Custom files ----------------------------------------------------------------------

test_relevate_conflicts_bitbucket_auto() {
  declare -A relevate_conflicts_result
  manage_conflicts_relevation relevate_conflicts_result --file "$FILES_TO_TEST" --url "$BITBUCKET_TEST_REPO_URL" --limit 5
  assertArrayEquals EXPECTED_RESULTS relevate_conflicts_result "Bitbucket Auto method results mismatch"
}

# ------------------------------------------------------------------------------

# Load shunit2 (This executes the tests)
if [ -f "$TEST_DIR/shunit2" ]; then
  . "$TEST_DIR/shunit2"
else
  echo "Error: shunit2 executable not found in $TEST_DIR."
  exit 1
fi
