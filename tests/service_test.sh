#!/usr/bin/env bash
#
# tests/service_test.sh - Unit Tests for Service Lifecycle Manager
#

set -euo pipefail

# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/helpers/test_helper.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/service.sh"

setup_test_work_dir

test_service_skip_flag() {
  make_temp_home
  export BLIZL_VOXTYPE_SKIP_SERVICE=true

  # Functions must return safely without error when service management is skipped
  service_is_active "voxtype.service" && fail "service_is_active should return false when skipped" || true
  service_restart_if_active "voxtype.service" || fail "service_restart_if_active failed"
  service_restore_state "voxtype.service" "false" "false" || fail "service_restore_state failed"
  pass "Service manager gracefully obeys BLIZL_VOXTYPE_SKIP_SERVICE"
}

# Run tests
printf 'Running service_test.sh:\n'
test_service_skip_flag
printf 'All service tests passed.\n'
