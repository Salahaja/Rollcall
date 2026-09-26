--[[
    test_history.lua - the loot history: what is kept, where it dropped,
    finding it again, and telling people. Offline.

    Usage (from the addon folder):
        lua tools/test_history.lua
--]]

local T = dofile("tools/harness.lua")

-- AtlasLoot's own tables, in the shape its Turtle WoW edition keeps them.
AtlasLoot_TableNames = {
  SCHRattlegore = { "Rattlegore", "AtlasLootItems", "|cffFFFFFF[58-60]|r Scholomance" },
  SCHTrash = { "Trash Mobs", "AtlasLootItems", "|cffFFFFFF[58-60]|r Scholomance" },
  STRATBaron = { "Baron Rivendare", "AtlasLootItems", "|cffFFFFFF[58-60]|r Stratholme" },
  WBAzuregos = { "Azuregos", "AtlasLootWBItems", "Azshara" },
  CraftAxe = { "Blacksmithing", "AtlasLootCrafting", "" },
}
AtlasLoot_Data = {
  AtlasLootItems = {
    SCHRattlegore = { { 10001, "icon", "=q2=Scaled Shroud", "=ds=", "20%" }, { 0, "", "", "" } },
    SCHTrash = { { 10002, "icon", "=q2=Soft Leather Boots", "=ds=", "1%" },
                 { 10006, "icon", "=q2=Heavy Kite Shield", "=ds=", "1%" } },
    STRATBaron = { { 10006, "icon", "=q2=Heavy Kite Shield", "=ds=", "10%" },
                   { 10004, "icon", "=q2=Walnut Wand", "=ds=", "10%" } },
  },
  AtlasLootWBItems = { WBAzuregos = { { 10008, "icon", "=q4=Bonecrusher", "=ds=", "5%" } } },
  AtlasLootCrafting = { CraftAxe = { { 10007, "icon", "=q2=Hardened Axe", "=ds=" } } },
}

T.load()
local W, RC, H = T.W, Rollcall, Rollcall.history
local check, said, line, link, chat = T.check, T.said, T.line, T.link, T.chat

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

-- A whole roll through Blizzard's window, as a party plays it out.
local function shroudRoll(id)
  T.startRoll(id, 10001)
  local _, i = T.windowFor(id)
  chat(said(LOOT_ROLL_NEED, "Tank", 10001))
  chat(said(LOOT_ROLL_NEED, "Bob", 10001))
  chat(said(LOOT_ROLL_GREED, "Heals", 10001))
  chat(said(LOOT_ROLL_PASSED, "Sneak", 10001))
  T.click(i, "GreedButton")
  chat(line(LOOT_ROLL_ROLLED_NEED, { 87 }, 10001, { "Bob" }))
  chat(line(LOOT_ROLL_ROLLED_NEED, { 55 }, 10001, { "Tank" }))
  chat(said(LOOT_ROLL_WON, "Bob", 10001))
end

print("\nRollcall: the loot history\n")

