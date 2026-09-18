# Changelog

## rc0.4 — 2026-09-18

- Restore the character overhead progress bar for background record/restore using authoritative server progress, without recreating a long TimedAction.
- Preserve foreground TimedAction ownership of the same UI bar; background CD progress returns after the foreground action ends.
- Replace rc0.3 pause-on-condition-loss with checkpoint-and-stop: losing microphone during recording, headphones/earbuds, usable power, device-on state, or valid held/attached placement saves the current whole-page CD checkpoint and ends the active session.
- Keep hand/equipped ↔ valid attachment-slot transitions continuous; these do not end the session.
- Reuse Personal Journal 1.3.2's `YYYY/MM/DD HH:MM` recorded timestamp format and vanilla tooltip-render strategy for physical song CDs.
- Add reviewed EN/CN/CH recorded-time tooltip text.
- Keep the rc0.3 vanilla-style green mood-effect HaloText feedback.

## rc0.3 — 2026-09-18

- Replace long record/restore TimedActions with server-authoritative background knowledge sessions.
- Advance session time with the same B42.20 `GameTime.getMultiplier()` units used by `BaseAction.update()`, preserving the existing duration scale.
- Let recording/restoring continue while the CD player is held or attached to the character.
- Remove Survivor's Song Hotbar overrides; normal keyboard/mouse/controller equip and stow shortcuts remain vanilla/attachment-mod owned.
- Keep whole-page interruption checkpoints logically owned by the physical CD across eject/reinsert and different CD players.
- Keep erase/load/eject as short native TimedActions.
- Show vanilla TV/radio-style green downward HaloText whenever a normal music CD actually reduces an enabled negative mood stat.

## rc0.2 — 2026-09-18

- Shorten active labels to `正在录入cd` and `正在听取cd`.
- Save server-authoritative whole-page checkpoints when record/restore is interrupted.
- Make the checkpoint follow the physical CD across eject/reinsert and across different CD players.
- Resume from the saved checkpoint and run only the remaining duration on the next Play.
- Fix the first mounted-device shortcut integration prototype.

## rc0.1 — 2026-09-18

- First public release-candidate source baseline.
- Uses vanilla `Base.Disc_Retail` for normal, erased blank, and recorded-song physical CDs.
- Keeps blank/song presence in the native CD-player DeviceData media slot through a temporary vanilla RecordedMedia carrier.
- Reuses the original Play/Stop UI for record/restore and keeps normal RecordedMedia playback vanilla-owned.
- Multiplayer record/restore completion is server authoritative.
