--[[
    History.lua - every finished roll: who picked what, who rolled what, who
    won, and where it dropped. Kept in RollcallDB.history, newest last.

    "Where it dropped" comes from AtlasLoot's own loot tables when AtlasLoot
    is installed: an item on a boss's table is that boss's loot, one on a
    "Trash Mobs" table is trash, and one on no table at all is a world drop -
    the random greens, which are exactly what the Trash tab is there to keep
    out of the way. Without AtlasLoot nothing can be said and everything is
    simply listed.
--]]

local RC = Rollcall
local H = {}
RC.history = H

H.MAX = 500             -- rolls kept; the oldest go first
H.SEND_GAP = 0.4        -- seconds between announced lines: a burst can get you muted
H.LINE_MAX = 250        -- a chat message takes 255
H.queue = {}

local LETTER = { NEED = "N", GREED = "G", PASS = "P", MS = "M", OS = "O", TMOG = "T" }
local CHOICE = { N = "NEED", G = "GREED", P = "PASS", M = "MS", O = "OS", T = "TMOG" }

function H:DB()
    local db = RC:DB()
    if type(db.history) ~= "table" then db.history = {} end
    if type(db.nextId) ~= "number" then db.nextId = 1 end
    return db
end

function H:Init()
    self:DB()
end

----------------------------------------------------------------------
-- where it dropped
----------------------------------------------------------------------

local sources = {}

function H.CanClassify()
    return type(AtlasLoot_Data) == "table" and type(AtlasLoot_TableNames) == "table"
end

--- "[52-60] Blackrock Depths" in color, as AtlasLoot labels it, to the name.
local function placeName(label)
    local s = string.gsub(label or "", "|c%x%x%x%x%x%x%x%x", "")
    s = string.gsub(s, "|r", "")
    s = string.gsub(s, "^%s*%[[^%]]*%]%s*", "")
    return s
end

--[[ Every boss or trash table an item is on. Instance loot and world
     bosses only: crafting, reputation and PvP tables list items that do not
     drop from anything. Looked up once per item and remembered. ]]
local function lookup(itemId)
    local found = {}
    for key, info in pairs(AtlasLoot_TableNames) do
        local set = type(info) == "table" and info[2]
        if set == "AtlasLootItems" or set == "AtlasLootWBItems" then
            local rows = AtlasLoot_Data[set] and AtlasLoot_Data[set][key]
            if type(rows) == "table" then
                for i = 1, table.getn(rows) do
                    local row = rows[i]
                    if type(row) == "table" and row[1] == itemId then
                        table.insert(found, { trash = string.find(key, "Trash") ~= nil,
                                              boss = info[1], place = placeName(info[3]) })
                        break
                    end
                end
            end
        end
    end
    return found
end

--[[ "boss", "trash", "world" or "?", then the boss's name and the place.

     Where it actually dropped decides first. An item that is both a boss's
     loot in one dungeon and trash loot in the one you are standing in
     dropped from trash. ]]
function H.SourceOf(itemId, zone)
    if not itemId then return "world" end
    if not H.CanClassify() then return "?" end
    local found = sources[itemId]
    if not found then
        found = lookup(itemId)
        sources[itemId] = found
    end
    for pass = 1, 4 do
        local wantTrash = pass == 2 or pass == 4
        local hereOnly = pass <= 2
        for i = 1, table.getn(found) do
            local f = found[i]
            if f.trash == wantTrash and (not hereOnly or f.place == zone) then
                if f.trash then return "trash", nil, f.place end
                return "boss", f.boss, f.place
            end
        end
    end
    return "world"
end

----------------------------------------------------------------------
-- keeping it
----------------------------------------------------------------------

--[[ Picks are kept as one short string per roll, "Bob:N:87:MAGE:Mail;...",
     rather than a table each: SavedVariables are written out as Lua source
     at every logout and read back at every login, and a raid's worth of
     picks per roll adds up. Names cannot contain ":" or ";". A sixth field,
     how many times they /rolled, is there only when it was more than once. ]]
function H.Pack(picks)
    local out = {}
    for i = 1, table.getn(picks) do
        local p = picks[i]
        local roll = ""
        if p.roll then roll = tostring(p.roll) end
        local s = p.name .. ":" .. (LETTER[p.choice] or "?") .. ":" .. roll .. ":" ..
            (p.class or "") .. ":" .. (p.cannot or "")
        if p.again then s = s .. ":" .. p.again end
        table.insert(out, s)
    end
    return table.concat(out, ";")
