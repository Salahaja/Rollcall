--[[
    HistoryFrame.lua - the loot history window.

    Somebody asks who won the thing that dropped an hour ago: find it here,
    tick it - or several - and send them to party, raid, guild or straight
    back to whoever whispered you. Boss loot and trash are kept apart, so the
    random greens a trash pack drops do not bury the one drop anybody asks
    about.

    Open with /rollcall history, or bind a key under Key Bindings > Rollcall.
--]]

local RC = Rollcall
local H = RC.history
local F = {}
H.window = F

F.ROWS = 10
F.ROW_H = 34
F.kind = nil            -- "boss", "trash" or "all"; chosen on first open
F.text = ""
F.offset = 0
F.selected = {}         -- [entry id] = true
F.withRolls = false
F.list = {}

BINDING_HEADER_ROLLCALL = "Rollcall"
BINDING_NAME_ROLLCALL_HISTORY = "Loot history"

local function button(name, parent, text, width)
    local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    b:SetWidth(width)
    b:SetHeight(22)
    b:SetText(text)
    return b
end

local function inputBox(name, parent, width)
    local box = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
    box:SetWidth(width)
    box:SetHeight(20)
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    box:SetScript("OnEnterPressed", function() this:ClearFocus() end)
    return box
end

local function newRow(list, i)
    local row = CreateFrame("Button", "RollcallHistoryRow" .. i, list)
    row:SetWidth(512)
    row:SetHeight(F.ROW_H - 2)
    row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * F.ROW_H)
    row:RegisterForClicks("LeftButtonUp")
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function() F:Scroll(-(arg1 or 0)) end)

    local hl = row:CreateTexture(nil, "BACKGROUND")
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetAllPoints(row)
    hl:Hide()
    row.hl = hl

    local box = row:CreateTexture(nil, "ARTWORK")
    box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
    box:SetWidth(24)
    box:SetHeight(24)
    box:SetPoint("LEFT", row, "LEFT", 2, 0)
    local tick = row:CreateTexture(nil, "OVERLAY")
    tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    tick:SetWidth(24)
    tick:SetHeight(24)
    tick:SetPoint("LEFT", row, "LEFT", 2, 0)
    tick:Hide()
    row.tick = tick

    local item = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    item:SetPoint("TOPLEFT", row, "TOPLEFT", 32, -3)
    item:SetWidth(270)
    item:SetHeight(14)
    item:SetJustifyH("LEFT")
    row.item = item

    local sub = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    sub:SetPoint("TOPLEFT", row, "TOPLEFT", 32, -19)
    sub:SetWidth(320)
    sub:SetHeight(12)
    sub:SetJustifyH("LEFT")
    row.sub = sub

    local outcome = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    outcome:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -4)
    outcome:SetWidth(210)
    outcome:SetHeight(14)
    outcome:SetJustifyH("RIGHT")
    row.outcome = outcome

    -- `this` is read before anything else runs; see RC.HookWindow.
    row:SetScript("OnClick", function() F:ClickRow(this) end)
    row:SetScript("OnEnter", function()
        local hovered = this
        hovered.hl:Show()
        F:RowTooltip(hovered)
    end)
    row:SetScript("OnLeave", function()
        local left = this
        left.hl:Hide()
        GameTooltip:Hide()
    end)
    return row
end

