# Rollcall (v1.1.0)

See who picked **Need**, **Greed** and **Pass** on a roll before you pick yourself, right beside Blizzard's normal roll windows. Catch the mage needing on mail before you click.

And when someone asks later who won that thing, look it up: every roll is kept, **boss loot apart from trash**, and you can tick the ones you want and announce them to party, raid, guild or a whisper. **Master-looted raids** are kept too — everyone's `/roll`, main spec, off spec or transmog, and who the item went to.

For WoW 1.12 (vanilla, Turtle WoW, OctoWoW). AtlasLoot is optional; with it, the history can tell boss loot from trash.

## Install

Download `Rollcall-1.1.0.zip` from the [latest release](https://github.com/Salahaja/Rollcall/releases/latest) and extract it into `Interface\AddOns\`. You should end up with `Interface\AddOns\Rollcall\Rollcall.toc`.

Don't use the "Source code" zips. They extract to a folder named `Rollcall-1.1.0`, and the client won't load an addon whose folder name doesn't match its `.toc`.

OctoLauncher users can add it as a git addon: URL `https://github.com/Salahaja/Rollcall`, folder `Rollcall`, branch `main`.

**Fully restart the client afterwards.** Vanilla only looks for new addons at launch, so `/reload` won't find it. Then try `/rollcall test`.

## Beside the roll windows

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

## Loot history

Every finished roll is kept: the item, where it dropped, who picked what, everybody's roll, and who won. The last 500 are kept.

Open it with **`/rollcall history`**, or bind a key under *Key Bindings > Rollcall > Loot history*.

- **Bosses / Trash / All.** Where an item drops comes from AtlasLoot's own loot tables. An item on a boss's table is that boss's loot; one on a "Trash Mobs" table is trash; one on no table at all is a world drop, like the random greens. The window opens on **Bosses**, so the green junk stays out of the way. When an item is both, where it actually dropped decides. Without AtlasLoot everything is listed under All.
- **Search** for any part of the item, the winner, anyone who rolled, the boss or the dungeon.
- **Tick** the rolls you want, then **Party**, **Raid**, **Guild** or **Whisper**. The whisper box already holds whoever last whispered you (or your target), since that's usually who's asking. Tick *with everyone's rolls* to post the whole Need / Greed / Pass breakdown with the numbers.
- **Hover** a row for the full breakdown, **Shift-click** to link the item in chat, **Ctrl-click** to try it on.

What gets posted looks like this:

    [Scaled Shroud] from Rattlegore - won by Bob (Need 87)
    Need: Tank 55, Bob 87 (can't use Mail); Greed: Heals; Pass: Sneak

Lines go out one at a time, a moment apart, so a long announcement can't get you muted for spam.

### Master loot

Under master loot nothing is rolled through the game's windows: the master looter links an item, people `/roll`, and the item is handed out. Rollcall reads it the way a raid runs it:

- **`/roll 100` is main spec, `/roll 99` off spec, `/roll 98` transmog.** Other ranges aren't loot rolls and are left alone.
- **The master looter linking one item** in raid chat — or anyone's raid warning with one — starts that item's rolls afresh; whatever was rolled before was for something else.
- **Handing it out** ("Bob receives loot: [Item]") turns the rolls into a history entry: everyone's roll, who got it and with which, and who the master looter was.

It catches the usual things, too:

- **Rolled twice** for the same item: the first roll stands, and the entry says "(rolled 2x)".
- **Main spec on something their class can't use** — a mage's `/roll 100` on plate — is flagged, just as a Need would be.
- **Given to someone other than the best roll** — main spec over off spec over transmog, then the number — the entry says whose roll was best. Loot council and reserves do that on purpose; now it's written down either way.
- **A second copy** handed out straight after the first goes by the same rolls, to the next in line.

Items below the loot threshold are ordinary looting, not a hand-out, and never disturb the rolls going on.

    [Onslaught Girdle] from Ragnaros - won by Cara (MS 95)
    MS: Bob 87, Cara 95; OS: Dan 60; Tmog: Tester 40

### What a raid keeps

In a raid the history keeps **Rare and better** unless you say otherwise — a raid's greens are exactly the clutter you don't want to scroll past. Change it with **`/rollcall raid uncommon|rare|epic|legendary`**, or click the **Raid: Rare+** button at the top of the history window to step through them. It applies to master loot and the game's own rolls alike. Outside a raid every roll is kept, as before.

## How it works

With **Detailed Loot Information** on, the game prints a line for every pick as it happens ("Bob has selected Need for: [Item]"), every roll once they are thrown ("Need Roll - 87 for [Item] by Bob") and the winner ("Bob won: [Item]"). Rollcall reads those lines. Without that option the game says only who won, so Rollcall turns it on once at first login and tells you. If you turn it off again later, it leaves your choice alone and just reminds you. The history still records winners with it off.

The chat lines name the item, not the roll. When the same item is up twice, a pick goes to the older roll that player hasn't picked on yet, your own picks go exactly where you clicked, and each winner goes to the roll whose numbers were just announced.

## Commands

| Command | What it does |
| --- | --- |
| `/rollcall` | Status and help |
| `/rollcall history` | Open the loot history window (`/rollcall history clear` forgets it all, after asking) |
| `/rollcall find <text>` | List matching rolls in your chat, with their numbers |
| `/rollcall report <#> party\|raid\|guild\|w <name>` | Post rolls by number; add `rolls` for everyone's rolls |
| `/rollcall last [party\|raid\|guild\|w <name>]` | Show or post the most recent roll |
| `/rollcall test` | Put a pretend roll on a real window for 30 seconds, using one of your equipped items. Nothing you click on it reaches the server. |
| `/rollcall warn on\|off` | The chat line when someone Needs what their class can't use |
| `/rollcall detail` | Turn Detailed Loot Information back on |
| `/rollcall raid uncommon\|rare\|epic\|legendary` | What a raid's history keeps: that rarity and better (Rare as it ships) |

## Other addons

Anything that replaces Blizzard's roll windows hides the panels with them, like ShaguTweaks-mods' *Improved Roll Frames* or pfUI's roll frames; the history still works. Moving the windows (for example with MoveAnything) is fine: the panel follows, and switches to the left side near the screen's right edge.

## Development

    lua tools/vanilla_lint.lua Rollcall.lua History.lua HistoryFrame.lua   # 1.12 / Lua 5.0
    lua tools/test_rollcall.lua   # the panels, against Blizzard's own roll-window code
    lua tools/test_history.lua    # the history, sorting, search and announcing
    lua tools/test_masterloot.lua # master loot: /roll 100/99/98, hand-outs, the raid rarity
