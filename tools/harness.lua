--[[
    harness.lua - as much of the 1.12 client as Rollcall touches, for the
    offline tests. `local T = dofile("tools/harness.lua")`, then T.load().

    The four roll windows are built the way the client's XML builds them and
    run Turtle WoW's own GroupLootFrame code, copied below unchanged. So the
    addon meets the real behavior: UIParent opening a window before any addon
    hears about the roll, a window that hides itself for a roll whose item
    has gone, and `this` left pointing at whatever script ran last - which
    in 1.12 is not put back when a nested script returns.

    Everything a test changes lives in T.W.
--]]

package.path = "./?.lua;" .. package.path

----------------------------------------------------------------------
-- Lua 5.0 as the client runs it
----------------------------------------------------------------------

math.mod = math.mod or math.fmod
string.gfind = string.gfind or string.gmatch
table.getn = table.getn or function(t) return #t end
table.setn = table.setn or function() end
unpack = unpack or table.unpack

--[[ The client's %d is a 32-bit C int: anything from 2^31 up prints as
     -2147483648 there. Print it the client's way. ]]
do
  local realFormat = string.format
  string.format = function(fmt, ...)
    local args = table.pack(...)
    if type(fmt) == "string" then
      local i = 0
      for spec in string.gmatch(fmt, "%%[-+ #0]*%d*%.?%d*[%a%%]") do
        if spec ~= "%%" then
          i = i + 1
          local conv = string.sub(spec, -1)
          local v = args[i]
          if (conv == "d" or conv == "i") and type(v) == "number"
             and (v >= 2147483648 or v < -2147483648) then
            args[i] = -2147483648
          end
        end
      end
    end
    return realFormat(fmt, table.unpack(args, 1, args.n))
  end
end

local T = {}
local W = {
  now = 1000, epoch0 = 1790000000, locale = "enUS", zone = "Scholomance",
  cvars = { showLootSpam = "1" }, chat = {}, said = {}, rolls = {}, sent = {},
  equipped = {}, guild = true, shift = false, ctrl = false, editOpen = false,
  inserted = {}, dressed = {}, popups = {},
  roster = { player = { "Tester", "Warrior", "WARRIOR" }, party = {}, raid = {} },
}
T.W = W

----------------------------------------------------------------------
-- checks
----------------------------------------------------------------------

T.failures, T.checks = 0, 0
function T.check(label, got, want)
  T.checks = T.checks + 1
  if got ~= want then
    T.failures = T.failures + 1
    print("  FAIL " .. label .. ": got " .. tostring(got) .. ", wanted " .. tostring(want))
  end
end

function T.done()
  print(string.format("\n%d checks, %d failed\n", T.checks, T.failures))
  if T.failures > 0 then os.exit(1) end
end

----------------------------------------------------------------------
-- the client
----------------------------------------------------------------------

function GetTime() return W.now end
function time() return W.epoch0 + math.floor(W.now) end
function date(fmt, t) return os.date(fmt, t) end
function GetCVar(k) return W.cvars[k] end
function SetCVar(k, v) W.cvars[k] = tostring(v) end
function GetLocale() return W.locale end
function GetRealZoneText() return W.zone end
function getglobal(n) return _G[n] end

DEFAULT_CHAT_FRAME = { AddMessage = function(self, m) table.insert(W.chat, m) end }
SlashCmdList = {}
UISpecialFrames = {}
StaticPopupDialogs = {}
YES, NO = "Yes", "No"

function StaticPopup_Show(which, a1) table.insert(W.popups, { which = which, arg = a1 }) end
function SendChatMessage(text, chat, lang, target)
  table.insert(W.said, { text = text, chat = chat, target = target })
end
function IsInGuild() return W.guild and 1 or nil end
function IsShiftKeyDown() return W.shift and 1 or nil end
function IsControlKeyDown() return W.ctrl and 1 or nil end
function DressUpItemLink(link) table.insert(W.dressed, link) end
ChatFrameEditBox = {
  IsVisible = function() return W.editOpen and 1 or nil end,
  Insert = function(self, text) table.insert(W.inserted, text) end,
}

-- Frames, in creation order: that is also the order events arrive in, which
-- is why UIParent (FrameXML) hears about a roll before any addon does.
local ORDERED = {}
T.ORDERED = ORDERED
local Object = {}
Object.__index = Object

local function new(kind, name, parent)
  local o = setmetatable({ _kind = kind, _name = name, _parent = parent, _shown = true,
                           _scripts = {}, _events = {}, _points = {}, _children = {},
                           _w = 0, _h = 0 }, Object)
  if parent then table.insert(parent._children, o) end
  if name then _G[name] = o end
  table.insert(ORDERED, o)
  return o
end

-- Like the client: `this` is set for the script, and not put back after.
local function run(o, script)
  local fn = o._scripts[script]
  if fn then
    this = o
    fn()
  end
end
T.run = run

function CreateFrame(kind, name, parent, template)
  local o = new(kind or "Frame", name, parent)
  if template == "UIPanelCloseButton" then
    o._scripts.OnClick = function() this:GetParent():Hide() end
  elseif template == "UICheckButtonTemplate" and name then
    new("FontString", name .. "Text", o)
  end
  o._template = template
  return o
end

function Object:GetName() return self._name end
function Object:GetParent() return self._parent end
function Object:GetID() return self._id or 0 end
function Object:SetID(id) self._id = id end
function Object:IsShown() return self._shown end
function Object:IsVisible()
  local o = self
  while o do
    if not o._shown then return false end
    o = o._parent
  end
  return true
end
function Object:Show()
  if self._shown then return end
  self._shown = true
  if self:IsVisible() then run(self, "OnShow") end
end
function Object:Hide()
  if not self._shown then return end
  self._shown = false
  run(self, "OnHide")
end
function Object:SetScript(s, fn) self._scripts[s] = fn end
function Object:GetScript(s) return self._scripts[s] end
function Object:RegisterEvent(e) self._events[e] = true end
function Object:UnregisterEvent(e) self._events[e] = nil end
function Object:SetWidth(w) self._w = w end
function Object:SetHeight(h) self._h = h end
function Object:GetWidth() return self._w end
function Object:GetHeight() return self._h end
function Object:GetEffectiveScale() return 1 end
function Object:GetRight() return self._right end
function Object:ClearAllPoints() self._points = {} end
function Object:SetPoint(point, rel, relPoint, x, y)
  table.insert(self._points, { point, rel, relPoint, x, y })
end
function Object:GetPoint(i)
  local p = self._points[i or 1]
  if p then return p[1], p[2], p[3], p[4], p[5] end
end
function Object:SetTexture(t) self._texture = t end
function Object:SetMinMaxValues(a, b) self._min, self._max = a, b end
function Object:SetText(t)
  self._text = t
  -- An edit box tells its own script when its text changes, as the client's does.
  if self._kind == "EditBox" then run(self, "OnTextChanged") end
end
function Object:GetText()
  -- An empty edit box says "", not nil.
  if self._kind == "EditBox" then return self._text or "" end
  return self._text
end
function Object:GetStringWidth()
  local plain = string.gsub(string.gsub(self._text or "", "|c%x%x%x%x%x%x%x%x", ""), "|r", "")
  return string.len(plain) * 5
end
function Object:CreateFontString(name) return new("FontString", name, self) end
function Object:CreateTexture(name) return new("Texture", name, self) end
function Object:LockHighlight() self._locked = true end
function Object:UnlockHighlight() self._locked = false end
function Object:Enable() self._disabled = false end
function Object:Disable() self._disabled = true end
function Object:IsEnabled() return not self._disabled end
function Object:SetChecked(v) self._checked = v and 1 or nil end
function Object:GetChecked() return self._checked end

-- What Rollcall calls and nothing here needs to read back.
for _, name in ipairs({
  "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetVertexColor",
  "SetJustifyH", "SetMovable", "EnableMouse", "RegisterForDrag", "RegisterForClicks",
  "EnableMouseWheel", "SetFrameStrata", "SetToplevel", "SetClampedToScreen",
  "StartMoving", "StopMovingOrSizing", "SetNormalTexture", "SetPushedTexture",
  "SetHighlightTexture", "SetBlendMode", "SetAllPoints", "SetAutoFocus", "ClearFocus",
  "SetFocus",
}) do
  Object[name] = function() end
end

function T.fire(e, a1, a2)
  local i = 1
  while ORDERED[i] do
    local o = ORDERED[i]
    if o._events[e] and o._scripts.OnEvent then
      this, event, arg1, arg2 = o, e, a1, a2
      o._scripts.OnEvent()
    end
    i = i + 1
  end
end

UIParent = CreateFrame("Frame", "UIParent")
UIParent._right = 1024
UIParent:RegisterEvent("START_LOOT_ROLL")
UIParent:SetScript("OnEvent", function()
  if event == "START_LOOT_ROLL" then GroupLootFrame_OpenNewFrame(arg1, arg2) end
end)

-- Showing a tooltip runs its own script, which is what leaves `this`
-- pointing at the tooltip afterwards.
GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
GameTooltip._shown = false
GameTooltip.lines = {}
function GameTooltip:SetOwner(owner) self.owner = owner self.lines = {} end
function GameTooltip:SetText(t) self.lines = { t } self:Show() end
function GameTooltip:AddLine(t) table.insert(self.lines, t) end
function GameTooltip:Show() self._shown = true run(self, "OnShow") end
GameTooltip:SetScript("OnShow", function() end)

----------------------------------------------------------------------
-- the game's strings, classes and items
----------------------------------------------------------------------

-- Turtle WoW's GlobalStrings.lua, identical to 1.12.1's for these.
LOOT_ROLL_ALL_PASSED = "Everyone passed on: %s|Hitem:%d:%d:%d:%d|h[%s]|h%s"
LOOT_ROLL_GREED = "%s has selected Greed for: %s|Hitem:%d:%d:%d:%d|h[%s]|h%s"
LOOT_ROLL_GREED_SELF = "You have selected Greed for: %s|Hitem:%d:%d:%d:%d|h[%s]|h%s"
LOOT_ROLL_NEED = "%s has selected Need for: %s|Hitem:%d:%d:%d:%d|h[%s]|h%s"
LOOT_ROLL_NEED_SELF = "You have selected Need for: %s|Hitem:%d:%d:%d:%d|h[%s]|h%s"
LOOT_ROLL_PASSED = "%s passed on: %s|Hitem:%d:%d:%d:%d|h[%s]|h%s"
LOOT_ROLL_PASSED_SELF = "You passed on: %s|Hitem:%d:%d:%d:%d|h[%s]|h%s"
LOOT_ROLL_ROLLED = "%s rolls a %d on: %s|Hitem:%d:%d:%d:%d|h[%s]|h%s"
LOOT_ROLL_ROLLED_GREED = "Greed Roll - %d for %s|Hitem:%d:%d:%d:%d|h[%s]|h%s by %s"
LOOT_ROLL_ROLLED_GREED_SELF = "You roll a %d (Greed) on: %s|Hitem:%d:%d:%d:%d|h[%s]|h%s"
LOOT_ROLL_ROLLED_NEED = "Need Roll - %d for %s|Hitem:%d:%d:%d:%d|h[%s]|h%s by %s"
LOOT_ROLL_ROLLED_NEED_SELF = "You roll a %d (Need) on: %s|Hitem:%d:%d:%d:%d|h[%s]|h%s"
LOOT_ROLL_ROLLED_SELF = "You roll a %d on: %s|Hitem:%d:%d:%d:%d|h[%s]|h%s"
LOOT_ROLL_WON = "%s won: %s|Hitem:%d:%d:%d:%d|h[%s]|h%s"
LOOT_ROLL_WON_NO_SPAM_GREED = "%1$s won: %3$s|Hitem:%4$d:%5$d:%6$d:%7$d|h[%8$s]|h%9$s |cff818181(Greed - %2$d)|r"
LOOT_ROLL_WON_NO_SPAM_NEED = "%1$s won: %3$s|Hitem:%4$d:%5$d:%6$d:%7$d|h[%8$s]|h%9$s |cff818181(Need - %2$d)|r"
LOOT_ROLL_YOU_WON = "You won: %s|Hitem:%d:%d:%d:%d|h[%s]|h%s"
LOOT_ROLL_YOU_WON_NO_SPAM_GREED = "You won: %2$s|Hitem:%3$d:%4$d:%5$d:%6$d|h[%7$s]|h%8$s |cff818181(Greed - %1$d)|r"
LOOT_ROLL_YOU_WON_NO_SPAM_NEED = "You won: %2$s|Hitem:%3$d:%4$d:%5$d:%6$d|h[%7$s]|h%8$s |cff818181(Need - %1$d)|r"
NEED, GREED, PASS = "Need", "Greed", "Pass"

-- Someone getting loot, and a /roll: Turtle WoW's GlobalStrings, unchanged.
LOOT_ITEM = "%s receives loot: %s."
LOOT_ITEM_MULTIPLE = "%s receives loot: %sx%d."
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)"
ITEM_QUALITY0_DESC, ITEM_QUALITY1_DESC, ITEM_QUALITY2_DESC = "Poor", "Common", "Uncommon"
ITEM_QUALITY3_DESC, ITEM_QUALITY4_DESC, ITEM_QUALITY5_DESC = "Rare", "Epic", "Legendary"

RAID_CLASS_COLORS = {
  HUNTER = { r = 0.67, g = 0.83, b = 0.45 }, WARLOCK = { r = 0.58, g = 0.51, b = 0.79 },
  PRIEST = { r = 1.0, g = 1.0, b = 1.0 }, PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
  MAGE = { r = 0.41, g = 0.8, b = 0.94 }, ROGUE = { r = 1.0, g = 0.96, b = 0.41 },
  DRUID = { r = 1.0, g = 0.49, b = 0.04 }, SHAMAN = { r = 0.0, g = 0.44, b = 0.87 },
  WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
}

local function unitEntry(unit)
  if unit == "player" then return W.roster.player end
  local _, _, p = string.find(unit or "", "^party(%d+)$")
  if p then return W.roster.party[tonumber(p)] end
  local _, _, r = string.find(unit or "", "^raid(%d+)$")
  if r then return W.roster.raid[tonumber(r)] end
  if unit == "target" then return W.roster.target end
end
function UnitName(unit) local e = unitEntry(unit) return e and e[1] end
function UnitClass(unit) local e = unitEntry(unit) if e then return e[2], e[3] end end
function UnitIsPlayer(unit) return unitEntry(unit) and 1 or nil end
function GetNumPartyMembers() return table.getn(W.roster.party) end
function GetNumRaidMembers() return table.getn(W.roster.raid) end
--- The loot method: "group" unless a test says "master", with the master
--- looter's party index (0 is you) and raid index, as 1.12 returns them.
function GetLootMethod() return W.lootMethod or "group", W.mlParty, W.mlRaid end
function GetLootThreshold() return W.threshold or 2 end

T.ITEMS = {
  [10001] = { "Scaled Shroud", 2, "Armor", "Mail", "INVTYPE_CHEST" },
  [10002] = { "Soft Leather Boots", 2, "Armor", "Leather", "INVTYPE_FEET" },
  [10003] = { "Plain Robe", 2, "Armor", "Cloth", "INVTYPE_ROBE" },
  [10004] = { "Walnut Wand", 2, "Weapon", "Wands", "INVTYPE_RANGEDRIGHT" },
  [10006] = { "Heavy Kite Shield", 2, "Armor", "Shields", "INVTYPE_SHIELD" },
  [10007] = { "Hardened Axe", 2, "Weapon", "One-Handed Axes", "INVTYPE_WEAPON" },
  [10008] = { "Bonecrusher", 4, "Weapon", "Two-Handed Maces", "INVTYPE_2HWEAPON" },
  -- A raid's: what the master looter hands out.
  [20001] = { "Onslaught Girdle", 4, "Armor", "Plate", "INVTYPE_WAIST" },
  [20002] = { "Lava Core", 3, "Trade Goods", "Trade Goods", "" },
  [20003] = { "Choker of Enlightenment", 4, "Armor", "Miscellaneous", "INVTYPE_NECK" },
}
local ITEMS = T.ITEMS
-- 1.12 order: name, link, quality, minLevel, type, subType, stack, equipLoc, texture.
function GetItemInfo(ref)
  local id = tonumber(ref)
  if not id and type(ref) == "string" then
    local _, _, s = string.find(ref, "item:(%d+)")
    id = tonumber(s)
  end
  local it = id and ITEMS[id]
  if not it then return nil end
  return it[1], "item:" .. id .. ":0:0:0", it[2], 30, it[3], it[4], 1, it[5], "tex" .. id
end

local COLORS = { [2] = "|cff1eff00", [3] = "|cff0070dd", [4] = "|cffa335ee" }

function T.link(id)
  return COLORS[ITEMS[id][2]] .. "|Hitem:" .. id .. ":0:0:0|h[" .. ITEMS[id][1] .. "]|h|r"
end

--[[ A chat line exactly as the client builds it: the arguments before the
     item, the item in its seven parts, the arguments after it. ]]
function T.line(fmt, before, id, after)
  local args = {}
  for i = 1, table.getn(before or {}) do table.insert(args, before[i]) end
  local it = ITEMS[id]
  for _, v in ipairs({ COLORS[it[2]], id, 0, 0, 0, it[1], "|r" }) do table.insert(args, v) end
  for i = 1, table.getn(after or {}) do table.insert(args, after[i]) end
  return string.format(fmt, unpack(args))
end

-- The common case, "<who> has selected Need for: [item]" and "You ...".
function T.said(fmt, who, id)
  if who then return T.line(fmt, { who }, id) end
  return T.line(fmt, {}, id)
end

--- The winner line with Detailed Loot Information off, numbered arguments
--- and all; Lua's own string.format cannot do "%1$s".
function T.wonQuietly(who, id, choice, roll)
  local it = ITEMS[id]
  local what = "Need"
  if choice == "GREED" then what = "Greed" end
  local head = "You won: "
  if who then head = who .. " won: " end
  return head .. T.link(id) .. " |cff818181(" .. what .. " - " .. roll .. ")|r"
end

function GetLootRollItemInfo(id)
  local r = W.rolls[id]
  if not r then return nil end
  return "tex" .. r.item, ITEMS[r.item][1], 1, ITEMS[r.item][2], r.bop
end
function GetLootRollItemLink(id)
  local r = W.rolls[id]
  return r and T.link(r.item)
end
function GetLootRollTimeLeft(id)
  local r = W.rolls[id]
  if not r then return 0 end
  return math.max(0, (r.ends - W.now) * 1000)
end

local SELF_LINE = { [0] = "LOOT_ROLL_PASSED_SELF", [1] = "LOOT_ROLL_NEED_SELF",
                    [2] = "LOOT_ROLL_GREED_SELF" }
--[[ Your pick: the client hides your window by cancelling it, and the game
     then says in chat what you picked, as it does for everyone. ]]
function RollOnLoot(id, rollType)
  table.insert(W.sent, { id = id, type = rollType })
  T.fire("CANCEL_LOOT_ROLL", id)
  local r = W.rolls[id]
  if r then T.fire("CHAT_MSG_LOOT", T.said(_G[SELF_LINE[rollType]], nil, r.item)) end
end

function GetInventoryItemLink(unit, slot) return W.equipped[slot] end

----------------------------------------------------------------------
-- Blizzard's roll windows: LootFrame.xml's layout, LootFrame.lua's code
----------------------------------------------------------------------

NUM_GROUP_LOOT_FRAMES = 4
GROUP_LOOT_BACKDROP, GROUP_LOOT_BACKDROP_GOLD = {}, {}
ITEM_QUALITY_COLORS = {
  [0] = { r = 0.62, g = 0.62, b = 0.62 }, [1] = { r = 1, g = 1, b = 1 },
  [2] = { r = 0.12, g = 1, b = 0 }, [3] = { r = 0, g = 0.44, b = 0.87 },
  [4] = { r = 0.64, g = 0.21, b = 0.93 },
}

-- Turtle-WoW-UI-Source, Interface/FrameXML/LootFrame.lua, unchanged.
function GroupLootFrame_OpenNewFrame(id, rollTime)
	local frame;
	for i=1, NUM_GROUP_LOOT_FRAMES do
		frame = _G["GroupLootFrame"..i];
		if ( not frame:IsVisible() ) then
			frame.rollID = id;
			frame.rollTime = rollTime;
			_G["GroupLootFrame"..i.."Timer"]:SetMinMaxValues(0, rollTime);
			frame:Show();
			return;
		end
	end
end

function GroupLootFrame_OnShow()
	local texture, name, count, quality, bindOnPickUp = GetLootRollItemInfo(this.rollID);
	if ( not name ) then
		this:Hide();
		return;
	end
	if ( bindOnPickUp ) then
		this:SetBackdrop(GROUP_LOOT_BACKDROP_GOLD);
		_G[this:GetName().."Corner"]:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Gold-Corner");
		_G[this:GetName().."Decoration"]:Show();
	else
		this:SetBackdrop(GROUP_LOOT_BACKDROP);
		_G[this:GetName().."Corner"]:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Corner");
		_G[this:GetName().."Decoration"]:Hide();
	end

	_G["GroupLootFrame"..this:GetID().."IconFrameIcon"]:SetTexture(texture);
	_G["GroupLootFrame"..this:GetID().."Name"]:SetText(name);
	local color = ITEM_QUALITY_COLORS[quality];
	_G["GroupLootFrame"..this:GetID().."Name"]:SetVertexColor(color.r, color.g, color.b);
end

function GroupLootFrame_OnEvent()
	if ( event == "CANCEL_LOOT_ROLL" ) then
		if ( arg1 == this.rollID ) then
			this:Hide();
		end
	end
end

-- The template: 243x84, bottom center, stacked 15 apart.
for i = 1, NUM_GROUP_LOOT_FRAMES do
  local name = "GroupLootFrame" .. i
  local host = CreateFrame("Frame", name, UIParent)
  host._shown = false
  host:SetID(i)
  host:SetWidth(243)
  host:SetHeight(84)
  host._right = 512 + 121
  CreateFrame("Texture", name .. "Corner", host)
  CreateFrame("Texture", name .. "Decoration", host)
  local icon = CreateFrame("Button", name .. "IconFrame", host)
  CreateFrame("Texture", name .. "IconFrameIcon", icon)
  CreateFrame("FontString", name .. "Name", host)
  CreateFrame("StatusBar", name .. "Timer", host)

  local pass = CreateFrame("Button", name .. "PassButton", host)
  pass:SetScript("OnClick", function() RollOnLoot(this:GetParent().rollID, 0) end)
  pass:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT") GameTooltip:SetText(PASS)
  end)
  local need = CreateFrame("Button", name .. "RollButton", host)
  need:SetScript("OnClick", function() RollOnLoot(this:GetParent().rollID, 1) end)
  need:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT") GameTooltip:SetText(NEED)
  end)
  local greed = CreateFrame("Button", name .. "GreedButton", host)
  greed:SetScript("OnClick", function() RollOnLoot(this:GetParent().rollID, 2) end)
  greed:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT") GameTooltip:SetText(GREED)
  end)

  host:RegisterEvent("CANCEL_LOOT_ROLL")
  host:SetScript("OnShow", function() GroupLootFrame_OnShow() end)
  host:SetScript("OnEvent", function() GroupLootFrame_OnEvent() end)