function F:Build()
    if self.frame then return self.frame end
    local f = CreateFrame("Frame", "RollcallHistoryFrame", UIParent)
    self.frame = f
    f:Hide()
    f:SetWidth(560)
    f:SetHeight(500)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:SetScript("OnShow", function() F:OnShow() end)
    -- Escape closes it, like any of Blizzard's windows.
    table.insert(UISpecialFrames, "RollcallHistoryFrame")

    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -18)
    title:SetText("Rollcall - Loot history")

    -- What a raid's history keeps; a click steps to the next rarity.
    local rarity = button("RollcallHistoryRaidRarity", f, "", 112)
    rarity:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -12)
    rarity:SetScript("OnClick", function() F.NextRarity() end)
    rarity:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText("In a raid, keep " .. RC.QualityName(RC:RaidQuality()) .. " and better")
        GameTooltip:AddLine("Click for the next rarity. Outside a raid, every roll is kept.",
            1, 1, 1, 1)
        GameTooltip:Show()
    end)
    rarity:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.rarity = rarity

    local close = CreateFrame("Button", "RollcallHistoryClose", f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)

    -- Bosses | Trash | All
    self.tabs = {}
    local tabs = { { "boss", "Bosses" }, { "trash", "Trash" }, { "all", "All" } }
    for i = 1, 3 do
        local tab = button("RollcallHistoryTab" .. i, f, tabs[i][2], 72)
        tab:SetPoint("TOPLEFT", f, "TOPLEFT", 20 + (i - 1) * 76, -42)
        tab.kind = tabs[i][1]
        tab:SetScript("OnClick", function() F:SetKind(this.kind) end)
        self.tabs[i] = tab
    end

    local search = inputBox("RollcallHistorySearch", f, 150)
    search:SetPoint("TOPRIGHT", f, "TOPRIGHT", -26, -42)
    search:SetScript("OnTextChanged", function()
        F.text = this:GetText() or ""
        F.offset = 0
        F:Refresh()
    end)
    self.search = search
    local searchLabel = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    searchLabel:SetPoint("RIGHT", search, "LEFT", -10, 0)
    searchLabel:SetText("Search")

    local note = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -66)
    self.note = note

    local list = CreateFrame("Frame", "RollcallHistoryList", f)
    list:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -80)
    list:SetWidth(512)
    list:SetHeight(F.ROWS * F.ROW_H)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function() F:Scroll(-(arg1 or 0)) end)
    self.rows = {}
    for i = 1, F.ROWS do self.rows[i] = newRow(list, i) end

    local empty = list:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    empty:SetPoint("CENTER", list, "CENTER", 0, 0)
    self.empty = empty

    -- A page at a time; the mouse wheel goes a row at a time.
    local up = CreateFrame("Button", "RollcallHistoryUp", f)
    up:SetWidth(24)
    up:SetHeight(24)
    up:SetPoint("TOPLEFT", list, "TOPRIGHT", 2, 0)
    up:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up")
    up:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Down")
    up:SetScript("OnClick", function() F:Scroll(-F.ROWS) end)
    local down = CreateFrame("Button", "RollcallHistoryDown", f)
    down:SetWidth(24)
    down:SetHeight(24)
    down:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 2, 0)
    down:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    down:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
    down:SetScript("OnClick", function() F:Scroll(F.ROWS) end)

    local range = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    range:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", 0, -4)
    self.range = range

    -- What is ticked, and whether to post everyone's rolls with it.
    local picked = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    picked:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 24, 56)
    self.picked = picked
    local clear = button("RollcallHistoryClear", f, "Untick all", 80)
    clear:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 100, 51)
    clear:SetScript("OnClick", function()
        F.selected = {}
        F:Refresh(true)
    end)
    local rolls = CreateFrame("CheckButton", "RollcallHistoryWithRolls", f, "UICheckButtonTemplate")
    rolls:SetWidth(24)
    rolls:SetHeight(24)
    rolls:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 300, 50)
    getglobal("RollcallHistoryWithRollsText"):SetText("with everyone's rolls")
    rolls:SetScript("OnClick", function() F.withRolls = this:GetChecked() and true or false end)

    -- Where it goes.
    local sendLabel = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    sendLabel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 24, 25)
    sendLabel:SetText("Send to")
    local where = { { "PARTY", "Party" }, { "RAID", "Raid" }, { "GUILD", "Guild" },
                    { "WHISPER", "Whisper" } }
    for i = 1, 4 do
        local b = button("RollcallHistorySend" .. i, f, where[i][2], 72)
        b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 80 + (i - 1) * 76, 20)
        b.where = where[i][1]
        b:SetScript("OnClick", function() F:Send(this.where) end)
    end
    local whisper = inputBox("RollcallHistoryWhisperTo", f, 120)
    whisper:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 394, 21)
    self.whisper = whisper

    return f
