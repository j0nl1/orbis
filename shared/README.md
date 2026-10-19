# Shared application modules

Only code with the same contract and behaviour on iPadOS and macOS belongs here.

- `Capabilities` resolves session feature availability from platform and protocol
  evidence through a shared input port. Immutable snapshots keep UI consumers
  independent of FreeRDP, AppKit, and UIKit.
- `Clipboard` defines an immutable text/PNG value and local clipboard port.
  Platform adapters own OS access, image decoding, and privacy policy; protocol
  adapters own RDP wire encodings and transfer coordination.
- `Diagnostics` records local session/error history and available MetricKit crash
  or hang reports, with a bounded JSON export and no automatic uploads.
- `Profiles` defines connection profiles, selection, automatic connection, and
  persistence.
- `Security` stores RDP passwords and hostname-bound gateway credentials in
  separate Apple Keychain items.
- `Transport` defines the connection port, direct and Cloudflare adapters, and
  adapter session ownership. Both applications select an adapter before starting
  RDP and keep its prepared session alive until the connection attempt ends.

The application composition root selects an adapter through `OrbisTransportFactory`
and injects `OrbisConnectionTransport` into the RDP session controller. Each
`prepareWithCompletion:` call returns a separate `OrbisTransportSession`, owned
by that connection attempt. Preparation completes asynchronously on the main
queue, including cancellation. `close` is idempotent and must run on the main
queue before the attempt's session is released.

Direct transport leaves normal RDP routing and redirection intact. Cloudflare
prepares a loopback TCP destination and carries each accepted stream over an
Access-authenticated WebSocket. The RDP adapter applies that physical destination
through FreeRDP's public transport callbacks without changing the logical server
or certificate identity. Gateway handshake errors are available through the
transport session; RDP continues to own established-stream failure and login
handoff.

Profiles persist a transport type and non-secret options. Credentials are resolved
outside the RDP controller and never belong in transport options. Legacy direct
profiles remain valid, and the prototype's `usesCloudflareTunnel` flag migrates to
`transport.type = cloudflare`. Unknown types are preserved and fail adapter
selection explicitly, preventing accidental direct connections.

A future gateway adds an adapter and selection/configuration support. It does not
need provider checks in the RDP controller. A system-managed private network such
as Tailscale can use the direct adapter; an embedded network implementation may
provide its own adapter.

Platform views, session lifecycle, and keyboard or touch policy belong to their
owning application. FreeRDP adapters remain behind the versioned integration
patch. This keeps the shared layer small and prevents platform conditionals from
accumulating in it.

## Session capabilities

`OrbisSessionCapabilities` implements the `OrbisSessionCapabilitySink` input port.
Each connection calls `beginSession`, retains its generation identifier, and sends
complete feature evidence through `updateFeature:direction:facts:limits:forGeneration:`.
Reconnect resets all evidence. Late callbacks from earlier generations, updates
after session end, and invalid feature/direction keys are rejected. An unconfigured
feature is unavailable because it is not implemented.

The shared policy considers implementation, user preference, local permission,
channel readiness, peer support, and explicit restrictions. Send and receive are
independent. Unknown evidence is distinct from a known refusal. A peer with
unknown support does not prevent an initial transfer attempt when local gates and
the channel are ready: `canAttempt` can be true while state remains `checking`.
This matters for protocols that do not announce every supported clipboard format.
It does not claim that a transfer will succeed.

Current clipboard contents and transient transfer errors are not capability
evidence. An empty clipboard does not establish unsupported images, and a generic
failure must not become a permanent server restriction. Feature limits describe
implemented or negotiated formats, byte limits, display dimensions, or monitor
counts. A zero numeric limit means unknown, not a zero allowance or unlimited
support guarantee.

Snapshots and their results are immutable, can be retained across later updates,
and can be read from any thread. The store serializes updates and coalesces change
notifications on the main queue. Observers of
`OrbisSessionCapabilitiesDidChangeNotification` read the store's latest snapshot;
notifications do not carry obsolete generation snapshots. UI code presents that
state without interpreting RDP details. These interfaces support both ARC and MRC
consumers.

## Local clipboard port

`OrbisClipboardPort` reads and publishes `OrbisClipboardContent` on the main
thread. The value can retain text and a normalized PNG together. It bounds text
to 8 MiB in UTF-8 and encoded PNG data to 32 MiB, rejecting excess data rather than
truncating it. Image adapters additionally validate encoding, a 16 Mi-pixel decoded
budget, and a maximum side length of 16384 pixels before decoding or publication.
The payload value checks PNG signature and encoded size; it does not decode images.

The macOS adapter can observe clipboard changes according to platform policy;
the iPadOS adapter reads only following a user action. Neither capability queries
nor session negotiation should read the local clipboard or trigger a privacy
prompt. A rejected publication preserves existing local clipboard content. Nil
read results do not prove that the user or server denied permission. The protocol
adapter converts RDP formats such as DIB without exposing those formats through
the local clipboard interface.
