#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Regression coverage for third-party badge claims in README.adoc.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readme="$repo_root/README.adoc"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  return 1
}

validate_readme_badges() {
  local candidate=$1
  local errors=0

  if grep -Eiq 'bestpractices\.dev|bestpractices\.coreinfrastructure\.org|OpenSSF[[:space:]]+Best[[:space:]]+Practices' "$candidate"; then
    fail "README must not claim an OpenSSF Best Practices certification without a verified registration" || true
    errors=$((errors + 1))
  fi

  if grep -Eq '(^|[^[:digit:]])8509([^[:digit:]]|$)' "$candidate"; then
    fail "README must not reference unrelated OpenSSF Best Practices project 8509" || true
    errors=$((errors + 1))
  fi

  if ! grep -Fqx 'image:https://api.scorecard.dev/projects/github.com/metadatastician/spline/badge[OpenSSF Scorecard,link="https://scorecard.dev/viewer/?uri=github.com/metadatastician/spline"]' "$candidate"; then
    fail "README must retain the repository-specific OpenSSF Scorecard badge" || true
    errors=$((errors + 1))
  fi

  ((errors == 0))
}

if [[ ! -f $readme ]]; then
  fail "README.adoc not found at repository root"
  exit 1
fi

# The checked-in README is the primary regression target.
validate_readme_badges "$readme"

# Negative controls prove that the test rejects the original false badge and
# related variants instead of passing only because the current line is absent.
fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT

cp "$readme" "$fixture_dir/original-badge.adoc"
printf '%s\n' 'nimage:https://www.bestpractices.dev/projects/8509/badge[OpenSSF Best Practices,link="https://www.bestpractices.dev/projects/8509"]' >> "$fixture_dir/original-badge.adoc"
if validate_readme_badges "$fixture_dir/original-badge.adoc" >/dev/null 2>&1; then
  fail "validator accepted the removed false-certification badge"
  exit 1
fi

cp "$readme" "$fixture_dir/label-only.adoc"
printf '%s\n' 'Status: openssf best practices certification pending.' >> "$fixture_dir/label-only.adoc"
if validate_readme_badges "$fixture_dir/label-only.adoc" >/dev/null 2>&1; then
  fail "validator accepted a case-variant certification claim"
  exit 1
fi

cp "$readme" "$fixture_dir/project-id-only.adoc"
printf '%s\n' 'Certification project: 8509' >> "$fixture_dir/project-id-only.adoc"
if validate_readme_badges "$fixture_dir/project-id-only.adoc" >/dev/null 2>&1; then
  fail "validator accepted the unrelated project id without its original URL"
  exit 1
fi

printf '%s\n' 'PASS: README badge claims are repository-specific and exclude false Best Practices certification.'
