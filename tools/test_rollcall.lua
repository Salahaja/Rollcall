--[[
    test_rollcall.lua - the picks beside Blizzard's roll windows, offline.

    Usage (from the addon folder):
        lua tools/test_rollcall.lua

    Runs against tools/harness.lua: Blizzard's own roll-window code, and the
    client's habit of leaving `this` pointing at whatever script ran last.
--]]

local T = dofile("tools/harness.lua")
T.load()
local W, RC = T.W, Rollcall
local check, said, link = T.check, T.said, T.link
local chat, lines, windowFor, click = T.chat, T.lines, T.windowFor, T.click

print("\nRollcall: picks beside Blizzard's roll windows\n")

----------------------------------------------------------------------
print("reading the chat lines")
----------------------------------------------------------------------
do
  local ev = RC.ParseLine(said(LOOT_ROLL_NEED, "Bob", 10001))
  check("a Need line names the player", ev.name, "Bob")
  check("  and the pick", ev.kind .. "/" .. ev.choice, "pick/NEED")
  check("  and keeps the whole item link", ev.link, link(10001))
  ev = RC.ParseLine(said(LOOT_ROLL_GREED, "Heals", 10001))
  check("a Greed line", ev.choice, "GREED")
  ev = RC.ParseLine(said(LOOT_ROLL_PASSED, "Sneak", 10001))
  check("a Pass line", ev.name .. "/" .. ev.choice, "Sneak/PASS")
  ev = RC.ParseLine(said(LOOT_ROLL_ALL_PASSED, nil, 10001))
  check("everyone passing is nobody's pick", ev.kind .. "/" .. tostring(ev.name), "passed/nil")
  ev = RC.ParseLine(said(LOOT_ROLL_NEED_SELF, nil, 10001))
  check("your own pick is yours, by name", ev.name .. "/" .. ev.choice, "Tester/NEED")
  ev = RC.ParseLine(said(LOOT_ROLL_PASSED_SELF, nil, 10001))
  check("  your own pass too", ev.name .. "/" .. ev.choice, "Tester/PASS")
  check("who won is not a pick", RC.ParseLine(said(LOOT_ROLL_WON, "Bob", 10001)).kind, "won")
  -- Read now, for master loot; under group loot it adds nothing
  -- (test_masterloot.lua), because the roll's own winner line said it.
  check("getting loot is a 'got', not a pick or a roll",
    RC.ParseLine("You receive loot: " .. link(10003) .. ".").kind, "got")

  local key, id = RC.ItemKey(link(10001))
  check("an item is known by its full link", key, "item:10001:0:0:0")
  check("  and by its id", id, 10001)
  check("a link is taken exactly, and nothing around it",
    RC.CleanLink("junk " .. link(10001) .. " (Greed - 5)"), link(10001))

  -- A format with pattern characters in it must still match literally.
  local p = RC.Compile("50% off (%s) [x]. %s")
  local _, _, a, b = string.find("50% off (Bob) [x]. Tank", p)
  check("pattern characters in a format are matched as text", tostring(a) .. "/" .. tostring(b),
    "Bob/Tank")
end

