# Technical Reference — rc0.1

## Scope

Survivor's Song targets Project Zomboid Build 42.20 and Mod ID `SurvivorsSong`.

The public runtime has no external dependency and does not add a custom physical CD item type.

## Physical CD Model

B42.20 uses `Base.Disc_Retail` for CD inventory items. Survivor's Song keeps that vanilla item type for every player-visible disc:

- normal music CD: `Base.Disc_Retail` with a valid RecordedMedia index;
- erased blank CD: fresh/unrecorded `Base.Disc_Retail`;
- recorded song CD: fresh/unrecorded `Base.Disc_Retail` plus Survivor's Song ModData.

A blank/song disc cannot be inserted directly through vanilla `DeviceData:addMediaItem()`, because that API accepts only RecordedMedia. The runtime therefore inserts a temporary `Base.Disc_Retail` carrier with a valid CD media index and stores only blank/song semantics plus knowledge payload on the CD-player item.

Eject uses the native occupied-slot removal path, discards the temporary generated carrier, and returns one player-visible unrecorded `Base.Disc_Retail`.

## Record and Restore

Recording requires a loaded blank mode, an on/powered CD player, installed headphones/earbuds, a carried vanilla microphone, and at least one positive skill-XP record.

Restore requires the same device/power/headphone conditions but not the microphone.

The existing CD-player Play control starts the custom knowledge TimedAction. Blank/song modes never call native `StartPlayMedia()`.

## Multiplayer Authority

The server reconstructs and validates record/restore TimedActions and owns final application. The client only mirrors presentation after authoritative completion.

Long knowledge actions disable the normal real-time timeout. Progress display samples server `NetTimedAction` progress and does not locally award XP or force completion.

## Normal RecordedMedia Playback

Normal music CDs remain vanilla-owned. Survivor's Song only adds an optional duration extension: vanilla, 30, 60 (default), or 120 game minutes.

Manual Stop is terminal for an extended session. Listening effects are limited to boredom, unhappiness, stress, panic, and anger and require actually audible playback.

## rc0.1 Known Limitations

- Record/restore interruption checkpoints are not persisted yet.
- Starting a second record/restore after interruption does not resume from the previous fraction.
- A mounted CD player can be handled by external hotbar/attachment mods, but rc0.1 does not coordinate those shortcut actions with an active Survivor's Song knowledge TimedAction.

These limitations are targeted for rc0.2.
