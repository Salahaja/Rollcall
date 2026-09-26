--[[
    Rollcall - who picked Need, Greed and Pass, on the normal roll windows.

    While Detailed Loot Information is on, the game prints a line for every
    pick the moment it is made: "Bob has selected Need for: [Item]". That is
    the only place the information exists, so Rollcall reads those lines and
    writes them beside Blizzard's own roll windows, which it otherwise leaves
    alone: same size, same place, same buttons.

    Beside each window: who has picked Need, Greed and Pass so far, in class
    colors, with a count on each of Blizzard's buttons and the whole list in
    the button's tooltip. A Need from a class that can never use the item (a
    mage needing mail) is marked in red and noted in your chat.

    Slash command: /rollcall
--]]

Rollcall = {}
local RC = Rollcall

RC.VERSION = "1.0.0"
RC.NEED, RC.GREED, RC.PASS = "NEED", "GREED", "PASS"
RC.ORDER = { "NEED", "GREED", "PASS" }
RC.MAX_NAMES = 4        -- names on a line before it says "+N"
RC.GRACE = 5            -- seconds a roll is kept after its timer runs out
RC.TEST_ID = -4242      -- the pretend roll /rollcall test puts up
RC.TEST_SECONDS = 30
RC.PANEL_MIN_W, RC.PANEL_MAX_W = 110, 340

RC.rolls = {}           -- [rollID] = record; see RC:Record
RC.seq = 0
RC.panels = {}          -- [window index] = the panel beside GroupLootFrameN

-- Blizzard's names for the three buttons on a roll window.
local BUTTONS = { NEED = "RollButton", GREED = "GreedButton", PASS = "PassButton" }

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

----------------------------------------------------------------------
-- reading the chat lines
----------------------------------------------------------------------

--[[ The strings come from the client's own GlobalStrings, so this reads the
     language the game is in. They spell the item out in parts - color,
     "|Hitem:%d:%d:%d:%d|h", "[%s]", "|h%s" - and one capture for the whole
     link is all that is needed, so that part becomes a single %s first. ]]
local ITEM_PARTS = "%s|Hitem:%d:%d:%d:%d|h[%s]|h%s"

local function escape(s)
    return (string.gsub(s, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

--- A GlobalStrings format as an anchored Lua pattern with one capture per %s.
function RC.Pattern(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    local a, b = string.find(fmt, ITEM_PARTS, 1, true)
    if a then fmt = string.sub(fmt, 1, a - 1) .. "%s" .. string.sub(fmt, b + 1) end
    local out, pos = "^", 1
    while true do
        local s, e = string.find(fmt, "%s", pos, true)
        if not s then break end
        out = out .. escape(string.sub(fmt, pos, s - 1)) .. "(.+)"
        pos = e + 1
    end
    return out .. escape(string.sub(fmt, pos)) .. "$"
end

local MATCHERS

local function matchers()
    if MATCHERS then return MATCHERS end
    MATCHERS = {}
    local function add(fmt, choice)
        local p = RC.Pattern(fmt)
        if p then table.insert(MATCHERS, { p, choice }) end
    end
    -- The specific ones first: "Everyone passed on" and "You passed on" are
    -- also "<name> passed on", and must not become a player called Everyone.
    add(LOOT_ROLL_ALL_PASSED, false)
    add(LOOT_ROLL_NEED_SELF, false)
    add(LOOT_ROLL_GREED_SELF, false)
    add(LOOT_ROLL_PASSED_SELF, false)
    add(LOOT_ROLL_NEED, RC.NEED)
    add(LOOT_ROLL_GREED, RC.GREED)
    add(LOOT_ROLL_PASSED, RC.PASS)
    return MATCHERS
end

--- "Bob has selected Need for: [Item]" -> "Bob", "NEED", the link. Nil for
--- every other line, your own picks included: your window already knows.
function RC.Parse(msg)
    if type(msg) ~= "string" then return nil end
    local list = matchers()
    for i = 1, table.getn(list) do
        local _, _, who, link = string.find(msg, list[i][1])
        if who then
            if not list[i][2] then return nil end
            return who, list[i][2], link
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
     those picks still have to land on the right roll - which matters when
     the same item is up twice. So a record lasts until its own timer plus a
     few seconds, not until the window closes. ]]
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
    self.seq = self.seq + 1
    r = { id = rollID, seq = self.seq, link = link, key = key, itemId = itemId,
          expires = GetTime() + ms / 1000 + RC.GRACE, picks = {}, seen = {} }
    self.rolls[rollID] = r
    return r
end

function RC:Prune()
    local now = GetTime()
    for id, r in pairs(self.rolls) do
        if now > r.expires then self.rolls[id] = nil end
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
    if choice == RC.NEED then pick.cannot = RC.CannotUse(class, key) end
    return pick
end

--[[ Put a pick on the roll it belongs to.

     The chat line names the item, not the roll. When the same item is up
     twice, the pick goes to the oldest open roll of it this player has not
     picked on yet. Everyone picks once per roll, so that fills both rolls
     completely whichever one is clicked first. ]]
function RC:Assign(pick, key, itemId)
    self:Discover()
    local now, best = GetTime(), nil
    for pass = 1, 2 do
        for _, r in pairs(self.rolls) do
            local same = (pass == 1 and r.key == key) or (pass == 2 and r.itemId == itemId)
            if same and now <= r.expires and not r.seen[pick.name] and
               (not best or r.seq < best.seq) then
                best = r
            end
        end
        -- The exact link first; the bare item id only if nothing matched it.
        if best then break end
    end
    if not best then return nil end
    best.seen[pick.name] = pick.choice
    table.insert(best.picks, pick)
    return best
end

function RC:Warn(pick, link)
    if not self:DB().warn then return end
    local who = pick.className or pick.class or "?"
    RC.Say("|cffff4040" .. pick.name .. "|r (" .. who .. ") picked Need on " .. link ..
        " - " .. who .. "s can't use " .. pick.cannot .. ".")
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
--- class can never use. `long` says what, for the tooltip.
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

local function label(choice)
    if choice == RC.NEED then return "|cffff8040" .. (NEED or "Need") .. "|r" end
    if choice == RC.GREED then return "|cffffd100" .. (GREED or "Greed") .. "|r" end
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
    if count == 0 then return label(choice) .. "  |cff707070-|r", 0 end
    local text = label(choice) .. "  " .. table.concat(names, ", ")
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

----------------------------------------------------------------------
-- /rollcall test: a pretend roll on a real window
----------------------------------------------------------------------

--[[ Blizzard's window asks the game about its roll, and would hide itself
     for one the game has never heard of. So while a test is up, those
     questions about the pretend roll are answered here - and clicking any
     button on it goes nowhere near the server. Installed on first use only,
     and every real roll passes straight through. ]]
function RC:WrapRollAPI()
    if self.wrapped then return end
    self.wrapped = true
    local realInfo, realLink = GetLootRollItemInfo, GetLootRollItemLink
    local realLeft, realRoll = GetLootRollTimeLeft, RollOnLoot

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
    RollOnLoot = function(id, choice)
        if id == RC.TEST_ID then
            RC:EndTest()
            return
        end
        return realRoll(id, choice)
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
     never who picked what, and Rollcall would have nothing to show. So it
     is switched on once, saying so. If you turn it off again afterwards,
     that is your call: from then on Rollcall only reminds you. ]]
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
end

