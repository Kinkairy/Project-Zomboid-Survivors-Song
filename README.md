# Survivor's Song

[简体中文](#简体中文) | [English](#english)

## 简体中文

Survivor's Song 是面向 Project Zomboid Build 42.20 的 CD 技能记录 Mod。

它复用原版 CD 播放器和原版 `Base.Disc_Retail`，不新增实体 CD 类型。普通音乐 CD 可以在 CD 机内擦除为空白盘；空白盘可记录角色技能 XP，之后由允许的角色通过同一台原版 CD 播放器恢复缺失 XP。

- 当前版本：`rc0.2`
- Mod ID：`SurvivorsSong`
- 目标版本：Project Zomboid Build 42.20
- 支持语言：简体中文、繁体中文、English
- 外部依赖：无

### 核心设计

- 普通 RecordedMedia CD 仍由原版播放、字幕、媒体奖励和 Play/Stop 逻辑负责。
- 擦除后的空白盘和录制后的歌曲盘仍是原版 `Base.Disc_Retail`。
- 空白/歌曲盘在 CD 机中仍占用原版 DeviceData 媒体槽；ModData 只保存空白/歌曲语义和技能数据。
- 录入需要：空白盘、CD 机开启且有电、已安装耳机/耳塞、角色携带原版麦克风。
- 恢复需要：歌曲盘、CD 机开启且有电、已安装耳机/耳塞；不需要麦克风。
- 多人模式以服务器动作完成为最终权威；客户端不直接提交技能结果。
- 普通音乐 CD 可选延长为原版时长、30、60 或 120 游戏分钟。
- 增强听歌效果仅涉及无聊、不开心、压力、恐慌和愤怒。

### 仓库结构

```text
docs/TECHNICAL_REFERENCE.md             技术参考
translations/catalog.json               三语文本源
workshop/Contents/mods/SurvivorsSong    Mod 运行源码
CHANGELOG.md                            公开变更记录
CONTRIBUTING.md                         贡献说明
SECURITY.md                             安全问题说明
```

公开仓库不包含内部测试工具、服务器地址、私有部署流程、发布凭据或原始运行日志。

源码安装时，将 `workshop/Contents/mods/SurvivorsSong` 复制到 Project Zomboid Mods 目录。

这是非官方社区项目，与 The Indie Stone 无关联。项目采用 [MIT License](LICENSE)。

## English

Survivor's Song is a CD-based skill-recording mod for Project Zomboid Build 42.20.

It reuses the vanilla CD player and vanilla `Base.Disc_Retail` item. A normal music CD can be erased in the player, reused as a blank disc to record character skill XP, and later played through the same vanilla device to restore missing XP for an allowed character.

- Current version: `rc0.2`
- Mod ID: `SurvivorsSong`
- Target: Project Zomboid Build 42.20
- Languages: Simplified Chinese, Traditional Chinese, English
- External dependencies: none

### Core Design

- Normal RecordedMedia CDs remain owned by vanilla playback, subtitles, media rewards, and Play/Stop behavior.
- Erased blank discs and recorded song discs remain vanilla `Base.Disc_Retail` items.
- Blank/song discs still occupy the native DeviceData media slot; ModData stores only Survivor's Song semantics and skill payload.
- Recording requires a blank disc, powered/on CD player, installed headphones/earbuds, and a vanilla microphone carried by the character.
- Restore requires a recorded song, powered/on CD player, and installed headphones/earbuds; no microphone is required.
- Multiplayer completion is server authoritative.
- Interrupted recording/restoring saves a server-authoritative whole-page checkpoint; pressing Play again resumes only the remaining duration.
- If a hotbar/equip/stow action targets the same CD player during recording/restoring, the knowledge action stops first, saves its checkpoint, and lets the normal shortcut continue.
- Normal music playback can use vanilla duration or extend to 30, 60, or 120 game minutes.
- Enhanced listening effects are limited to boredom, unhappiness, stress, panic, and anger.

### Repository Layout

```text
docs/TECHNICAL_REFERENCE.md             Technical reference
translations/catalog.json               Reviewed trilingual source catalog
workshop/Contents/mods/SurvivorsSong    Runtime source
CHANGELOG.md                            Public change history
CONTRIBUTING.md                         Contribution notes
SECURITY.md                             Security policy
```

The public repository excludes internal test harnesses, server addresses, private deployment workflows, publishing credentials, and raw runtime logs.

For source installation, copy `workshop/Contents/mods/SurvivorsSong` into the Project Zomboid Mods directory.

This is an unofficial community project and is not affiliated with The Indie Stone.
Licensed under the [MIT License](LICENSE).