----------------------------------------------------------------------
print("what is kept")
----------------------------------------------------------------------
do
  T.reset()
  T.startRoll(1, 10001)
  chat(said(LOOT_ROLL_NEED, "Tank", 10001))
  chat(line(LOOT_ROLL_ROLLED_NEED, { 55 }, 10001, { "Tank" }))
  check("nothing is kept while the roll is still going", table.getn(RollcallDB.history), 0)

  T.reset()
  shroudRoll(1)
  local e = last()
  check("a won roll is kept", table.getn(RollcallDB.history), 1)
  check("  with its winner", e.w, "Bob")
  check("  how they won", e.wc .. " " .. e.wr, "N 87")
  check("  and their class", e.wk, "MAGE")
  check("the boss it drops from, by AtlasLoot", e.k .. "/" .. e.b .. "/" .. e.pl,
    "boss/Rattlegore/Scholomance")
  check("where it dropped", e.z, "Scholomance")
  check("the item's own link", e.l, link(10001))
  check("  and its name", e.n, "Scaled Shroud")
  check("a Need its class can't use is remembered", e.x, 1)
  local tank = pickOf(e, "Tank")
  check("everyone's pick and number: Tank", tank.choice .. " " .. tank.roll, "NEED 55")
  check("  Bob's can't-use with it", pickOf(e, "Bob").cannot, "Mail")
  check("  your own pick", pickOf(e, "Tester").choice, "GREED")
  check("  a pass", pickOf(e, "Sneak").choice, "PASS")
  T.startRoll(2, 10003)
  check("a finished roll is kept once", table.getn(RollcallDB.history), 1)

  -- Nobody wanted it.
  T.reset()
  T.startRoll(3, 10002)
  chat(said(LOOT_ROLL_PASSED, "Tank", 10002))
  T.click(1, "PassButton")
  chat(said(LOOT_ROLL_ALL_PASSED, nil, 10002))
  e = last()
  check("everyone passing is kept too", e.s, "passed")
  check("  with no winner", e.w, nil)
  check("trash is trash, by AtlasLoot", e.k .. "/" .. tostring(e.b) .. "/" .. e.pl,
    "trash/nil/Scholomance")

  -- You won.
  T.reset()
  T.startRoll(4, 10003)
  chat(said(LOOT_ROLL_GREED, "Tank", 10003))
  T.click(1, "RollButton")
  chat(line(LOOT_ROLL_ROLLED_NEED_SELF, { 42 }, 10003))
  chat(said(LOOT_ROLL_YOU_WON, nil, 10003))
  e = last()
  check("you winning is kept under your name", e.w, "Tester")
  check("  with your roll", e.wr, 42)
  check("an item on no loot table is a world drop", e.k, "world")

  -- A plain "rolls a" line still lands on the pick it belongs to.
  T.reset()
  T.startRoll(5, 10003)
  chat(said(LOOT_ROLL_GREED, "Heals", 10003))
  chat(line(LOOT_ROLL_ROLLED, { "Heals", 33 }, 10003))
  chat(said(LOOT_ROLL_WON, "Heals", 10003))
  check("a roll line without Need or Greed still counts", last().wc .. " " .. last().wr, "G 33")
end

----------------------------------------------------------------------
print("with Detailed Loot Information off")
----------------------------------------------------------------------
do
  -- The game then says only who won, and how, in one line.
  T.reset()
  chat(T.wonQuietly("Heals", 10004, "GREED", 77))
  local e = last()
  check("the winner line alone is kept", e.w .. " " .. e.wc .. " " .. e.wr, "Heals G 77")
  check("  its boss found even from another dungeon", e.k .. "/" .. e.b .. "/" .. e.pl,
    "boss/Baron Rivendare/Stratholme")
  chat(T.wonQuietly(nil, 10007, "NEED", 12))
  e = last()
  check("  and your own win", e.w .. " " .. e.wc .. " " .. e.wr, "Tester N 12")
  check("a crafted item is nobody's loot", e.k, "world")
  chat(T.wonQuietly("Tank", 10008, "NEED", 99))
  check("a world boss's loot is a boss's", last().k .. "/" .. last().b, "boss/Azuregos")
end

----------------------------------------------------------------------
print("rolls you had no window for")
----------------------------------------------------------------------
do
  T.reset()
  chat(said(LOOT_ROLL_NEED, "Tank", 10006))
  chat(said(LOOT_ROLL_GREED, "Heals", 10006))
  chat(line(LOOT_ROLL_ROLLED_NEED, { 5 }, 10006, { "Tank" }))
  chat(said(LOOT_ROLL_WON, "Tank", 10006))
  local e = last()
  check("a roll you were not in is kept", e.w .. " " .. e.wr, "Tank 5")
  check("  with every pick", table.getn(H.Unpack(e.p)), 2)
  check("dropped in Scholomance, this shield is its trash", e.k, "trash")

  W.zone = "Stratholme"
  chat(said(LOOT_ROLL_NEED, "Tank", 10006))
  chat(said(LOOT_ROLL_WON, "Tank", 10006))
  e = last()
  check("the same shield in Stratholme is the Baron's", e.k .. "/" .. e.b, "boss/Baron Rivendare")
end

----------------------------------------------------------------------
print("the same item up twice")
----------------------------------------------------------------------
local function twoBoots()
  T.reset()
  T.startRoll(11, 10002)
  T.startRoll(12, 10002)
  chat(said(LOOT_ROLL_NEED, "Tank", 10002))    -- the first roll
  chat(said(LOOT_ROLL_GREED, "Tank", 10002))   -- the second
  chat(said(LOOT_ROLL_GREED, "Heals", 10002))  -- the first
  chat(said(LOOT_ROLL_GREED, "Heals", 10002))  -- the second