end

----------------------------------------------------------------------
-- loading the addon, and driving it
----------------------------------------------------------------------

--- Every file the .toc lists, in its order, then the saved variables event.
function T.load()
  for line in io.lines("Rollcall.toc") do
    line = string.gsub(line, "\r", "")
    if string.find(line, "%.lua$") then dofile(line) end
  end
  T.fire("VARIABLES_LOADED")
end

function T.plain(s)
  s = string.gsub(s or "", "|H.-|h(.-)|h", "%1")
  return (string.gsub(string.gsub(s, "|c%x%x%x%x%x%x%x%x", ""), "|r", ""))
end

function T.advance(seconds) W.now = W.now + seconds end

function T.startRoll(id, item, seconds)
  seconds = seconds or 60
  W.rolls[id] = { item = item, ends = W.now + seconds }
  T.fire("START_LOOT_ROLL", id, seconds * 1000)
end

function T.chat(msg) T.fire("CHAT_MSG_LOOT", msg) end

function T.windowFor(id)
  for i = 1, 4 do
    local h = _G["GroupLootFrame" .. i]
    if h:IsVisible() and h.rollID == id then return h, i end
  end
end

function T.lines(i)
  local p = _G["RollcallPanel" .. i]
  return T.plain(p.lines[1]:GetText()), T.plain(p.lines[2]:GetText()), T.plain(p.lines[3]:GetText())
