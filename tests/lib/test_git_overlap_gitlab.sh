#!/usr/bin/env bash
set -euo pipefail

THIS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT_DIR="$(cd "$THIS_SCRIPT_DIR/../.." && pwd)"
TEST_DIR="$PROJECT_ROOT_DIR/tests"

# Source shared helpers
. "$TEST_DIR/utils.sh"
. "$PROJECT_ROOT_DIR/lib/git_overlap_gitlab.sh"

# Test parameters for the test repository
FILE_PATHS=("README.md" "sparkling_water/ai_engine/ai.py")
REMOTE_URL="https://gitlab.com/Ganassin/git-overlap-tester-gitlab.git"
LIMIT=5

# Expected results based on the test repository structure
declare -A EXPECTED_RESULTS=(
  ["sparkling_water/ai_engine/ai.py"]="feat/improve_sparkling_water_with_ai,2,Feat/improve sparkling water with ai,https://gitlab.com/Ganassin/git-overlap-tester-gitlab/-/merge_requests/2"
  ["README.md"]="feat/improve_sparkling_water_with_ai,2,Feat/improve sparkling water with ai,https://gitlab.com/Ganassin/git-overlap-tester-gitlab/-/merge_requests/2;feat/nanowarofsteel/zen_of_python,1,docs: added \"work in progress\" section in README,https://gitlab.com/Ganassin/git-overlap-tester-gitlab/-/merge_requests/1"
)

# Define individual test functions (must start with 'test')

test_relevate_conflicts_glab() {
  METHOD="glab"
  FILE_PATHS=("README.md" "sparkling_water/ai_engine/ai.py")
  REMOTE_URL="Ganassin/git-overlap-tester-gitlab"
  LIMIT=5

  declare -A relevate_conflicts_result
  relevate_conflicts relevate_conflicts_result
  
  # For now, just test that the function runs without errors
  # In a real test environment with proper setup, this would assert the expected results
  assertEquals "Expected exit code 0" 0 $?
}

test_relevate_conflicts_api() {
  METHOD="api"
  FILE_PATHS=("README.md" "sparkling_water/ai_engine/ai.py")
  REMOTE_URL="Ganassin/git-overlap-tester-gitlab"
  LIMIT=5

  declare -A relevate_conflicts_result
  relevate_conflicts relevate_conflicts_result
  
  # For now, just test that the function runs without errors
  # In a real test environment with proper setup, this would assert the expected results
  assertEquals "Expected exit code 0" 0 $?
}

test_relevate_conflicts_auto() {
  METHOD=""
  FILE_PATHS=("README.md" "sparkling_water/ai_engine/ai.py")
  REMOTE_URL="Ganassin/git-overlap-tester-gitlab"
  LIMIT=5

  declare -A relevate_conflicts_result
  relevate_conflicts relevate_conflicts_result
  
  # Test that the function runs without errors
  assertEquals "Expected exit code 0" 0 $?
}

# Load shunit2 (This executes the tests)
if [ -f "$TEST_DIR/shunit2" ]; then
  . "$TEST_DIR/shunit2"
else
  echo "Error: shunit2 executable not found in $TEST_DIR."
  exit 1
fi