end

function H.Unpack(s)
    local picks = {}
    for part in string.gfind(s or "", "[^;]+") do
        local _, _, name, c, roll, class, cannot, again =
            string.find(part, "^([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):?([^:]*)$")
        if name and name ~= "" then
            local pick = { name = name, choice = CHOICE[c] or "?", roll = tonumber(roll) }
            if class ~= "" then pick.class = class end
            if cannot ~= "" then pick.cannot = cannot end
            if again ~= "" then pick.again = tonumber(again) end
            table.insert(picks, pick)
        end
    end
    return picks
end

--- A roll's picks in the order they are shown: Need/Greed/Pass for the
--- game's rolls, main spec/off spec/transmog for master loot.
function H.Order(entry)
    if entry.s == "master" then return RC.ML_ORDER end
    return RC.ORDER
end

--- A finished roll, from Rollcall's record of it (see RC:Commit).
function H:Add(r)
    local db = self:DB()
    local kind, boss, place = H.SourceOf(r.itemId, r.zone)
    local winner = r.winner and RC.FindPick(r, r.winner)
    local flagged
    for i = 1, table.getn(r.picks) do
        if r.picks[i].cannot then flagged = 1 end
    end
    local _, _, quality = GetItemInfo(r.key)
    local entry = {
        id = db.nextId, t = r.startedAt, l = RC.CleanLink(r.link),
        n = RC.LinkName(r.link) or "?", q = quality, z = r.zone,
        k = kind, b = boss, pl = place, s = r.status, w = r.winner, x = flagged,
        p = H.Pack(r.picks),
        -- Master loot: who handed it out, a stack's size, and who rolled
        -- best when that was not who got it.
        ml = r.looter, c = r.count, top = r.top,
    }
    if winner then
        entry.wc = LETTER[winner.choice]
        entry.wr = winner.roll
        entry.wk = winner.class
    elseif r.winner then
        -- Given without a roll of theirs: their class from the group.
        entry.wk = (RC.ClassOf(r.winner))
    end
    db.nextId = db.nextId + 1
    table.insert(db.history, entry)
    local max = db.maxHistory or H.MAX
    while table.getn(db.history) > max do table.remove(db.history, 1) end
    if self.onChange then self.onChange() end
    return entry
end

function H:Clear()
    self:DB().history = {}
    if self.onChange then self.onChange() end
end

----------------------------------------------------------------------
-- finding it
----------------------------------------------------------------------

--- kind: "boss", "trash" (trash, world drops and anything unknown) or "all".
--- text: any part of the item, the winner, anyone who rolled, the boss or
--- the place, in any case.
function H.Matches(entry, kind, text)
    if kind == "boss" and entry.k ~= "boss" then return false end
    if kind == "trash" and entry.k == "boss" then return false end
    if text and text ~= "" then
        local hay = string.lower((entry.n or "") .. " " .. (entry.w or "") .. " " ..
            (entry.b or "") .. " " .. (entry.pl or "") .. " " .. (entry.z or "") .. " " ..
            (entry.p or "") .. " " .. (entry.ml or ""))
        if not string.find(hay, string.lower(text), 1, true) then return false end
    end
    return true
end

--- Matching rolls, newest first.
function H:List(kind, text)
    local out, all = {}, self:DB().history
    for i = table.getn(all), 1, -1 do
        if H.Matches(all[i], kind, text) then table.insert(out, all[i]) end
    end
    return out
end

function H:Get(id)
    local all = self:DB().history
    for i = table.getn(all), 1, -1 do
        if all[i].id == id then return all[i] end
    end
    return nil
end

----------------------------------------------------------------------
-- saying it
----------------------------------------------------------------------

local function word(choice)
    if choice == "NEED" then return NEED or "Need" end
    if choice == "GREED" then return GREED or "Greed" end
    if choice == "PASS" then return PASS or "Pass" end
    if choice == "MS" then return "MS" end
    if choice == "OS" then return "OS" end
    if choice == "TMOG" then return "Tmog" end
    return nil
end