----------------------------------------------------------------------
print("on Blizzard's window")
----------------------------------------------------------------------
do
  T.reset()
  T.startRoll(1, 10001)
  local host, i = windowFor(1)
  check("Blizzard's window opens as usual", host ~= nil, true)
  check("the panel sits beside it", T.panelShown(i), true)
  local need, greed, pass = lines(i)
  check("nothing picked yet reads as a dash", need, "Need  -")
  check("  for all three", greed .. "|" .. pass, "Greed  -|Pass  -")
  local point, rel, relPoint = _G["RollcallPanel" .. i]:GetPoint(1)
  check("on the window's right", tostring(point) .. ">" .. tostring(relPoint), "LEFT>RIGHT")
  check("  attached to Blizzard's window itself", rel, host)

  chat(said(LOOT_ROLL_NEED, "Tank", 10001))
  chat(said(LOOT_ROLL_GREED, "Heals", 10001))
  chat(said(LOOT_ROLL_PASSED, "Sneak", 10001))
  need, greed, pass = lines(i)
  check("a Need shows at once", need, "Need  Tank")
  check("a Greed", greed, "Greed  Heals")
  check("a Pass", pass, "Pass  Sneak")
  check("names are in class colors",
    string.find(_G["RollcallPanel" .. i].lines[1]:GetText(), "|cffc79c6eTank|r", 1, true) ~= nil, true)
  check("the Need button counts them", T.badge(i, "NEED"), "1")
  check("  the Greed button too", T.badge(i, "GREED"), "1")

  -- The ninja: a mage needing mail.
  W.chat = {}
  chat(said(LOOT_ROLL_NEED, "Bob", 10001))
  need = lines(i)
  check("a Need the class can never use is marked", need, "Need  Tank, Bob (can't use)")
  check("  in red", string.find(_G["RollcallPanel" .. i].lines[1]:GetText(),
    "|cffff2020Bob (can't use)|r", 1, true) ~= nil, true)
  check("  and said in your chat", T.chatHas("Bob (Mage) picked Need on [Scaled Shroud]"), true)
  check("  with the reason", T.chatHas("Mages can't use Mail"), true)
  check("the count goes up", T.badge(i, "NEED"), "2")

  -- Blizzard's own tooltip still comes first; the names follow it.
  local tip = T.hover(i, "RollButton")
  check("hovering Need keeps Blizzard's text", tip[1], "Need")
  check("  then lists who", T.has(tip, "Tank"), true)
  check("  with the reason in full", T.has(tip, "Bob (can't use Mail)"), true)
  check("hovering Greed lists Greed only", table.concat(T.hover(i, "GreedButton"), "|"), "Greed|Heals")
  check("hovering Pass lists Pass only", table.concat(T.hover(i, "PassButton"), "|"), "Pass|Sneak")

  -- A line can arrive twice; a player still picks once.
  chat(said(LOOT_ROLL_NEED, "Tank", 10001))
  check("the same pick twice counts once", T.badge(i, "NEED"), "2")

  -- Picks you are not in a roll for still warn you.
  W.chat = {}
  chat(said(LOOT_ROLL_NEED, "Bob", 10006))
  check("a ninja pick with no window of yours still warns", T.chatHas("Mages can't use Shields"), true)

  -- Once you pick, Blizzard hides the window, and the panel goes with it.
  W.chat = {}
  click(i, "GreedButton")
  check("your pick reaches the server", W.sent[1] and W.sent[1].type, 2)
  check("Blizzard's window closes", host:IsVisible(), false)
  check("  and the panel with it", T.panelShown(i), false)
  check("your own pick is kept with the others",
    RC.FindPick(RC.rolls[1], "Tester") and RC.FindPick(RC.rolls[1], "Tester").choice, "GREED")
  check("  and never warned about", table.getn(W.chat), 0)
end

