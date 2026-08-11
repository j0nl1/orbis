#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
freerdp_source_dir="$("$project_root/scripts/prepare-freerdp.sh")"
launcher="$project_root/ipados/Sources/OrbisController.m"
editor_header="$project_root/ipados/Sources/OrbisProfileEditorController.h"
editor="$project_root/ipados/Sources/OrbisProfileEditorController.m"
about_info="$project_root/shared/Sources/About/OrbisAcknowledgements.m"
ipad_about="$project_root/ipados/Sources/OrbisAboutController.m"
mac_about="$project_root/macos/Sources/OrbisAboutController.m"
session="$freerdp_source_dir/client/iOS/Controllers/RDPSessionViewController.m"
session_view_header="$freerdp_source_dir/client/iOS/Views/RDPSessionView.h"
session_view="$freerdp_source_dir/client/iOS/Views/RDPSessionView.m"

require_literal() {
  local file="$1"
  local literal="$2"
  local description="$3"
  if ! rg --fixed-strings --quiet -- "$literal" "$file"; then
    echo "FAIL: $description" >&2
    return 1
  fi
}

reject_literal() {
  local file="$1"
  local literal="$2"
  local description="$3"
  if rg --fixed-strings --quiet -- "$literal" "$file"; then
    echo "FAIL: $description" >&2
    return 1
  fi
}

failures=0
require_literal "$about_info" '⌘C, ⌘V, ⌘A, ⌘Z, and ⌘⌫ work inside the remote session' \
  "About must explain Orbis's Mac-to-Linux shortcut translation" || failures=$((failures + 1))
require_literal "$ipad_about" 'setText:OrbisProductDescription' \
  "iPadOS About must show the product description" || failures=$((failures + 1))
require_literal "$mac_about" 'OrbisProductDescription' \
  "macOS About must show the product description" || failures=$((failures + 1))
require_literal "$launcher" 'UIButton *chevron' \
  "the visible card chevron must be an actionable button" || failures=$((failures + 1))
require_literal "$launcher" '[chevron addAction:' \
  "the card chevron must toggle the connection card" || failures=$((failures + 1))
require_literal "$launcher" 'UIView *statusGlyph' \
  "the status icon and spinner must share one centered layout slot" || failures=$((failures + 1))
require_literal "$launcher" 'initWithArrangedSubviews:@[ statusGlyph, statusLabel ]' \
  "the status badge must center a stable glyph slot beside its label" || failures=$((failures + 1))
require_literal "$launcher" 'initWithArrangedSubviews:@[ connectionIcon, identity, statusSpacer, statusStack ]' \
  "the status badge must center against the complete connection identity" || failures=$((failures + 1))
require_literal "$launcher" '[statusSpacer setContentHuggingPriority:1.0' \
  "a flexible spacer must push the fitted status badge to the trailing edge" || \
  failures=$((failures + 1))
require_literal "$launcher" '[statusStack setContentCompressionResistancePriority:UILayoutPriorityRequired' \
  "the status badge must preserve its intrinsic width" || failures=$((failures + 1))
reject_literal "$launcher" 'UIStackView *titleRow' \
  "the status badge must not align only with the title line" || failures=$((failures + 1))
require_literal "$launcher" '[UIColor systemTealColor]' \
  "the selected connection must use the modern teal accent" || failures=$((failures + 1))
reject_literal "$launcher" '[UIColor systemIndigoColor]' \
  "the previous indigo accent must not remain" || failures=$((failures + 1))
reject_literal "$launcher" '[[statusIconView heightAnchor] constraintEqualToConstant:14.0]' \
  "a hidden status icon must not fight the stack view's vertical collapsing constraint" || \
  failures=$((failures + 1))
reject_literal "$launcher" '[[activityIndicator heightAnchor] constraintEqualToConstant:14.0]' \
  "a hidden spinner must not fight the stack view's vertical collapsing constraint" || \
  failures=$((failures + 1))
reject_literal "$launcher" 'UILabel *details' \
  "connection details must stay behind the Details action" || failures=$((failures + 1))
