#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Regression coverage for the foundation CI configuration.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  return 1
}

assert_equal() {
  local expected=$1
  local actual=$2
  local message=$3

  [[ $actual == "$expected" ]] ||
    fail "$message (expected '$expected', got '${actual:-<missing>}')"
}

assert_line_count() {
  local expected=$1
  local needle=$2
  local file=$3
  local message=$4
  local actual

  actual=$(grep -Fxc -- "$needle" "$file" || true)
  assert_equal "$expected" "$actual" "$message"
}

dependabot_limit() {
  local file=$1
  local ecosystem=$2

  awk -v ecosystem="$ecosystem" '
    function unquote(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^"|"$/, "", value)
      return value
    }

    /^[[:space:]]*-[[:space:]]*package-ecosystem:/ {
      value = $0
      sub(/^[^:]+:[[:space:]]*/, "", value)
      selected = (unquote(value) == ecosystem)
      next
    }

    selected && /^[[:space:]]*open-pull-requests-limit:/ {
      value = $0
      sub(/^[^:]+:[[:space:]]*/, "", value)
      gsub(/[[:space:]]+$/, "", value)
      print value
      matches++
    }

    END {
      if (matches != 1) {
        exit 1
      }
    }
  ' "$file"
}

action_ref() {
  local file=$1
  local action=$2

  awk -v action="$action" '
    /^[[:space:]]*uses:/ {
      value = $0
      sub(/^[[:space:]]*uses:[[:space:]]*/, "", value)
      sub(/[[:space:]]+#.*$/, "", value)
      prefix = action "@"
      if (index(value, prefix) == 1) {
        print substr(value, length(prefix) + 1)
        matches++
      }
    }

    END {
      if (matches != 1) {
        exit 1
      }
    }
  ' "$file"
}

permission_value() {
  local file=$1
  local permission=$2

  awk -v permission="$permission" '
    /^permissions:$/ {
      selected = 1
      next
    }

    selected && /^[^[:space:]]/ {
      selected = 0
    }

    selected && $0 ~ "^  " permission ":[[:space:]]*" {
      value = $0
      sub(/^[^:]+:[[:space:]]*/, "", value)
      print value
      matches++
    }

    END {
      if (matches != 1) {
        exit 1
      }
    }
  ' "$file"
}

validate_dependabot() {
  local file=$1
  local actual_count

  [[ -f $file ]] || { fail "Dependabot configuration is missing"; return 1; }
  assert_equal 2 "$(dependabot_limit "$file" github-actions)" \
    "GitHub Actions updates must be capped at two open pull requests" || return 1
  assert_equal 0 "$(dependabot_limit "$file" cargo)" \
    "Cargo version updates must remain disabled without affecting security updates" || return 1
  assert_equal 3 "$(dependabot_limit "$file" mix)" \
    "Mix updates must be capped at three open pull requests" || return 1
  assert_equal 3 "$(dependabot_limit "$file" npm)" \
    "npm updates must be capped at three open pull requests" || return 1
  assert_equal 3 "$(dependabot_limit "$file" pip)" \
    "pip updates must be capped at three open pull requests" || return 1

  actual_count=$(grep -Ec '^[[:space:]]+open-pull-requests-limit:' "$file" || true)
  assert_equal 5 "$actual_count" \
    "Only the five explicitly configured ecosystems may define pull-request limits" || return 1
}

validate_codeql() {
  local file=$1
  local checkout_sha=3d3c42e5aac5ba805825da76410c181273ba90b1
  local codeql_sha=cdf488f595d80d6e07e03d4674febd5ab45fa938

  [[ -f $file ]] || { fail "CodeQL workflow is missing"; return 1; }
  assert_equal "$checkout_sha" "$(action_ref "$file" actions/checkout)" \
    "CodeQL checkout must use the reviewed immutable revision" || return 1
  assert_equal "$codeql_sha" "$(action_ref "$file" github/codeql-action/init)" \
    "CodeQL initialization must use the reviewed immutable revision" || return 1
  assert_equal "$codeql_sha" "$(action_ref "$file" github/codeql-action/analyze)" \
    "CodeQL analysis must use the same reviewed immutable revision" || return 1

  assert_line_count 1 '          persist-credentials: false' "$file" \
    "CodeQL checkout must disable persisted credentials exactly once" || return 1

  awk -v checkout="$checkout_sha" '
    /^[[:space:]]*-[[:space:]]+name:/ && in_checkout {
      exit(credentials == 1 ? 0 : 1)
    }

    $0 ~ "uses:[[:space:]]+actions/checkout@" checkout {
      in_checkout = 1
      next
    }

    in_checkout && /^[[:space:]]+persist-credentials:[[:space:]]+false([[:space:]]*)$/ {
      credentials++
    }

    END {
      if (in_checkout) {
        exit(credentials == 1 ? 0 : 1)
      }
      exit 1
    }
  ' "$file" || { fail "persist-credentials: false must belong to the checkout step"; return 1; }
}

validate_scorecard() {
  local file=$1
  local standards_sha=8750b94ac1bbe8c51ad13fe106669b13478f0b62
  local permission_count

  [[ -f $file ]] || { fail "Scorecard workflow is missing"; return 1; }
  assert_line_count 1 'on:' "$file" "Scorecard must define one trigger section" || return 1
  assert_line_count 1 '    - cron: "0 0 * * 0"' "$file" \
    "Scorecard must retain its weekly schedule" || return 1
  assert_line_count 1 '    branches: [main, master]' "$file" \
    "Scorecard must run for pushes to both primary branch names" || return 1
  assert_line_count 1 '  workflow_dispatch:' "$file" \
    "Scorecard must support manual execution" || return 1
  assert_line_count 1 '  group: ${{ github.workflow }}-${{ github.ref }}' "$file" \
    "Scorecard runs must be grouped per workflow and ref" || return 1
  assert_line_count 1 '  cancel-in-progress: true' "$file" \
    "Superseded Scorecard runs must be cancelled" || return 1

  assert_equal read "$(permission_value "$file" actions)" \
    "Scorecard actions permission must be read-only" || return 1
  assert_equal read "$(permission_value "$file" contents)" \
    "Scorecard contents permission must be read-only" || return 1
  assert_equal write "$(permission_value "$file" security-events)" \
    "Scorecard must be able to publish security events" || return 1
  assert_equal write "$(permission_value "$file" id-token)" \
    "Scorecard must be able to request an OIDC token" || return 1

  permission_count=$(awk '
    /^permissions:$/ { selected = 1; next }
    selected && /^[^[:space:]]/ { selected = 0 }
    selected && /^  [[:alnum:]-]+:[[:space:]]+(read|write|none)$/ { count++ }
    END { print count + 0 }
  ' "$file")
  assert_equal 4 "$permission_count" \
    "Scorecard must not receive undeclared top-level permissions" || return 1

  assert_equal "$standards_sha" \
    "$(action_ref "$file" hyperpolymath/standards/.github/workflows/scorecard-reusable.yml)" \
    "Scorecard must call the reviewed immutable reusable-workflow revision" || return 1
  assert_line_count 1 '  scorecard:' "$file" "Scorecard must define one scorecard job" || return 1
  assert_line_count 0 '    secrets: inherit' "$file" \
    "Scorecard must not pass repository secrets to the reusable workflow" || return 1
}

validate_repository_layout() {
  local root=$1
  [[ ! -e $root/.github/.nojekyll ]] ||
    fail ".github/.nojekyll must remain removed"
}

validate_all() {
  local root=$1
  validate_dependabot "$root/.github/dependabot.yml" || return 1
  validate_codeql "$root/.github/workflows/codeql.yml" || return 1
  validate_scorecard "$root/.github/workflows/scorecard.yml" || return 1
  validate_repository_layout "$root"
}

expect_rejected() {
  local description=$1
  shift

  if "$@" >/dev/null 2>&1; then
    fail "$description was accepted"
  fi
}

validate_all "$repo_root"

fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT
mkdir -p "$fixture_root/.github/workflows"
cp "$repo_root/.github/dependabot.yml" "$fixture_root/.github/dependabot.yml"
cp "$repo_root/.github/workflows/codeql.yml" "$fixture_root/.github/workflows/codeql.yml"
cp "$repo_root/.github/workflows/scorecard.yml" "$fixture_root/.github/workflows/scorecard.yml"

# Negative controls make sure the assertions detect the insecure regressions
# instead of merely accepting the checked-in files.
sed -i '0,/open-pull-requests-limit: 2/s//open-pull-requests-limit: 3/' \
  "$fixture_root/.github/dependabot.yml"
expect_rejected "an increased GitHub Actions update limit" \
  validate_dependabot "$fixture_root/.github/dependabot.yml"
cp "$repo_root/.github/dependabot.yml" "$fixture_root/.github/dependabot.yml"

sed -i 's#actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1#actions/checkout@v7.0.1#' \
  "$fixture_root/.github/workflows/codeql.yml"
expect_rejected "a mutable checkout tag" \
  validate_codeql "$fixture_root/.github/workflows/codeql.yml"
cp "$repo_root/.github/workflows/codeql.yml" "$fixture_root/.github/workflows/codeql.yml"

sed -i 's/persist-credentials: false/persist-credentials: true/' \
  "$fixture_root/.github/workflows/codeql.yml"
expect_rejected "persisted checkout credentials" \
  validate_codeql "$fixture_root/.github/workflows/codeql.yml"
cp "$repo_root/.github/workflows/codeql.yml" "$fixture_root/.github/workflows/codeql.yml"

sed -i 's/@8750b94ac1bbe8c51ad13fe106669b13478f0b62/@main/' \
  "$fixture_root/.github/workflows/scorecard.yml"
expect_rejected "a mutable Scorecard reusable-workflow ref" \
  validate_scorecard "$fixture_root/.github/workflows/scorecard.yml"
cp "$repo_root/.github/workflows/scorecard.yml" "$fixture_root/.github/workflows/scorecard.yml"

sed -i 's/  contents: read/  contents: write/' \
  "$fixture_root/.github/workflows/scorecard.yml"
expect_rejected "elevated Scorecard contents permissions" \
  validate_scorecard "$fixture_root/.github/workflows/scorecard.yml"
cp "$repo_root/.github/workflows/scorecard.yml" "$fixture_root/.github/workflows/scorecard.yml"

sed -i '/^  workflow_dispatch:$/d' "$fixture_root/.github/workflows/scorecard.yml"
expect_rejected "a Scorecard workflow without manual dispatch" \
  validate_scorecard "$fixture_root/.github/workflows/scorecard.yml"

touch "$fixture_root/.github/.nojekyll"
expect_rejected "a restored .github/.nojekyll marker" \
  validate_repository_layout "$fixture_root"

printf '%s\n' 'PASS: foundation CI settings and security boundaries are enforced.'
