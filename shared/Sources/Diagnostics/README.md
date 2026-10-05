# Local diagnostics

`OrbisDiagnostics` stores a private local history and subscribes to Apple's
MetricKit crash and hang diagnostics. Nothing is uploaded automatically.
macOS exposes Orbis → Export Diagnostics; iPad exposes Settings → Diagnostics →
Export Diagnostics. The JSON export can be opened in an editor for investigation.

Events include timestamps, a launch identifier, app version/build, the running
executable's Mach-O UUID, OS version, platform, and numeric context. Capture points
cover connection attempts, established sessions, failure codes, disconnects,
display changes, macOS fullscreen/screen transitions, and iPad workspace actions.
The recorder excludes passwords, tokens, hostnames, account names, keyboard input,
clipboard contents, raw error descriptions, and NSError userInfo. Only numeric
values under the fixed context keys are accepted. Crash and hang reports retain
call stacks, binary UUIDs, offsets, diagnostic app versions and numeric causes;
free-form exception and termination text is omitted.

The store lives in Application Support/Orbis/Diagnostics within each application's
user directory or iPad sandbox. It keeps two event files of at most 1 MiB each and
up to ten system reports of at most 2 MiB each. Duplicate system payloads are not
saved again; report time determines retention, so replaying old MetricKit history
does not evict newer reports. Oversized stack trees are marked as omitted, and
oversized complete payloads are skipped. Concurrent calls serialize disk access.
Files use owner-only permissions, are excluded from backup, and use iPad file
protection after the first unlock. Exported temporary files are removed when the
share sheet or macOS save operation finishes.

MetricKit delivery is controlled by the operating system and is not guaranteed
for every termination. Reports may become available after reopening the app;
force-quitting or an ordinary session error does not necessarily produce a crash
report. Event records are written during normal execution rather than inside
unsafe crash signal handlers. Diagnostic recording failures do not interrupt RDP.

For NSError records, `error_kind` identifies these domains in order:
0 NSCocoaErrorDomain, 1 NSPOSIXErrorDomain, 2 NSURLErrorDomain,
3 com.dnexus.orbis.session, 4 com.dnexus.orbis.transport,
5 com.dnexus.orbis.tunnel, 6 com.dnexus.orbis.keychain,
7 com.dnexus.orbis.display, and 8 any other domain.

Builds preserve app debugging symbols in `Orbis.app.dSYM` beside the native build
output. Match a diagnostic binary UUID to its dSYM using `dwarfdump --uuid` before
symbolication; different builds on the same day can share a displayed version.
Keep each relevant dSYM and the corresponding executable outside the repository
when investigating reports. Third-party frames also require the matching library
symbols, which may be unavailable in optimized dependency builds.

Shared XCTest tests cover persistence, exclusion of secret data, concurrent
writers, event rotation, diagnostic payload ingestion, deduplication, retention,
and export errors. The same tests run on macOS and in the iPad app-hosted suite
with injected system payloads. Live OS crash/hang delivery still requires testing
on a real device; the tests do not deliberately crash the user's installed app.