end
do
  -- The first settles first: Tank needed there, so only Need is rolled.
  twoBoots()
  chat(line(LOOT_ROLL_ROLLED_NEED, { 60 }, 10002, { "Tank" }))
  chat(said(LOOT_ROLL_WON, "Tank", 10002))
  chat(line(LOOT_ROLL_ROLLED_GREED, { 30 }, 10002, { "Tank" }))
  chat(line(LOOT_ROLL_ROLLED_GREED, { 90 }, 10002, { "Heals" }))
  chat(said(LOOT_ROLL_WON, "Heals", 10002))
  local h = RollcallDB.history
  check("two copies, two rolls kept", table.getn(h), 2)
  check("  the first to Tank on Need", h[1].w .. " " .. h[1].wc .. " " .. h[1].wr, "Tank N 60")
  check("  the second to Heals on Greed", h[2].w .. " " .. h[2].wc .. " " .. h[2].wr, "Heals G 90")
  check("  each with its own numbers", pickOf(h[2], "Tank").roll .. "/" .. pickOf(h[1], "Tank").roll,
    "30/60")

  -- The second settles first. Heals greeded both; the roll already under
  -- way is the one being settled.
  twoBoots()
  chat(line(LOOT_ROLL_ROLLED_GREED, { 30 }, 10002, { "Tank" }))
  chat(line(LOOT_ROLL_ROLLED_GREED, { 90 }, 10002, { "Heals" }))
  chat(said(LOOT_ROLL_WON, "Heals", 10002))
  chat(line(LOOT_ROLL_ROLLED_NEED, { 60 }, 10002, { "Tank" }))
  chat(said(LOOT_ROLL_WON, "Tank", 10002))
  h = RollcallDB.history
  check("settled the other way round, each win still lands on its roll",
    h[1].w .. " " .. h[1].wc .. " " .. h[1].wr .. " / " .. h[2].w .. " " .. h[2].wc .. " " .. h[2].wr,
    "Heals G 90 / Tank N 60")
  check("  a shared player's number goes to the roll under way",
    tostring(pickOf(h[1], "Heals").roll) .. "/" .. tostring(pickOf(h[2], "Heals").roll), "90/nil")
  check("  and a Greed number goes to a Greed pick", pickOf(h[1], "Tank").choice .. " " ..
    tostring(pickOf(h[1], "Tank").roll), "GREED 30")
end

----------------------------------------------------------------------
print("rolls that never finish")
----------------------------------------------------------------------
do
  T.reset()
  T.startRoll(21, 10003, 10)
  chat(said(LOOT_ROLL_NEED, "Tank", 10003))
  T.advance(10 + RC.GRACE + RC.RESULT_WAIT + 1)
  T.startRoll(22, 10004)
  check("a roll that never finished is kept with what it had", last().s, "open")
  check("  saying so", H.Outcome(last()), "no winner seen")

  T.reset()
  T.startRoll(23, 10003)
  chat(said(LOOT_ROLL_GREED, "Tank", 10003))
  T.fire("PLAYER_LOGOUT")
  check("logging out keeps a roll still waiting for its winner", last() and last().s, "open")

  T.reset()
  T.startRoll(24, 10003, 10)
  T.advance(60)
  T.startRoll(25, 10004)
  check("a roll nobody picked on leaves nothing behind", table.getn(RollcallDB.history), 0)
end

----------------------------------------------------------------------
print("keeping it small")
----------------------------------------------------------------------
do
  T.reset()
  RollcallDB.maxHistory = 5
  local first = RollcallDB.nextId
  for n = 1, 7 do chat(T.wonQuietly("Tank", 10003, "NEED", n)) end
  check("the history keeps its limit", table.getn(RollcallDB.history), 5)
  check("  dropping the oldest", RollcallDB.history[1].wr, 3)
  check("  and numbers keep counting", RollcallDB.history[5].id, first + 6)
  RollcallDB.maxHistory = nil

  local picks = { { name = "Bob", choice = "NEED", roll = 87, class = "MAGE", cannot = "Mail" },
                  { name = "Sneak", choice = "PASS" }, { name = "Odd", choice = "?", roll = 3 } }
  local back = H.Unpack(H.Pack(picks))
  check("packed picks come back whole",
    back[1].name .. back[1].choice .. back[1].roll .. back[1].class .. back[1].cannot, "BobNEED87MAGEMail")
  check("  empty fields stay empty",
    tostring(back[2].roll) .. tostring(back[2].class) .. tostring(back[2].cannot), "nilnilnil")
  check("  an unknown choice stays unknown", back[3].choice .. back[3].roll, "?3")
