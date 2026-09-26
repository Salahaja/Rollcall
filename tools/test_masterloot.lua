--[[
    test_masterloot.lua - master loot: the master looter links an item,
    people /roll 100 (main spec), 99 (off spec) or 98 (transmog), and the
    item is handed out; all of it into the history. And the rarity a raid's
    history keeps. Offline.

    Usage (from the addon folder):
        lua tools/test_masterloot.lua
--]]

local T = dofile("tools/harness.lua")

-- Ragnaros's table, in the shape AtlasLoot's Turtle WoW edition keeps it.
AtlasLoot_TableNames = {
  MCRagnaros = { "Ragnaros", "AtlasLootItems", "|cffFFFFFF[60]|r Molten Core" },
}
AtlasLoot_Data = {
  AtlasLootItems = {
    MCRagnaros = { { 20001, "icon", "=q4=Onslaught Girdle", "=ds=", "20%" },
                   { 20003, "icon", "=q4=Choker of Enlightenment", "=ds=", "20%" } },
  },
}

T.load()
local W, RC, H = T.W, Rollcall, Rollcall.history
local check, link = T.check, T.link

local function count() return table.getn(RollcallDB.history) end
local function last()
  local h = RollcallDB.history
  return h[table.getn(h)]
end
local function pickOf(entry, name)
  local picks = H.Unpack(entry.p)
  for i = 1, table.getn(picks) do
    if picks[i].name == name then return picks[i] end
  end
end

--- A raid in Molten Core, Alice master looting.
local function raid()
  T.reset()
  W.roster.party = {}
  W.roster.raid = {
    { "Tester", "Warrior", "WARRIOR" }, { "Alice", "Priest", "PRIEST" },
    { "Bob", "Mage", "MAGE" }, { "Cara", "Warrior", "WARRIOR" }, { "Dan", "Rogue", "ROGUE" },
  }
  W.lootMethod, W.mlRaid, W.threshold = "master", 2, 2
  W.zone = "Molten Core"
end

local function rolls(name, roll, high)
  T.fire("CHAT_MSG_SYSTEM", string.format(RANDOM_ROLL_RESULT, name, roll, 1, high))
end
local function gets(name, id, n)
  if n then
    T.chat(string.format(LOOT_ITEM_MULTIPLE, name, link(id), n))
  else
    T.chat(string.format(LOOT_ITEM, name, link(id)))
  end
end
local function announce(msg, sender) T.fire("CHAT_MSG_RAID", msg, sender or "Alice") end

print("\nRollcall: master loot\n")

----------------------------------------------------------------------
print("a hand-out, with its rolls")
----------------------------------------------------------------------
do
  raid()
  announce(link(20003) .. " roll MS 100 / OS 99 / tmog 98")
  rolls("Bob", 87, 100)
  rolls("Cara", 95, 100)
  rolls("Dan", 60, 99)
  rolls("Tester", 40, 98)
  gets("Cara", 20003)
  local e = last()
  check("handing it out puts it in the history", count(), 1)
  check("  as a master-loot entry", e.s, "master")
  check("  to whoever got it", e.w, "Cara")
  check("  with the roll they won it with", e.wc .. " " .. tostring(e.wr), "M 95")
  check("  and who handed it out", e.ml, "Alice")
  check("  from the boss that drops it", e.k .. " " .. tostring(e.b), "boss Ragnaros")
  check("  everyone's roll, by its range", pickOf(e, "Bob").choice .. " " .. pickOf(e, "Bob").roll ..
    ", " .. pickOf(e, "Dan").choice .. " " .. pickOf(e, "Dan").roll .. ", " ..
    pickOf(e, "Tester").choice .. " " .. pickOf(e, "Tester").roll, "MS 87, OS 60, TMOG 40")
  check("  said as 'won by'", H.Outcome(e), "won by Cara (MS 95)")
  local lines = H.ChatLines(e, true)
  check("  announced with the rolls in main spec, off spec, transmog order",
    lines[2], "MS: Bob 87, Cara 95; OS: Dan 60; Tmog: Tester 40")
  check("  and on the Boss tab", table.getn(H:List("boss")), 1)
  check("  found by the master looter's name", table.getn(H:List("all", "alice")), 1)
end