----------------------------------------------------------------------
print("who can never use what")
----------------------------------------------------------------------
do
  T.reset()
  check("a mage can't use mail", RC.CannotUse("MAGE", "item:10001:0:0:0"), "Mail")
  check("a warrior can", RC.CannotUse("WARRIOR", "item:10001:0:0:0"), nil)
  check("a rogue can't use mail", RC.CannotUse("ROGUE", "item:10001:0:0:0"), "Mail")
  check("a shaman can (from 40, and saving it is fine)", RC.CannotUse("SHAMAN", "item:10001:0:0:0"), nil)
  check("cloth is anyone's", RC.CannotUse("WARRIOR", "item:10003:0:0:0"), nil)
  check("a hunter can't use a wand", RC.CannotUse("HUNTER", "item:10004:0:0:0"), "Wands")
  check("a mage can", RC.CannotUse("MAGE", "item:10004:0:0:0"), nil)
  check("a shaman can use a shield", RC.CannotUse("SHAMAN", "item:10006:0:0:0"), nil)
  check("a druid can't", RC.CannotUse("DRUID", "item:10006:0:0:0"), "Shields")
  check("melee weapons are never judged", RC.CannotUse("MAGE", "item:10007:0:0:0"), nil)
  check("nobody unknown is judged", RC.CannotUse(nil, "item:10001:0:0:0"), nil)

  -- On a client in another language the names would never match: no guessing.
  W.locale = "deDE"
  T.startRoll(2, 10001)
  local _, i = windowFor(2)
  W.chat = {}
  chat(said(LOOT_ROLL_NEED, "Bob", 10001))
  check("in another language nobody is marked", (lines(i)), "Need  Bob")
  check("  nor warned about", table.getn(W.chat), 0)

  -- Chat warnings can be turned off; the red mark stays.
  W.locale = "enUS"
  SlashCmdList["ROLLCALL"]("warn off")
  W.chat = {}
  chat(said(LOOT_ROLL_NEED, "Sneak", 10001))
  check("with warnings off, the panel still marks it", (lines(i)), "Need  Bob, Sneak (can't use)")
  check("  but chat stays quiet", table.getn(W.chat), 0)
  SlashCmdList["ROLLCALL"]("warn on")

  -- Your own Need is never reported to you, even on what you can't use.
  T.startRoll(3, 10004)
  local _, w = windowFor(3)
  W.chat = {}
  click(w, "RollButton")
  check("your own Need on a wand is marked", RC.FindPick(RC.rolls[3], "Tester").cannot, "Wands")
  check("  but never reported to you", table.getn(W.chat), 0)
end

----------------------------------------------------------------------
print("the same item up twice")
----------------------------------------------------------------------
do
  T.reset()
  T.startRoll(11, 10002)
  T.startRoll(12, 10002)
  local _, a = windowFor(11)
  local _, b = windowFor(12)
  check("two windows for two rolls", a ~= nil and b ~= nil and a ~= b, true)

  -- Chat does not say which roll; each player picks once per roll.
  chat(said(LOOT_ROLL_GREED, "Tank", 10002))
  chat(said(LOOT_ROLL_NEED, "Tank", 10002))
  local needA, greedA = lines(a)
  local needB, greedB = lines(b)
  check("the first pick lands on the older roll", greedA, "Greed  Tank")
  check("  the second on the other", needB, "Need  Tank")
  check("  and neither roll has it twice", needA .. "|" .. greedB, "Need  -|Greed  -")

  -- You pick on the NEWER one first: your pick goes where you clicked.
  click(b, "PassButton")
  check("your window closes", windowFor(12), nil)
  check("your own pick lands on the roll you clicked",
    RC.FindPick(RC.rolls[12], "Tester") ~= nil and RC.FindPick(RC.rolls[11], "Tester") == nil, true)

  -- The roll is still going after your window has closed.
  chat(said(LOOT_ROLL_PASSED, "Heals", 10002))
  chat(said(LOOT_ROLL_PASSED, "Heals", 10002))
  check("later picks still fill both rolls", table.getn(RC.rolls[11].picks) .. "/" ..
    table.getn(RC.rolls[12].picks), "2/3")
  local _, _, passA = lines(a)
  check("  and the open window shows its own", passA, "Pass  Heals")
end

