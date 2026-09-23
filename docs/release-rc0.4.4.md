# Survivor's Song rc0.4.4

Date: 2026-09-23. B42.20 / Multiplayer. Mod ID: SurvivorsSong. Existing Workshop ID: 3803803266.

## Repair and boundary

- R1 accepted gameplay: recorded discs update through the existing Play button without erasure; missing recoverable XP is restored first.
- Record calculation copies the Journal skill-only merge: normalized comparison, raw positive XP difference, retention of higher saved values, raw finite XP storage. Non-finite disc entries remain rejected. No Journal runtime dependency is added.
- Authority creates a record plan from its own initial delta. The encoded snapshot, device, loaded-disc fields and actor are bound to that plan. Completion checks context and identity, then writes only that snapshot. Later XP is deferred until the next update; no passive-XP abort loop.
- Pausing preserves completed whole pages. A new start recalculates work and clamps the existing credit, as before. Disc data schema 2 and checkpoint schema 1 remain unchanged.
- Existing author names/accounts are retained. When both usernames exist, they must match. Otherwise the original character name must match. Unnamed/unbound old discs are left intact and denied, not claimed or erased automatically.
- Button and joypad share one 250 ms read-only view. Each decision captures the native skill map once; clicking does fresh validation and never trusts the UI sample.

## Thin-shell scope

Native CD insert/eject, native radio/media playback, mounted-media hooks, native addXpNoMultiplier and ISReadABook.getDuration remain in use. The unchanged recording time formula follows Journal write timing; background sessions intentionally remain separate from its foreground TimedAction adapter. No Java changes, new buttons or localization keys.

## Validation

49 regression cases executed against the production shared, progress and client modules, with PZ/Java interfaces stubbed. Pass on Lua 5.3 and Lua 5.4. Includes authority-owned snapshots, delayed XP, old-disc ownership, raw precision, no-op timestamps, restore ratios, interruption/checkpoint copy, attachment continuity, no duplicate skill scans, client write rejection and server request rebuilding. This is not B42.20 in-game or real-network certification. The user tested the earlier R1 update path; rc0.4.4 requires a fresh game smoke test.

## Deployment and rollback

Publish/deploy the complete pinned Contents tree, never just a single changed Lua. Server and clients must use the same release. Preserve the existing Workshop item and visibility. Back up matching runtime directories before replacement; rollback restores Mod files only and must never rewind a live save automatically. Repository source commits are not evidence of Workshop upload or NUC runtime activation.