end

----------------------------------------------------------------------
print("finding it")
----------------------------------------------------------------------
do
  T.reset()
  chat(T.wonQuietly("Bob", 10001, "NEED", 87))                 -- Rattlegore's
  chat(said(LOOT_ROLL_GREED, "Heals", 10002))
  chat(said(LOOT_ROLL_NEED, "Sneak", 10002))
  chat(T.wonQuietly("Sneak", 10002, "NEED", 5))                -- trash
  chat(T.wonQuietly(nil, 10003, "GREED", 20))                  -- a world drop
  check("Bosses shows boss loot only", table.getn(H:List("boss")), 1)
  check("Trash shows trash and world drops", table.getn(H:List("trash")), 2)
  check("All shows everything, newest first", H:List("all")[1].n, "Plain Robe")
  check("search finds an item in any case", H:List("all", "SHROUD")[1].w, "Bob")
  check("  a winner", table.getn(H:List("all", "sneak")), 1)
  check("  a boss", H:List("all", "rattle")[1].n, "Scaled Shroud")
  check("  anyone who rolled on it", H:List("all", "heals")[1].n, "Soft Leather Boots")
  check("  and nothing for nonsense", table.getn(H:List("all", "zzz")), 0)
end

----------------------------------------------------------------------
print("telling people")
----------------------------------------------------------------------
do
  T.reset()
  shroudRoll(1)
  local e = last()
  local out = H.ChatLines(e, false)
  check("one line: the item, its boss and who won", T.plain(out[1]),
    "[Scaled Shroud] from Rattlegore - won by Bob (Need 87)")
  check("  the item a real link", string.find(out[1], link(10001), 1, true), 1)
  out = H.ChatLines(e, true)
  check("with rolls: everyone's picks after it", out[2],
    "Need: Tank 55, Bob 87 (can't use Mail); Greed: Heals, Tester; Pass: Sneak")
  local clean = true
  for i = 1, table.getn(out) do
    local rest = string.gsub(out[i], "|c%x%x%x%x%x%x%x%x|Hitem:[%d:]+|h%[[^%]]*%]|h|r", "")
    if string.find(rest, "|", 1, true) then clean = false end
  end
  check("no '|' goes out but the link's own", clean, true)

  -- Sent a line at a time, so a long list cannot get you muted.
  W.said = {}
  check("announcing queues its lines", H:Announce({ e }, "party", nil, true), 2)
  T.tick(RollcallSender, 0.05)
  check("  the first goes at once", table.getn(W.said), 1)
  T.tick(RollcallSender, 0.2)
  check("  the next only after a pause", table.getn(W.said), 1)
  T.tick(RollcallSender, 0.5)
  check("  then the rest", table.getn(W.said), 2)
  check("  to the party", W.said[1].chat, "PARTY")

  W.said, W.chat = {}, {}
  check("not in a raid, nothing goes to raid", H:Announce({ e }, "raid"), 0)
  check("  and it says why", T.chatHas("you are not in a raid"), true)
  check("a whisper needs a name", H:Announce({ e }, "whisper", ""), 0)
  H:Announce({ e }, "whisper", "Asker")
  T.tick(RollcallSender, 1)
  check("  and goes to it", W.said[1] and (W.said[1].chat .. " " .. W.said[1].target), "WHISPER Asker")
  W.guild = false
  check("no guild, no guild chat", H:Announce({ e }, "guild"), 0)
  W.guild = true

  -- A raid's worth of rolls splits across lines, none too long.
  local many = {}
  for n = 1, 40 do table.insert(many, { name = "Raider" .. n, choice = "GREED", roll = n }) end
  local big = { n = "Plain Robe", l = link(10003), k = "world", s = "won", w = "Raider40",
                wc = "G", wr = 40, p = H.Pack(many) }
  out = H.ChatLines(big, true)
  local longest, names = 0, 0
  for i = 1, table.getn(out) do
    if string.len(out[i]) > longest then longest = string.len(out[i]) end
    if i > 1 then
      for _ in string.gmatch(out[i], "Raider%d+") do names = names + 1 end
    end
  end
  check("a raid's rolls take several lines", table.getn(out) > 2, true)
  check("  none too long for one chat message", longest <= 255, true)
  check("  and every name makes it", names, 40)