end

function T.badge(i, choice) return _G["RollcallBadge" .. i .. choice]:GetText() end

function T.panelShown(i)
  local p = _G["RollcallPanel" .. i]
  return p ~= nil and p:IsVisible()
end

--- Hover a frame; what the tooltip says, without colors.
function T.enter(frame)
  GameTooltip.lines = {}
  this = frame
  frame._scripts.OnEnter()
  local out = {}
  for n = 1, table.getn(GameTooltip.lines) do out[n] = T.plain(GameTooltip.lines[n]) end
  return out
end

function T.hover(i, suffix) return T.enter(_G["GroupLootFrame" .. i .. suffix]) end

--- Click a button; a check button flips first, as the client's does.
function T.press(frame)
  if frame._kind == "CheckButton" then
    if frame._checked then frame._checked = nil else frame._checked = 1 end
  end
  this = frame
  frame._scripts.OnClick()
end

function T.click(i, suffix) T.press(_G["GroupLootFrame" .. i .. suffix]) end

function T.wheel(frame, delta)
  this, arg1 = frame, delta
  frame._scripts.OnMouseWheel()
end

--- Let an OnUpdate run for `seconds`, in small steps like frames.
function T.tick(frame, seconds)
  local left = seconds
  while left > 0 and frame:IsVisible() and frame._scripts.OnUpdate do
    this, arg1 = frame, 0.1
    frame._scripts.OnUpdate()
    left = left - 0.1
  end