----------------------------------------------------------------------
print("rolls come and go")
----------------------------------------------------------------------
do
  -- A roll is forgotten once its timer has run out.
  T.reset()
  T.startRoll(21, 10003, 10)
  T.advance(50)
  T.fire("CANCEL_LOOT_ROLL", 21)   -- the game ends it when its timer runs out
  T.startRoll(22, 10004)
  check("an old roll is dropped when a new one starts", RC.rolls[21], nil)
  chat(said(LOOT_ROLL_NEED, "Tank", 10003))
  check("  and a stray line for it does not land on another roll", RC.rolls[22].picks[1], nil)

  -- Past its timer, a roll takes no more picks even before it is dropped.
  T.reset()
  T.startRoll(23, 10003, 10)
  T.advance(20)
  chat(said(LOOT_ROLL_NEED, "Tank", 10003))
  check("a roll past its timer takes no more picks", RC.rolls[23].picks[1], nil)

  -- The game can give a new roll an old roll's number.
  T.reset()
  T.startRoll(24, 10003)
  chat(said(LOOT_ROLL_NEED, "Tank", 10003))
  click(1, "PassButton")
  W.rolls[24] = { item = 10004, ends = W.now + 60 }
  T.fire("START_LOOT_ROLL", 24, 60000)
  local _, k = windowFor(24)
  check("a new item under an old roll's number starts clean", (lines(k)), "Need  -")

  -- The chat's link and the window's can differ in the last fields; the
  -- item is still the same item.
  T.reset()
  T.startRoll(25, 10003)
  local _, m = windowFor(25)
  chat("Tank has selected Need for: |cff1eff00|Hitem:10003:0:0:77|h[Plain Robe]|h|r")
  check("the same item with a different link still counts", (lines(m)), "Need  Tank")

  -- A /reload in the middle of a roll loses Rollcall's memory, not the window.
  T.reset()
  T.startRoll(31, 10003)
  local _, i = windowFor(31)
  RC.rolls = {}
  chat(said(LOOT_ROLL_NEED, "Tank", 10003))
  check("after a reload the open window is found again", (lines(i)), "Need  Tank")

  -- Addon first, window second: the panel still appears, and for the new
  -- roll - the window last showed another one, and must not show it again.
  T.reset()
  T.startRoll(40, 10003)
  chat(said(LOOT_ROLL_NEED, "Tank", 10003))
  click(1, "PassButton")
  local mine
  for n = 1, table.getn(T.ORDERED) do
    if T.ORDERED[n] == RollcallEventFrame then mine = n end
  end
  table.remove(T.ORDERED, mine)
  table.insert(T.ORDERED, 1, RollcallEventFrame)
  T.startRoll(41, 10004)
  local _, j = windowFor(41)
  check("when Rollcall hears first, the window still gets its panel", T.panelShown(j), true)
  check("  showing the new roll, not the last one", (lines(j)), "Need  -")
  table.remove(T.ORDERED, 1)
  table.insert(T.ORDERED, mine, RollcallEventFrame)

  -- A roll whose item has gone: Blizzard hides the window, nothing breaks.
  T.reset()
  T.fire("START_LOOT_ROLL", 51, 60000)
  check("Blizzard hides a window with no item", windowFor(51), nil)
  check("  and no panel is left behind", T.panelShown(1), false)

  -- Near the right edge the panel goes on the left instead.
  T.reset()
  GroupLootFrame1._right = 1000
  T.startRoll(61, 10003)
  local point, _, relPoint = RollcallPanel1:GetPoint(1)
  check("at the screen's right edge the panel moves left",
    tostring(point) .. ">" .. tostring(relPoint), "RIGHT>LEFT")
  GroupLootFrame1._right = 512 + 121

  -- Rendering again never piles up more counts on Blizzard's buttons.
  T.reset()
  T.startRoll(71, 10003)
  for _ = 1, 5 do chat(said(LOOT_ROLL_PASSED, "Tank", 10003)) end
  local count = 0
  for _, child in ipairs(GroupLootFrame1RollButton._children) do
    if child._kind == "FontString" then count = count + 1 end
  end
  check("one count per button, however often it is redrawn", count, 1)
end

----------------------------------------------------------------------
print("a raid's worth of passes")
----------------------------------------------------------------------
do
  T.reset()
  W.roster.party = {}
  local names = { "Aa", "Bb", "Cc", "Dd", "Ee", "Ff", "Gg" }
  for n = 1, 7 do W.roster.raid[n] = { names[n], "Hunter", "HUNTER" } end
  T.startRoll(81, 10003)
  local _, i = windowFor(81)
  for n = 1, 7 do chat(said(LOOT_ROLL_PASSED, names[n], 10003)) end
  local _, _, pass = lines(i)
  check("a long list is cut short", pass, "Pass  Aa, Bb, Cc, Dd  +3")
  check("raid members get class colors too",
    string.find(_G["RollcallPanel" .. i].lines[3]:GetText(), "|cffabd473Aa|r", 1, true) ~= nil, true)
  local tip = T.hover(i, "PassButton")
  check("the tooltip has everyone", table.getn(tip), 8)
