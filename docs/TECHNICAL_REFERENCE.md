# Technical Reference — rc0.4

## Scope

Survivor's Song targets Project Zomboid Build 42.20 and Mod ID `SurvivorsSong`.

The public runtime has no external dependency and does not add a custom physical CD item type.

## Physical CD Model

B42.20 uses `Base.Disc_Retail` for CD inventory items. Survivor's Song keeps that vanilla item type for every player-visible disc:

- normal music CD: `Base.Disc_Retail` with a valid RecordedMedia index;
- erased blank CD: fresh/unrecorded `Base.Disc_Retail`;
- recorded song CD: fresh/unrecorded `Base.Disc_Retail` plus Survivor's Song ModData.

A blank/song disc cannot be inserted directly through vanilla `DeviceData:addMediaItem()`, because that API accepts only RecordedMedia. The runtime therefore inserts a temporary `Base.Disc_Retail` carrier with a valid CD media index and stores blank/song semantics plus knowledge payload on the CD-player item while loaded.

Eject uses the native occupied-slot removal path, discards the temporary generated carrier, and returns one player-visible unrecorded `Base.Disc_Retail`.

## Record and Restore

Recording requires:

- loaded blank mode and occupied native media slot;
- CD player turned on with usable power;
- headphones/earbuds installed on that device;
- vanilla `Base.Microphone` carried by the character;
- SkillXP enabled and a positive skill-XP workload.

Restore requires the same device/power/headphone conditions but not the microphone. Account-bound songs remain restricted when a non-empty authenticated username exists.

The existing Play/Stop control is reused. Blank/song modes never enter native `StartPlayMedia()`.

## Background Session Model

rc0.4 does not keep record/restore as a long character TimedAction. The client sends only a start/stop request containing the real CD-player item ID and action kind. The server validates the actor and device, computes the workload, advances the session, applies the final recording or XP restore, and sends read-only progress state back to the owning player.

Session time advances with `getGameTime():getMultiplier()`, matching the time unit used by B42.20 `BaseAction.update()`. Record/restore workload and time conversion use the same Personal Journal 1.3.x skill-only model:

- page conversion: `ceil(units * 7 / 1000)`, minimum 1 page;
- write: `600 + skills * 120 + ceil(XP / 100) * 1`;
- read: `900 + skills * 90 + ceil(XP / 100) * 0.8`;
- write uses vanilla MinutesPerPage / MinutesPerDay conversion;
- restore uses `ISReadABook.getDuration()` on a disposable workload view;
- configurable record/restore multipliers default to 1.0.

The client does not supply elapsed time, pages, XP payload, or completion.

## Checkpoint Ownership and Termination

The interruption checkpoint logically belongs to the physical CD. Because the player-visible disc is replaced by the native media-slot carrier while loaded, the checkpoint is mirrored on the CD-player ModData during insertion. Eject copies it back to the physical `Base.Disc_Retail`; inserting that same disc into any CD player copies it back before the remaining duration is calculated.

A whole-page checkpoint is bound to action kind and actor identity. Successful completion clears it.

In rc0.4, losing any required condition is terminal for the in-memory session. The server first saves the current whole-page checkpoint, then ends the session. This includes:

- microphone loss while recording;
- headphones/earbuds removed;
- usable power lost;
- device switched off;
- CD player no longer held/equipped or actually attached to the character.

Moving the same active CD player between hand/equipment and a valid character attachment slot does not end the session.

## Progress Presentation

The background session does not occupy the character TimedAction queue. The client displays the authoritative session fraction through the normal character overhead progress bar.

If a foreground TimedAction is active, Survivor's Song does not overwrite that bar. When the foreground action ends, the current CD-session fraction is shown again.

Inventory item job text/delta remains synchronized with the same background session state.

## Recorded-Time Presentation

Completed song recordings store a game timestamp using the same format as Personal Journal 1.3.2:

`YYYY/MM/DD HH:MM`

The physical song CD displays the timestamp by temporarily supplying a localized tooltip while vanilla `ISToolTipInv` renders the item. The reviewed public strings are:

- EN: `Recorded: %1`
- CN: `记录时间：%1`
- CH: `記錄時間：%1`

No runtime dependency on Personal Journal is required.

## Normal RecordedMedia Playback

Normal music CDs remain vanilla-owned. Survivor's Song only adds an optional playback-duration extension: vanilla, 30, 60 (default), or 120 game minutes.

Manual Stop is terminal for an extended session. Enhanced listening effects are limited to boredom, unhappiness, stress, panic, and anger and require actually audible playback: device on, usable power, native media playing, headphones/earbuds installed, and volume above zero.

Boredom/Unhappiness/Stress are enabled by default; Panic/Anger are opt-in. When an enabled negative mood stat actually decreases, Survivor's Song uses vanilla `HaloTextHelper.addTextWithArrow()` with the good/green color and downward direction, matching TV/radio-style feedback.

Custom blank/song record/restore modes do not receive these normal-CD listening effects.

## Media Mutation Transactions

Erase/load/eject remain short native `NetTimedAction` operations. Before media mutation changes the loaded-disc state, any background record/restore session on that device is checkpointed and ended.

Custom eject remains transactional: if native carrier removal cannot be finalized, the occupied media slot is restored and newly generated carrier items are cleaned before failure is returned.
