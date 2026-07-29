# Battle Scrolls

Combat metrics tracking addon for The Elder Scrolls Online, with native gamepad UI. Runs on console and PC.

## Features

- **DPS Meter** - Real-time damage display with multiple designs (personal and group modes)
- **Combat Journal** - Browse past encounters with detailed breakdowns
- **Damage Tracking** - Per-target, per-ability breakdown with direct/DoT/crit analysis
- **Healing Tracking** - Healing done and received with source/target breakdown
- **Buff/Debuff Tracking** - Effect uptimes on player, group members, and bosses
- **Proc Tracking** - Monitor proc uptime and performance
- **Group DPS Sharing** - Share DPS data with group members (requires LibGroupBroadcast)

## Installation

### Console (PlayStation / Xbox)

1. In ESO, go to **Settings → Add-Ons → Browse Add-Ons**
2. Search for "Battle Scrolls"
3. Select and install

Dependencies (LibGroupBroadcast, LibAsync) are installed automatically.

### PC (Windows / Mac)

Download `BattleScrolls-<version>-PC.zip` from the
[releases page](https://github.com/vladislavsheludchenkov/BattleScrolls/releases)
and extract it into your AddOns folder:

| OS      | Path                                                                       |
| ------- | -------------------------------------------------------------------------- |
| Windows | `Documents\Elder Scrolls Online\live\AddOns\`                              |
| Mac     | `~/Documents/Elder Scrolls Online/live/AddOns/`                            |

You should end up with `AddOns/BattleScrolls/BattleScrolls.txt`.

**Dependencies are not installed automatically on PC.** Install both first:

- [LibGroupBroadcast](https://www.esoui.com/downloads/info3866-LibGroupBroadcast.html) (95 or newer)
- [LibAsync](https://www.esoui.com/downloads/info2211-LibAsync.html) (3.1.0 or newer)

Either the PC or the console download works — the client reads both `.txt` and
`.addon` manifests.

Optional: [LibHarvensAddonSettings](https://www.esoui.com/downloads/info1097-LibHarvensAddonSettings.html)
adds a Battle Scrolls entry to the standard addon settings panel.

#### Interface modes on PC

Both modes are supported.

- **Gamepad Mode** — identical to console, including the Journal entry in the
  gamepad main menu and the Battle Scrolls page on the character sheet.
- **Keyboard Mode** — a native mouse-driven window covering instances,
  encounters, the metrics tabs, the group comparison, Aggregate queries, and
  settings (via LibAddonMenu-2.0, under Settings → Addons).

Both are driven by the same recording and analysis code, so your history is
shared between them.

A few things are gamepad-only for now: sorting the group comparison table, and
the Aggregate options that need a multi-select dialog (choosing specific zones,
instances or boss names, and a custom day count). In keyboard mode, clicking an
Aggregate field cycles through its available options.

## Usage

### DPS Meter
The DPS meter appears automatically during combat. Configure via Journal settings:
- Toggle personal/group modes
- Choose from multiple visual designs
- Adjust position and scale

### Combat Journal
Access the Journal from the main menu, or on PC via the `/bs` chat command or a
key bound under **Controls → Battle Scrolls → Open Battle Scrolls**. Browse:
1. **Instances** - Combat sessions grouped by zone
2. **Encounters** - Individual fights within each instance
3. **Metrics** - Detailed damage, healing, and effect breakdowns

### Configuration
All settings are available in the Journal's Settings tab. On PC in keyboard
mode they appear under **Settings → Addons → Battle Scrolls** instead, which
needs [LibAddonMenu-2.0](https://www.esoui.com/downloads/info7-LibAddonMenu.html).

Settings cover:
- Recording options (zones, fight types)
- Effect tracking (buffs, debuffs)
- Memory management (storage limits)
- DPS meter appearance

## Supported Languages

- English, Russian - reviewed by native speakers
- German, French, Spanish, Japanese, Chinese - AI-generated

The PC-only strings (keybind name and the Gamepad Mode notices) are
AI-generated in every language, Russian included.

## Support

- **GitHub**: [Issues](https://github.com/vladislavsheludchenkov/BattleScrolls/issues)
- **Email**: v@sheludchenkov.com
- **Xbox EU**: @Semigroup1329

## License

MIT License - see [LICENSE](LICENSE) for details.

## Credits

**Author**: Semigroup1329

## Acknowledgements

- **Hodor Reflexes** by @andy.s and @m00nyONE - the "Hodor" group meter design is closely based on their work
- **Hodor Restyle** by Hyperioxes - the "Bars" group meter design is loosely inspired by this
- **LibCombat** by Solinur - ideas for solving some combat tracking edge cases (vSS/vCR portal handling)
- **Area Damage** [ability list](https://github.com/Shienar/AreaDamage) by Shienar - used for AoE vs ST breakdown
- **PotionMaker** by votan - alchemy trait translations sourced from [PotionMaker lang files](https://github.com/votan73/ESO/tree/master/Addons/PotionMaker/lang)
- **Dolgubon's Lazy Writ Crafter** by Dolgubon - alchemy effect ID mapping referenced from [Alchemy.lua](https://github.com/Dolgubon/DolgubonsLazyWritCreator)

---

*This Add-on is not created by, affiliated with, or sponsored by ZeniMax Media Inc. or its affiliates. The Elder Scrolls® and related logos are registered trademarks or trademarks of ZeniMax Media Inc. in the United States and/or other countries.*