require_literal "$launcher" 'initWithArrangedSubviews:@[ connectButton, edit, info, delete ]' \
  "expanded cards must expose one compact four-icon action rail" || failures=$((failures + 1))
require_literal "$launcher" '[UIButtonConfiguration prominentGlassButtonConfiguration]' \
  "connect must use the prominent iPadOS glass treatment" || failures=$((failures + 1))
require_literal "$launcher" '[UIButtonConfiguration glassButtonConfiguration]' \
  "secondary card actions must use the iPadOS glass treatment" || failures=$((failures + 1))
require_literal "$launcher" 'constraintEqualToConstant:54.0' \
  "icon actions must keep a generous circular touch target" || failures=$((failures + 1))
reject_literal "$launcher" '[connect setTitle:' \
  "the connect action must be icon-only" || failures=$((failures + 1))
reject_literal "$launcher" '[editConfiguration setTitle:' \
  "the edit action must be icon-only" || failures=$((failures + 1))
reject_literal "$launcher" '[infoConfiguration setTitle:' \
  "the details action must be icon-only" || failures=$((failures + 1))
reject_literal "$launcher" '[deleteConfiguration setTitle:' \
  "the delete action must be icon-only" || failures=$((failures + 1))
require_literal "$editor_header" 'UITextField *_passwordField;' \
  "the connection editor must offer a password field" || failures=$((failures + 1))
reject_literal "$launcher" 'UIButton *password' \
  "password management must not take a separate card action" || failures=$((failures + 1))
require_literal "$editor_header" 'initWithProfile:(OrbisProfile *)profile hasSavedPassword:' \
  "the editor must know whether a Keychain password already exists" || failures=$((failures + 1))
require_literal "$editor" 'setImage:[UIImage systemImageNamed:@"pencil"]' \
  "a saved password must expose an explicit replace action" || failures=$((failures + 1))
require_literal "$editor" '@"********"' \
  "the editor must mask a preserved Keychain password" || failures=$((failures + 1))
require_literal "$editor" '[replacePasswordButton setTintColor:[UIColor blackColor]];' \
  "the password replacement pencil must be black" || failures=$((failures + 1))
reject_literal "$editor" '@"Leave blank to keep saved password"' \
  "password preservation must not rely on an ambiguous blank-field instruction" || \
  failures=$((failures + 1))
require_literal "$editor" 'didSaveProfile:_profile password:' \
  "the editor must hand the transient password to the Keychain owner" || failures=$((failures + 1))
reject_literal "$session" 'loadNibNamed:@"RDPConnectingView"' \
  "the legacy Connecting/Cancel panel must not be loaded" || failures=$((failures + 1))
require_literal "$session" '[_session_scrollview setHidden:YES];' \
  "the unpainted remote canvas must remain hidden while connecting" || failures=$((failures + 1))
require_literal "$session_view_header" 'sessionViewDidPresentFirstFrame:' \
  "the renderer must expose a first-presented-frame boundary" || failures=$((failures + 1))
require_literal "$session_view" '[commandBuffer addCompletedHandler:' \
  "the renderer must wait for Metal to complete the first frame" || failures=$((failures + 1))
require_literal "$session_view_header" 'setNeedsDisplayForRemoteFrameInRect:' \
  "real RDP paint updates must be distinct from internal redraws" || failures=$((failures + 1))
require_literal "$session_view" 'if (_hasReceivedRemoteFrame && !_hasScheduledFirstFrame &&' \
  "internal layout renders must not reveal an empty desktop" || failures=$((failures + 1))
require_literal "$session" '[_session_view setNeedsDisplayForRemoteFrameInRect:rect];' \
  "only a FreeRDP dirty rect may arm first-frame presentation" || failures=$((failures + 1))
require_literal "$session" '- (void)sessionViewDidPresentFirstFrame:(RDPSessionView *)sessionView' \
  "the remote canvas must be revealed only after the first Metal frame" || failures=$((failures + 1))
reject_literal "$session_view" '[self setNeedsDisplayInRemoteRect:[self bounds]];' \
  "creating the desktop texture must not render an empty buffer" || failures=$((failures + 1))

if ((failures > 0)); then
  exit 1
fi

echo "PASS: Orbis connection UX contract"
