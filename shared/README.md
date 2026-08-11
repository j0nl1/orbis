# Shared application modules

Only code with the same contract and behaviour on iPadOS and macOS belongs here.

- `Profiles` defines connection profiles, selection, automatic connection, and
  persistence.
- `Security` stores one password per profile in Apple Keychain.

Platform views, session lifecycle, and keyboard or touch policy belong to their
owning application. FreeRDP adapters remain behind the versioned integration
patch. This keeps the shared layer small and prevents platform conditionals from
accumulating in it.
