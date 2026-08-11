#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

controller="ipados/Sources/OrbisController.m"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

rg -q 'UIViewPropertyAnimator' "$controller" || \
  fail 'profile cards do not use an interruptible layout animator'

rg -q 'dampingRatio:' "$controller" || \
  fail 'profile-card expansion has no spring damping'

rg -q 'layoutIfNeeded' "$controller" || \
  fail 'profile-card expansion does not animate the resolved layout'

toggle_body="$(awk '
  /^- \(void\)toggleProfileCardWithIdentifier:/ {
    occurrence++
    if (occurrence == 2)
      capture = 1
  }
  capture { print }
  capture && /^}/ { exit }
' "$controller")"

if grep -q 'refreshProfileUI' <<<"$toggle_body"; then
  fail 'profile-card expansion rebuilds every card'
fi

if grep -q 'TransitionCrossDissolve' <<<"$toggle_body"; then
  fail 'profile-card expansion cross-fades instead of animating its layout'
fi

rg -q 'setHidden:!expanded' "$controller" || \
  fail 'profile-card expansion does not reveal its existing details panel'

printf 'PASS: Orbis profile-card animation contract\n'
