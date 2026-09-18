# Changelog

## rc0.2 — 2026-09-18

- Shorten active labels to `正在录入cd` and `正在听取cd`.
- Save server-authoritative whole-page checkpoints when record/restore is interrupted.
- Resume from the saved checkpoint and run only the remaining duration on the next Play.
- Clear stale client active-action state on forced cancellation.
- Let same-device hotbar/equip/stow actions stop the knowledge action first so attached-device shortcuts remain usable.

## rc0.1 — 2026-09-18

- First public release-candidate source baseline.
- Uses vanilla `Base.Disc_Retail` for normal, erased blank, and recorded-song physical CDs.
- Keeps blank/song presence in the native CD-player DeviceData media slot through a temporary vanilla RecordedMedia carrier.
- Reuses the original Play/Stop UI for record/restore and keeps normal RecordedMedia playback vanilla-owned.
- Multiplayer record/restore completion is server authoritative.
- Known rc0.1 limitations: interrupted record/restore does not yet resume from a saved checkpoint, and mounted-CD-player shortcut interaction during a custom knowledge action is not yet integrated.
