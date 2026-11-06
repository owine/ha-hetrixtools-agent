#!/usr/bin/env bats

# .github/scripts/release-gate.sh with gh replaced by an exported function:
# the stub answers only the three calls the gate should make, against a fixed
# main SHA, so a pass also shows the gate compared against that SHA.

setup() {
  GATE=".github/scripts/release-gate.sh"
  export GITHUB_SHA=abc123 REPO=o/r TAG_NAME=hetrixtools-agent-v1.2.3 PRERELEASE=false
  export STUB_STATUS=ahead STUB_CURRENT=1.2.2 STUB_FAIL=0 STUB_CFG_FAIL=0
  gh() {
    [ "$STUB_FAIL" = 1 ] && return 1
    case "$*" in
      *repos/o/r/git/ref/heads/main*) echo mainsha999 ;;
      *repos/o/r/compare/abc123...mainsha999*) echo "$STUB_STATUS" ;;
      *repos/o/r/contents/hetrixtools-agent/config.yaml\?ref=mainsha999*)
        [ "$STUB_CFG_FAIL" = 1 ] && return 1
        printf 'name: x\nversion: "%s"\nslug: y\n' "$STUB_CURRENT" ;;
      *) echo "unexpected gh $*" >&2; return 1 ;;
    esac
  }
  export -f gh
}

gate() { run bash "$GATE"; }

@test "a full release on main, newer than HA's version, passes and prints it" {
  gate
  [ "$status" -eq 0 ]
  [ "$output" = "1.2.3" ]
}

@test "the tagged commit may be main itself" {
  STUB_STATUS=identical gate
  [ "$status" -eq 0 ]
}

@test "the version HA already offers passes, so a run can be repeated" {
  STUB_CURRENT=1.2.3 gate
  [ "$status" -eq 0 ]
}

@test "versions compare numerically" {
  STUB_CURRENT=1.2.10 TAG_NAME=hetrixtools-agent-v1.10.0 gate
  [ "$status" -eq 0 ]
  STUB_CURRENT=1.2.10 gate
  [ "$status" -eq 1 ]
}

@test "a release older than HA's version fails" {
  STUB_CURRENT=2.0.0 gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"older than 2.0.0"* ]]
}

@test "an unreadable config.yaml on main fails" {
  STUB_CFG_FAIL=1 gate
  [ "$status" -eq 1 ]
  STUB_CURRENT=garbage gate
  [ "$status" -eq 1 ]
}

@test "a prerelease fails, and so does a missing prerelease flag" {
  PRERELEASE=true gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"prerelease"* ]]
  PRERELEASE= gate
  [ "$status" -eq 1 ]
}

@test "a tagged commit that is not on main fails" {
  for s in diverged behind; do
    STUB_STATUS=$s gate
    [ "$status" -eq 1 ]
    [[ "$output" == *"not on main ($s)"* ]]
  done
}

@test "a failing gh call fails the gate" {
  STUB_FAIL=1 gate
  [ "$status" -eq 1 ]
}

@test "a tag outside hetrixtools-agent-vX.Y.Z fails" {
  TAG_NAME=other-v1.2.3 gate
  [ "$status" -eq 1 ]
  TAG_NAME=hetrixtools-agent-v1.2 gate
  [ "$status" -eq 1 ]
}
