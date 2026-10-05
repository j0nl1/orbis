#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${ORBIS_BUILD_DIR:-$project_root/.build/ipados/simulator}"
result_path="${ORBIS_IPADOS_TEST_RESULT_PATH:-$HOME/.codex/artifacts/reports/orbis-ipados/$(date -u +%Y%m%dT%H%M%SZ).xcresult}"
mkdir -p "$(dirname "$result_path")"
if [[ -z "${ORBIS_SIMULATOR_DESTINATION:-}" ]]; then
  simulator_id="$(xcrun simctl list devices available --json | python3 -c '
import json, sys
for devices in json.load(sys.stdin)["devices"].values():
    for device in devices:
        if device["name"].startswith("iPad"):
            print(device["udid"])
            sys.exit(0)
sys.exit("No available iPad simulator. Install an iOS simulator runtime in Xcode.")
')"
  export ORBIS_SIMULATOR_DESTINATION="platform=iOS Simulator,id=$simulator_id"
fi

ORBIS_BUILD_IPADOS_TESTS=ON "$project_root/scripts/build-orbis-simulator.sh"

# CMake generates the XCTest bundle, while Xcode owns app hosting and simulator injection.
python3 - "$build_dir/iFreeRDP.xcodeproj" <<'PY'
from pathlib import Path
import re, sys
from xml.sax.saxutils import escape
project = Path(sys.argv[1]).resolve()
container = escape(str(project), {'"': '&quot;'})
pbx = (project / "project.pbxproj").read_text()
def reference(name, product):
    pattern = r'([A-F0-9]{24}) /\* ' + re.escape(name) + r' \*/ = \{\s*isa = PBXNativeTarget;'
    match = re.search(pattern, pbx)
    if not match:
        raise SystemExit(f"Missing Xcode target: {name}")
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{match[1]}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:{container}"/>'
app = reference("iFreeRDP", "Orbis.app")
tests = reference("OrbisIPadTests", "OrbisIPadTests.xctest")
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{app}</BuildActionEntry>
<BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{tests}</BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
<Testables><TestableReference skipped="NO">{tests}</TestableReference></Testables>
<MacroExpansion>{app}</MacroExpansion>
</TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app}</BuildableProductRunnable></LaunchAction>
</Scheme>'''
path = project / "xcshareddata/xcschemes/OrbisIPadValidation.xcscheme"
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(scheme)
PY

env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false \
  PKG_CONFIG_PATH="$build_dir/deps/Frameworks/pkgconfig" \
  xcodebuild -project "$build_dir/iFreeRDP.xcodeproj" -scheme OrbisIPadValidation \
    -configuration Debug -sdk iphonesimulator -destination "$ORBIS_SIMULATOR_DESTINATION" \
    -resultBundlePath "$result_path" \
    CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_IDENTITY=- \
    COMPILER_INDEX_STORE_ENABLE=NO test
