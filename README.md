# Rollcall (v1.0.0)

See who picked **Need**, **Greed** and **Pass** on a roll before you pick yourself, right beside Blizzard's normal roll windows. Catch the mage needing on mail before you click.

For WoW 1.12 (vanilla, Turtle WoW, OctoWoW). No other addons needed.

## Install

Download `Rollcall-1.0.0.zip` from the [latest release](https://github.com/Salahaja/Rollcall/releases/latest) and extract it into `Interface\AddOns\`. You should end up with `Interface\AddOns\Rollcall\Rollcall.toc`.

Don't use the "Source code" zips. They extract to a folder named `Rollcall-1.0.0`, and the client won't load an addon whose folder name doesn't match its `.toc`.

OctoLauncher users can add it as a git addon: URL `https://github.com/Salahaja/Rollcall`, folder `Rollcall`, branch `main`.

**Fully restart the client afterwards.** Vanilla only looks for new addons at launch, so `/reload` won't find it. Then try `/rollcall test`.

## What it shows

Blizzard's roll windows stay exactly as they are: same size, same place, same buttons. Rollcall adds three things:

- **A panel beside each window**, listing who has picked Need, Greed and Pass so far, in class colors. It updates the moment each person clicks.
- **A count on each of Blizzard's buttons.**
- **The full list in each button's tooltip**, under Blizzard's own "Need" / "Greed" / "Pass".

A **Need from a class that can never use the item** is shown in red, like *Bob (can't use)*, and Rollcall notes it in your chat, where only you can see it. It only judges what is certain for every class:

| Item | Can never use it |
| --- | --- |
| Leather | Mage, Priest, Warlock |
| Mail | Mage, Priest, Warlock, Druid, Rogue |
| Plate | everyone but Warrior and Paladin |
| Shields | everyone but Warrior, Paladin and Shaman |
| Librams / Idols / Totems | everyone but Paladin / Druid / Shaman |
| Wands | everyone but Mage, Priest and Warlock |
| Bows, guns, crossbows | everyone but Warrior, Hunter and Rogue |

Melee weapons are never judged, and neither is level: a level 30 hunter needing mail is saving it, not stealing it. A wrong accusation is worse than a missed one, and the class colors already give most of those away. The check works on English clients only; on other languages nobody is marked.

## How it works

With **Detailed Loot Information** on, the game prints a line for every pick as it happens, like "Bob has selected Need for: [Item]". Rollcall reads those lines. Without that option the game only says who won, so Rollcall turns it on once at first login and tells you. If you turn it off again later, it leaves your choice alone and just reminds you.

The chat line names the item, not the roll. When the same item is up twice, each pick goes to the older roll that player hasn't picked on yet, which fills both correctly.

## Commands

| Command | What it does |
| --- | --- |
| `/rollcall` | Status and help |
| `/rollcall test` | Put a pretend roll on a real window for 30 seconds, using one of your equipped items, to see how it looks. Nothing you click on it reaches the server. |
| `/rollcall warn on\|off` | The chat line when someone Needs what their class can't use |
| `/rollcall detail` | Turn Detailed Loot Information back on |

## Other addons

Anything that replaces Blizzard's roll windows hides Rollcall with them. That includes ShaguTweaks-mods' *Improved Roll Frames* and pfUI's roll frames. Moving the windows (for example with MoveAnything) is fine: the panel follows, and switches to the left side near the screen's right edge.

## Development

    lua tools/vanilla_lint.lua Rollcall.lua   # 1.12 / Lua 5.0 compatibility
    lua tools/test_rollcall.lua               # against Blizzard's own roll-window code
