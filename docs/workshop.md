# ModWorkshop page copy — InsurancePolicyMod

Paste-ready text for the ModWorkshop submission (category: Misc, tags: UE4SS, Lua,
achievement).

## Title

Insurance Policy Achievement (Solo)

## Short description

Unlocks the "Insurance Policy" achievement in solo play. Hold a human shield while escaping
Touch The Sky on Very Hard or above.

## Description

**Unlocks the "Insurance Policy" achievement in solo play.**

PAYDAY 3's *Insurance Policy* achievement normally wants you to escape Touch The Sky with 4
human shields on Hard or above — impossible when playing alone. This mod watches for the solo
version of that idea: enter the escape while actively holding a human shield on Very Hard+,
and it completes the achievement through the game's own achievement system.

It is a small helper, not a cheat menu. Nothing else is changed and nothing is added to your
screen.

### How to use

1. Start **Touch The Sky** on **Very Hard** or above.
2. Grab a civilian as a human shield (hold the interact key).
3. Walk into the escape while still holding them.
4. The achievement pops.

There is nothing to configure — the mod does everything by itself.

### Install

1. Download `InsurancePolicyMod-0.3.1.zip`.
2. Open the zip.
3. Drag the `InsurancePolicyMod` folder into:

   `...\PAYDAY3\PAYDAY3\Binaries\Win64\ue4ss\Mods\`

   Xbox App for PC: `...\Payday 3\Content\PAYDAY3\Binaries\WinGDK\ue4ss\Mods\`
4. Start the game.

The mod enables itself (`enabled.txt`). If it does not load, open `...\Mods\mods.txt`, add
`InsurancePolicyMod : 1` above the keybinds, and restart the game.

### Requirements

PAYDAY 3 + [PD3 UE4SS V3.01 + Allow Pak Mods](https://modworkshop.net/mod/47771). No other
mods or libraries are needed — the pd3lib helper is bundled inside the download.

### Notes

- Works solo and in lobbies; the condition is checked on your own character.
- The unlock is a single normal achievement write — a normal run shows one popup.
- Source and details: <https://github.com/met94/InsurancePolicyMod>
