#!/usr/bin/env bats

setup() {
    load 'test_helper/bats-helpers'
    STATUSLINE="${PROJECT_ROOT}/statusline.sh"
}

@test "statusline: empty stdin outputs fallback" {
    run bash -c 'echo -n "" | "'"$STATUSLINE"'"'
    assert_output --partial "no data"
    assert_success
}

@test "statusline: invalid JSON outputs fallback" {
    run bash -c 'echo "not json" | "'"$STATUSLINE"'"'
    assert_output --partial "no data"
    assert_success
}

@test "format_tokens: non-numeric input returns 0" {
    run format_tokens "abc"
    assert_output "0"
}

@test "format_time: non-numeric input returns 0s" {
    run format_time "abc"
    assert_output "0s"
}

@test "color_by_pct: empty input returns GREEN" {
    run color_by_pct ""
    assert_output "$GREEN"
}

@test "color_by_pct: non-numeric input returns GREEN" {
    run color_by_pct "abc"
    assert_output "$GREEN"
}

@test "make_bar: non-numeric pct returns all empty" {
    run make_bar "abc" 10
    assert_output "░░░░░░░░░░"
}
