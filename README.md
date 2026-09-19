# Survivor's Song

[简体中文](#简体中文) | [English](#english)

## 简体中文

Survivor's Song 是面向 Project Zomboid Build 42.20 的 CD 技能记录 Mod。

它复用原版 CD 播放器和原版 `Base.Disc_Retail`，不新增实体 CD 类型。普通音乐 CD 可以在 CD 机内擦除为空白盘；空白盘可记录角色技能 XP，之后由允许的角色通过同一台原版 CD 播放器恢复缺失 XP。

- 当前版本：`rc0.4`
- Mod ID：`SurvivorsSong`
- 目标版本：Project Zomboid Build 42.20
- 支持语言：简体中文、繁体中文、English
- 外部依赖：无

### 核心设计

- 普通 RecordedMedia CD 仍由原版播放、字幕、媒体奖励和 Play/Stop 逻辑负责。
- 擦除后的空白盘和录制后的歌曲盘仍是原版 `Base.Disc_Retail`。
- 空白/歌曲盘在 CD 机中仍占用原版 DeviceData 媒体槽；ModData 只保存空白/歌曲语义、技能数据和中断检查点。
- 录入需要：空白盘、CD 机开启且有电、已安装耳机/耳塞、角色携带原版麦克风。
- 恢复需要：歌曲盘、CD 机开启且有电、已安装耳机/耳塞；不需要麦克风。
- 录入/恢复使用服务器权威后台会话，不长期占用角色 TimedAction 队列，因此 CD 机可以像正常播放 CD 一样挂回角色附件位继续工作。
- 角色头顶进度条仍显示服务器权威的录入/听取进度；如果前台另有正常 TimedAction，该前台动作优先使用同一进度条，结束后后台 CD 进度重新显示。
- 麦克风、耳机/耳塞、电源、开关或合法手持/附件状态失效时，会保存当前整页检查点并结束本次会话；重新满足条件后按 Play 可从检查点继续。
- 检查点逻辑属于物理 CD：弹出后换到另一台 CD 机仍可继续。
- 歌曲 CD 保存并显示与 Personal Journal 1.3.2 相同格式的记录时间：`YYYY/MM/DD HH:MM`。
- 普通音乐 CD 可选延长为原版时长、30、60 或 120 游戏分钟。
- 普通音乐 CD 的增强听歌效果仅涉及无聊、不开心、压力、恐慌和愤怒；实际降低数值时会显示原版电视/广播风格的绿色向下提示。

### 仓库结构

```text
translations/catalog.json               三语文本源
workshop/Contents/mods/SurvivorsSong    Mod 运行源码
```

公开仓库不包含内部测试工具、服务器地址、私有部署流程、发布凭据或原始运行日志。

源码安装时，将 `workshop/Contents/mods/SurvivorsSong` 复制到 Project Zomboid Mods 目录。

这是非官方社区项目，与 The Indie Stone 无关联。项目采用 [MIT License](LICENSE)。

## English

Survivor's Song is a CD-based skill-recording mod for Project Zomboid Build 42.20.

It reuses the vanilla CD player and vanilla `Base.Disc_Retail` item. A normal music CD can be erased in the player, reused as a blank disc to record character skill XP, and later played through the same vanilla device to restore missing XP for an allowed character.

- Current version: `rc0.4`
- Mod ID: `SurvivorsSong`
- Target: Project Zomboid Build 42.20
- Languages: Simplified Chinese, Traditional Chinese, English
- External dependencies: none

### Core Design

- Normal RecordedMedia CDs remain owned by vanilla playback, subtitles, media rewards, and Play/Stop behavior.
- Erased blank discs and recorded song discs remain vanilla `Base.Disc_Retail` items.
- Blank/song discs still occupy the native DeviceData media slot; ModData stores Survivor's Song semantics, skill payload, and interruption checkpoint only.
- Recording requires a blank disc, powered/on CD player, installed headphones/earbuds, and a vanilla microphone carried by the character.
- Restore requires a recorded song, powered/on CD player, and installed headphones/earbuds; no microphone is required.
- Record/restore runs as a server-authoritative background session rather than a long character TimedAction, so the CD player can be stowed on a valid character attachment while the session continues.
- The character overhead progress bar displays authoritative background progress without blocking the normal TimedAction queue. Foreground TimedActions temporarily own that bar and the CD progress returns afterward.
- Losing any required condition—microphone while recording, headphones, usable power, turned-on state, or valid held/attached placement—saves the current whole-page checkpoint and ends the current session. Press Play again after restoring the requirements to continue from the saved checkpoint.
- The checkpoint logically follows the physical CD across eject/reinsert and across different CD players.
- Recorded song CDs show the Personal Journal 1.3.2-style game timestamp `YYYY/MM/DD HH:MM` in their tooltip.
- Normal music playback can use vanilla duration or extend to 30, 60, or 120 game minutes.
- Enhanced normal-CD listening effects are limited to boredom, unhappiness, stress, panic, and anger. A vanilla TV/radio-style green downward HaloText appears only when an enabled negative mood stat actually decreases.

### Repository Layout

```text
translations/catalog.json               Reviewed trilingual source catalog
workshop/Contents/mods/SurvivorsSong    Runtime source
```

The public repository excludes internal test harnesses, server addresses, private deployment workflows, publishing credentials, and raw runtime logs.

For source installation, copy `workshop/Contents/mods/SurvivorsSong` into the Project Zomboid Mods directory.

This is an unofficial community project and is not affiliated with The Indie Stone.
Licensed under the [MIT License](LICENSE).