end

----------------------------------------------------------------------
print("Detailed Loot Information")
----------------------------------------------------------------------
do
  -- Off at the first login: switched on, and said so.
  RollcallDB = nil
  W.cvars.showLootSpam = "0"
  W.chat = {}
  RC:Init()
  check("off at first, it is switched on", W.cvars.showLootSpam, "1")
  check("  saying so", T.chatHas("turned on Detailed Loot Information"), true)

  -- Turned off again by hand: respected, with a reminder.
  W.cvars.showLootSpam = "0"
  W.chat = {}
  RC:Init()
  check("turned off by hand, it stays off", W.cvars.showLootSpam, "0")
  check("  with a reminder", T.chatHas("/rollcall detail"), true)
  SlashCmdList["ROLLCALL"]("detail")
  check("/rollcall detail turns it back on", W.cvars.showLootSpam, "1")

  -- Already on: never touched.
  RollcallDB = nil
  W.cvars.showLootSpam = "1"
  W.chat = {}
  RC:Init()
  check("already on, nothing is said", table.getn(W.chat), 0)
  check("  and it is not switched back on later", RollcallDB.detailSet, true)
end

----------------------------------------------------------------------
print("/rollcall test")
----------------------------------------------------------------------
do
  T.reset()
  W.equipped = { [5] = link(10001) }
  SlashCmdList["ROLLCALL"]("test")
  local host, i = windowFor(RC.TEST_ID)
  check("a pretend roll opens on Blizzard's window", host ~= nil, true)
  check("  showing your own item", GroupLootFrame1Name:GetText(), "Scaled Shroud")
  local need, greed, pass = lines(i)
  check("  with a group's worth of picks", need, "Need  Tankadin, Sneakyboi (can't use)")
  check("  greeds", greed, "Greed  Healzor, Pewpew")
  check("  and a pass", pass, "Pass  Afkbob")

  -- Clicking on it goes nowhere.
  click(i, "RollButton")
  check("clicking the pretend roll sends nothing", table.getn(W.sent), 0)
  check("  and ends it", windowFor(RC.TEST_ID), nil)
  check("  cleanly", RC.test, nil)
  check("  and it never reaches the loot history", table.getn(RollcallDB.history), 0)
  SlashCmdList["ROLLCALL"]("test")
  T.fire("PLAYER_LOGOUT")
  check("  not even when you log out during it", table.getn(RollcallDB.history), 0)
  RC:EndTest()

  -- Real rolls pass straight through the same functions.
  T.startRoll(91, 10003)
  local _, j = windowFor(91)
  click(j, "GreedButton")
  check("a real roll still reaches the server", W.sent[1] and W.sent[1].id, 91)

  -- It ends on its own, too.
  T.reset()
  SlashCmdList["ROLLCALL"]("test")
  T.advance(RC.TEST_SECONDS + 1)
  this = RollcallEventFrame
  RollcallEventFrame._scripts.OnUpdate()
  check("the pretend roll closes by itself", windowFor(RC.TEST_ID), nil)

  -- Nothing equipped, nothing to show.
  T.reset()
  W.equipped = {}
  SlashCmdList["ROLLCALL"]("test")
  check("with nothing equipped it says why", T.chatHas("equip something first"), true)

  -- All four windows busy.
  T.reset()
  W.equipped = { [5] = link(10001) }
  for n = 1, 4 do T.startRoll(100 + n, 10003) end
  SlashCmdList["ROLLCALL"]("test")
  check("with every window busy it says so", T.chatHas("all four roll windows are in use"), true)
  check("  and leaves no pretend roll behind", RC.test, nil)
end

T.done()