end

function F:Toggle()
    local f = self:Build()
    if f:IsVisible() then f:Hide() else f:Show() end
end

function F:OnShow()
    if not self.kind then
        if H.CanClassify() then self.kind = "boss" else self.kind = "all" end
    end
    -- Whoever asks you who won something usually asks by whisper.
    local typed = self.whisper:GetText()
    if not typed or typed == "" then
        local who = RC.lastWhisper
        if not who and UnitIsPlayer and UnitIsPlayer("target") then who = UnitName("target") end
        if who then self.whisper:SetText(who) end
    end
    self:Refresh()
end

function F:SetKind(kind)
    self.kind = kind
    self.offset = 0
    self:Refresh()
end

function F:Scroll(delta)
    self.offset = self.offset + delta
    self:Refresh(true)
end

--- One pick for a tooltip: the name in class color (red for a Need the
--- class can never use), its roll, and why it is red.
function F.PickText(p)
    local s = p.name
    if p.cannot then
        s = "|cffff2020" .. s .. "|r"
    else
        local hex = RC.ClassHex(p.class)
        if hex then s = "|cff" .. hex .. s .. "|r" end
    end
    if p.roll and p.choice ~= RC.PASS then s = s .. " " .. p.roll end
    if p.cannot then s = s .. " |cffff2020(can't use " .. p.cannot .. ")|r" end
    if p.again then s = s .. " |cffff2020(rolled " .. p.again .. "x)|r" end
    return s
end

--- The right-hand side of a row: who won and how, in color.
function F.OutcomeText(entry)
    local flag = ""
    if entry.x then flag = "|cffff2020(!)|r " end
    if entry.s == "master" and entry.w then
        local name = entry.w
        local hex = RC.ClassHex(entry.wk)
        if hex then name = "|cff" .. hex .. name .. "|r" end
        local choice = H.WinnerChoice(entry)
        if choice and entry.wr then return flag .. name .. "  " .. RC.Label(choice) .. " " .. entry.wr end
        return flag .. name .. "  |cff909090given|r"
    end
    if entry.s == "won" and entry.w then
        local name = entry.w
        local hex = RC.ClassHex(entry.wk)
        if hex then name = "|cff" .. hex .. name .. "|r" end
        local how = ""
        local choice = H.WinnerChoice(entry)
        if choice then how = "  " .. RC.Label(choice) end
        if entry.wr then how = how .. " " .. entry.wr end
        return flag .. name .. how
    end
    if entry.s == "passed" then return flag .. "|cff909090everyone passed|r" end
    return flag .. "|cff909090no winner seen|r"
end

function F.EmptyText(kind, text)
    if text and text ~= "" then return "Nothing matches \"" .. text .. "\"." end
    if kind == "boss" then return "No boss loot yet. Everything else is under Trash." end
    if kind == "trash" then return "No trash or world drops yet." end
    return "No rolls yet. Each one appears here as soon as it is won."
end

local RARITY_WORDS = { [2] = "uncommon", [3] = "rare", [4] = "epic", [5] = "legendary" }

--- Uncommon, rare, epic, legendary, and round again.
function F.NextRarity()
    local q = RC:RaidQuality() + 1
    if not RARITY_WORDS[q] then q = 2 end
    RC:SetRaidQuality(RARITY_WORDS[q])
end

