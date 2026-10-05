# Shared application modules

Only code with the same contract and behaviour on iPadOS and macOS belongs here.

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
