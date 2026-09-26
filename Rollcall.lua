--[[
    Rollcall - who picked Need, Greed and Pass, on the normal roll windows,
    and a history of who rolled what and who won.

    While Detailed Loot Information is on, the game prints a line for every
    pick the moment it is made ("Bob has selected Need for: [Item]"), every
    roll once they are thrown ("Need Roll - 87 for [Item] by Bob") and the
    winner ("Bob won: [Item]"). That is the only place any of it exists, so
    Rollcall reads those lines.

    Beside each of Blizzard's own roll windows, which it otherwise leaves
    alone: who has picked Need, Greed and Pass so far, in class colors, with a
    count on each of Blizzard's buttons and the whole list in each button's
    tooltip. A Need from a class that can never use the item (a mage needing
    mail) is marked in red and noted in your chat.

    Every finished roll is kept (History.lua), with where it dropped, so boss
    loot can be told from trash and announced to your group.

    Slash command: /rollcall
--]]

Rollcall = {}
local RC = Rollcall

RC.VERSION = "1.1.0"
RC.NEED, RC.GREED, RC.PASS = "NEED", "GREED", "PASS"
RC.ORDER = { "NEED", "GREED", "PASS" }
RC.MAX_NAMES = 4        -- names on a line before it says "+N"
RC.GRACE = 5            -- seconds a roll takes picks after its timer runs out
RC.RESULT_WAIT = 30     -- and how much longer its rolls and winner may arrive
RC.CHAT_ROLL_TIME = 60  -- a roll's length when only chat has told us about it
RC.TEST_ID = -4242      -- the pretend roll /rollcall test puts up
RC.TEST_SECONDS = 30
-- Master loot: /roll 100 is main spec, 99 off spec, 98 transmog.
RC.MS, RC.OS, RC.TMOG = "MS", "OS", "TMOG"
RC.ML_ORDER = { "MS", "OS", "TMOG" }
RC.ROLL_RANGES = { [100] = "MS", [99] = "OS", [98] = "TMOG" }
RC.RAID_QUALITY = 3     -- in a raid the history keeps Rare and better, unless told
RC.SAME_ITEM_WAIT = 180 -- a second copy handed out this soon goes by the same rolls
RC.PANEL_MIN_W, RC.PANEL_MAX_W = 110, 340

RC.rolls = {}           -- [rollID] = record; see RC:Record
RC.seq = 0
RC.chatSeq = 0
RC.panels = {}          -- [window index] = the panel beside GroupLootFrameN
RC.ownHint = {}         -- [rollID] = what you clicked on it; see HookRollOnLoot

-- Blizzard's names for the three buttons on a roll window.
local BUTTONS = { NEED = "RollButton", GREED = "GreedButton", PASS = "PassButton" }

-- RollOnLoot's numbers.
local CHOICE_OF = { [0] = "PASS", [1] = "NEED", [2] = "GREED" }

local CLASSES = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE",
                  "SHAMAN", "WARLOCK", "WARRIOR" }