----------------------------------------------------------------------
print("which rolls are for it")
----------------------------------------------------------------------
do
  raid()
  rolls("Bob", 12, 100)                         -- for whatever came before
  announce(link(20001))
  rolls("Cara", 70, 100)
  gets("Cara", 20001)
  check("rolls before the item was linked are not for it", pickOf(last(), "Bob"), nil)
  check("  the ones after are", pickOf(last(), "Cara").roll, 70)

  raid()
  announce(link(20001))
  rolls("Bob", 20, 100)
  rolls("Bob", 99, 100)
  gets("Bob", 20001)
  check("a second roll by the same player: the first stands", pickOf(last(), "Bob").roll, 20)
  check("  and it is noted", pickOf(last(), "Bob").again, 2)
  check("  in what is announced", string.find(H.ChatLines(last(), true)[2], "(rolled 2x)", 1, true) ~= nil, true)

  raid()
  rolls("Bob", 50, 50)                          -- a range that is not MS, OS or tmog
  rolls("Cara", 30, 1000)
  rolls("Dan", 5, 100)
  gets("Dan", 20001)
  check("rolls in other ranges are not loot rolls", pickOf(last(), "Bob") == nil and pickOf(last(), "Cara") == nil, true)

  raid()
  rolls("Bob", 44, 100)
  announce(link(20001), "Bob")                  -- not the master looter
  gets("Cara", 20001)
  check("raid chat from someone else does not start the rolls over", pickOf(last(), "Bob").roll, 44)

  raid()
  rolls("Bob", 44, 100)
  T.fire("CHAT_MSG_RAID_WARNING", link(20001) .. " now", "Raidlead")
  rolls("Dan", 81, 100)
  gets("Dan", 20001)
  check("a raid warning with the item starts them over, from anyone", pickOf(last(), "Bob"), nil)

  raid()
  announce(link(20001))
  rolls("Bob", 70, 100)
  gets("Cara", 20003)                           -- a different item, handed out first
  check("an item handed out while another is rolled for gets none of its rolls",
    pickOf(last(), "Bob"), nil)
  gets("Bob", 20001)
  check("  they stay for the item they were for", pickOf(last(), "Bob").roll, 70)
end

----------------------------------------------------------------------
print("given without the best roll, and copies")
----------------------------------------------------------------------
do
  raid()
  announce(link(20001))
  rolls("Bob", 90, 100)
  rolls("Cara", 60, 100)
  gets("Dan", 20001)                            -- Dan never rolled
  local e = last()
  check("given to someone who did not roll: 'given to'", H.Outcome(e), "given to Dan")
  check("  and whose roll was best is kept", e.top, "Bob")
  check("  their class, for the colour", e.wk, "ROGUE")

  raid()
  announce(link(20001))
  rolls("Cara", 91, 99)                         -- a higher number, but off spec
  rolls("Bob", 90, 100)
  gets("Bob", 20001)
  check("main spec beats a higher off-spec roll: nothing to note", last().top, nil)

  raid()
  announce(link(20002))
  rolls("Bob", 90, 100)
  rolls("Cara", 80, 100)
  rolls("Dan", 70, 100)
  gets("Bob", 20002)
  gets("Cara", 20002)                           -- the second copy
  local e2 = last()
  check("a second copy straight after goes by the same rolls", pickOf(e2, "Dan").roll, 70)
  check("  to the next in line: nothing to note", e2.top, nil)
  check("  won by", H.Outcome(e2), "won by Cara (MS 80)")
  gets("Bob", 20002)                            -- a third, to the one who has one
  check("  one to someone who already has a copy notes the best roll left",
    last().top, "Dan")
end

