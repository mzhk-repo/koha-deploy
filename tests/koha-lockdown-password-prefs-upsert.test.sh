#!/usr/bin/env bash
# Regression test: lockdown must create missing password preference rows.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${PROJECT_ROOT}/scripts/koha-lockdown-password-prefs.sh"

require_pattern() {
  local pattern="$1"

  grep -Fq -- "${pattern}" "${script}" || {
    printf 'missing required lockdown fragment: %s\n' "${pattern}" >&2
    exit 1
  }
}

require_pattern 'INSERT INTO systempreferences (variable, value)'
require_pattern "('OpacResetPassword', '0'),"
require_pattern "('OpacPasswordChange', '0')"
require_pattern 'ON DUPLICATE KEY UPDATE value=VALUES(value);'
require_pattern 'Koha::Caches->get_instance->flush_all'

printf 'PASS: password lockdown creates or updates both preferences and flushes cache\n'
