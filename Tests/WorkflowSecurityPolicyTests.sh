#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CHECKER="$ROOT/Scripts/check-workflow-security"
FIXTURES=$(mktemp -d)

cleanup() {
  rm -rf "$FIXTURES"
}
trap cleanup EXIT INT TERM

write_workflow() {
  directory=$1
  content=$2
  mkdir -p "$directory/.github/workflows"
  printf '%s\n' "$content" > "$directory/.github/workflows/test.yml"
}

expect_pass() {
  name=$1
  directory=$2
  if ! "$CHECKER" "$directory"; then
    echo "Expected workflow policy to pass: $name" >&2
    exit 1
  fi
}

expect_fail() {
  name=$1
  directory=$2
  expected=$3
  if output=$("$CHECKER" "$directory" 2>&1); then
    echo "Expected workflow policy to fail: $name" >&2
    exit 1
  fi
  case "$output" in
    *"$expected"*)
      ;;
    *)
      echo "Workflow policy failed for the wrong reason: $name" >&2
      echo "$output" >&2
      exit 1
      ;;
  esac
}

safe="$FIXTURES/safe"
write_workflow "$safe" '
name: Safe
on:
  pull_request:
permissions:
  contents: read
jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
        with:
          persist-credentials: false
      - run: echo safe
'
expect_pass "read-only pinned GitHub action" "$safe"

write_permissions="$FIXTURES/write-permissions"
write_workflow "$write_permissions" '
name: Unsafe
on: [push]
permissions:
  contents: write
jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - run: echo unsafe
'
expect_fail \
  "write token permission" \
  "$write_permissions" \
  'permissions.contents requests "write"'

job_permissions="$FIXTURES/job-permissions"
write_workflow "$job_permissions" '
name: Unsafe
on: [push]
permissions:
  contents: read
jobs:
  publish:
    permissions:
      id-token: write
    runs-on: ubuntu-latest
    steps:
      - run: echo unsafe
'
expect_fail \
  "job write token permission" \
  "$job_permissions" \
  'permissions.id-token requests "write"'

pull_request_target="$FIXTURES/pull-request-target"
write_workflow "$pull_request_target" '
name: Unsafe
on:
  pull_request_target:
permissions:
  contents: read
jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - run: echo unsafe
'
expect_fail \
  "pull_request_target trigger" \
  "$pull_request_target" \
  "uses pull_request_target"

unpinned_action="$FIXTURES/unpinned-action"
write_workflow "$unpinned_action" '
name: Unsafe
on: [pull_request]
permissions:
  contents: read
jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false
'
expect_fail \
  "unpinned action" \
  "$unpinned_action" \
  "is not a pinned GitHub-owned action"

external_action="$FIXTURES/external-action"
write_workflow "$external_action" '
name: Unsafe
on: [pull_request]
permissions:
  contents: read
jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: third-party/example@0123456789012345678901234567890123456789
'
expect_fail \
  "third-party action" \
  "$external_action" \
  "is not a pinned GitHub-owned action"

persisted_credentials="$FIXTURES/persisted-credentials"
write_workflow "$persisted_credentials" '
name: Unsafe
on: [pull_request]
permissions:
  contents: read
jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
'
expect_fail \
  "persisted checkout credentials" \
  "$persisted_credentials" \
  "must set persist-credentials: false"

secret_reference="$FIXTURES/secret-reference"
write_workflow "$secret_reference" '
name: Unsafe
on: [push]
permissions:
  contents: read
jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - run: |
          curl -H "Authorization: ${{ secrets.RELEASE_TOKEN }}" example.com
'
expect_fail \
  "secret reference" \
  "$secret_reference" \
  "references a repository or environment secret"

echo "Workflow security policy tests passed."
