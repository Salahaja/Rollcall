--[[
    test_rollcall.lua - Rollcall against Blizzard's own roll windows, offline.

    Usage (from the addon folder):
        lua tools/test_rollcall.lua [path/to/Rollcall.lua]

    The four roll windows are built the way the client's XML builds them and
    run Turtle WoW's own GroupLootFrame code, copied below unchanged. So the
    addon meets the real behavior: UIParent opening a window before any addon
    hears about the roll, a window that hides itself for a roll whose item
    has gone, and `this` left pointing at whatever script ran last - which
    in 1.12 is not put back when a nested script returns.
--]]

package.path = "./?.lua;" .. package.path
local ADDON = arg[1] or "Rollcall.lua"

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

local failures, checks = 0, 0
local function check(label, got, want)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print("  FAIL " .. label .. ": got " .. tostring(got) .. ", wanted " .. tostring(want))
  end
end

----------------------------------------------------------------------
-- the client
----------------------------------------------------------------------

local NOW = 1000
function GetTime() return NOW end

local CVARS = { showLootSpam = "1" }
function GetCVar(k) return CVARS[k] end
function SetCVar(k, v) CVARS[k] = tostring(v) end

local LOCALE = "enUS"
function GetLocale() return LOCALE end

local CHAT = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(self, m) table.insert(CHAT, m) end }
SlashCmdList = {}
function getglobal(n) return _G[n] end

-- Frames, in creation order: that is also the order events arrive in, which
-- is why UIParent (FrameXML) hears about a roll before any addon does.
local ORDERED = {}
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

function CreateFrame(kind, name, parent) return new(kind or "Frame", name, parent) end

-- Like the client: `this` is set for the script, and not put back after.
local function run(o, script)
  local fn = o._scripts[script]
  if fn then
    this = o
    fn()
  end
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
function Object:SetBackdrop(b) self._backdrop = b end
function Object:SetBackdropColor() end
function Object:SetBackdropBorderColor() end
function Object:SetTexture(t) self._texture = t end
function Object:SetVertexColor() end
function Object:SetMinMaxValues(a, b) self._min, self._max = a, b end
function Object:SetJustifyH() end
function Object:SetText(t) self._text = t end
function Object:GetText() return self._text end
function Object:GetStringWidth()
  local plain = string.gsub(string.gsub(self._text or "", "|c%x%x%x%x%x%x%x%x", ""), "|r", "")
  return string.len(plain) * 5
end
function Object:CreateFontString(name) return new("FontString", name, self) end

local function fire(e, a1, a2)
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
LOOT_ROLL_WON = "%s won: %s|Hitem:%d:%d:%d:%d|h[%s]|h%s"
NEED, GREED, PASS = "Need", "Greed", "Pass"

RAID_CLASS_COLORS = {
  HUNTER = { r = 0.67, g = 0.83, b = 0.45 }, WARLOCK = { r = 0.58, g = 0.51, b = 0.79 },
  PRIEST = { r = 1.0, g = 1.0, b = 1.0 }, PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
  MAGE = { r = 0.41, g = 0.8, b = 0.94 }, ROGUE = { r = 1.0, g = 0.96, b = 0.41 },
  DRUID = { r = 1.0, g = 0.49, b = 0.04 }, SHAMAN = { r = 0.0, g = 0.44, b = 0.87 },
  WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
}

local ROSTER = { player = { "Tester", "Warrior", "WARRIOR" }, party = {}, raid = {} }
local function unitEntry(unit)
  if unit == "player" then return ROSTER.player end
  local _, _, p = string.find(unit or "", "^party(%d+)$")
  if p then return ROSTER.party[tonumber(p)] end
  local _, _, r = string.find(unit or "", "^raid(%d+)$")
  if r then return ROSTER.raid[tonumber(r)] end
end
function UnitName(unit) local e = unitEntry(unit) return e and e[1] end
function UnitClass(unit) local e = unitEntry(unit) if e then return e[2], e[3] end end
function GetNumPartyMembers() return table.getn(ROSTER.party) end
function GetNumRaidMembers() return table.getn(ROSTER.raid) end

