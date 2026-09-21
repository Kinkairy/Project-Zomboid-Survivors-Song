# Survivor's Song

Project Zomboid B42.20 independent functional mod.

Current version: `rc0.4.3`. Extends the native UI compatibility guards to generic inventory-item inspection: non-`InventoryItem` Java components such as `FluidContainer` are rejected before CD item methods are called, preventing liquid-transfer tooltip debugger errors. Recorded CD names retain the native-style `CD: ` prefix and each player's language, including existing recordings.

## Rebuild baseline

The R2 runtime implementation is rebuilt from the last accepted R0 source baseline:

`b7c95867e71f289584cd65d2516b6ffc3493aed4` — `Add Survivor's Song R0`

It does not incrementally patch the failed R1 erased-disc runtime implementation. The maintenance layout and reviewed trilingual-catalog rule are retained, but the CD-player workflow below is a new implementation on top of R0 behavior.

## Core gameplay

1. Insert a normal vanilla RecordedMedia CD into a vanilla `Base.CDplayer`.
2. Right-click that CD player and choose **Erase CD**.
3. The inserted disc becomes blank semantics. Its native device-media slot remains occupied so the original eject UI keeps working; when ejected the physical item is a erased vanilla `Base.Disc_Retail` with no RecordedMedia index.
4. Insert/keep that blank CD, install headphones/earbuds in that exact CD player, carry vanilla `Base.Microphone`, turn the player on, and press the original **Play** button.
5. Play starts a server-authoritative background skill-recording session instead of native RecordedMedia playback. The session does not occupy the character TimedAction queue and produces no music, subtitles, media reward, or Survivor's Song listening effect.
6. Completion turns the disc into **`CD: <character>'s Song`** / **`CD: <角色>的歌`** while the ejected physical item remains vanilla `Base.Disc_Retail`.
7. Insert the song into a powered/on CD player with headphones installed and press **Play** to start a background restore/listening session. A microphone is not required for restore.
8. A recorded song can be erased back to blank.

No Record/Restore buttons are added to the device window. If blank/song requirements are not satisfied, the existing Play control is simply disabled; no character-overhead warning is emitted.

## Normal CD playback

Normal RecordedMedia CDs keep vanilla sound, subtitles, media rewards and manual Play/Stop. Survivor's Song adds an optional game-time playback duration:

- Vanilla;
- 30 game minutes;
- **60 game minutes (default)**;
- 120 game minutes.

If the native CD program finishes before a configured deadline, it starts again until the selected number of game minutes has elapsed. Manual Stop always ends the extension immediately.

The enhanced listening layer remains limited to Boredom, Unhappiness, Stress, Panic and Anger. Its strength is fixed; there is no strength-percentage sandbox option. Boredom/Unhappiness/Stress are enabled by default and Panic/Anger are opt-in. Effects apply only while a normal CD is actually audible: the player is on, powered, playing, has headphones/earbuds installed, and volume is above zero. rc0.3 also shows the same green downward HaloText style used by vanilla TV/radio interactions when an enabled negative mood stat actually decreases.

R2.2 also aligns the long skill-record/restore action presentation with Personal Journal 1.3.2: multiplayer inventory and overhead progress bars display the same sampled server progress, including explicit waiting/applying/completion-confirmation phases. XP snapshot precision and restore comparisons follow the Journal 1.3.2 skill-only path.

R2.3 fixes dedicated-server blank-CD creation by using vanilla B42.20 `instanceItem()` for both the temporary carrier and ejected `Base.CD`; this removes the server-only `InventoryItemFactory` null error during erase/eject.

R2.4 corrects the physical CD type for B42.20: there is no `Base.CD` item. Blank and recorded-song discs reuse vanilla `Base.Disc_Retail` with `RecordedMediaIndex=-1`, while temporary device-slot carriers remain `Base.Disc_Retail` with a valid native media index.

R2.5 fixes dedicated-server eject by leaving a freshly created `Base.Disc_Retail` at its native default unrecorded state instead of calling `setRecordedMediaIndex(-1)` through the Java bridge.

## Project layout

- `docs/` — runtime behavior and game-test plan.
- `deployment/` — local/test copy helper only; it does not publish Workshop content or restart servers.
- `translations/` — reviewed EN/CN/CH catalog and runtime synchronization tool.
- `../../tests/survivors-song/` — offline structural/contract checks.
- `../../tests/survivors-song/validate_workshop.py` — project-level validation entry point.
- `workshop/Contents/mods/SurvivorsSong/` — deployable B42.20 payload.

rc0.2 adds server-authoritative interruption checkpoints for recording/restoring. The checkpoint belongs to the physical CD: while the disc is loaded its state is mirrored on the CD player because the real physical item is temporarily replaced by the native media-slot carrier; eject copies the checkpoint back to the physical `Base.Disc_Retail`, and loading that same disc into any CD player restores it before Play resumes from the completed-page checkpoint.

rc0.4 keeps the rc0.3 background-session model and restores the character overhead progress bar from authoritative server progress without reoccupying the TimedAction queue. Mercenary Loadout and vanilla equip/stow shortcuts therefore remain normal while the visible overhead bar continues to represent the CD session.

Any required condition becoming invalid is terminal for the current in-memory session: ordinary-container storage, power-off, battery loss, missing headphones/earbuds, and a missing microphone during recording all save the current whole-page CD checkpoint and end the session. Re-satisfy the requirements and press Play again to resume from that saved CD checkpoint. Moving the active CD player between hand/equipment and a valid character attachment slot is not a failure and continues the same session.

Recorded song CDs also reuse Personal Journal 1.3.2's recorded-time presentation: the same `YYYY/MM/DD HH:MM` game-time stamp is saved and the physical song CD tooltip shows `Recorded / 记录时间 / 記錄時間`.

The active labels are intentionally short: recording shows `正在录入cd`; restoring shows `正在听取cd`.

Published Workshop item: `3803803266`.

## Current thin-shell repair

Normal-CD enhancement applies every enabled mood option once per game minute,
including repeated CDs. Magnitudes match native interaction units: Boredom,
Unhappiness and Panic decrease by 5; Stress and Anger decrease by 0.05 on their
0..1 scales. CharacterStat.add owns clamping; HaloTextHelper shows real changes.
Vanilla media-line rewards remain separate. Disabling the enhancement does not
disable native first-time media rewards. All-off disables every added effect.
Sleeping, stopped, muted, unpowered or headphone-less listening grants no pulse.
Multiple carried devices cannot stack pulses within one game minute.

The native joypad router owns A/B controls and physical CD enumeration. Only
custom load/eject/play adapters remain. The window renders device/session state;
client action completion no longer writes optimistic disc metadata. Custom media
stop requests are latched so a pending server reply or native stop tail cannot
cause a repeated-stop loop.

Authoritative knowledge sessions check the native online-player list before
advancing. Disconnect retains whole-page checkpoints and releases the session
without sending a packet to the absent player. Skill XP restoration retains
the Personal Journal target-minus-current algorithm and native addXpNoMultiplier.