end

function T.has(list, want)
  for n = 1, table.getn(list) do if list[n] == want then return true end end
  return false
end

function T.chatHas(text)
  for n = 1, table.getn(W.chat) do
    if string.find(T.plain(W.chat[n]), text, 1, true) then return true end
  end
  return false
end

--- A clean slate between scenarios: no windows, rolls, chat or history.
function T.reset()
  for i = 1, 4 do _G["GroupLootFrame" .. i]:Hide() end
  Rollcall.rolls = {}
  Rollcall.ownHint = {}
  W.rolls, W.sent, W.chat, W.said = {}, {}, {}, {}
  W.inserted, W.dressed, W.popups = {}, {}, {}
  W.roster.party = { { "Bob", "Mage", "MAGE" }, { "Tank", "Warrior", "WARRIOR" },
                     { "Heals", "Priest", "PRIEST" }, { "Sneak", "Rogue", "ROGUE" } }
  W.roster.raid = {}
  W.roster.target = nil
  W.locale = "enUS"
  W.zone = "Scholomance"
  W.shift, W.ctrl, W.editOpen = false, false, false
  RollcallDB.warn = true
  RollcallDB.history = {}
  Rollcall.history.queue = {}
  -- Master loot, and the rarity a raid keeps.
  W.lootMethod, W.mlParty, W.mlRaid, W.threshold = nil, nil, nil, nil
  Rollcall:NewSession()
  Rollcall.lastGiven = nil
  RollcallDB.raidQuality = nil
end

return T