local ITEMS = {
  [10001] = { "Scaled Shroud", 2, "Armor", "Mail", "INVTYPE_CHEST" },
  [10002] = { "Soft Leather Boots", 2, "Armor", "Leather", "INVTYPE_FEET" },
  [10003] = { "Plain Robe", 2, "Armor", "Cloth", "INVTYPE_ROBE" },
  [10004] = { "Walnut Wand", 2, "Weapon", "Wands", "INVTYPE_RANGEDRIGHT" },
  [10006] = { "Heavy Kite Shield", 2, "Armor", "Shields", "INVTYPE_SHIELD" },
  [10007] = { "Hardened Axe", 2, "Weapon", "One-Handed Axes", "INVTYPE_WEAPON" },
}
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

local function link(id)
  return "|cff1eff00|Hitem:" .. id .. ":0:0:0|h[" .. ITEMS[id][1] .. "]|h|r"
end

-- A chat line exactly as the client builds it from the format.
local function said(fmt, who, id)
  if who then return string.format(fmt, who, "|cff1eff00", id, 0, 0, 0, ITEMS[id][1], "|r") end
  return string.format(fmt, "|cff1eff00", id, 0, 0, 0, ITEMS[id][1], "|r")
end

local ROLLS, SENT = {}, {}
function GetLootRollItemInfo(id)
  local r = ROLLS[id]
  if not r then return nil end
  return "tex" .. r.item, ITEMS[r.item][1], 1, ITEMS[r.item][2], r.bop
end
function GetLootRollItemLink(id)
  local r = ROLLS[id]
  return r and link(r.item)
end
function GetLootRollTimeLeft(id)
  local r = ROLLS[id]
  if not r then return 0 end
  return math.max(0, (r.ends - NOW) * 1000)
end
-- The client hides your window once you have picked, by cancelling it.
function RollOnLoot(id, rollType)
  table.insert(SENT, { id = id, type = rollType })
  fire("CANCEL_LOOT_ROLL", id)
end

local EQUIPPED = {}
function GetInventoryItemLink(unit, slot) return EQUIPPED[slot] end

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
-- load the addon, as the client would after FrameXML
----------------------------------------------------------------------

dofile(ADDON)
fire("VARIABLES_LOADED")
local RC = Rollcall

local function plain(s)
  s = string.gsub(s or "", "|H.-|h(.-)|h", "%1")
  return (string.gsub(string.gsub(s, "|c%x%x%x%x%x%x%x%x", ""), "|r", ""))
end
local function startRoll(id, item, seconds)
  seconds = seconds or 60
  ROLLS[id] = { item = item, ends = NOW + seconds }
  fire("START_LOOT_ROLL", id, seconds * 1000)
end
local function chat(msg) fire("CHAT_MSG_LOOT", msg) end
local function windowFor(id)
  for i = 1, 4 do
    local h = _G["GroupLootFrame" .. i]
    if h:IsVisible() and h.rollID == id then return h, i end
  end
end
local function lines(i)
  local p = _G["RollcallPanel" .. i]
  return plain(p.lines[1]:GetText()), plain(p.lines[2]:GetText()), plain(p.lines[3]:GetText())
end
local function badge(i, choice) return _G["RollcallBadge" .. i .. choice]:GetText() end
local function panelShown(i)
  local p = _G["RollcallPanel" .. i]
  return p ~= nil and p:IsVisible()
end
local function hover(i, suffix)
  local b = _G["GroupLootFrame" .. i .. suffix]
  this = b
  b._scripts.OnEnter()
  local out = {}
  for n = 1, table.getn(GameTooltip.lines) do out[n] = plain(GameTooltip.lines[n]) end
  return out
end
local function click(i, suffix)
  local b = _G["GroupLootFrame" .. i .. suffix]
  this = b
  b._scripts.OnClick()
end
local function has(list, want)
  for n = 1, table.getn(list) do if list[n] == want then return true end end
  return false
end
local function chatHas(text)
  for n = 1, table.getn(CHAT) do
    if string.find(plain(CHAT[n]), text, 1, true) then return true end
  end
  return false
end
local function reset()
  for i = 1, 4 do _G["GroupLootFrame" .. i]:Hide() end
  RC.rolls = {}
  ROLLS, SENT, CHAT = {}, {}, {}
  ROSTER.party = { { "Bob", "Mage", "MAGE" }, { "Tank", "Warrior", "WARRIOR" },
                   { "Heals", "Priest", "PRIEST" }, { "Sneak", "Rogue", "ROGUE" } }
  ROSTER.raid = {}
  LOCALE = "enUS"
  RollcallDB.warn = true
end

print("\nRollcall: picks beside Blizzard's roll windows\n")