function RC.Say(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Rollcall|r: " .. msg)
end

function RC:DB()
    if type(RollcallDB) ~= "table" then RollcallDB = {} end
    return RollcallDB
end

function RC.Windows()
    return NUM_GROUP_LOOT_FRAMES or 4
end

function RC.Me()
    return UnitName("player")
end

local function zoneNow()
    return (GetRealZoneText and GetRealZoneText()) or ""
end

local function clockNow()
    return (time and time()) or 0
end

----------------------------------------------------------------------
-- reading the chat lines
----------------------------------------------------------------------

--[[ Every line is read with the client's own GlobalStrings format, so this
     reads the language the game is in.

     The formats spell the item out in parts - color, "|Hitem:%d:%d:%d:%d|h",
     "[%s]", "|h%s" - and one capture for the whole link is all that is
     needed, so that part becomes a single placeholder first. The winner lines
     used when Detailed Loot Information is off number their arguments
     ("%1$s won: %3$s ... %2$d"); captures come back in string order, so each
     remembers which argument it was, and they are handed out in argument
     order. ]]
local ITEM_SEGMENT = "(%%%d*%$?s)|Hitem:%%%d*%$?d:%%%d*%$?d:%%%d*%$?d:%%%d*%$?d" ..
                     "|h%[%%%d*%$?s%]|h%%%d*%$?s"

local function escape(s)
    return (string.gsub(s, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

--- A GlobalStrings format as an anchored Lua pattern, and which argument
--- each capture is, in the order the captures come back.
function RC.Compile(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    fmt = string.gsub(fmt, ITEM_SEGMENT, "%1")
    local out, order, pos, seq = "^", {}, 1, 0
    while true do
        local s, e, num, dollar, conv = string.find(fmt, "%%(%d*)(%$?)([sd])", pos)
        if not s then break end
        out = out .. escape(string.sub(fmt, pos, s - 1))
        if conv == "s" then out = out .. "(.+)" else out = out .. "(%-?%d+)" end
        seq = seq + 1
        local index = seq
        if dollar == "$" and num ~= "" then index = tonumber(num) end
        table.insert(order, index)
        pos = e + 1
    end
    return out .. escape(string.sub(fmt, pos)) .. "$", order
end

--[[ What each line is, most specific first: "You won" is also "<name> won",
     "Everyone passed on" and "You passed on" are also "<name> passed on", and
     a winner line with its roll attached is also a plain winner line.
     { global, kind, choice, fields in argument order, about you } ]]
local LINES = {
    { "LOOT_ROLL_YOU_WON_NO_SPAM_NEED", "won", "NEED", { "roll", "item" }, true },
    { "LOOT_ROLL_YOU_WON_NO_SPAM_GREED", "won", "GREED", { "roll", "item" }, true },
    { "LOOT_ROLL_WON_NO_SPAM_NEED", "won", "NEED", { "name", "roll", "item" } },
    { "LOOT_ROLL_WON_NO_SPAM_GREED", "won", "GREED", { "name", "roll", "item" } },
    { "LOOT_ROLL_ALL_PASSED", "passed", nil, { "item" } },
    { "LOOT_ROLL_YOU_WON", "won", nil, { "item" }, true },
    { "LOOT_ROLL_WON", "won", nil, { "name", "item" } },
    { "LOOT_ROLL_ROLLED_NEED_SELF", "roll", "NEED", { "roll", "item" }, true },
    { "LOOT_ROLL_ROLLED_GREED_SELF", "roll", "GREED", { "roll", "item" }, true },
    { "LOOT_ROLL_ROLLED_SELF", "roll", nil, { "roll", "item" }, true },
    { "LOOT_ROLL_ROLLED_NEED", "roll", "NEED", { "roll", "item", "name" } },
    { "LOOT_ROLL_ROLLED_GREED", "roll", "GREED", { "roll", "item", "name" } },
    { "LOOT_ROLL_ROLLED", "roll", nil, { "name", "roll", "item" } },
    { "LOOT_ROLL_NEED_SELF", "pick", "NEED", { "item" }, true },
    { "LOOT_ROLL_GREED_SELF", "pick", "GREED", { "item" }, true },
    { "LOOT_ROLL_PASSED_SELF", "pick", "PASS", { "item" }, true },
    { "LOOT_ROLL_NEED", "pick", "NEED", { "name", "item" } },
    { "LOOT_ROLL_GREED", "pick", "GREED", { "name", "item" } },
    { "LOOT_ROLL_PASSED", "pick", "PASS", { "name", "item" } },
    -- Someone getting an item: under master loot, the master looter handing
    -- it out. A count means a stack, so the "x2" forms go first.
    { "LOOT_ITEM_SELF_MULTIPLE", "got", nil, { "item", "count" }, true },
    { "LOOT_ITEM_SELF", "got", nil, { "item" }, true },
    { "LOOT_ITEM_MULTIPLE", "got", nil, { "name", "item", "count" } },
    { "LOOT_ITEM", "got", nil, { "name", "item" } },
}

local MATCHERS

local function matchers()
    if MATCHERS then return MATCHERS end
    MATCHERS = {}
    for i = 1, table.getn(LINES) do
        local spec = LINES[i]
        local pattern, order = RC.Compile(getglobal(spec[1]))
        if pattern then
            table.insert(MATCHERS, { pattern = pattern, order = order, kind = spec[2],
                                     choice = spec[3], fields = spec[4], self = spec[5] })
        end
    end
    return MATCHERS
end

--[[ One line of loot chat as what happened, or nil:
       { kind = "pick" | "roll" | "won" | "passed" | "got",
         name = who (you, by name, for your own lines), choice, roll, link,
         count (a stack, for "got") } ]]
function RC.ParseLine(msg)
    if type(msg) ~= "string" then return nil end
    local list = matchers()
    for i = 1, table.getn(list) do
        local m = list[i]
        local found = { string.find(msg, m.pattern) }
        if found[1] then
            local args = {}
            for n = 1, table.getn(m.order) do args[m.order[n]] = found[n + 2] end
            local ev = { kind = m.kind, choice = m.choice }
            for n = 1, table.getn(m.fields) do
                local field = m.fields[n]
                if field == "name" then ev.name = args[n]
                elseif field == "roll" then ev.roll = tonumber(args[n])
                elseif field == "count" then ev.count = tonumber(args[n])
                else ev.link = args[n] end
            end
            if m.self then ev.name = RC.Me() end
            if not ev.name and ev.kind ~= "passed" then return nil end
            return ev
        end
    end
    return nil
end

--- "item:1234:0:584:0" and 1234, from a link however it is colored.
function RC.ItemKey(link)
    if type(link) ~= "string" then return nil end
    local _, _, key, id = string.find(link, "(item:(%d+):%-?%d+:%-?%d+:%-?%d+)")
    if key then return key, tonumber(id) end
    local _, _, bare = string.find(link, "item:(%d+)")
    if bare then return "item:" .. bare, tonumber(bare) end
    return nil
end

--- Exactly an item link and nothing else, or nil. Only this is ever sent to
--- chat: a link the server does not like can cost you the message.
function RC.CleanLink(s)
    if type(s) ~= "string" then return nil end
    local _, _, link = string.find(s, "(|c%x%x%x%x%x%x%x%x|Hitem:[%d:%-]+|h%[.-%]|h|r)")
    return link
end

function RC.LinkName(link)
    if type(link) ~= "string" then return nil end
    local _, _, name = string.find(link, "%[(.-)%]")
    return name
end

----------------------------------------------------------------------
-- who is who
----------------------------------------------------------------------

--- Class token ("MAGE") and its display name, for anyone in the group.
function RC.ClassOf(name)
    if not name then return nil end
    if UnitName("player") == name then
        local shown, token = UnitClass("player")
        return token, shown
    end
    local n = GetNumRaidMembers and GetNumRaidMembers() or 0
    for i = 1, n do
        local unit = "raid" .. i
        if UnitName(unit) == name then
            local shown, token = UnitClass(unit)
            return token, shown
        end
    end
    n = GetNumPartyMembers and GetNumPartyMembers() or 0
    for i = 1, n do
        local unit = "party" .. i
        if UnitName(unit) == name then
            local shown, token = UnitClass(unit)
            return token, shown
        end
    end
    return nil
end

--[[ Which classes can never use an item, by the item's subtype.

     Only categories where that is true for every class are listed: armor,
     shields, relics, wands, and bows, guns and crossbows. Melee weapons are
     left out on purpose. A wrong "can't use" accuses someone who did nothing
     wrong, which is worse than missing a ninja the class colors already give
     away. Level does not count: a level 30 hunter needing mail is saving it,
     not stealing it. ]]
local function allBut(keep)
    local t = {}
    for i = 1, table.getn(CLASSES) do
        if CLASSES[i] ~= keep then t[CLASSES[i]] = true end
    end
    return t
end

local NOT_RANGED = { PALADIN = true, DRUID = true, SHAMAN = true,
                     MAGE = true, PRIEST = true, WARLOCK = true }

local CANNOT = {
    Leather   = { MAGE = true, PRIEST = true, WARLOCK = true },
    Mail      = { MAGE = true, PRIEST = true, WARLOCK = true, DRUID = true, ROGUE = true },
    Plate     = { MAGE = true, PRIEST = true, WARLOCK = true, DRUID = true, ROGUE = true,
                  HUNTER = true, SHAMAN = true },
    Shields   = { MAGE = true, PRIEST = true, WARLOCK = true, DRUID = true, ROGUE = true,
                  HUNTER = true },
    Librams   = allBut("PALADIN"),
    Idols     = allBut("DRUID"),
    Totems    = allBut("SHAMAN"),
    Wands     = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true,
                  DRUID = true, SHAMAN = true },
    Bows      = NOT_RANGED,
    Guns      = NOT_RANGED,
    Crossbows = NOT_RANGED,
}

--- The subtype names above are the English client's. On any other language
--- they would never match - so say nothing rather than guess.
function RC.EnglishClient()
    local locale = GetLocale and GetLocale()
    return locale == nil or locale == "enUS" or locale == "enGB"
end

--- The item's subtype ("Mail") when this class can never use it, else nil.
function RC.CannotUse(class, key)
    if not class or not key or not RC.EnglishClient() then return nil end
    local _, _, _, _, _, subType = GetItemInfo(key)
    local barred = subType and CANNOT[subType]
    if barred and barred[class] then return subType end
    return nil
end

--- The first class that can never use an item, for /rollcall test.
function RC.BarredClass(key)
    for i = 1, table.getn(CLASSES) do
        if RC.CannotUse(CLASSES[i], key) then return CLASSES[i] end
    end
    return nil
end

----------------------------------------------------------------------
-- rolls
----------------------------------------------------------------------

--[[ One record per roll, keyed by the roll's id.

     A record outlives its window. Blizzard hides the window the moment YOU
     pick, but everyone else goes on picking until the timer runs out, and
     then the rolls and the winner arrive - and all of it still has to land on
     the right roll, which matters when the same item is up twice. So a record
     takes picks until its own timer plus a few seconds, and results for a
     while after that. ]]
function RC:Record(rollID, rollTime)
    if not rollID then return nil end
    local r = self.rolls[rollID]
    if r then return r end
    local link = GetLootRollItemLink and GetLootRollItemLink(rollID)
    local key, itemId = RC.ItemKey(link)
    if not key then return nil end
    -- The time actually left, not the roll's full length: a window found
    -- after a /reload may be most of the way through.
    local ms = GetLootRollTimeLeft and GetLootRollTimeLeft(rollID)
    if type(ms) ~= "number" then ms = rollTime or 60000 end
    if ms < 0 then ms = 0 end
    return self:NewRecord(rollID, link, key, itemId, ms / 1000)
end

function RC:NewRecord(id, link, key, itemId, seconds)
    self.seq = self.seq + 1
    local r = { id = id, seq = self.seq, link = RC.CleanLink(link) or link, key = key,
                itemId = itemId, expires = GetTime() + seconds + RC.GRACE,
                picks = {}, seen = {}, zone = zoneNow(), startedAt = clockNow(),
                raid = RC.InRaid() }
    self.rolls[id] = r
    return r
end

--- A roll only chat has told us about: one you have no window for.
function RC:ChatRecord(key, itemId, link)
    self.chatSeq = self.chatSeq + 1
    local r = self:NewRecord("chat" .. self.chatSeq, link, key, itemId, RC.CHAT_ROLL_TIME)
    r.chatOnly = true
    return r
end

--- Into the history, once: finished, or given up on with picks to show.
function RC:Commit(r)
    if r.committed or r.id == RC.TEST_ID then return end
    r.committed = true
    if not r.resolved and table.getn(r.picks) == 0 then return end
    -- In a raid, only what is rare enough to be asked about later.
    if r.raid and (RC.Quality(r.link) or 0) < self:RaidQuality() then return end
    if not r.status then r.status = "open" end
    if RC.history then RC.history:Add(r) end
end

function RC:Prune()
    local now = GetTime()
    for id, r in pairs(self.rolls) do
        if r.committed or now > r.expires + RC.RESULT_WAIT then
            self:Commit(r)
            self.rolls[id] = nil
        end
    end
end

--- Rolls whose window is up but which started before Rollcall was loaded,
--- after a /reload in the middle of a roll.
function RC:Discover()
    for i = 1, RC.Windows() do
        local host = getglobal("GroupLootFrame" .. i)
        if host and host:IsVisible() and host.rollID and not self.rolls[host.rollID] then
            self:Record(host.rollID, host.rollTime)
        end
    end
end

--- Everything about a pick that does not depend on which roll it is on.
function RC.Pick(name, choice, key)
    local class, className = RC.ClassOf(name)
    local pick = { name = name, choice = choice, class = class, className = className }
    -- Need, or its master-loot twin, main spec: what the class must be able to use.
    if choice == RC.NEED or choice == RC.MS then pick.cannot = RC.CannotUse(class, key) end
    return pick
end

function RC.FindPick(r, name)
    for i = 1, table.getn(r.picks) do
        if r.picks[i].name == name then return r.picks[i] end
    end
    return nil
end

local function takesPicks(r, now) return not r.resolved and now <= r.expires end
local function takesResults(r, now)
    return not r.resolved and now <= r.expires + RC.RESULT_WAIT
end

--- The records for an item that `open` says yes to, oldest first. The exact
--- link first; the bare item id only if nothing matched it.
function RC:Candidates(key, itemId, open)
    local now, out = GetTime(), {}
    for pass = 1, 2 do
        for _, r in pairs(self.rolls) do
            local same = (pass == 1 and r.key == key) or (pass == 2 and r.itemId == itemId)
            if same and open(r, now) then table.insert(out, r) end
        end
        if table.getn(out) > 0 then break end
    end
    table.sort(out, function(a, b) return a.seq < b.seq end)
    return out
end

--[[ Put a pick on the roll it belongs to.

     The chat line names the item, not the roll. When the same item is up
     twice, the pick goes to the oldest open roll of it this player has not
     picked on yet. Everyone picks once per roll, so that fills both rolls
     completely whichever one is clicked first. Your own picks go exactly
     where you clicked. ]]
function RC:Assign(pick, key, itemId, link)
    self:Discover()
    local list = self:Candidates(key, itemId, function(r, now)
        return takesPicks(r, now) and not r.seen[pick.name]
    end)
    local best = list[1]
    if pick.name == RC.Me() then
        for i = 1, table.getn(list) do
            if self.ownHint[list[i].id] == pick.choice then
                best = list[i]
                break
            end
        end
        if best then self.ownHint[best.id] = nil end
    end
    -- A roll you have no window for is still a roll.
    if not best then best = self:ChatRecord(key, itemId, link) end
    best.seen[pick.name] = pick.choice
    table.insert(best.picks, pick)
    return best
end

--- A pick for a result line whose pick we never saw.
function RC:AddLatePick(r, name, choice, key)
    local pick = RC.Pick(name, choice or "?", key)
    r.seen[name] = pick.choice
    table.insert(r.picks, pick)
    return pick
end

local function hasRolls(r)
    for i = 1, table.getn(r.picks) do
        if r.picks[i].roll then return true end
    end
    return false
end

--[[ The first roll in `list` whose numbers have started coming in, else the
     first. A roll's lines arrive together - all its numbers, then its winner
     - so when the same item is up twice, the one already under way is the
     one being settled. ]]
local function underWay(list)
    for i = 1, table.getn(list) do
        if hasRolls(list[i]) then return list[i] end
    end
    return list[1]
end

--- "Need Roll - 87 for [Item] by Bob": onto the roll where Bob picked that
--- and has no number yet.
function RC:OnRoll(ev, key, itemId)
    local list = self:Candidates(key, itemId, takesResults)
    local picked, free = {}, {}
    for i = 1, table.getn(list) do
        local p = RC.FindPick(list[i], ev.name)
        if p and not p.roll and p.choice ~= RC.PASS and
           (not ev.choice or p.choice == ev.choice) then
            table.insert(picked, list[i])
        elseif not p then
            table.insert(free, list[i])
        end
    end
    local target = underWay(picked)
    if target then
        RC.FindPick(target, ev.name).roll = ev.roll
        return target
    end
    -- A number for a pick we never saw.
    target = underWay(free) or self:ChatRecord(key, itemId, ev.link)
    self:AddLatePick(target, ev.name, ev.choice, key).roll = ev.roll
    return target
end

--- "Bob won: [Item]": the roll Bob was actually in, and that roll is done.
function RC:OnWon(ev, key, itemId)
    local list = self:Candidates(key, itemId, takesResults)
    local target
    -- The winner's own number came just before the winner line.
    for i = 1, table.getn(list) do
        local p = RC.FindPick(list[i], ev.name)
        if p and p.roll then
            target = list[i]
            break
        end
    end
    if not target then
        local picked = {}
        for i = 1, table.getn(list) do
            local p = RC.FindPick(list[i], ev.name)
            if p and (p.choice == RC.NEED or p.choice == RC.GREED or p.choice == "?") then
                table.insert(picked, list[i])
            end
        end
        target = underWay(picked) or underWay(list) or self:ChatRecord(key, itemId, ev.link)
    end
    local p = RC.FindPick(target, ev.name) or self:AddLatePick(target, ev.name, ev.choice, key)
    -- The winner line with Detailed Loot Information off says how they won.
    if ev.choice and p.choice == "?" then p.choice = ev.choice end
    if ev.roll then p.roll = ev.roll end
    target.resolved, target.status, target.winner = true, "won", ev.name
    self:Commit(target)
    return target
end

--- "Everyone passed on: [Item]": the roll nobody wanted is done.
function RC:OnAllPassed(ev, key, itemId)
    local list = self:Candidates(key, itemId, takesResults)
    local target
    for i = 1, table.getn(list) do
        local everyone = true
        for n = 1, table.getn(list[i].picks) do
            if list[i].picks[n].choice ~= RC.PASS then everyone = false end
        end
        if everyone then
            target = list[i]
            break
        end
    end
    target = target or list[1] or self:ChatRecord(key, itemId, ev.link)
    target.resolved, target.status = true, "passed"
    self:Commit(target)
    return target
end

----------------------------------------------------------------------
-- master loot
----------------------------------------------------------------------

--[[ Under master loot nothing is rolled through the game's windows: the
     master looter links an item, people /roll - 100 for main spec, 99 for
     off spec, 98 for transmog - and the item is handed to someone, which
     chat reports as "Bob receives loot: [Item]." So the rolls are gathered
     from the system lines as they come, and the hand-out turns them into a
     history entry: everyone's rolls, who got it and with which roll.

     The master looter linking one item in raid or party chat, or anyone's
     raid warning with one, starts that item's rolls afresh: whatever was
     rolled before was for something else. Handing it out ends them. With
     nothing linked, the rolls since the last hand-out are the ones. ]]

local QUALITY_BY_COLOUR = { ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2,
    ["0070dd"] = 3, ["a335ee"] = 4, ["ff8000"] = 5, ["e6cc80"] = 6 }

--- An item's quality: the client's word for it, else its link's colour.
function RC.Quality(link)
    local key = RC.ItemKey(link)
    if key and GetItemInfo then
        local _, _, q = GetItemInfo(key)
        if q then return q end
    end
    local _, _, hex = string.find(link or "", "|c%x%x(%x%x%x%x%x%x)")
    if not hex then return nil end
    return QUALITY_BY_COLOUR[string.lower(hex)]
end

function RC.InRaid()
    return GetNumRaidMembers and GetNumRaidMembers() > 0
end

--- The master looter's name; nil unless the loot is master loot.
function RC.MasterLooter()
    if not GetLootMethod then return nil end
    local method, partyMaster, raidMaster = GetLootMethod()
    if method ~= "master" then return nil end
    if raidMaster and RC.InRaid() then return UnitName("raid" .. raidMaster) end
    if partyMaster == 0 then return RC.Me() end
    if partyMaster then return UnitName("party" .. partyMaster) end
    return nil
end

function RC:RaidQuality() return self:DB().raidQuality or RC.RAID_QUALITY end

function RC.QualityName(q)
    return getglobal("ITEM_QUALITY" .. tostring(q) .. "_DESC") or tostring(q)
end

function RC:NewSession(key, itemId)
    self.session = { key = key, itemId = itemId, rolls = {}, order = {} }
end
RC:NewSession()

local ROLL_PATTERN
--- "Bob rolls 87 (1-100)" as its parts: name, roll, low, high.
function RC.ParseRoll(msg)
    if ROLL_PATTERN == nil then ROLL_PATTERN = RC.Compile(RANDOM_ROLL_RESULT) or false end
    if not ROLL_PATTERN or type(msg) ~= "string" then return nil end
    local _, _, name, roll, low, high = string.find(msg, ROLL_PATTERN)
    if not name then return nil end
    return name, tonumber(roll), tonumber(low), tonumber(high)
end

--- A /roll, kept against the item being rolled for: each player's first.
function RC:OnSystem(msg)
    local name, roll, low, high = RC.ParseRoll(msg)
    if not name or low ~= 1 then return end
    local choice = RC.ROLL_RANGES[high]
    if not choice then return end
    local s = self.session
    local mine = s.rolls[name]
    if mine then
        -- Rolled again for the same thing: the first stands, and it is noted.
        mine.again = (mine.again or 1) + 1
        return
    end
    s.rolls[name] = { name = name, choice = choice, roll = roll }
    table.insert(s.order, name)
end

--[[ An item linked where the raid will see it: the master looter in raid or
     party chat, or anyone's raid warning. One link names the item being
     rolled for; several leave it open to whichever is handed out first. ]]
function RC:OnAnnounce(msg, sender, warning)
    if type(msg) ~= "string" then return end
    if not warning then
        local ml = RC.MasterLooter()
        if not ml or sender ~= ml then return end
    end
    local count = 0
    for _ in string.gfind(msg, "|Hitem:") do count = count + 1 end
    if count == 0 then return end
    if count == 1 then
        local key, itemId = RC.ItemKey(msg)
        self:NewSession(key, itemId)
    else
        self:NewSession()
    end
end

--[[ Who rolled best: main spec over off spec over transmog, then the higher
     number. Anyone in `skip` already has a copy of this item. ]]
local RANK = { MS = 3, OS = 2, TMOG = 1 }
local function topRoller(picks, skip)
    local best
    for i = 1, table.getn(picks) do
        local p = picks[i]
        if p.roll and RANK[p.choice] and not skip[p.name] then
            if not best or RANK[p.choice] > RANK[best.choice] or
               (RANK[p.choice] == RANK[best.choice] and p.roll > best.roll) then
                best = p
            end
        end
    end
    return best
end

--[[ "Bob receives loot: [Item]" under master loot, at or above its
     threshold: the master looter handing something out. Below the threshold
     is ordinary looting, and under group loot the roll's own winner line has
     already said who got it. ]]
function RC:OnGot(ev, key, itemId)
    local ml = RC.MasterLooter()
    if not ml then return nil end
    local q = RC.Quality(ev.link)
    local threshold = (GetLootThreshold and GetLootThreshold()) or 2
    if not q or q < threshold then return nil end

    local s, last = self.session, self.lastGiven
    local forThis = (s.itemId == nil or s.itemId == itemId)
    local rolls, skip = nil, {}
    if forThis and table.getn(s.order) > 0 then
        rolls = s
    elseif last and last.itemId == itemId and GetTime() - last.at <= RC.SAME_ITEM_WAIT then
        -- Another copy, straight after the first: the same rolls, next in line.
        rolls, skip = last.session, last.given
    end

    local r = self:ChatRecord(key, itemId, ev.link)
    r.looter, r.count = ml, ev.count
    if rolls then
        for i = 1, table.getn(rolls.order) do
            local rr = rolls.rolls[rolls.order[i]]
            local pick = RC.Pick(rr.name, rr.choice, key)
            pick.roll, pick.again = rr.roll, rr.again
            table.insert(r.picks, pick)
        end
    end
    r.resolved, r.status, r.winner = true, "master", ev.name

    -- Someone else rolled better, and did not get it: worth a line.
    local best = topRoller(r.picks, skip)
    local won = RC.FindPick(r, ev.name)
    if best and best.name ~= ev.name and
       not (won and won.choice == best.choice and won.roll == best.roll) then
        r.top = best.name
    end

    if rolls then
        if rolls == s then last = { itemId = itemId, session = s, given = {} } end
        last.given[ev.name] = true
        last.at = GetTime()
        self.lastGiven = last
    end
    if forThis then self:NewSession() end
    self:Commit(r)
    return r
end

local RARITY = { uncommon = 2, green = 2, rare = 3, blue = 3, epic = 4, purple = 4,
                 legendary = 5, orange = 5 }

--- What a raid's history keeps: this rarity and better.
function RC:SetRaidQuality(word)
    local q = RARITY[string.lower(word or "")]
    if q then self:DB().raidQuality = q end
    local what = RC.QualityName(self:RaidQuality())
    if q or word == "" or not word then
        RC.Say("in a raid, the history keeps " .. what .. " and better.")
    else
        RC.Say("\"" .. word .. "\" is not a rarity - uncommon, rare, epic or legendary.")
    end
    if RC.history and RC.history.onChange then RC.history.onChange() end
end

function RC:Warn(pick, link)
    if not self:DB().warn then return end
    local who = pick.className or pick.class or "?"
    RC.Say("|cffff4040" .. pick.name .. "|r (" .. who .. ") picked Need on " .. link ..
        " - " .. who .. "s can't use " .. pick.cannot .. ".")
end

function RC:HandleLine(msg)
    local ev = RC.ParseLine(msg)
    if not ev then return end
    local key, itemId = RC.ItemKey(ev.link)
    if not key then return end
    self:Prune()
    local r
    if ev.kind == "pick" then
        local pick = RC.Pick(ev.name, ev.choice, key)
        r = self:Assign(pick, key, itemId, ev.link)
        -- Warned about even when you have no window for it yourself; never
        -- about your own picks.
        if pick.cannot and ev.name ~= RC.Me() then self:Warn(pick, ev.link) end
    elseif ev.kind == "roll" then
        r = self:OnRoll(ev, key, itemId)
    elseif ev.kind == "won" then
        r = self:OnWon(ev, key, itemId)
    elseif ev.kind == "passed" then
        r = self:OnAllPassed(ev, key, itemId)
    elseif ev.kind == "got" then
        r = self:OnGot(ev, key, itemId)
    end
    if r then self:RefreshAll() end
end

----------------------------------------------------------------------
-- beside Blizzard's windows
----------------------------------------------------------------------

function RC.ClassHex(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not c then return nil end
    return string.format("%02x%02x%02x", math.floor(c.r * 255 + 0.5),
        math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
end

--- A name in its class color, or red when its Need is for something the
--- class can never use. `long` says what, for tooltips.
function RC.NameText(p, long)
    if p.cannot then
        local why = " (can't use)"
        if long then why = " (can't use " .. p.cannot .. ")" end
        return "|cffff2020" .. p.name .. why .. "|r"
    end
    local hex = RC.ClassHex(p.class)
    if hex then return "|cff" .. hex .. p.name .. "|r" end
    return p.name
end

function RC.Label(choice)
    if choice == RC.NEED then return "|cffff8040" .. (NEED or "Need") .. "|r" end
    if choice == RC.GREED then return "|cffffd100" .. (GREED or "Greed") .. "|r" end
    if choice == RC.MS then return "|cffff8040MS|r" end
    if choice == RC.OS then return "|cffffd100OS|r" end
    if choice == RC.TMOG then return "|cffc080ffTmog|r" end
    if choice == "?" then return "|cffa0a0a0?|r" end
    return "|cffa0a0a0" .. (PASS or "Pass") .. "|r"
end

--- One line of the panel, and how many picked that.
function RC.Line(r, choice)
    local names, count = {}, 0
    for i = 1, table.getn(r.picks) do
        local p = r.picks[i]
        if p.choice == choice then
            count = count + 1
            if count <= RC.MAX_NAMES then table.insert(names, RC.NameText(p)) end
        end
    end
    if count == 0 then return RC.Label(choice) .. "  |cff707070-|r", 0 end
    local text = RC.Label(choice) .. "  " .. table.concat(names, ", ")
    if count > RC.MAX_NAMES then
        text = text .. "  |cff909090+" .. (count - RC.MAX_NAMES) .. "|r"
    end
    return text, count
end

function RC:Panel(i)
    if self.panels[i] then return self.panels[i] end
    local host = getglobal("GroupLootFrame" .. i)
    if not host then return nil end

    -- A child of Blizzard's window, so it shows, hides and moves with it.
    local panel = CreateFrame("Frame", "RollcallPanel" .. i, host)
    panel:SetWidth(RC.PANEL_MIN_W)
    panel:SetHeight(58)
    panel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    panel:SetBackdropColor(0, 0, 0, 0.85)
    panel:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

    panel.lines = {}
    for n = 1, 3 do
        local line = panel:CreateFontString("RollcallPanel" .. i .. "Line" .. n, "OVERLAY",
            "GameFontHighlightSmall")
        line:SetJustifyH("LEFT")
        if n == 1 then
            line:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -9)
        else
            line:SetPoint("TOPLEFT", panel.lines[n - 1], "BOTTOMLEFT", 0, -4)
        end
        panel.lines[n] = line
    end

    -- A count on each of Blizzard's own buttons.
    panel.badges = {}
    for n = 1, 3 do
        local choice = RC.ORDER[n]
        local button = getglobal(host:GetName() .. BUTTONS[choice])
        if button then
            local badge = button:CreateFontString("RollcallBadge" .. i .. choice, "OVERLAY",
                "NumberFontNormal")
            badge:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 2)
            panel.badges[choice] = badge
        end
    end

    self.panels[i] = panel
    return panel
end

--- To the right of the window, or its left if the right would run off the
--- screen - which it can, once something like MoveAnything has moved it.
function RC.Place(panel, host)
    panel:ClearAllPoints()
    local right, screen = host:GetRight(), UIParent:GetRight()
    local overflow = false
    if right and screen then
        overflow = right * host:GetEffectiveScale() + panel:GetWidth() * panel:GetEffectiveScale()
            > screen * UIParent:GetEffectiveScale()
    end
    if overflow then
        panel:SetPoint("RIGHT", host, "LEFT", 2, 0)
    else
        panel:SetPoint("LEFT", host, "RIGHT", -2, 0)
    end
end

function RC:Render(i)
    local host = getglobal("GroupLootFrame" .. i)
    local panel = self:Panel(i)
    if not host or not panel then return end
    local r = host.rollID and self:Record(host.rollID, host.rollTime)
    if not r then
        panel:Hide()
        for _, badge in pairs(panel.badges) do badge:SetText("") end
        return
    end

    local widest = 0
    for n = 1, 3 do
        local choice = RC.ORDER[n]
        local text, count = RC.Line(r, choice)
        panel.lines[n]:SetText(text)
        local w = panel.lines[n]:GetStringWidth() or 0
        if w > widest then widest = w end
        local badge = panel.badges[choice]
        if badge then
            if count > 0 then badge:SetText(tostring(count)) else badge:SetText("") end
        end
    end
    panel:SetWidth(math.max(RC.PANEL_MIN_W, math.min(RC.PANEL_MAX_W, widest + 20)))
    RC.Place(panel, host)
    panel:Show()
end

function RC:RefreshAll()
    for i = 1, RC.Windows() do
        local host = getglobal("GroupLootFrame" .. i)
        if host and host:IsVisible() then self:Render(i) end
    end
end

--- The whole list, under Blizzard's own "Need" / "Greed" / "Pass".
function RC:Tooltip(button)
    local host = button:GetParent()
    local r = host and host.rollID and self.rolls[host.rollID]
    if not r then return end
    local shown = 0
    for i = 1, table.getn(r.picks) do
        local p = r.picks[i]
        if p.choice == button.rollcallChoice then
            GameTooltip:AddLine(RC.NameText(p, true))
            shown = shown + 1
        end
    end
    if shown == 0 then GameTooltip:AddLine("Nobody yet", 0.5, 0.5, 0.5) end
    GameTooltip:Show()
end

--[[ Wrap, never replace: Blizzard's own OnShow still sets the window up,
     and its OnEnter still writes "Need".

     `this` is read before calling Blizzard's code, never after. It is a
     global, and any script that runs in between - the tooltip's own OnShow,
     for one - leaves it pointing at itself. And which button is which is
     kept on the button, not in a closure over the loop's variable, which
     would read nil in the client's Lua 5.0 once the loop had moved on. ]]
function RC.HookWindow(i)
    local host = getglobal("GroupLootFrame" .. i)
    if not host or host.rollcallHooked then return end
    host.rollcallHooked = true

    local onShow = host:GetScript("OnShow")
    host:SetScript("OnShow", function()
        local window = this
        if onShow then onShow() end
        -- Blizzard's OnShow hides a window whose item has already gone.
        if window:IsVisible() then RC:Render(window:GetID()) end
    end)

    for n = 1, 3 do
        local choice = RC.ORDER[n]
        local button = getglobal(host:GetName() .. BUTTONS[choice])
        if button then
            button.rollcallChoice = choice
            local onEnter = button:GetScript("OnEnter")
            button:SetScript("OnEnter", function()
                local hovered = this
                if onEnter then onEnter() end
                RC:Tooltip(hovered)
            end)
        end
    end
end

--[[ What you click says which roll your own pick was for, which the chat
     line cannot when the same item is up twice. Only a hint, though: the
     chat line is what says the pick really happened - a bind-on-pickup Need
     can still be cancelled at the confirmation. ]]
function RC.HookRollOnLoot()
    if RC.rollHooked or not RollOnLoot then return end
    RC.rollHooked = true
    local real = RollOnLoot
    RollOnLoot = function(id, rollType)
        -- The pretend roll never reaches the server.
        if id == RC.TEST_ID then
            RC:EndTest()
            return
        end
        if id then RC.ownHint[id] = CHOICE_OF[rollType] end
        return real(id, rollType)
    end
end

----------------------------------------------------------------------
-- /rollcall test: a pretend roll on a real window
----------------------------------------------------------------------

--[[ Blizzard's window asks the game about its roll, and would hide itself
     for one the game has never heard of. So while a test is up, those
     questions about the pretend roll are answered here. Installed on first
     use only, and every real roll passes straight through. ]]
function RC:WrapRollAPI()
    if self.wrapped then return end
    self.wrapped = true
    local realInfo, realLink = GetLootRollItemInfo, GetLootRollItemLink
    local realLeft = GetLootRollTimeLeft

    GetLootRollItemInfo = function(id)
        if id == RC.TEST_ID and RC.test then
            local name, _, quality, _, _, _, _, _, texture = GetItemInfo(RC.test.key)
            return texture, name, 1, quality, nil
        end
        return realInfo(id)
    end
    GetLootRollItemLink = function(id)
        if id == RC.TEST_ID and RC.test then return RC.test.link end
        return realLink(id)
    end
    GetLootRollTimeLeft = function(id)
        if id == RC.TEST_ID and RC.test then
            return math.max(0, (RC.test.ends - GetTime()) * 1000)
        end
        return realLeft(id)
    end
end

local DEMO_NAMES = { DRUID = "Druid", HUNTER = "Hunter", MAGE = "Mage", PALADIN = "Paladin",
                     PRIEST = "Priest", ROGUE = "Rogue", SHAMAN = "Shaman",
                     WARLOCK = "Warlock", WARRIOR = "Warrior" }

-- Chest first: armor is where "can't use" usually shows.
local TEST_SLOTS = { 5, 7, 1, 3, 10, 8, 6, 9, 16, 17, 18, 15, 2, 11, 12, 13, 14, 4, 19 }

function RC:Test()
    if self.test then self:EndTest() end
    local link
    for i = 1, table.getn(TEST_SLOTS) do
        link = GetInventoryItemLink("player", TEST_SLOTS[i])
        if link then break end
    end
    local key = RC.ItemKey(link)
    if not key or not GetItemInfo(key) then
        RC.Say("equip something first - the test puts one of your own items up for a pretend roll.")
        return
    end

    self:WrapRollAPI()
    self.rolls[RC.TEST_ID] = nil
    self.test = { link = link, key = key, ends = GetTime() + RC.TEST_SECONDS }
    GroupLootFrame_OpenNewFrame(RC.TEST_ID, RC.TEST_SECONDS * 1000)

    local opened = false
    for i = 1, RC.Windows() do
        local host = getglobal("GroupLootFrame" .. i)
        if host and host:IsVisible() and host.rollID == RC.TEST_ID then opened = true end
    end
    local r = opened and self:Record(RC.TEST_ID, RC.TEST_SECONDS * 1000)
    if not r then
        self.test = nil
        RC.Say("all four roll windows are in use - try again when they close.")
        return
    end

    -- A believable group, with a ninja if any class is barred from this item.
    local ninja = RC.BarredClass(key) or "ROGUE"
    local demo = {
        { "Tankadin", RC.NEED, "PALADIN" }, { "Sneakyboi", RC.NEED, ninja },
        { "Healzor", RC.GREED, "PRIEST" }, { "Pewpew", RC.GREED, "HUNTER" },
        { "Afkbob", RC.PASS, "WARLOCK" },
    }
    for i = 1, table.getn(demo) do
        local d = demo[i]
        local pick = { name = d[1], choice = d[2], class = d[3], className = DEMO_NAMES[d[3]] }
        if pick.choice == RC.NEED then pick.cannot = RC.CannotUse(pick.class, key) end
        r.seen[pick.name] = pick.choice
        table.insert(r.picks, pick)
    end
    self:RefreshAll()

    self.eventFrame:SetScript("OnUpdate", function()
        if RC.test and GetTime() >= RC.test.ends then RC:EndTest() end
    end)
    RC.Say("a pretend roll is up for " .. RC.TEST_SECONDS .. " seconds. Hover the buttons " ..
        "for the full lists; nothing you click on it reaches the server.")
end

function RC:EndTest()
    self.eventFrame:SetScript("OnUpdate", nil)
    if not self.test then return end
    self.test = nil
    self.rolls[RC.TEST_ID] = nil
    for i = 1, RC.Windows() do
        local host = getglobal("GroupLootFrame" .. i)
        if host and host.rollID == RC.TEST_ID then host:Hide() end
    end
end

----------------------------------------------------------------------
-- settings and commands
----------------------------------------------------------------------

--[[ Without Detailed Loot Information the game reports only the winner,
     never who picked what, and Rollcall would have nothing to show beside
     the windows. So it is switched on once, saying so. If you turn it off
     again afterwards, that is your call: from then on Rollcall only reminds
     you. ]]
function RC:Init()
    local db = self:DB()
    if db.warn == nil then db.warn = true end
    if GetCVar("showLootSpam") == "0" then
        if not db.detailSet then
            SetCVar("showLootSpam", "1")
            db.detailSet = true
            RC.Say("turned on Detailed Loot Information (Interface Options). Without it " ..
                "the game says only who won, never who picked what.")
        else
            RC.Say("Detailed Loot Information is off, so nobody's picks can be shown. " ..
                "/rollcall detail turns it back on.")
        end
    else
        db.detailSet = true
    end
    if RC.history then RC.history:Init() end
end

function RC:Status()
    local detail = GetCVar("showLootSpam") ~= "0"
    local state = "|cff40ff40on|r"
    if not detail then state = "|cffff4040OFF|r - picks can't be seen; /rollcall detail turns it on" end
    local warn = "on"
    if not self:DB().warn then warn = "off" end
    RC.Say("v" .. RC.VERSION .. ". Detailed Loot Information " .. state ..
        ". Chat warnings " .. warn .. ".")
    RC.Say("/rollcall history - who rolled what and who won; tick rolls to announce them")
    RC.Say("/rollcall find <item or name> - search it here; /rollcall report <#> party|raid|guild|w <name>")
    RC.Say("/rollcall test - a pretend roll, to see it without waiting for a drop")
    RC.Say("/rollcall warn on|off - the chat line when someone Needs what their class can't use")
    RC.Say("/rollcall raid uncommon|rare|epic|legendary - what a raid's history keeps (now " ..
        RC.QualityName(self:RaidQuality()) .. " and better)")
end

function RC:Slash(msg)
    local _, _, cmd, rest = string.find(msg or "", "^%s*(%S*)%s*(.-)%s*$")
    cmd = string.lower(cmd or "")
    rest = rest or ""
    local db = self:DB()
    if cmd == "test" then
        self:Test()
    elseif cmd == "warn" then
        local how = string.lower(rest)
        if how == "off" then db.warn = false
        elseif how == "on" then db.warn = true
        else db.warn = not db.warn end
        if db.warn then RC.Say("chat warnings on.") else RC.Say("chat warnings off.") end
    elseif cmd == "detail" then
        SetCVar("showLootSpam", "1")
        RC.Say("Detailed Loot Information is on.")
    elseif cmd == "raid" then
        self:SetRaidQuality(rest)
    elseif RC.history and RC.history:Slash(cmd, rest) then
        -- history, log, find, report, last
    else
        self:Status()
    end
end

----------------------------------------------------------------------
-- events
----------------------------------------------------------------------

function RC:OnEvent(e, a1, a2)
    if e == "CHAT_MSG_LOOT" then
        self:HandleLine(a1)
    elseif e == "START_LOOT_ROLL" then
        self:Prune()
        -- A fresh roll, even if an old one once had this id.
        local old = self.rolls[a1]
        if old then
            self:Commit(old)
            self.rolls[a1] = nil
        end
        self:Record(a1, a2)
        self:RefreshAll()
    elseif e == "CHAT_MSG_SYSTEM" then
        self:OnSystem(a1)
    elseif e == "CHAT_MSG_RAID_WARNING" then
        self:OnAnnounce(a1, a2, true)
    elseif e == "CHAT_MSG_RAID" or e == "CHAT_MSG_RAID_LEADER" or e == "CHAT_MSG_PARTY" then
        self:OnAnnounce(a1, a2)
    elseif e == "CHAT_MSG_WHISPER" then
        -- Whoever asks you who won something usually asks by whisper.
        self.lastWhisper = a2
    elseif e == "PLAYER_LOGOUT" then
        -- Rolls still waiting for a winner are kept with what they have.
        for _, r in pairs(self.rolls) do self:Commit(r) end
    elseif e == "VARIABLES_LOADED" then
        self:Init()
    end
end

local events = CreateFrame("Frame", "RollcallEventFrame")
RC.eventFrame = events
events:RegisterEvent("VARIABLES_LOADED")
events:RegisterEvent("START_LOOT_ROLL")
events:RegisterEvent("CHAT_MSG_LOOT")
events:RegisterEvent("CHAT_MSG_WHISPER")
events:RegisterEvent("PLAYER_LOGOUT")
-- Master loot: the /roll lines, and the master looter linking what is up.
events:RegisterEvent("CHAT_MSG_SYSTEM")
events:RegisterEvent("CHAT_MSG_RAID")
events:RegisterEvent("CHAT_MSG_RAID_LEADER")
events:RegisterEvent("CHAT_MSG_RAID_WARNING")
events:RegisterEvent("CHAT_MSG_PARTY")
events:SetScript("OnEvent", function() RC:OnEvent(event, arg1, arg2) end)

-- FrameXML is loaded before any addon, so the four windows exist already.
for i = 1, RC.Windows() do RC.HookWindow(i) end
RC.HookRollOnLoot()

SLASH_ROLLCALL1 = "/rollcall"
SlashCmdList["ROLLCALL"] = function(msg) RC:Slash(msg) end