--- "won by Bob (Need 87)", "everyone passed" or "no winner seen"; for
--- master loot, "won by Bob (MS 87)", or "given to Bob" with no roll of his.
function H.Outcome(entry)
    if entry.s == "master" and entry.w then
        local how = word(CHOICE[entry.wc])
        if how and entry.wr then return "won by " .. entry.w .. " (" .. how .. " " .. entry.wr .. ")" end
        return "given to " .. entry.w
    end
    if entry.s == "won" and entry.w then
        local how = word(CHOICE[entry.wc])
        if how and entry.wr then
            how = how .. " " .. entry.wr
        elseif entry.wr then
            how = tostring(entry.wr)
        end
        if how then return "won by " .. entry.w .. " (" .. how .. ")" end
        return "won by " .. entry.w
    end
    if entry.s == "passed" then return "everyone passed" end
    return "no winner seen"
end

--- How the winner won: "NEED", "GREED" or nil when it was never said.
function H.WinnerChoice(entry)
    return CHOICE[entry.wc]
end

--- The item link when there is one, else its name in brackets; "x2" for a stack.
function H.ItemText(entry)
    local s = entry.l or ("[" .. (entry.n or "?") .. "]")
    if entry.c and entry.c > 1 then s = s .. "x" .. entry.c end
    return s
end

function H.SourceText(entry)
    local place = ""
    if entry.pl and entry.pl ~= "" then place = " - " .. entry.pl end
    if entry.k == "boss" then return (entry.b or "?") .. place end
    if entry.k == "trash" then return "Trash" .. place end
    if entry.k == "world" then return "World drop" end
    if entry.z and entry.z ~= "" then return entry.z end
    return "?"
end

function H.When(t)
    if not t or t == 0 or not date then return "?" end
    local day = date("%m/%d", t)
    if day == date("%m/%d", time()) then return date("%H:%M", t) end
    return day .. " " .. date("%H:%M", t)
end

--- One line for your own chat frame, with the id to report it by.
function H.LocalLine(entry)
    return "|cff808080#" .. entry.id .. "|r " .. H.ItemText(entry) .. " - " .. H.Outcome(entry) ..
        " |cff808080(" .. H.SourceText(entry) .. ", " .. H.When(entry.t) .. ")|r"
end