----------------------------------------------------------------------
print("reading the chat lines")
----------------------------------------------------------------------
do
  local who, choice, l = RC.Parse(said(LOOT_ROLL_NEED, "Bob", 10001))
  check("a Need line names the player", who, "Bob")
  check("  and the pick", choice, "NEED")
  check("  and keeps the whole item link", l, link(10001))
  who, choice = RC.Parse(said(LOOT_ROLL_GREED, "Heals", 10001))
  check("a Greed line", choice, "GREED")
  who, choice = RC.Parse(said(LOOT_ROLL_PASSED, "Sneak", 10001))
  check("a Pass line", who .. "/" .. choice, "Sneak/PASS")
  check("everyone passing is nobody's pick", RC.Parse(said(LOOT_ROLL_ALL_PASSED, nil, 10001)), nil)
  check("your own pick is left to your own window",
    RC.Parse(said(LOOT_ROLL_NEED_SELF, nil, 10001)), nil)
  check("  your own pass too", RC.Parse(said(LOOT_ROLL_PASSED_SELF, nil, 10001)), nil)
  check("who won is not a pick", RC.Parse(said(LOOT_ROLL_WON, "Bob", 10001)), nil)
  check("ordinary loot lines are not picks",
    RC.Parse("You receive loot: " .. link(10003) .. "."), nil)

  local key, id = RC.ItemKey(link(10001))
  check("an item is known by its full link", key, "item:10001:0:0:0")
  check("  and by its id", id, 10001)

  -- A format with pattern characters in it must still match literally.
  local p = RC.Pattern("50% off (%s) [x]. %s")
  local _, _, a, b = string.find("50% off (Bob) [x]. Tank", p)
  check("pattern characters in a format are matched as text", tostring(a) .. "/" .. tostring(b),
    "Bob/Tank")
end

----------------------------------------------------------------------
print("on Blizzard's window")
----------------------------------------------------------------------
do
  reset()
  startRoll(1, 10001)
  local host, i = windowFor(1)
  check("Blizzard's window opens as usual", host ~= nil, true)
  check("the panel sits beside it", panelShown(i), true)
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
  check("the Need button counts them", badge(i, "NEED"), "1")
  check("  the Greed button too", badge(i, "GREED"), "1")

  -- The ninja: a mage needing mail.
  CHAT = {}
  chat(said(LOOT_ROLL_NEED, "Bob", 10001))
  need = lines(i)
  check("a Need the class can never use is marked", need, "Need  Tank, Bob (can't use)")
  check("  in red", string.find(_G["RollcallPanel" .. i].lines[1]:GetText(),
    "|cffff2020Bob (can't use)|r", 1, true) ~= nil, true)
  check("  and said in your chat", chatHas("Bob (Mage) picked Need on [Scaled Shroud]"), true)
  check("  with the reason", chatHas("Mages can't use Mail"), true)
  check("the count goes up", badge(i, "NEED"), "2")

  -- Blizzard's own tooltip still comes first; the names follow it.
  local tip = hover(i, "RollButton")
  check("hovering Need keeps Blizzard's text", tip[1], "Need")
  check("  then lists who", has(tip, "Tank"), true)
  check("  with the reason in full", has(tip, "Bob (can't use Mail)"), true)
  check("hovering Greed lists Greed only", table.concat(hover(i, "GreedButton"), "|"), "Greed|Heals")
  check("hovering Pass lists Pass only", table.concat(hover(i, "PassButton"), "|"), "Pass|Sneak")

  -- A line can arrive twice; a player still picks once.
  chat(said(LOOT_ROLL_NEED, "Tank", 10001))
  check("the same pick twice counts once", badge(i, "NEED"), "2")

  -- Picks you are not in a roll for still warn you.
  CHAT = {}
  chat(said(LOOT_ROLL_NEED, "Bob", 10006))
  check("a ninja pick with no window of yours still warns", chatHas("Mages can't use Shields"), true)

  -- Once you pick, Blizzard hides the window, and the panel goes with it.
  click(i, "GreedButton")
  check("your pick reaches the server", SENT[1] and SENT[1].type, 2)
  check("Blizzard's window closes", host:IsVisible(), false)
  check("  and the panel with it", panelShown(i), false)
end

