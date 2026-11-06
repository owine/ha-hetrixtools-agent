#!/usr/bin/env bats

# tests/upstream-delta.py on small fixtures. The manifest lists, per
# `# >>> ha-app patch` block, how many upstream lines it replaces and a hash of
# them; everything outside the blocks must be upstream verbatim.

bats_require_minimum_version 1.5.0

setup() {
  DELTA="tests/upstream-delta.py"
  T="$(mktemp -d)"
  printf '%s\n' a b c d e f g > "$T/up"
  # c and d are replaced by a patch block.
  printf '%s\n' a b '# >>> ha-app patch: x >>>' C '# <<< ha-app patch <<<' e f g > "$T/ve"
}

teardown() { rm -rf "$T"; }

manifest() { python3 -I "$DELTA" --suggest "$T/up" "$T/ve" > "$T/m"; }
check() { run python3 -I "$DELTA" "$T/up" "$T/ve" "$T/m"; }

@test "upstream plus declared patch blocks passes" {
  manifest
  [ "$(grep -v '^#' "$T/m")" = "2 $(printf 'c\nd\n' | sha256sum | cut -c1-16) x" ]
  check
  [ "$status" -eq 0 ]
}

@test "an upstream line dropped next to a block fails" {
  manifest
  printf '%s\n' a '# >>> ha-app patch: x >>>' C '# <<< ha-app patch <<<' e f g > "$T/ve"
  check
  [ "$status" -eq 1 ]
}

@test "an upstream line dropped far from any block fails" {
  manifest
  printf '%s\n' a b '# >>> ha-app patch: x >>>' C '# <<< ha-app patch <<<' e g > "$T/ve"
  check
  [ "$status" -eq 1 ]
}

@test "a changed line outside a block fails" {
  manifest
  sed -i.bak 's/^f$/F/' "$T/ve"
  check
  [ "$status" -eq 1 ]
}

@test "an upstream change inside a replaced span fails" {
  manifest
  printf '%s\n' a b c D e f g > "$T/up"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"block 1"* ]]
}

@test "merging two blocks by deleting markers fails" {
  printf '%s\n' a b c d e f g > "$T/up"
  printf '%s\n' '# >>> ha-app patch: x >>>' A '# <<< ha-app patch <<<' b c \
    '# >>> ha-app patch: y >>>' D '# <<< ha-app patch <<<' e f g > "$T/ve"
  manifest
  printf '%s\n' '# >>> ha-app patch: x >>>' A b X c D '# <<< ha-app patch <<<' e f g > "$T/ve"
  check
  [ "$status" -eq 1 ]
}

@test "nested or unbalanced markers fail" {
  manifest
  printf '%s\n' a b '# >>> ha-app patch: x >>>' '# >>> ha-app patch: y >>>' C \
    '# <<< ha-app patch <<<' '# <<< ha-app patch <<<' e f g > "$T/ve"
  check
  [ "$status" -eq 1 ]
  printf '%s\n' a b '# <<< ha-app patch <<<' e f g > "$T/ve"
  check
  [ "$status" -eq 1 ]
}

@test "CRLF line endings or a missing final newline fail" {
  manifest
  sed -i.bak 's/$/\r/' "$T/ve"
  check
  [ "$status" -eq 1 ]
  printf '%s\n' a b '# >>> ha-app patch: x >>>' C '# <<< ha-app patch <<<' e f > "$T/ve"
  printf 'g' >> "$T/ve"
  check
  [ "$status" -eq 1 ]
}
