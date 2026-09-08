#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "$repo_root/tests/check_alignment.sh" "${GROOVE_CHECKOUT:?set an explicit Groove checkout path}"
