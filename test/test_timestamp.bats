#!/usr/bin/env bats

setup() {
    load 'test_helper/bats-helpers'
}

@test "iso_to_epoch: valid ISO timestamp returns epoch" {
    run iso_to_epoch "2026-01-01T00:00:00Z"
    assert_success
    [[ "$output" =~ ^[0-9]+$ ]]
}

@test "iso_to_epoch: empty input fails" {
    run iso_to_epoch ""
    assert_failure
}

@test "format_remaining: null input returns ?" {
    run format_remaining "null"
    assert_output "?"
}

@test "format_remaining: empty input returns ?" {
    run format_remaining ""
    assert_output "?"
}

@test "format_remaining: past timestamp returns soon" {
    run format_remaining "2020-01-01T00:00:00Z"
    assert_output "soon"
}

# --- syntax checks ---
@test "statusline.sh syntax is valid" {
    run bash -n "${PROJECT_ROOT}/statusline.sh"
    assert_success
}

@test "fetch-plan-usage.sh syntax is valid" {
    run bash -n "${PROJECT_ROOT}/fetch-plan-usage.sh"
    assert_success
}

@test "install.sh syntax is valid" {
    run bash -n "${PROJECT_ROOT}/install.sh"
    assert_success
}

@test "log-session.sh syntax is valid" {
    run bash -n "${PROJECT_ROOT}/log-session.sh"
    assert_success
}

@test "lib/hud-utils.sh syntax is valid" {
    run bash -n "${PROJECT_ROOT}/lib/hud-utils.sh"
    assert_success
}
