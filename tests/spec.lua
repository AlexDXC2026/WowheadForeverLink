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
TICKERS = {}
function C_Timer.NewTicker(_, f)
	local t = { f = f }
	function t:Cancel() self.cancelled = true end
	TICKERS[#TICKERS + 1] = t
	return t
end
function RunTickers()
	for _, t in ipairs(TICKERS) do
		local guard = 0
		while not t.cancelled do t.f(); guard = guard + 1; assert(guard < 1000, "ticker never ends") end
	end
	TICKERS = {}
end
function GetBuildInfo() return "1.60.1", "70959", "", 16001 end
function GetLocale() return LOCALE end
C_AddOns = { GetAddOnMetadata = function(_, field) return field == "Version" and "1.2.0" or nil end }
function hooksecurefunc(tbl, name, f)
	if type(tbl) == "string" then tbl, name, f = _G, tbl, name end
	local orig = tbl[name]
	tbl[name] = function(...) local r = { orig(...) }; f(...); return unpack(r) end
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
function Frame:HookScript(n, f)
	local old = self.scripts[n]
	self.scripts[n] = function(...) if old then old(...) end f(...) end
end
function Frame:SetOwner(owner) self.owner = owner; self.lines = {} end
function Frame:GetOwner() return self.owner end
function Frame:AddLine(text) self.lines = self.lines or {}; self.lines[#self.lines + 1] = text end
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

-- Questie (optional dependency): database, frame pool and map icons
ALT = false
function IsAltKeyDown() return ALT end
function UnitLevel() return 36 end
COMPLETED = { [100] = true }
C_QuestLog.IsOnQuest = function(id) return id == 783 end
C_QuestLog.IsQuestFlaggedCompleted = function(id) return COMPLETED[id] == true end
WorldMapFrame = NewFrame(UIParent)
QUESTIE_QUESTS = {
	[100] = { name = "First Step" },
	[101] = { name = "Second Step" },
	[500] = { name = "Into the Swamp", requiredLevel = 30, preQuestGroup = { 100, -101 } },
	[600] = { name = "High Road", requiredLevel = 40, preQuestSingle = { 100 } },
	[700] = { name = "Free Quest" },
	[1180] = { name = "A Favor for Krazek", requiredLevel = 30 },
	[1181] = { name = "Ore for the Goblins" },
	[900] = { name = "Orcs Only", requiredRaces = 2 },
	[78093] = { name = "Return to Delgren" },
	[96438] = { name = "Battle at the Mannoroc Coven", requiredLevel = 35 }, -- Questie lacks its pre-quest
	[79939] = { name = "The Broken Hammer" },
	[79940] = { name = "A Lost Brother" },
	[96449] = { name = "Aeonas's Secret Refuge", requiredLevel = 35 }, -- Questie lacks its pre-quests
	[86777] = { name = "Master Feardred" },
	[86792] = { name = "Thinning Their Forces" },
	[86797] = { name = "Return to Rageroar" }, -- Questie lacks its one-of pre-quests
	[6610] = { name = "Clamlette Surprise", requiredLevel = 35, requiredSkill = { 185, 225 } }, -- Cooking 225
}
local questieDB = {
	GetQuest = function(id) return QUESTIE_QUESTS[id] end,
	QueryQuestSingle = function(id, key) local q = QUESTIE_QUESTS[id]; return q and q[key] end,
	IsDoableVerbose = function(id) return id == 500 and "Unavailable: Missing pre-quest" or "Available" end,
	IsDoable = function(id) return id ~= 1181 end,
}
-- LibQuestieDB (the database Questie is built on): items listed per quest.
local QUESTIEDB_OBJECTIVES = {
	[783] = { nil, nil, { { 4278 }, { 6666 } } }, -- in the log
	[100] = { nil, nil, { { 4278 }, { 3333 } } }, -- completed
	[900] = { nil, nil, { { 4278 } } }, -- another race
	[1181] = { nil, nil, { 4278 } }, -- bare ID
	[1180] = { nil, nil, { { 4278, "Lesser Bloodstone Ore" } } },
	[501] = { nil, nil, { { 7777 } } },
}
LibQuestieDB = {
	RequireContract = function(n) return n == 2 end,
	Quest = {
		GetAllIds = function() return { 100, 500, 501, 600, 700, 783, 900, 1180, 1181 } end,
		Get = function(id, key)
			if key == "objectives" then return QUESTIEDB_OBJECTIVES[id] or {} end
			if key == "requiredSourceItems" then return id == 600 and { 8888 } or nil end
			local q = QUESTIE_QUESTS[id]; return q and q[key]
		end,
	},
	-- Like Questie: startQuest is 0 for items that start no quest.
	Item = { Get = function(id, key) if key == "startQuest" then return id == 5000 and 700 or 0 end end },
}
local questiePlayer = {
	HasRequiredRace = function(mask) return not mask or mask == 0 or mask % 2 == 1 end, -- human
	HasRequiredClass = function() return true end,
}
PROFESSIONS = { [185] = { "Cooking", 180 } }
local questieProfessions = {
	GetPlayerProfessions = function() return PROFESSIONS end,
	GetProfessionName = function(_, id) return ({ [185] = "Cooking" })[id] end,
}
local questieL10n = setmetatable({}, { __call = function(_, text) return text == "Cooking" and "Cocina" or text end })
local questieFrames = 1
local questiePool = {}
function questiePool:GetFrame()
	questieFrames = questieFrames + 1
	return CreateFrame("Button", "QuestieFrame" .. questieFrames)
end
CreateFrame("Button", "QuestieFrame1") -- created before the addon hooks the pool
-- Questie's map tooltip: ShowOnTooltip builds through a fresh Tooltip._Rebuild,
-- which Questie calls again when a modifier key changes.
local questieTooltip = {}
function questieTooltip.ShowOnTooltip(icon, tooltip)
	tooltip._owner = icon
	tooltip._Rebuild = function(tt) tt.lines = { "Questie: " .. tostring(icon.data and icon.data.Id) } end
	tooltip:_Rebuild()
	tooltip:Show()
end
QuestieLoader = {
	ImportModule = function(_, name)
		return ({ QuestieDB = questieDB, QuestieFramePool = questiePool, MapIconTooltip = questieTooltip, QuestiePlayer = questiePlayer, QuestieProfessions = questieProfessions, l10n = questieL10n })[name]
	end,
}

-- Item clicks and item tooltips
MOUSE_BUTTON = "LeftButton"
function GetMouseButtonClicked() return MOUSE_BUTTON end
function HandleModifiedItemClick() return false end
Enum = { TooltipDataType = { Item = 0 } }
ItemRefTooltip = NewFrame()
RARESCANNER_BUTTON = NewFrame(UIParent) -- RareScanner's "rare found" alert
TooltipDataProcessor = { AddTooltipPostCall = function(kind, f) if kind == Enum.TooltipDataType.Item then ITEM_POSTCALL = f end end }

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
-- New companion app: told once at login, /wh app shows its download link
local function countLog(text) local n = 0 for _, line in ipairs(LOG) do if line:find(text, 1, true) then n = n + 1 end end return n end
local companionNotice = ns.L.COMPANION_UPDATED:match("^(.-)%%s")
check(countLog(companionNotice) == 1, "companion update notice not shown once")
check(WowheadForeverLinkDB.companionSeen ~= nil, "companion version not remembered")
fire("PLAYER_LOGIN")
check(countLog(companionNotice) == 1, "companion update notice repeated")
SlashCmdList.WOWHEADFOREVERLINK("app")
check(lastURL() == "https://github.com/AlexDXC2026/WowheadForeverLink/releases/latest/download/WowheadForeverLink-Companion.exe", "/wh app URL: " .. tostring(lastURL()))
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

-- Questie map icons: Alt + click opens the quest with its requirements
local info = function() return WowheadForeverLinkWindow.info end
check(QuestieFrame1.wowheadForeverLink, "icon created before the hook not decorated")
local icon = questiePool:GetFrame()
check(icon.wowheadForeverLink, "icon from the pool not decorated")
icon.data = { Id = 500 }
SlashCmdList.WOWHEADFOREVERLINK("q 5")
icon.scripts.OnClick(icon, "LeftButton")
check(lastURL() == B .. "quest=5", "plain click on a Questie icon opened Wowhead")
ALT = true; icon.scripts.OnClick(icon, "LeftButton"); ALT = false
check(lastURL() == B .. "quest=500", "Alt+click URL: " .. tostring(lastURL()))
check(WowheadForeverLinkWindow.title.text == "Into the Swamp", "Questie quest name as title")
local text = tostring(info().text)
check(info():IsShown(), "requirements hidden")
check(text:find("Missing pre-quest", 1, true), "Questie availability text")
check(text:find("ReadyCheck-Ready:14|t " .. ns.L.REQ_LEVEL:format(30, 36), 1, true), "level met")
check(text:find("ReadyCheck-Ready:14|t First Step", 1, true), "completed pre-quest")
check(text:find("ReadyCheck-NotReady:14|t Second Step", 1, true), "missing pre-quest (negative ID)")
check(text:find(ns.L.REQ_ALL, 1, true), "all-of label")

icon.data = { Id = 600 }
ALT = true; icon.scripts.OnClick(icon, "LeftButton"); ALT = false
text = tostring(info().text)
check(text:find("ReadyCheck-NotReady:14|t " .. ns.L.REQ_LEVEL:format(40, 36), 1, true), "level not met")
check(text:find(ns.L.REQ_ONE, 1, true), "one-of label")

icon.data = { Id = 700 }
ALT = true; icon.scripts.OnClick(icon, "LeftButton"); ALT = false
check(tostring(info().text):find(ns.L.REQ_NONE, 1, true), "no pre-quests line")

-- Pre-quest missing from Questie's data (Battle at the Mannoroc Coven needs the orb chain)
icon.data = { Id = 96438 }
ALT = true; icon.scripts.OnClick(icon, "LeftButton"); ALT = false
text = tostring(info().text)
check(text:find("ReadyCheck-NotReady:14|t Return to Delgren", 1, true), "missing Questie pre-quest not shown")
check(not text:find(ns.L.REQ_NONE, 1, true), "says no pre-quests although one is missing")
check(not text:find("Available", 1, true), "Questie's wrong verdict shown")
COMPLETED[78093] = true
ALT = true; icon.scripts.OnClick(icon, "LeftButton"); ALT = false
text = tostring(info().text)
check(text:find("ReadyCheck-Ready:14|t Return to Delgren", 1, true), "done pre-quest not marked")
check(text:find("Available", 1, true), "Questie's verdict hidden once the pre-quest is done")
COMPLETED[78093] = nil

-- Aeonas's Secret Refuge needs Katherine's chain, also missing from Questie
icon.data = { Id = 96449 }
COMPLETED[96438] = true; COMPLETED[79939] = true
ALT = true; icon.scripts.OnClick(icon, "LeftButton"); ALT = false
text = tostring(info().text)
check(text:find("ReadyCheck-Ready:14|t Battle at the Mannoroc Coven", 1, true), "chain start not marked done")
check(text:find("ReadyCheck-NotReady:14|t A Lost Brother", 1, true), "missing A Lost Brother not shown")
check(not text:find(ns.L.REQ_NONE, 1, true) and not text:find("Available", 1, true), "Aeonas's Secret Refuge still says available")
COMPLETED[79940] = true
ALT = true; icon.scripts.OnClick(icon, "LeftButton"); ALT = false
check(tostring(info().text):find("Available", 1, true), "verdict hidden once the chain is done")
COMPLETED[96438] = nil; COMPLETED[79939] = nil; COMPLETED[79940] = nil

-- Return to Rageroar comes after either of two chains, missing from Questie
icon.data = { Id = 86797 }
ALT = true; icon.scripts.OnClick(icon, "LeftButton"); ALT = false
text = tostring(info().text)
check(text:find(ns.L.REQ_ONE, 1, true), "one-of label for missing branch pre-quests")
check(text:find("ReadyCheck-NotReady:14|t Master Feardred", 1, true) and text:find("ReadyCheck-NotReady:14|t Thinning Their Forces", 1, true), "branch pre-quests not shown")
check(not text:find(ns.L.REQ_NONE, 1, true) and not text:find("Available", 1, true), "Return to Rageroar still says available")
COMPLETED[86792] = true
ALT = true; icon.scripts.OnClick(icon, "LeftButton"); ALT = false
check(tostring(info().text):find("Available", 1, true), "verdict hidden although one branch is done")
COMPLETED[86792] = nil

-- Profession skill: Clamlette Surprise needs Cooking 225
icon.data = { Id = 6610 }
ALT = true; icon.scripts.OnClick(icon, "LeftButton"); ALT = false
text = tostring(info().text)
check(text:find("ReadyCheck-NotReady:14|t " .. ns.L.REQ_SKILL:format("Cooking", 225, 180), 1, true), "missing skill level not shown")
PROFESSIONS[185][2] = 225
ALT = true; icon.scripts.OnClick(icon, "LeftButton"); ALT = false
check(tostring(info().text):find("ReadyCheck-Ready:14|t " .. ns.L.REQ_SKILL:format("Cooking", 225, 225), 1, true), "reached skill level not marked")
PROFESSIONS[185] = nil -- profession not learned: Questie's translated name, rank 0
ALT = true; icon.scripts.OnClick(icon, "LeftButton"); ALT = false
check(tostring(info().text):find("ReadyCheck-NotReady:14|t " .. ns.L.REQ_SKILL:format("Cocina", 225, 0), 1, true), "unlearned profession not shown")
PROFESSIONS[185] = { "Cooking", 180 }
icon.data = { Id = 700 }
ALT = true; icon.scripts.OnClick(icon, "LeftButton"); ALT = false
check(not tostring(info().text):find(ns.L.REQ_SKILL:gsub("%%.*", ""), 1, true), "skill line on a quest without one")

-- A quest already in the log shows no requirements
SlashCmdList.WOWHEADFOREVERLINK("q 783")
check(not info():IsShown(), "requirements shown for a quest in the log")

-- Hovering a Questie "!" icon: requirements + Alt hint, kept after Questie redraws
local function tooltipText() return table.concat(GameTooltip.lines or {}, "\n") end
icon.data = { Id = 500, Type = "available" }
questieTooltip.ShowOnTooltip(icon, GameTooltip)
local tt = tooltipText()
check(tt:find("Questie: 500", 1, true), "Questie's own tooltip lines lost")
check(tt:find(ns.L.REQ_TITLE, 1, true), "no requirements in the tooltip")
check(tt:find("ReadyCheck-NotReady:14|t Second Step", 1, true), "missing pre-quest not in the tooltip")
check(GameTooltip.lines[#GameTooltip.lines] == ns.L.QUESTIE_ALT_CLICK, "no Alt+click hint in the tooltip")
GameTooltip:_Rebuild() -- modifier key pressed
tt = tooltipText()
check(tt:find(ns.L.REQ_TITLE, 1, true) and tt:find(ns.L.QUESTIE_ALT_CLICK, 1, true), "lines lost after Questie's rebuild")
local count = 0
for _ in tt:gmatch(ns.L.QUESTIE_ALT_CLICK:gsub("%p", "%%%0")) do count = count + 1 end
check(count == 1, "hint duplicated after rebuild: " .. count)
-- A second show wraps the new _Rebuild once (no stacking)
questieTooltip.ShowOnTooltip(icon, GameTooltip); GameTooltip:_Rebuild()
count = 0
for _ in tooltipText():gmatch(ns.L.QUESTIE_ALT_CLICK:gsub("%p", "%%%0")) do count = count + 1 end
check(count == 1, "hint stacked after a second show: " .. count)
-- Objective icons (not "!"): only the hint, no requirements
icon.data = { Id = 500, Type = "monster" }
questieTooltip.ShowOnTooltip(icon, GameTooltip)
check(not tooltipText():find(ns.L.REQ_TITLE, 1, true), "requirements on an objective icon")
SlashCmdList.WOWHEADFOREVERLINK("diag")
check(WowheadForeverLinkDB.status.questie and WowheadForeverLinkDB.status.questieTooltip, "diag questie")

-- Items: Alt + click opens the item's quest (no requirements), or the item page
local function itemLink(id) return "|cffffffff|Hitem:" .. id .. "::::::::36:::::|h[Item " .. id .. "]|h|r" end
local function altClick(link) ALT = true; HandleModifiedItemClick(link); ALT = false end
check(#TICKERS == 1, "item index not started after login")
altClick(itemLink(5000))
check(lastURL() == B .. "quest=700", "item that starts a quest: " .. tostring(lastURL()))
check(not info():IsShown(), "requirements shown for an item's quest")
altClick(itemLink(4278))
check(lastURL() == B .. "item=4278", "item page before the index was built: " .. tostring(lastURL()))
check(WowheadForeverLinkWindow.title.text == "Item 4278", "item title: " .. tostring(WowheadForeverLinkWindow.title.text))
RunTickers()
altClick(itemLink(4278))
check(lastURL() == B .. "quest=1180", "objective item URL: " .. tostring(lastURL()))
check(WowheadForeverLinkWindow.title.text == "A Favor for Krazek", "item quest title")
check(not info():IsShown(), "requirements shown for an item's quest")
altClick(itemLink(7777)); check(lastURL() == B .. "quest=501", "item of a quest with no name")
altClick(itemLink(8888)); check(lastURL() == B .. "quest=600", "required source item")
altClick(itemLink(6666)); check(lastURL() == B .. "quest=783", "item of a quest in the log")
altClick(itemLink(3333)); check(lastURL() == B .. "item=3333", "item of a done quest opens the item")
altClick(itemLink(9999)); check(lastURL() == B .. "item=9999", "item without quests opens the item")

SlashCmdList.WOWHEADFOREVERLINK("q 5")
HandleModifiedItemClick(itemLink(4278))
check(lastURL() == B .. "quest=5", "click without Alt opened Wowhead")
ALT = true; SHIFT = true; HandleModifiedItemClick(itemLink(4278)); ALT = false; SHIFT = false
check(lastURL() == B .. "quest=5", "Alt+Shift click opened Wowhead")
MOUSE_BUTTON = "RightButton"; altClick(itemLink(4278)); MOUSE_BUTTON = "LeftButton"
check(lastURL() == B .. "quest=5", "Alt+right click opened Wowhead")
altClick(nil); altClick(NewSecret()); altClick("not a link")
check(lastURL() == B .. "quest=5", "bad link opened Wowhead")

-- Item tooltip: hint only when the item has a quest
GameTooltip:SetOwner(UIParent); ITEM_POSTCALL(GameTooltip, { id = 4278 })
check(GameTooltip.lines[#GameTooltip.lines] == ns.L.ITEM_ALT_CLICK, "no hint on a quest item tooltip")
GameTooltip:SetOwner(UIParent); ITEM_POSTCALL(GameTooltip, { id = 9999 })
check(#GameTooltip.lines == 0, "hint on an item without quests")
GameTooltip:SetOwner(UIParent); ITEM_POSTCALL(GameTooltip, { id = 3333 })
check(#GameTooltip.lines == 0, "hint on an item of a done quest")
local compare = NewFrame(); compare:SetOwner(UIParent); ITEM_POSTCALL(compare, { id = 4278 })
check(#compare.lines == 0, "hint on a comparison tooltip")
GameTooltip:SetOwner(UIParent); ITEM_POSTCALL(GameTooltip, { id = NewSecret() }); ITEM_POSTCALL(GameTooltip, nil)
check(#GameTooltip.lines == 0, "hint with a secret or missing item")

-- RareScanner alert: Wowhead icon on it
local rare = WowheadForeverLinkRareButton
check(rare ~= nil and rare.parent == RARESCANNER_BUTTON, "no icon on RareScanner's alert")
RARESCANNER_BUTTON.entityID = 61; RARESCANNER_BUTTON.name = "Thuros Lightfingers"; RARESCANNER_BUTTON.atlasName = "VignetteKillElite"
rare.scripts.OnClick(rare)
check(lastURL() == B .. "npc=61#drops", "rare NPC URL: " .. tostring(lastURL()))
RARESCANNER_BUTTON.entityID = "2843"; RARESCANNER_BUTTON.name = "Battered Chest"; RARESCANNER_BUTTON.atlasName = "VignetteLoot"
rare.scripts.OnClick(rare)
check(lastURL() == B .. "object=2843#contains", "rare container URL: " .. tostring(lastURL()))
RARESCANNER_BUTTON.entityID = 900; RARESCANNER_BUTTON.name = "Storm"; RARESCANNER_BUTTON.atlasName = "VignetteEvent"
rare.scripts.OnClick(rare)
check(lastURL() == B .. "search?q=Storm", "rare event URL: " .. tostring(lastURL()))
SlashCmdList.WOWHEADFOREVERLINK("q 5")
RARESCANNER_BUTTON.entityID = nil; RARESCANNER_BUTTON.name = nil
rare.scripts.OnClick(rare)
check(lastURL() == B .. "quest=5", "alert without a rare opened Wowhead")

SlashCmdList.WOWHEADFOREVERLINK("diag")
s = WowheadForeverLinkDB.status
check(s.itemClick and s.itemTooltip and s.itemIndex == "ready" and s.rareScanner, "diag items and rares")

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