end

----------------------------------------------------------------------
print("/rollcall commands")
----------------------------------------------------------------------
do
  T.reset()
  chat(T.wonQuietly("Bob", 10001, "NEED", 87))
  local id = last().id
  chat(T.wonQuietly("Tank", 10002, "NEED", 5))
  W.chat = {}
  SlashCmdList["ROLLCALL"]("find shroud")
  check("/rollcall find lists matches by number",
    T.chatHas("#" .. id .. " [Scaled Shroud] - won by Bob (Need 87)"), true)
  SlashCmdList["ROLLCALL"]("find zzz")
  check("  and says when nothing matches", T.chatHas("nothing matches \"zzz\""), true)

  W.said = {}
  SlashCmdList["ROLLCALL"]("report " .. id .. " party")
  T.tick(RollcallSender, 1)
  check("/rollcall report posts it", W.said[1] and T.plain(W.said[1].text),
    "[Scaled Shroud] from Rattlegore - won by Bob (Need 87)")
  SlashCmdList["ROLLCALL"]("report #" .. id .. " w Asker rolls")
  T.tick(RollcallSender, 2)
  check("  or whispers it, with the rolls", table.getn(W.said) .. " " .. W.said[3].target .. " " ..
    W.said[3].text, "3 Asker Need: Bob 87 (can't use Mail)")
  W.chat = {}
  SlashCmdList["ROLLCALL"]("report 999 party")
  check("  and says when there is no such roll", T.chatHas("no roll #999"), true)
  SlashCmdList["ROLLCALL"]("report party")
  check("  or no number at all", T.chatHas("which roll?"), true)

  W.chat = {}
  SlashCmdList["ROLLCALL"]("last")
  check("/rollcall last shows the newest", T.chatHas("[Soft Leather Boots] - won by Tank (Need 5)"), true)
  SlashCmdList["ROLLCALL"]("last raid")
  check("  and posts it where you say", T.chatHas("you are not in a raid"), true)

  SlashCmdList["ROLLCALL"]("history clear")
  check("clearing asks first", W.popups[1] and W.popups[1].which .. " " .. W.popups[1].arg,
    "ROLLCALL_CLEAR_HISTORY 2")
  check("  and has not cleared yet", table.getn(RollcallDB.history), 2)
  StaticPopupDialogs["ROLLCALL_CLEAR_HISTORY"].OnAccept()
  check("  until you say yes", table.getn(RollcallDB.history), 0)
end

