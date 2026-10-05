# macOS updates from GitHub Releases

Orbis uses Sparkle 2.10.0 to check a signed appcast hosted as a GitHub release
asset. Publishing a release provides the universal ZIP, `appcast.xml`, and
`SHA256SUMS`. The app's feed URL is
`https://github.com/j0nl1/orbis/releases/latest/download/appcast.xml`.

The app checks daily and offers **Orbis > Check for Updates…**. Installation
requires the user's approval. Checks are deferred during remote sessions. If
the user starts a session after downloading an update, relaunch waits until
that session ends. Sparkle verifies the ZIP before extraction and also verifies
the feed. Updates preserve the existing profile files and Keychain credentials.
Ad-hoc updates may still require renewed Keychain authorization, as described below.

## Free signing

The release workflow does not require an Apple Developer membership, a
Developer ID certificate, or notarization. It uses an ad-hoc macOS code
signature and a free Ed25519 signature. The private Ed25519 key authenticates
both the update archive and the appcast against the public key embedded in the
installed app.

These signatures serve different purposes. Sparkle's signature protects updates
after installation; it does not make the app a notarized Apple application.
The first installation of an unnotarized GitHub download may require the user
to approve opening it in macOS System Settings > Privacy & Security. Organizations
can enforce policies that disallow such apps. A Developer ID signature and
notarization can be added later for smoother first-install distribution.

## Stable identity for local installations

An ad-hoc signature identifies a particular build, so replacing its executable
can trigger Keychain authorization again. For local installations, use the same
Apple Development identity on every update. For public distribution, use a
consistent Developer ID identity and notarization. Sparkle's Ed25519 signature
authenticates an update archive; it does not establish the application's identity
for Keychain access.

Configure a local identity without putting certificates or private keys in the
repository. Use the SHA-1 identity reported by `security find-identity -v -p
codesigning`, or its exact certificate name:

```sh
mkdir -p "$HOME/.config/orbis"
printf '%s\n' 'YOUR_CODE_SIGNING_IDENTITY' > "$HOME/.config/orbis/macos-signing-identity"
scripts/build-orbis-macos.sh
```

`ORBIS_MACOS_SIGNING_IDENTITY` overrides this file. Set it to `-` explicitly for
an ad-hoc test build. `ORBIS_MACOS_SIGNING_IDENTITY_FILE` overrides the file path.
If a configured identity is unavailable, signing fails rather than silently
changing the application's identity. In remote development, sign from the Mac's
logged-in GUI session when the signing key is not accessible over SSH.

The first transition from an ad-hoc build can still require authorization for
existing credentials. Choose **Always Allow** in the macOS Keychain prompt for
Orbis to remember that permission. Subsequent versions signed with the same
identity and bundle identifier retain the same designated requirement. This does
not change other applications' permissions or expose saved credentials. Switching
between Apple Development, Developer ID, and ad-hoc builds can prompt again.
The current GitHub release workflow still uses ad-hoc signing; the local identity
configuration applies to local builds only.

References: [Apple code signing requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements),
[Apple code signing overview](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Introduction/Introduction.html).

## One-time repository setup

The `j0nl1/orbis` repository's public variable and private secret were configured
on October 1, 2026. Normal releases reuse that key and require no manual signing
setup. The instructions below are for initial setup on another repository or
for restoring the existing configuration. Do not generate a replacement key for
routine releases.

On a Mac, download the pinned Sparkle distribution and generate a dedicated key
in the login Keychain:

```sh
sparkle_root="$(scripts/prepare-sparkle.sh)"
"$sparkle_root/bin/generate_keys" --account com.dnexus.orbis
```

Run the following from the same Mac with GitHub CLI authenticated to this
repository. The public key is a repository variable; the private key is a
repository secret. Never commit or print the private key.

```sh
"$sparkle_root/bin/generate_keys" --account com.dnexus.orbis -p |
  gh variable set ORBIS_UPDATE_PUBLIC_KEY --repo j0nl1/orbis

umask 077
key_file="$(mktemp -t orbis-update-key)"
"$sparkle_root/bin/generate_keys" --account com.dnexus.orbis -x "$key_file"
gh secret set ORBIS_SPARKLE_PRIVATE_KEY --repo j0nl1/orbis < "$key_file"
rm -f "$key_file"
```

