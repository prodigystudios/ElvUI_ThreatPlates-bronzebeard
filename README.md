# ElvUI Threat Plates

Lightweight ElvUI plugin for Wrath/Ascension that marks enemy NPC nameplates with a tank-threat indicator.

Instead of fighting ElvUI's built-in health coloring, this addon draws a separate border and optional overlay on the nameplate health bar. That makes the visual result more stable and avoids the flicker that can happen when multiple systems try to recolor the same status bar.

## What It Does

- Detects raid Main Tanks and colors enemy NPC nameplates based on which tank has threat.
- Uses class colors by default.
- Supports two custom tank colors.
- Can keep the player locked to Tank 1 when the player is one of the detected Main Tanks.
- Includes preview/test mode and quick appearance presets.
- Can be limited to group/raid play only.

## Requirements

- WoW client interface `30300`
- ElvUI enabled

## Installation

Place the addon folder in:

```text
Interface/AddOns/ElvUI_ThreatPlates
```

Then reload the UI or restart the client.

## Configuration

Open the ElvUI config and find the plugin under the Threat Plates section.

Current options include:

- Enable or disable the addon
- Auto-detect raid Main Tanks
- Restrict visuals to group/raid only
- Keep the player assigned as Tank 1
- Border thickness and opacity
- Overlay enable and opacity
- Quick presets: Subtle, Strong, Border Only, Overlay Only
- Two custom colors for Tank 1 and Tank 2

## Slash Commands

```text
/etp refresh
/etp enable
/etp disable
/etp automt
/etp preview
/etp debug
```

Aliases:

```text
/euitp
```

## Notes

- The addon is built around enemy NPC nameplates.
- Main Tank detection depends on raid Main Tank assignments.
- If custom colors are enabled, Tank 1 and Tank 2 use the configured custom colors instead of class colors.
- Preview mode shows the current style for a few seconds on visible plates.

## Version

Current TOC version: `1.3.0`