#!/usr/bin/env bats

setup() {
    load 'test_helper/bats-helpers'
}

# --- format_tokens ---
@test "format_tokens: 0 returns 0" {
    run format_tokens 0
    assert_output "0"
}

@test "format_tokens: 999 returns 999" {
    run format_tokens 999
    assert_output "999"
}

@test "format_tokens: 1500 returns 1.5K" {
    run format_tokens 1500
    assert_output "1.5K"
}

@test "format_tokens: 2500000 returns 2.5M" {
    run format_tokens 2500000
    assert_output "2.5M"
}

# --- format_time ---
@test "format_time: 0ms returns 0s" {
    run format_time 0
    assert_output "0s"
}

@test "format_time: 5000ms returns 5s" {
    run format_time 5000
    assert_output "5s"
}

@test "format_time: 125000ms returns 2m 5s" {
    run format_time 125000
    assert_output "2m 5s"
}

@test "format_time: 7200000ms returns 2h 0m" {
    run format_time 7200000
    assert_output "2h 0m"
}

# --- format_cost ---
@test "format_cost: 0 returns \$0.0000" {
    run format_cost 0
    assert_output '$0.0000'
}

@test "format_cost: 0.0012 returns \$0.0012" {
    run format_cost 0.0012
    assert_output '$0.0012'
}

@test "format_cost: 2.50 returns \$2.50" {
    run format_cost 2.50
    assert_output '$2.50'
}

# --- color_by_pct ---
@test "color_by_pct: 30 returns GREEN" {
    run color_by_pct 30
    assert_output "$GREEN"
}

@test "color_by_pct: 60 returns YELLOW" {
    run color_by_pct 60
    assert_output "$YELLOW"
}

@test "color_by_pct: 90 returns RED" {
    run color_by_pct 90
    assert_output "$RED"
}

# --- make_bar ---
@test "make_bar: 0% produces all empty blocks" {
    run make_bar 0 10
    assert_output "░░░░░░░░░░"
}

@test "make_bar: 100% produces all filled blocks" {
    run make_bar 100 10
    assert_output "██████████"
}

@test "make_bar: 50% produces half filled" {
    run make_bar 50 20
    assert_output "██████████░░░░░░░░░░"
}

@test "make_bar: >100% clamped to full" {
    run make_bar 150 10
    assert_output "██████████"
}