Keep a secure backup of this private key. Use the same key for future releases.
Changing the embedded public key without a supported Sparkle key rotation
breaks updates from existing installations. The workflow stops before building
if either repository setting is absent, and refuses to publish unsigned output.

## Automatic releases from main

Every push to `main`, including merge, squash, and rebase merges of pull requests,
starts the release workflow. No manual tag or version edit is needed. The workflow
chooses `vYYYY.MM.DD.N` using the current UTC date and the next available revision.
It considers all existing tags and releases, including drafts, to avoid reusing
a version after a failed publication. If a reserved version has a later date,
that date is retained and its revision increases so updates remain ordered.

Each build and its release tag use the exact commit that triggered the workflow,
even if `main` advances during the build. Releases are serialized, with up to 100
pending runs queued. A rerun or an older queued commit already included in the
most recent published stable release is skipped, preventing an older app from
being republished with a newer version. The tag is only created after the build,
packaging, and signature checks succeed. The workflow token creates the tag and
release without triggering another tag-push workflow.

This automation takes effect when the workflow change reaches `main`; that push
also starts the first automatic release. It uses the existing public variable
and private signing secret described above. The workflow never merges a pull
request or writes a commit to `main`.

## Manual release tags

To publish a specific commit manually, create and push a tag:

```sh
git tag v2026.09.30.1
git push origin v2026.09.30.1
```

Tags use `vYYYY.MM.DD.N`, where `N` is a revision from 1 through 9999 without
leading zeros. The displayed version is `YYYY.MM.DD`; the build number used for
ordering updates is `YYYYMMDD.N`. Increase the revision for another release on
the same day. Dates must be valid, and a release must be newer than the latest
published stable version. Prerelease suffixes are not accepted by this workflow.

## Build and publication

The workflow builds on native Apple Silicon and Intel runners, runs the native
suite, combines the app binaries, signs the resulting app, then generates and
verifies the signed ZIP and feed. Sparkle is already universal and is copied
without merging its slices. The workflow creates a draft with all three assets
before publishing it as the latest release. A build or packaging failure leaves
the previous public release available. A publication failure may leave a draft
that must be removed before retrying the same manual tag. Rerunning all jobs of
an automatic release allocates a new version after a failed publication;
distributable files are also retained as a workflow recovery artifact for seven days.

Do not manually mark older releases as latest, replace signed assets, or publish
an unrelated release as latest without its matching appcast. The stable feed
points at GitHub's latest release. The workflow serializes releases and checks
version ordering again immediately before publication.

## First installation and existing builds

Download the release ZIP, extract it, and copy `Orbis.app` into `/Applications`
or `~/Applications` before opening it. Builds made before this integration have
no updater and need this first installation manually. Future updates use Sparkle.

Ordinary local builds keep the updater disabled and make no update requests.
To enable it for a source build, supply the public key matching the releases:

```sh
ORBIS_ENABLE_UPDATES=ON \
ORBIS_UPDATE_PUBLIC_KEY=YOUR_BASE64_PUBLIC_KEY \
ORBIS_VERSION=2026.09.30 ORBIS_BUILD_NUMBER=20260930.1 \
scripts/build-orbis-macos.sh
```

`ORBIS_UPDATE_FEED_URL` overrides the feed for development or forks.
`ORBIS_CMAKE_GENERATOR` defaults to `Ninja`; `Unix Makefiles` is supported when
only the Xcode command-line tools are available for building the app. The full
native XCTest suite still requires Xcode.

## Verification before the first public release

Use a temporary key and a development feed to exercise an older installed app
updating to a newer build. Verify successful restart, unchanged profiles, and
unchanged Keychain credentials. Tamper with a copy of the ZIP and feed and
confirm Sparkle rejects both. Start an RDP session while an update is ready
and confirm relaunch waits until disconnection. Run this final installation
check on macOS 15 or later; ad-hoc command-line builds alone cannot verify the
whole installed-app lifecycle.

Primary references: [Sparkle setup](https://sparkle-project.org/documentation/),
[Sparkle settings](https://sparkle-project.org/documentation/customization/),
[publishing updates](https://sparkle-project.org/documentation/publishing/),
[GitHub workflow concurrency](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency),
and [workflow triggers](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow).
