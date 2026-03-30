#!/bin/bash
# Common test helper - sources lib and sets up assertions

# Load bats helpers (paths relative to test file directory)
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

# Define color variables that lib functions depend on
RED='\033[31m'
YELLOW='\033[33m'
GREEN='\033[32m'

# Source the library under test
PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
source "${PROJECT_ROOT}/lib/hud-utils.sh"