----------------------------------------------------------------------
print("the window")
----------------------------------------------------------------------
do
  T.reset()
  for n = 1, 12 do chat(T.wonQuietly("Tank", 10001, "NEED", n)) end   -- Rattlegore's
  for n = 21, 23 do chat(T.wonQuietly("Tank", 10002, "NEED", n)) end  -- trash
  T.fire("CHAT_MSG_WHISPER", "who got the shroud?", "Asker")

  SlashCmdList["ROLLCALL"]("history")
  local F = H.window
  check("/rollcall history opens it", RollcallHistoryFrame:IsVisible(), true)
  check("  Escape closes it", T.has(UISpecialFrames, "RollcallHistoryFrame"), true)
  check("  on the Bosses tab", RollcallHistoryTab1._locked, true)
  check("  boss loot only, newest first", T.plain(RollcallHistoryRow1.item:GetText()) .. " " ..
    T.plain(RollcallHistoryRow1.outcome:GetText()), "[Scaled Shroud] Tank  Need 12")
  check("  where it dropped under it",
    string.find(RollcallHistoryRow1.sub:GetText(), "Rattlegore - Scholomance", 1, true), 1)
  check("  ten rows at a time", RollcallHistoryRow10:IsVisible(), true)
  check("  saying how many", RollcallHistoryFrame and F.range:GetText(), "1-10 of 12")
  check("whoever whispered you last is ready to answer", RollcallHistoryWhisperTo:GetText(), "Asker")

  T.wheel(RollcallHistoryList, -1)
  check("the mouse wheel scrolls a row", F.range:GetText(), "2-11 of 12")
  T.press(RollcallHistoryDown)
  check("  the arrow a page, never past the end", F.range:GetText(), "3-12 of 12")
  T.press(RollcallHistoryUp)
  check("  and back", F.range:GetText(), "1-10 of 12")

  T.press(RollcallHistoryTab2)
  check("Trash has the rest", RollcallHistoryRow3:IsVisible() and not RollcallHistoryRow4:IsVisible(),
    true)
  RollcallHistorySearch:SetText("zzz")
  check("search narrows it down", T.plain(F.empty:GetText()), "Nothing matches \"zzz\".")
  RollcallHistorySearch:SetText("")
  T.press(RollcallHistoryTab3)
  check("All has everything", F.range:GetText(), "1-10 of 15")

  -- Tick two and send them.
  T.press(RollcallHistoryRow1)
  T.press(RollcallHistoryRow2)
  check("clicking a row ticks it", RollcallHistoryRow1.tick:IsVisible(), true)
  check("  and counts it", F.picked:GetText(), "2 ticked")
  T.press(RollcallHistoryRow2)
  check("  again unticks it", F.picked:GetText(), "1 ticked")
  T.press(RollcallHistoryRow2)
  W.said = {}
  T.press(RollcallHistorySend1)
  T.tick(RollcallSender, 2)
  check("Party posts what is ticked, in the order it dropped",
    table.getn(W.said) .. " " .. T.plain(W.said[1].text),
    "2 [Soft Leather Boots] - won by Tank (Need 22)")
  W.said = {}
  T.press(RollcallHistoryWithRolls)
  T.press(RollcallHistorySend4)
  T.tick(RollcallSender, 3)
  check("Whisper answers whoever asked, with rolls when ticked",
    table.getn(W.said) .. " " .. W.said[1].chat .. " " .. W.said[1].target, "4 WHISPER Asker")
  T.press(RollcallHistoryClear)
  check("untick all", F.picked:GetText(), "0 ticked")
  W.chat = {}
  T.press(RollcallHistorySend2)
  check("sending with nothing ticked says so", T.chatHas("tick the rolls"), true)

  -- The breakdown on hover, a link on shift-click, try-on on ctrl-click.
  RollcallHistorySearch:SetText("shroud")
  local tip = T.enter(RollcallHistoryRow1)
  check("hovering shows the item", tip[1], "[Scaled Shroud]")
  check("  where it dropped", tip[2], "Rattlegore - Scholomance")
  check("  who won", tip[3], "won by Tank (Need 12)")
  check("  and every pick", tip[4], "Need  Tank 12")
  W.shift, W.editOpen = true, true
  T.press(RollcallHistoryRow1)
  check("shift-click links the item into chat", W.inserted[1], link(10001))
  check("  without ticking it", F.picked:GetText(), "0 ticked")
  W.shift, W.ctrl = false, true
  T.press(RollcallHistoryRow1)
  check("ctrl-click tries it on", W.dressed[1], link(10001))
  W.ctrl = false

  -- A roll that finishes while it is open shows up at once.
  RollcallHistorySearch:SetText("")
  chat(T.wonQuietly("Bob", 10008, "NEED", 99))
  check("a new roll appears at once", T.plain(RollcallHistoryRow1.item:GetText()), "[Bonecrusher]")

  T.press(RollcallHistoryClose)
  check("the close button closes it", RollcallHistoryFrame:IsVisible(), false)

  -- Without AtlasLoot there is nothing to sort by, and it says so.
  local saved = AtlasLoot_Data
  AtlasLoot_Data = nil
  F.kind = nil
  RollcallHistoryWhisperTo:SetText("")
  RC.lastWhisper = nil
  W.roster.target = { "Targetguy", "Mage", "MAGE" }
  SlashCmdList["ROLLCALL"]("history")
  check("without AtlasLoot it opens on All", RollcallHistoryTab3._locked, true)
  check("  with Bosses and Trash off", RollcallHistoryTab1:IsEnabled(), false)
  check("  saying why", F.note:GetText(), "Install AtlasLoot to sort boss loot from trash.")
  check("  and your target ready to whisper", RollcallHistoryWhisperTo:GetText(), "Targetguy")
  AtlasLoot_Data = saved
  SlashCmdList["ROLLCALL"]("history")
end

T.done()