function RC:Status()
    local detail = GetCVar("showLootSpam") ~= "0"
    local state = "|cff40ff40on|r"
    if not detail then state = "|cffff4040OFF|r - picks can't be seen; /rollcall detail turns it on" end
    local warn = "on"
    if not self:DB().warn then warn = "off" end
    RC.Say("v" .. RC.VERSION .. ". Detailed Loot Information " .. state ..
        ". Chat warnings " .. warn .. ".")
    RC.Say("/rollcall test - a pretend roll, to see it without waiting for a drop")
    RC.Say("/rollcall warn on|off - the chat line when someone Needs what their class can't use")
end

function RC:Slash(msg)
    local _, _, cmd, rest = string.find(msg or "", "^%s*(%S*)%s*(.-)%s*$")
    cmd = string.lower(cmd or "")
    rest = string.lower(rest or "")
    local db = self:DB()
    if cmd == "test" then
        self:Test()
    elseif cmd == "warn" then
        if rest == "off" then db.warn = false
        elseif rest == "on" then db.warn = true
        else db.warn = not db.warn end
        if db.warn then RC.Say("chat warnings on.") else RC.Say("chat warnings off.") end
    elseif cmd == "detail" then
        SetCVar("showLootSpam", "1")
        RC.Say("Detailed Loot Information is on.")
    else
        self:Status()
    end
end

----------------------------------------------------------------------
-- events
----------------------------------------------------------------------

function RC:OnEvent(e, a1, a2)
    if e == "CHAT_MSG_LOOT" then
        local name, choice, link = RC.Parse(a1)
        if not name then return end
        local key, itemId = RC.ItemKey(link)
        if not key then return end
        local pick = RC.Pick(name, choice, key)
        local r = self:Assign(pick, key, itemId)
        -- Warned about even when you have no window for it yourself.
        if pick.cannot then self:Warn(pick, link) end
        if r then self:RefreshAll() end
    elseif e == "START_LOOT_ROLL" then
        self:Prune()
        -- A fresh roll, even if an old one once had this id.
        self.rolls[a1] = nil
        self:Record(a1, a2)
        self:RefreshAll()
    elseif e == "VARIABLES_LOADED" then
        self:Init()
    end
end

local events = CreateFrame("Frame", "RollcallEventFrame")
RC.eventFrame = events
events:RegisterEvent("VARIABLES_LOADED")
events:RegisterEvent("START_LOOT_ROLL")
events:RegisterEvent("CHAT_MSG_LOOT")
events:SetScript("OnEvent", function() RC:OnEvent(event, arg1, arg2) end)

-- FrameXML is loaded before any addon, so the four windows exist already.
for i = 1, RC.Windows() do RC.HookWindow(i) end

SLASH_ROLLCALL1 = "/rollcall"
SlashCmdList["ROLLCALL"] = function(msg) RC:Slash(msg) end