--[[ The lines to post for one roll: the item and who won, then - if asked
     for - everybody's picks and rolls, split so that no line is too long
     for one chat message. Nothing but the item itself is a link, and no
     other "|" goes out: it is chat's escape character. ]]
function H.ChatLines(entry, withRolls)
    local head = H.ItemText(entry)
    if entry.k == "boss" and entry.b then head = head .. " from " .. entry.b end
    local lines = { head .. " - " .. H.Outcome(entry) }
    if not withRolls then return lines end

    local picks, tokens, groups = H.Unpack(entry.p), {}, {}
    local order = H.Order(entry)
    for n = 1, table.getn(order) do
        local choice = order[n]
        local names = {}
        for i = 1, table.getn(picks) do
            local p = picks[i]
            if p.choice == choice then
                local s = p.name
                if p.roll and choice ~= RC.PASS then s = s .. " " .. p.roll end
                if p.cannot then s = s .. " (can't use " .. p.cannot .. ")" end
                if p.again then s = s .. " (rolled " .. p.again .. "x)" end
                table.insert(names, s)
            end
        end
        if table.getn(names) > 0 then table.insert(groups, { choice = choice, names = names }) end
    end
    for g = 1, table.getn(groups) do
        local names = groups[g].names
        table.insert(tokens, word(groups[g].choice) .. ":")
        for i = 1, table.getn(names) do
            local s = names[i]
            if i < table.getn(names) then
                s = s .. ","
            elseif g < table.getn(groups) then
                s = s .. ";"
            end
            table.insert(tokens, s)
        end
    end

    local line = ""
    for i = 1, table.getn(tokens) do
        local t = tokens[i]
        if line == "" then
            line = t
        elseif string.len(line) + 1 + string.len(t) <= H.LINE_MAX then
            line = line .. " " .. t
        else
            table.insert(lines, line)
            line = t
        end
    end
    if line ~= "" then table.insert(lines, line) end
    return lines
end

--- Where a line can go right now, and to whom - or nil and why not.
function H.Channel(where, target)
    where = string.upper(where or "")
    if where == "P" or where == "PARTY" then
        if GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0 then return "PARTY" end
        return nil, "you are not in a party."
    elseif where == "R" or where == "RAID" then
        if GetNumRaidMembers() > 0 then return "RAID" end
        return nil, "you are not in a raid."
    elseif where == "G" or where == "GUILD" then
        if IsInGuild and IsInGuild() then return "GUILD" end
        return nil, "you are not in a guild."
    elseif where == "W" or where == "WHISPER" or where == "TELL" then
        if target and target ~= "" then return "WHISPER", target end
        return nil, "whisper who? Type their name first."
    elseif where == "S" or where == "SAY" then
        return "SAY"
    end
    return nil, "say where: party, raid, guild or whisper <name>."
end

local sender = CreateFrame("Frame", "RollcallSender")
H.sender = sender
sender:Hide()
local waiting = 0
sender:SetScript("OnUpdate", function()
    waiting = waiting - (arg1 or 0)
    if waiting > 0 then return end
    local m = table.remove(H.queue, 1)
    if not m then
        sender:Hide()
        return
    end
    SendChatMessage(m.text, m.chat, nil, m.target)
    waiting = H.SEND_GAP
end)

--- Post rolls, oldest first, a line at a time. How many lines went out.
function H:Announce(entries, where, target, withRolls)
    local chat, to = H.Channel(where, target)
    if not chat then
        RC.Say(to)
        return 0
    end
    local n = 0
    for i = 1, table.getn(entries) do
        local lines = H.ChatLines(entries[i], withRolls)
        for j = 1, table.getn(lines) do
            table.insert(self.queue, { text = lines[j], chat = chat, target = to })
            n = n + 1
        end
    end
    if n > 0 then sender:Show() end
    return n
end

----------------------------------------------------------------------
-- commands
----------------------------------------------------------------------

function H:Find(text)
    local list = self:List("all", text)
    if table.getn(list) == 0 then
        if text == "" then RC.Say("no rolls recorded yet.")
        else RC.Say("nothing matches \"" .. text .. "\".") end
        return
    end
    for i = 1, math.min(10, table.getn(list)) do RC.Say(H.LocalLine(list[i])) end
    if table.getn(list) > 10 then
        RC.Say((table.getn(list) - 10) .. " more - search for more of the name to narrow it down.")
    end
    RC.Say("post one with /rollcall report <#> party|raid|guild|w <name>  (add \"rolls\" for everyone's rolls)")
end

--- "/rollcall report 12 15 raid", "/rollcall report 12 w Bob rolls"
function H:Report(rest)
    local ids, words = {}, {}
    for w in string.gfind(rest or "", "[^%s,]+") do table.insert(words, w) end
    local i = 1
    while words[i] do
        local _, _, num = string.find(words[i], "^#?(%d+)$")
        if not num then break end
        table.insert(ids, tonumber(num))
        i = i + 1
    end
    local where = words[i]
    local target, withRolls = nil, false
    i = i + 1
    local upper = string.upper(where or "")
    if upper == "W" or upper == "WHISPER" or upper == "TELL" then
        target = words[i]
        i = i + 1
    end
    if words[i] and string.lower(words[i]) == "rolls" then withRolls = true end

    if table.getn(ids) == 0 then
        RC.Say("which roll? /rollcall find <item or name> shows their numbers.")
        return
    end
    local entries = {}
    for n = 1, table.getn(ids) do
        local e = self:Get(ids[n])
        if e then table.insert(entries, e) else RC.Say("no roll #" .. ids[n] .. ".") end
    end
    if table.getn(entries) > 0 then self:Announce(entries, where, target, withRolls) end
end

StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs["ROLLCALL_CLEAR_HISTORY"] = {
    text = "Forget all %d rolls in Rollcall's loot history?",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function() H:Clear() end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

function H:Toggle()
    if self.window then
        self.window:Toggle()
    else
        self:Find("")
    end
end

--- The subcommands this module answers; false for anything else.
function H:Slash(cmd, rest)
    if cmd == "history" or cmd == "log" then
        if string.lower(rest) == "clear" then
            StaticPopup_Show("ROLLCALL_CLEAR_HISTORY", table.getn(self:DB().history))
        else
            self:Toggle()
        end
        return true
    elseif cmd == "find" then
        self:Find(rest)
        return true
    elseif cmd == "report" then
        self:Report(rest)
        return true
    elseif cmd == "last" then
        local all = self:DB().history
        local last = all[table.getn(all)]
        if not last then
            RC.Say("no rolls recorded yet.")
        elseif rest == "" then
            RC.Say(H.LocalLine(last))
        else
            self:Report(last.id .. " " .. rest)
        end
        return true
    end
    return false
end