function F:Refresh(keepList)
    if not self.frame or not self.frame:IsVisible() then return end
    if self.rarity then
        self.rarity:SetText("Raid: " .. RC.QualityName(RC:RaidQuality()) .. "+")
    end
    local sortable = H.CanClassify()
    for i = 1, 3 do
        local tab = self.tabs[i]
        if tab.kind == self.kind then tab:LockHighlight() else tab:UnlockHighlight() end
        if tab.kind ~= "all" and not sortable then tab:Disable() else tab:Enable() end
    end
    if sortable then
        self.note:SetText("")
    else
        self.note:SetText("Install AtlasLoot to sort boss loot from trash.")
    end

    if not keepList then self.list = H:List(self.kind, self.text) end
    local count = table.getn(self.list)
    local most = math.max(0, count - F.ROWS)
    if self.offset > most then self.offset = most end
    if self.offset < 0 then self.offset = 0 end

    for i = 1, F.ROWS do
        local row = self.rows[i]
        local entry = self.list[self.offset + i]
        row.entry = entry
        if entry then
            row.item:SetText(H.ItemText(entry))
            row.sub:SetText(H.SourceText(entry) .. "    " .. H.When(entry.t))
            row.outcome:SetText(F.OutcomeText(entry))
            if self.selected[entry.id] then row.tick:Show() else row.tick:Hide() end
            row:Show()
        else
            row:Hide()
        end
    end

    if count == 0 then
        self.empty:SetText(F.EmptyText(self.kind, self.text))
    else
        self.empty:SetText("")
    end
    if count > F.ROWS then
        self.range:SetText((self.offset + 1) .. "-" .. math.min(count, self.offset + F.ROWS) ..
            " of " .. count)
    else
        self.range:SetText("")
    end
    local ticked = 0
    for _ in pairs(self.selected) do ticked = ticked + 1 end
    self.picked:SetText(ticked .. " ticked")
end

function F:ClickRow(row)
    local entry = row.entry
    if not entry then return end
    if IsShiftKeyDown() then
        if entry.l and ChatFrameEditBox and ChatFrameEditBox:IsVisible() then
            ChatFrameEditBox:Insert(entry.l)
        end
        return
    end
    if IsControlKeyDown() then
        if entry.l and DressUpItemLink then DressUpItemLink(entry.l) end
        return
    end
    if self.selected[entry.id] then
        self.selected[entry.id] = nil
    else
        self.selected[entry.id] = true
    end
    self:Refresh(true)
end

function F:RowTooltip(row)
    local entry = row.entry
    if not entry then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(H.ItemText(entry))
    GameTooltip:AddLine(H.SourceText(entry), 0.7, 0.7, 0.7)
    GameTooltip:AddLine(H.Outcome(entry), 1, 1, 1)
    local picks = H.Unpack(entry.p)
    local order = H.Order(entry)
    for n = 1, table.getn(order) do
        local choice = order[n]
        local names = {}
        for i = 1, table.getn(picks) do
            if picks[i].choice == choice then table.insert(names, F.PickText(picks[i])) end
        end
        if table.getn(names) > 0 then
            GameTooltip:AddLine(RC.Label(choice) .. "  " .. table.concat(names, ", "), 1, 1, 1, 1)
        end
    end
    if entry.top then
        GameTooltip:AddLine("Best roll was " .. entry.top .. "'s, and it went to " ..
            (entry.w or "?") .. ".", 1, 0.5, 0.25, 1)
    end
    if entry.ml then GameTooltip:AddLine("Master looter: " .. entry.ml, 0.7, 0.7, 0.7) end
    local when = H.When(entry.t)
    if entry.z and entry.z ~= "" then when = entry.z .. "   " .. when end
    GameTooltip:AddLine(when, 0.5, 0.5, 0.5)
    GameTooltip:AddLine("Click to tick it. Shift-click links the item; Ctrl-click tries it on.",
        0.4, 0.8, 1, 1)
    GameTooltip:Show()
end

--- Post everything ticked, oldest first: the order it dropped in.
function F:Send(where)
    local picked, all = {}, H:DB().history
    for i = 1, table.getn(all) do
        if self.selected[all[i].id] then table.insert(picked, all[i]) end
    end
    if table.getn(picked) == 0 then
        RC.Say("tick the rolls you want to announce first.")
        return
    end
    local target
    if where == "WHISPER" then target = self.whisper:GetText() end
    H:Announce(picked, where, target, self.withRolls)
end

-- A roll that finishes while the window is open shows up in it at once.
H.onChange = function() F:Refresh() end