----------------------------------------------------------------------
print("what is not a hand-out")
----------------------------------------------------------------------
do
  -- A green looted while an epic is being rolled for: the raid keeps
  -- greens, but under the loot threshold nobody handed it out.
  raid()
  SlashCmdList["ROLLCALL"]("raid uncommon")
  W.threshold = 3
  announce(link(20001))
  rolls("Bob", 77, 100)
  gets("Dan", 10001)
  check("below the loot threshold is ordinary looting", count(), 0)
  gets("Bob", 20001)
  check("  and the rolls going on are still there", pickOf(last(), "Bob").roll, 77)

  raid()
  W.lootMethod = "group"
  rolls("Bob", 90, 100)
  gets("Bob", 20001)
  check("under group loot 'receives loot' adds nothing: the roll said it", count(), 0)

  raid()
  W.mlRaid = 1                                  -- you are the master looter
  announce(link(20001), "Tester")
  rolls("Bob", 12, 100)
  T.chat(string.format(LOOT_ITEM_SELF, link(20001)))
  check("handing one to yourself counts", last().w .. " " .. last().ml, "Tester Tester")
  check("  with its rolls", pickOf(last(), "Bob").roll, 12)

  raid()
  gets("Bob", 20002, 2)
  check("a stack keeps its size", last().c, 2)
  check("  and shows it", string.find(H.ItemText(last()), "x2$") ~= nil, true)
end

----------------------------------------------------------------------
print("a class that can't use it")
----------------------------------------------------------------------
do
  raid()
  announce(link(20001))
  rolls("Bob", 99, 100)                         -- a mage, main-specking plate
  rolls("Cara", 50, 100)
  gets("Cara", 20001)
  check("a main-spec roll a class can't use is flagged", pickOf(last(), "Bob").cannot, "Plate")
  check("  and the entry marked", last().x, 1)
  check("  and the best roll it would have been is not held against anyone",
    last().top, "Bob")
end

----------------------------------------------------------------------
print("what a raid keeps")
----------------------------------------------------------------------
do
  raid()
  gets("Bob", 10001)                            -- a green, handed out
  check("in a raid, below Rare is not kept, as it ships", count(), 0)
  SlashCmdList["ROLLCALL"]("raid uncommon")
  gets("Bob", 10001)
  check("  /rollcall raid uncommon keeps it", count(), 1)
  check("  and says so", T.chatHas("keeps Uncommon and better"), true)
  SlashCmdList["ROLLCALL"]("raid epic")
  gets("Bob", 20002)                            -- a rare
  check("/rollcall raid epic leaves the rares out", count(), 1)
  gets("Bob", 20001)
  check("  and keeps the epics", count(), 2)
  SlashCmdList["ROLLCALL"]("raid shiny")
  check("a word that is not a rarity says so", T.chatHas("not a rarity"), true)
  check("  and changes nothing", RollcallDB.raidQuality, 4)

  -- The game's own rolls obey it too.
  raid()
  W.lootMethod = "group"
  T.startRoll(1, 10001)
  T.chat(T.wonQuietly("Bob", 10001, "NEED", 50))
  check("a group-loot roll on a green in a raid is not kept at Rare", count(), 0)

  T.reset()                                     -- a party, not a raid
  T.startRoll(2, 10001)
  T.chat(T.wonQuietly("Bob", 10001, "NEED", 50))
  check("outside a raid, everything is kept as before", count(), 1)
end

----------------------------------------------------------------------
print("the window")
----------------------------------------------------------------------
do
  raid()
  announce(link(20003))
  rolls("Bob", 90, 100)
  rolls("Dan", 60, 99)
  gets("Dan", 20003)
  SlashCmdList["ROLLCALL"]("history")
  RollcallHistorySearch:SetText("choker")
  check("a hand-out shows who got it", T.plain(RollcallHistoryRow1.outcome:GetText()), "Dan  OS 60")
  local tip = T.enter(RollcallHistoryRow1)
  local all = table.concat(tip, "\n")
  check("hovering lists the rolls by main spec, off spec, transmog",
    string.find(all, "MS  Bob 90\nOS  Dan 60", 1, true) ~= nil, true)
  check("  says whose roll was best", string.find(all, "Best roll was Bob's", 1, true) ~= nil, true)
  check("  and who handed it out", string.find(all, "Master looter: Alice", 1, true) ~= nil, true)

  check("the rarity button shows what a raid keeps", T.plain(RollcallHistoryRaidRarity:GetText()), "Raid: Rare+")
  T.press(RollcallHistoryRaidRarity)
  check("  a click steps to the next", RollcallDB.raidQuality, 4)
  check("  and says so", T.plain(RollcallHistoryRaidRarity:GetText()), "Raid: Epic+")
  T.press(RollcallHistoryRaidRarity)
  T.press(RollcallHistoryRaidRarity)
  check("  round again after Legendary", RollcallDB.raidQuality, 2)
end

T.done()
