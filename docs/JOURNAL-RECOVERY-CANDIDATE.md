# Survivor's Song: complete Journal recovery candidate

Date: 2026-10-05 UTC. Release payload: `rc0.4.5`. Based on the owner-confirmed
private candidate `d1c6be9aea3ab80c2d778a8855bc953f96bab7aa`, in isolated
`fix/cd-background-recovery-rc045-20261005`. Publication receipts are outside
source. No client/server installation, restart or real-save mutation is authorized.

## Exact source baseline

- Confirmed implementation baseline: private branch
  `test/cd-journal-recovery-rc045-20261004`, commit
  `d1c6be9aea3ab80c2d778a8855bc953f96bab7aa`; Song subtree
  `85eeae4b02a5fca5258749a77109ad4b8f115845`, runtime subtree
  `3cab8698b8fd50bb3768ff6044b3bfb134d9dc2b`, tests subtree
  `e45fb4e06dc3f7bafd1a9e2d6425ccd3dad5f423`. No old dirty tree is an input.
- Song runtime was first synchronized to public
  [rc0.4.4 / 0176cbec193223c5fd2cb033997d1aeaf1dd7f8d](https://github.com/Kinkairy/Project-Zomboid-Survivors-Song/tree/0176cbec193223c5fd2cb033997d1aeaf1dd7f8d),
  runtime Git tree `736666b0a839e105e87c63cb04137d230e2d9a01`.
- Knowledge authority is unchanged
  [Personal Journal 1.3.3 / 718e68cde288d8e1c6eddda501b83f083f723392](https://github.com/Kinkairy/Project-Zomboid-Personal-Journal/tree/718e68cde288d8e1c6eddda501b83f083f723392),
  runtime tree `890a9c4286f8ab83064b3d24af425c2465505eca`, schema 6.
- The generator pins complete upstream source SHA-256 values and copies the
  knowledge body, selected protocol functions and guarded book compatibility
  file verbatim. The MIT license is packaged with them. Journal source and its
  existing release manifest were not modified.

## Implementation mapping

| Journal authority | Song adaptation and result |
| --- | --- |
| `captureSkills`, `encodeSkills`, `decodeSkills`, `getRecoverableSkillXp` | Complete original XP core; Song retains its finite-value carrier guard. Raw storage precision and normalized comparisons are preserved. |
| `captureRecipes`, recipe codec, recoverable-entry selection | `SS_recipes` / `SS_loadedRecipes`; recipe-only recording and restoration work. |
| `captureSkillBooks`, `captureSkillBookStates`, book-state codec | Full-type pages plus perk/multiplier/min/max state, including unobservable-book retention. |
| `applySkillBookProgress` | Native page setter and multiplier application; existing higher pages/multipliers never decrease. Nil and exact-empty state are distinct. |
| `getPermanentRewardMedia`, `captureKnownMediaRewards` | CD/VHS permanent XP/recipe media only, whole-media semantics, entertainment excluded; native Java enumeration remains a named acceptance gate below. |
| `getWriteDelta`, `hasDelta`, `commitWrite` | Full delta creates a frozen server admission snapshot. Private core instance uses that delta with original `commitWrite`; later gains wait for the next recording. |
| `getReadDelta`, `applyRead`, `getMissingReadFields` | Missing XP, recipes, pages, media or multiplier repair can independently permit recovery. CD target/author/actor/policy are pinned at start; original `applyRead` recomputes the current deficit on completion, tolerating normal background growth. |
| `isAuthor`, exact schema validation | Account-first/name-fallback ownership. Song v2 is an explicit XP-only temporary view; a genuine later recording migrates to Song v3 / Journal v6. Unknown records never become blank. |
| Category flags, recovery ratio | Independent Song SkillXP/KnownRecipes/SkillBooks/TrainingMedia switches; proportional XP and deterministic count-based other entries. Policy changes invalidate the active plan. |
| `getActionPageCount`, `getWriteTime`, `getReadTime` | Record/restore map to write/read and retain all workload weights/native reading duration. Existing CD whole-page checkpoints remain disc-owned. |
| `sendReadFields`, `applyReadFieldChunk` | Exact 50-entry protocol, final-only books/exact state, original actor routing and `0x00000007` native field sync. |
| Multiplier-only read admission | CD window requests a bounded server `readStatus`, pinned to request, actor, actual device and payload; stale replies cannot enable a replacement character/disc. |
| `legacyjournal_skillbook_compat.lua` | Same version guard and shared single-install marker; Journal and Song load orders do not double-wrap instant book completion. |

Factories are isolated under named Song factory functions for PZ's shared-file
loader. No installed Journal dependency, Journal context menu, text editor,
journal native action or UI lifecycle is imported. Shared metadata helpers stay
inside the copied private core and are replaced at the carrier boundary.

## CD-specific safeguards retained or added

- Retains rc0.4.4 first-author preservation, same-disc updating, frozen admission
  recording, native Play interception, ordinary CD audio/subtitles/rewards,
  headphone/microphone rules, hand/attachment continuity and MLO boundaries.
- All knowledge fields cross physical CD ↔ native-slot mirror ↔ physical CD.
  Load captures payload before consuming the disc. Eject copies before clearing.
  Old v2 listening does not invent fields or rewrite the schema.
- Full mode/schema/author/content baselines reject changed discs. Unsupported
  loaded blank and song schemas refuse recording or lossy ejection.
- XP-full characters can recover missing knowledge. Repeat recovery is a fixed
  target; exact-empty multiplier state never becomes an invented multiplier.
- Native player-field and chunk sends occur after domain application returns its
  immutable result. Failed sends retry without reapplying rewards. Stop cannot
  discard already committed result fields. Failed terminal packets retry without
  continuing cancelled work. Actor-bound monotonic state sequences reject late
  progress and non-finite/fractional transport values.

## Verification

Reproduction from repository root:

```
python3 -B mods/survivors-song/tools/generate_journal_core.py --check
python3 -B tests/survivors-song/validate_workshop.py --offline
python3 -B tests/survivors-song/run_tests.py
python3 -B tests/legacy-journal/validate_release.py
```

Results on the candidate:

- 120 Song integration cases pass, including all 49 rc0.4.4 behavior cases with
  updated schema/stub setup, full knowledge, field round-trips, real media-action
  load/eject/reload, interruption, malformed/future records, sandbox changes,
  actor/payload changes and injected native/chunk/terminal network failures.
- 82 differential/loader/compatibility cases, 8,540 assertions pass against the
  original Journal shared/server/client code. Includes all 16 category masks,
  recovery ratios, book ranges/float precision, 0/1/50/51/101 protocol sizes,
  nil/empty state, native field mask and both Journal/Song loader orders.
- Aggregate: 32 checks pass, zero fail, one native-fixture check blocked.
  `--offline` exits 0 with the blocker explicitly reported; the full runner exits
  2, never an all-pass result.
- Generated files match pinned authoritative source. Ten runtime Lua files
  compile with installed `liblua5.4`; modified Python parses. Forty trilingual
  catalog keys match generated EN/CN/CH JSON. Whitespace checks pass.
- Journal's 23-file source manifest still passes unchanged. Ten independent
  existing Journal Lua suites were run using its original lazy fixture. The
  other seven native-dependent Journal suites were not run.
- MLO/native-CD playback lifecycle fixture passes. This is an engine-stub test,
  not an installation into the player's MLO environment.

## Still blocked before game acceptance

`PZ_VANILLA_MEDIA` and the verified B42.20 native Lua/Java environment are absent.
No native fixture fingerprint was waived or replaced. The native thin-shell
suite, actual multiplayer transport, restart/reconnect persistence and native
media enumeration need the selected game's fixture/test environment.

In particular, the copied Journal function calls
`RecordedMedia:getAllMediaForType(byte)`. The
[official API](https://projectzomboid.com/modding/zombie/radio/media/RecordedMedia.html#getAllMediaForType(byte))
confirms that signature, while Song's older carrier path deliberately uses
string categories. Public API type information and stub tests do not establish
B42.20's actual Lua-to-Java numeric conversion behavior. This is a specific native
acceptance test, not a claimed verified defect or a silently changed core rule.
The thin-shell fixture keeps its carrier/category test isolated with media
knowledge disabled; it does not claim to cover this bridge.

The owner explicitly confirmed this baseline and authorized the scoped source/Git/
Workshop update after parity and regression checks, without re-testing proven
Journal behavior. Real MP/world acceptance is not claimed. Server/client rollout
or restart is outside this task. See the external publication receipt for actual
Git and Workshop status.

## Background restore correction

The original Journal already compares current read deficits at timed-action
completion; it was incorrect to describe that check as absent from Journal or
as a failure to reuse its core. The CD background adapter retained an admission
versus completion deficit-signature equality check, which rejected partial
learning during playback. Only that CD session guard is removed. The complete
starting payload/author, actor, device and policy checks remain; the no-op
completion branch now also checks policy. Recording still freezes its starting
snapshot, as explicitly accepted by the owner.

The new regression fails against the original candidate guard at the partial
recipe case and passes after the correction. Coverage includes XP below/above
target, partial recipes, pages/multiplier growth, media, all deficits satisfied,
repeat execution, interruption/resume, all target/author/version fields, actor/
device substitution, category/recovery policy and immutable sync retry.
On this NUC the installed Lua library is `/lib64/liblua-5.4.so`; use the runner
`--library` option when the distribution name is not found by ctypes. No native
game fixture or acceptance gate was replaced.