----------------------------------------------------------------------
print("who can never use what")
----------------------------------------------------------------------
do
  reset()
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
  LOCALE = "deDE"
  startRoll(2, 10001)
  local _, i = windowFor(2)
  CHAT = {}
  chat(said(LOOT_ROLL_NEED, "Bob", 10001))
  check("in another language nobody is marked", (lines(i)), "Need  Bob")
  check("  nor warned about", table.getn(CHAT), 0)

  -- Chat warnings can be turned off; the red mark stays.
  LOCALE = "enUS"
  SlashCmdList["ROLLCALL"]("warn off")
  CHAT = {}
  chat(said(LOOT_ROLL_NEED, "Sneak", 10001))
  check("with warnings off, the panel still marks it", (lines(i)), "Need  Bob, Sneak (can't use)")
  check("  but chat stays quiet", table.getn(CHAT), 0)
  SlashCmdList["ROLLCALL"]("warn on")
end

----------------------------------------------------------------------
print("the same item up twice")
----------------------------------------------------------------------
do
  reset()
  startRoll(11, 10002)
  startRoll(12, 10002)
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

  -- You pick on the first. Its window closes, but the roll is still going.
  click(a, "PassButton")
  check("your window closes", windowFor(11), nil)
  chat(said(LOOT_ROLL_PASSED, "Heals", 10002))
  chat(said(LOOT_ROLL_PASSED, "Heals", 10002))
  check("later picks still fill both rolls", table.getn(RC.rolls[11].picks) .. "/" ..
    table.getn(RC.rolls[12].picks), "2/2")
  local _, _, passB = lines(b)
  check("  and the open window shows its own", passB, "Pass  Heals")
end

----------------------------------------------------------------------
print("rolls come and go")
----------------------------------------------------------------------
do
  -- A roll is forgotten once its timer has run out.
  reset()
  startRoll(21, 10003, 10)
  NOW = NOW + 20
  fire("CANCEL_LOOT_ROLL", 21)   -- the game ends it when its timer runs out
  startRoll(22, 10004)
  check("an old roll is dropped when a new one starts", RC.rolls[21], nil)
  chat(said(LOOT_ROLL_NEED, "Tank", 10003))
  check("  and a stray line for it lands nowhere", RC.rolls[22].picks[1], nil)

  -- Past its timer, a roll takes no more picks even before it is dropped.
  reset()
  startRoll(23, 10003, 10)
  NOW = NOW + 20
  chat(said(LOOT_ROLL_NEED, "Tank", 10003))
  check("a roll past its timer takes no more picks", RC.rolls[23].picks[1], nil)

  -- The game can give a new roll an old roll's number.
  reset()
  startRoll(24, 10003)
  chat(said(LOOT_ROLL_NEED, "Tank", 10003))
  click(1, "PassButton")
  ROLLS[24] = { item = 10004, ends = NOW + 60 }
  fire("START_LOOT_ROLL", 24, 60000)
  local _, k = windowFor(24)
  check("a new item under an old roll's number starts clean", (lines(k)), "Need  -")

  -- The chat's link and the window's can differ in the last fields; the
  -- item is still the same item.
  reset()
  startRoll(25, 10003)
  local _, m = windowFor(25)
  chat("Tank has selected Need for: |cff1eff00|Hitem:10003:0:0:77|h[Plain Robe]|h|r")
  check("the same item with a different link still counts", (lines(m)), "Need  Tank")

  -- A /reload in the middle of a roll loses Rollcall's memory, not the window.
  reset()
  startRoll(31, 10003)
  local _, i = windowFor(31)
  RC.rolls = {}
  chat(said(LOOT_ROLL_NEED, "Tank", 10003))
  check("after a reload the open window is found again", (lines(i)), "Need  Tank")

  -- Addon first, window second: the panel still appears, and for the new
  -- roll - the window last showed another one, and must not show it again.
  reset()
  startRoll(40, 10003)
  chat(said(LOOT_ROLL_NEED, "Tank", 10003))
  click(1, "PassButton")
  local mine
  for n = 1, table.getn(ORDERED) do
    if ORDERED[n] == RollcallEventFrame then mine = n end
  end
  table.remove(ORDERED, mine)
  table.insert(ORDERED, 1, RollcallEventFrame)
  startRoll(41, 10004)
  local _, j = windowFor(41)
  check("when Rollcall hears first, the window still gets its panel", panelShown(j), true)
  check("  showing the new roll, not the last one", (lines(j)), "Need  -")
  table.remove(ORDERED, 1)
  table.insert(ORDERED, mine, RollcallEventFrame)

  -- A roll whose item has gone: Blizzard hides the window, nothing breaks.
  reset()
  fire("START_LOOT_ROLL", 51, 60000)
  check("Blizzard hides a window with no item", windowFor(51), nil)
  check("  and no panel is left behind", panelShown(1), false)

  -- Near the right edge the panel goes on the left instead.
  reset()
  GroupLootFrame1._right = 1000
  startRoll(61, 10003)
  local point, _, relPoint = RollcallPanel1:GetPoint(1)
  check("at the screen's right edge the panel moves left",
    tostring(point) .. ">" .. tostring(relPoint), "RIGHT>LEFT")
  GroupLootFrame1._right = 512 + 121

  -- Rendering again never piles up more counts on Blizzard's buttons.
  reset()
  startRoll(71, 10003)
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
  reset()
  ROSTER.party = {}
  ROSTER.raid = {}
  local names = { "Aa", "Bb", "Cc", "Dd", "Ee", "Ff", "Gg" }
  for n = 1, 7 do ROSTER.raid[n] = { names[n], "Hunter", "HUNTER" } end
  startRoll(81, 10003)
  local _, i = windowFor(81)
  for n = 1, 7 do chat(said(LOOT_ROLL_PASSED, names[n], 10003)) end
  local _, _, pass = lines(i)
  check("a long list is cut short", pass, "Pass  Aa, Bb, Cc, Dd  +3")
  check("raid members get class colors too",
    string.find(_G["RollcallPanel" .. i].lines[3]:GetText(), "|cffabd473Aa|r", 1, true) ~= nil, true)
  local tip = hover(i, "PassButton")
  check("the tooltip has everyone", table.getn(tip), 8)
