-- Offline spec for Wowhead Forever Link: a simulated WoW API with just what the addon uses.
-- Globals set by run.js: LOCALE, EXPECTED_BASE, ADDON_FILES.
unpack = unpack or table.unpack
LOG = {}
function print(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end LOG[#LOG + 1] = table.concat(t, " ") end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function strsplit(sep, s)
	local r = {}
	for p in (s .. sep):gmatch("(.-)" .. sep:gsub("%-", "%%-")) do r[#r + 1] = p end
	return unpack(r)
end
date = os.date
SlashCmdList = {}
UISpecialFrames = {}
TIMERS = {}
C_Timer = { After = function(_, f) TIMERS[#TIMERS + 1] = f end }
function RunTimers() local t = TIMERS; TIMERS = {}; for _, f in ipairs(t) do f() end end
function GetBuildInfo() return "1.60.1", "70959", "", 16001 end
function GetLocale() return LOCALE end
C_AddOns = { GetAddOnMetadata = function(_, field) return field == "Version" and "1.2.0" or nil end }
function hooksecurefunc(name, f)
	local orig = _G[name]
	_G[name] = function(...) local r = { orig(...) }; f(...); return unpack(r) end
end

-- Secret values: comparing, concatenating or indexing them errors, like in game.
local SECRET_MT = {
	__eq = function() error("compared a secret value") end,
	__concat = function() error("concatenated a secret value") end,
	__index = function() error("indexed a secret value") end,
}
function NewSecret() return setmetatable({}, SECRET_MT) end
function issecretvalue(v) return type(v) == "table" and getmetatable(v) == SECRET_MT end

-- Generic frames: unknown methods (capitalized) are no-ops; unknown fields are nil.
local frames = {}
local Frame = {}
Frame.__index = function(_, k)
	local m = rawget(Frame, k)
	if m then return m end
	if type(k) ~= "string" or not k:match("^%u") then return nil end
	return function() end
end
function Frame:SetScript(n, f) self.scripts[n] = f end
function Frame:RegisterEvent(e) self.events[e] = true end
function Frame:Show() self.shown = true end
function Frame:Hide() local was = self.shown; self.shown = false; if was and self.scripts.OnHide then self.scripts.OnHide(self) end end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:IsShown() return self.shown end
function Frame:GetParent() return self.parent end
function Frame:SetText(t) self.text = t end
function Frame:GetText() return self.text end
function Frame:GetFrameLevel() return 1 end
function Frame:SetFocus() self.focus = true end
function Frame:ClearFocus() self.focus = false end
function Frame:GetEffectiveScale() return 1 end
function Frame:GetLeft() return 100 end
function Frame:GetBottom() return 200 end
function Frame:CreateTexture() return NewFrame() end
function Frame:CreateFontString() return NewFrame() end
function NewFrame(parent)
	local f = setmetatable({ scripts = {}, events = {}, shown = true, parent = parent }, Frame)
	frames[#frames + 1] = f
	return f
end
function CreateFrame(_, name, parent)
	local f = NewFrame(parent)
	if name then _G[name] = f end
	return f
end
UIParent = NewFrame()
GameTooltip = NewFrame()
local function fire(e, ...) for _, f in ipairs(frames) do if f.events[e] then f.scripts.OnEvent(f, e, ...) end end end

-- Units
UNITS = {}
function UnitExists(u) return UNITS[u] ~= nil end
function UnitIsPlayer(u) return UNITS[u] and UNITS[u].player or false end
function UnitName(u) return UNITS[u] and UNITS[u].name end
function UnitGUID(u) return UNITS[u] and UNITS[u].guid end
SHIFT = false; CTRL = false
function IsShiftKeyDown() return SHIFT end
function IsControlKeyDown() return CTRL end
function GetCursorPosition() return 150, 260 end

-- Blizzard frames
TargetFrame = NewFrame(UIParent)
TargetFrame.TargetFrameContainer = { Portrait = NewFrame(TargetFrame) }
QuestFrame = NewFrame(UIParent); QuestFrame.CloseButton = NewFrame(QuestFrame)
CURRENT_QUEST = 0
function GetQuestID() return CURRENT_QUEST end
C_QuestLog = { GetTitleForQuestID = function(id) return id == 783 and "A Threat Within" or nil end }
local active = {}
QuestScrollFrame = { titleFramePool = { EnumerateActive = function() local i = 0; return function() i = i + 1; return active[i] end end } }
function QuestLogQuests_Update() end
QuestMapFrame = { DetailsFrame = { BackFrame = { BackButton = NewFrame() } } }
MENU_CALLBACKS = {}
Menu = { ModifyMenu = function(tag, cb) MENU_CALLBACKS[tag] = cb end }
function NewMenuRoot()
	local r = { buttons = {} }
	function r:CreateDivider() end
	function r:CreateButton(t, f) self.buttons[#self.buttons + 1] = { text = t, func = f } end
	return r
end

-- Load the addon files in .toc order with a shared namespace
local ns = {}
for _, file in ipairs(ADDON_FILES) do assert(loadfile(file))("WowheadForeverLink", ns) end

local failures = {}
local function check(cond, msg) if not cond then failures[#failures + 1] = msg end end
local function lastURL() return WowheadForeverLinkWindow and WowheadForeverLinkWindow.edit.text end
local B = EXPECTED_BASE

check(ns.wowheadBase == B, "base URL for " .. LOCALE .. ": " .. tostring(ns.wowheadBase))
fire("ADDON_LOADED", "WowheadForeverLink")
fire("PLAYER_LOGIN")
check(LOG[#LOG]:find("/wh", 1, true), "load message")
local b = WowheadForeverLinkTargetButton
check(b ~= nil and b.parent == TargetFrame, "target button not created on TargetFrame")
check(WowheadForeverLinkDetailsButton ~= nil, "details button not created")
check(BINDING_NAME_WOWHEADFOREVERLINK_TARGET ~= nil, "binding names")

-- No target: hidden
fire("PLAYER_TARGET_CHANGED"); check(not b:IsShown(), "shown without target")

-- NPC with readable GUID
UNITS.target = { name = "Kobold Vermin", guid = "Creature-0-1-0-12-6-0000ABCDEF" }
fire("PLAYER_TARGET_CHANGED"); check(b:IsShown(), "hidden with NPC")
b.scripts.OnClick(b)
check(lastURL() == B .. "npc=6#drops", "NPC URL: " .. tostring(lastURL()))
check(WowheadForeverLinkWindow.edit.focus, "edit box not focused")
check(tostring(WowheadForeverLinkWindow.title.text):find("Kobold Vermin", 1, true), "NPC title")

-- Ctrl+C closes the window
CTRL = true; WowheadForeverLinkWindow.edit.scripts.OnKeyDown(WowheadForeverLinkWindow.edit, "C"); CTRL = false
RunTimers(); check(not WowheadForeverLinkWindow:IsShown(), "Ctrl+C did not close the window")

-- Typing restores the URL
b.scripts.OnClick(b)
local e = WowheadForeverLinkWindow.edit
e.text = "garbage"; e.scripts.OnTextChanged(e, true)
check(e.text == B .. "npc=6#drops", "URL not restored")

-- Player: hidden
UNITS.target = { name = "Someone", player = true, guid = "Player-1-0ABC" }
fire("PLAYER_TARGET_CHANGED"); check(not b:IsShown(), "shown with player")

-- World object
UNITS.target = { name = "Chest", guid = "GameObject-0-1-0-12-1234-00" }
fire("PLAYER_TARGET_CHANGED"); b.scripts.OnClick(b)
check(lastURL() == B .. "object=1234#contains", "object URL")

-- Secret GUID: search by name, URL-encoded
UNITS.target = { name = "Señor Ñu", guid = NewSecret() }
fire("PLAYER_TARGET_CHANGED"); check(b:IsShown(), "hidden with secret GUID")
b.scripts.OnClick(b)
check(lastURL() == B .. "search?q=Se%C3%B1or%20%C3%91u", "search URL: " .. tostring(lastURL()))

-- Readable when targeted, secret on click: uses the cached data
UNITS.target = { name = "Wolf", guid = "Creature-0-1-0-12-299-00" }
fire("PLAYER_TARGET_CHANGED")
UNITS.target = { name = NewSecret(), guid = NewSecret() }
b.scripts.OnClick(b)
check(lastURL() == B .. "npc=299#drops", "cached target not used")

-- Everything secret: a notice, no error
fire("PLAYER_TARGET_CHANGED"); b.scripts.OnClick(b)
check(LOG[#LOG] == "|cff39c0edWowhead|r: " .. ns.L.UNIT_HIDDEN, "no notice with all secret")

-- Shift-drag stores a position relative to the target frame
SHIFT = true; b.scripts.OnDragStart(b); b.scripts.OnUpdate(b); b.scripts.OnDragStop(b); SHIFT = false
check(WowheadForeverLinkDB.x == 50 and WowheadForeverLinkDB.y == 60, "dragged position")
SlashCmdList.WOWHEADFOREVERLINK("reset"); check(WowheadForeverLinkDB.x == nil, "reset")

-- Quest list: the hook adds icons that open the quest
active = { NewFrame(), NewFrame() }
active[1].questID = 783; active[1].TagTexture = NewFrame()
QuestLogQuests_Update()
check(active[1].wowheadForeverLink and active[1].wowheadForeverLink:IsShown(), "no icon on quest row")
check(active[2].wowheadForeverLink and not active[2].wowheadForeverLink:IsShown(), "icon on row without quest")
active[1].wowheadForeverLink.scripts.OnClick(active[1].wowheadForeverLink)
check(lastURL() == B .. "quest=783", "quest list URL")
check(WowheadForeverLinkWindow.title.text == "A Threat Within", "quest title")
active[1].questID = 100; QuestLogQuests_Update()
active[1].wowheadForeverLink.scripts.OnClick(active[1].wowheadForeverLink)
check(lastURL() == B .. "quest=100", "recycled pool button")

-- Details button
QuestMapFrame.DetailsFrame.questID = 783
WowheadForeverLinkDetailsButton.scripts.OnClick(WowheadForeverLinkDetailsButton)
check(lastURL() == B .. "quest=783", "details button")

-- Slash commands (both languages)
SlashCmdList.WOWHEADFOREVERLINK("q 5"); check(lastURL() == B .. "quest=5", "/wh q")
SlashCmdList.WOWHEADFOREVERLINK("m 6"); check(lastURL() == B .. "quest=6", "/wh m")
SlashCmdList.WOWHEADFOREVERLINK("steam axe"); check(lastURL() == B .. "search?q=steam%20axe", "/wh text")
SlashCmdList.WOWHEADFOREVERLINK("last"); check(lastURL() == B .. "search?q=steam%20axe", "/wh last")
UNITS.mouseover = { name = "Murloc", guid = "Creature-0-1-0-12-285-00" }
WowheadForeverLink_Mouseover(); check(lastURL() == B .. "npc=285#drops", "mouseover binding")
SlashCmdList.WOWHEADFOREVERLINK("diag")
local s = WowheadForeverLinkDB.status
check(s.questList and s.questDetails and s.questFrame and s.menus and s.locale == LOCALE, "diag")

-- Portrait right-click menu
check(MENU_CALLBACKS.MENU_UNIT_TARGET and MENU_CALLBACKS.MENU_UNIT_FOCUS and MENU_CALLBACKS.MENU_UNIT_BOSS, "menus not hooked")
UNITS.target = { name = "Hogger", guid = "Creature-0-1-0-12-448-00" }
local root = NewMenuRoot(); MENU_CALLBACKS.MENU_UNIT_TARGET(nil, root, { unit = "target" })
check(#root.buttons == 1 and root.buttons[1].text:find(ns.L.MENU_ENTRY, 1, true), "no menu entry")
UNITS.target = { name = NewSecret(), guid = NewSecret() }
root.buttons[1].func()
check(lastURL() == B .. "npc=448#drops", "menu URL: " .. tostring(lastURL()))
UNITS.target = { name = "Someone", player = true, guid = "Player-1-0ABC" }
root = NewMenuRoot(); MENU_CALLBACKS.MENU_UNIT_TARGET(nil, root, { unit = "target" })
check(#root.buttons == 0, "menu entry on a player")
root = NewMenuRoot(); MENU_CALLBACKS.MENU_UNIT_TARGET(nil, root, nil)
check(#root.buttons == 0, "menu without context")

-- Any red error line in chat means a code path failed
for _, l in ipairs(LOG) do
	if l:find("|cffff4040", 1, true) then failures[#failures + 1] = "error in chat: " .. l end
end

if #failures > 0 then
	local out = {}
	for _, f in ipairs(failures) do out[#out + 1] = f end
	for _, d in ipairs(WowheadForeverLinkDB.diag) do out[#out + 1] = "diag " .. d end
	error(#failures .. " failure(s):\n  " .. table.concat(out, "\n  "))
end
