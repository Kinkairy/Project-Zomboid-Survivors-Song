# Changelog

## rc0.1 — 2026-09-18

- First public release-candidate source baseline.
- Uses vanilla `Base.Disc_Retail` for normal, erased blank, and recorded-song physical CDs.
- Keeps blank/song presence in the native CD-player DeviceData media slot through a temporary vanilla RecordedMedia carrier.
- Reuses the original Play/Stop UI for record/restore and keeps normal RecordedMedia playback vanilla-owned.
- Multiplayer record/restore completion is server authoritative.
- Known rc0.1 limitations: interrupted record/restore does not yet resume from a saved checkpoint, and mounted-CD-player shortcut interaction during a custom knowledge action is not yet integrated.