end

----------------------------------------------------------------------
print("Detailed Loot Information")
----------------------------------------------------------------------
do
  -- Off at the first login: switched on, and said so.
  RollcallDB = nil
  CVARS.showLootSpam = "0"
  CHAT = {}
  RC:Init()
  check("off at first, it is switched on", CVARS.showLootSpam, "1")
  check("  saying so", chatHas("turned on Detailed Loot Information"), true)

  -- Turned off again by hand: respected, with a reminder.
  CVARS.showLootSpam = "0"
  CHAT = {}
  RC:Init()
  check("turned off by hand, it stays off", CVARS.showLootSpam, "0")
  check("  with a reminder", chatHas("/rollcall detail"), true)
  SlashCmdList["ROLLCALL"]("detail")
  check("/rollcall detail turns it back on", CVARS.showLootSpam, "1")

  -- Already on: never touched.
  RollcallDB = nil
  CVARS.showLootSpam = "1"
  CHAT = {}
  RC:Init()
  check("already on, nothing is said", table.getn(CHAT), 0)
  check("  and it is not switched back on later", RollcallDB.detailSet, true)
end

----------------------------------------------------------------------
print("/rollcall test")
----------------------------------------------------------------------
do
  reset()
  EQUIPPED = { [5] = link(10001) }
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
  check("clicking the pretend roll sends nothing", table.getn(SENT), 0)
  check("  and ends it", windowFor(RC.TEST_ID), nil)
  check("  cleanly", RC.test, nil)

  -- Real rolls pass straight through the same functions.
  startRoll(91, 10003)
  local _, j = windowFor(91)
  click(j, "GreedButton")
  check("a real roll still reaches the server", SENT[1] and SENT[1].id, 91)

  -- It ends on its own, too.
  reset()
  SlashCmdList["ROLLCALL"]("test")
  NOW = NOW + RC.TEST_SECONDS + 1
  this = RollcallEventFrame
  RollcallEventFrame._scripts.OnUpdate()
  check("the pretend roll closes by itself", windowFor(RC.TEST_ID), nil)

  -- Nothing equipped, nothing to show.
  reset()
  EQUIPPED = {}
  SlashCmdList["ROLLCALL"]("test")
  check("with nothing equipped it says why", chatHas("equip something first"), true)

  -- All four windows busy.
  reset()
  EQUIPPED = { [5] = link(10001) }
  for n = 1, 4 do startRoll(100 + n, 10003) end
  SlashCmdList["ROLLCALL"]("test")
  check("with every window busy it says so", chatHas("all four roll windows are in use"), true)
  check("  and leaves no pretend roll behind", RC.test, nil)
end

print(string.format("\n%d checks, %d failed\n", checks, failures))
if failures > 0 then os.exit(1) end
