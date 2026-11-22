-- Wowhead Forever Link: open Wowhead (Forever section, client language) for
-- NPCs, objects and quests from inside the game.
-- Addons cannot open a browser or write to the clipboard, so the URL is shown
-- pre-selected and the player copies it with Ctrl+C. The optional companion
-- app (see README) opens copied Wowhead links automatically.

local ADDON_NAME, ns = ...
local L = ns.L
local BASE = ns.wowheadBase
local ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\icon.png"
local GetMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local VERSION = GetMetadata and GetMetadata(ADDON_NAME, "Version") or "?"
-- Last release that changed the companion app. Raise it only in a release that ships a new .exe:
-- players are told once, at login, to download it again.
local COMPANION_VERSION = "1.3.2"
local COMPANION_URL = "https://github.com/AlexDXC2026/WowheadForeverLink/releases/latest/download/WowheadForeverLink-Companion.exe"

local DB
local cachedTarget -- last readable data of the target, read when it changed
local hooked = {}

local function IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v)
end

local function Print(text)
	print("|cff39c0edWowhead|r: " .. text)
end

local function Diag(text)
	if not DB then return end
	DB.diag = DB.diag or {}
	local d = DB.diag
	d[#d + 1] = date("%Y-%m-%d %H:%M:%S") .. " " .. text
	while #d > 50 do table.remove(d, 1) end
end

-- Runs f protected: an error goes to chat and to the diag log, never breaks the rest.
local function Safe(where, f, ...)
	local ok, err = pcall(f, ...)
	if not ok then
		Diag("ERROR " .. where .. ": " .. tostring(err))
		Print("|cffff4040" .. L.ERROR_IN:format(where) .. "|r")
	end
end

local function UrlEncode(text)
	return (text:gsub("[^%w%-_%.~]", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

---------------------------------------------------------------------------
-- URL window
---------------------------------------------------------------------------
local window

local function CreateWindow()
	local f = CreateFrame("Frame", "WowheadForeverLinkWindow", UIParent, "BackdropTemplate")
	f:SetSize(400, 118)
	f:SetPoint("CENTER", 0, 180)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	if f.SetBackdrop then
		f:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
	end
	f:Hide()

	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetSize(18, 18)
	icon:SetPoint("TOPLEFT", 18, -16)
	icon:SetTexture(ICON)

	f.title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	f.title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
	f.title:SetPoint("RIGHT", f, "RIGHT", -34, 0)
	f.title:SetJustifyH("LEFT")
	f.title:SetWordWrap(false)

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	local e = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	e:SetSize(350, 20)
	e:SetPoint("TOP", 4, -46)
	e:SetAutoFocus(false)
	e:SetMaxLetters(0)
	f.edit = e

	f.hint = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	f.hint:SetPoint("TOP", e, "BOTTOM", -4, -10)
	f.hint:SetText(L.COPY_HINT)

	-- Optional extra lines (quest requirements from Questie).
	f.info = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	f.info:SetPoint("TOPLEFT", 24, -96)
	f.info:SetWidth(352)
	f.info:SetJustifyH("LEFT")
	f.info:SetJustifyV("TOP")
	f.info:SetSpacing(2)

	e:SetScript("OnEscapePressed", function() f:Hide() end)
	e:SetScript("OnEnterPressed", function() f:Hide() end)
	-- Typing restores the URL: the box only exists to copy from.
	e:SetScript("OnTextChanged", function(self, userInput)
		if userInput and f.url and self:GetText() ~= f.url then
			self:SetText(f.url)
			self:HighlightText()
		end
	end)
	e:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	e:SetScript("OnMouseUp", function(self)
		self:SetFocus()
		self:HighlightText()
	end)
	e:SetScript("OnKeyDown", function(_, key)
		if key == "C" and IsControlKeyDown() then
			local generation = f.generation
			C_Timer.After(0.1, function()
				if f.generation == generation and f:IsShown() then
					f:Hide()
					Print(L.COPIED)
				end
			end)
		end
	end)
	f:SetScript("OnHide", function() e:ClearFocus() end)

	if UISpecialFrames then
		table.insert(UISpecialFrames, "WowheadForeverLinkWindow")
	end
	return f
end

local WINDOW_HEIGHT = 118

local function ShowURL(url, title, infoLines)
	window = window or CreateWindow()
	window.generation = (window.generation or 0) + 1
	window.url = url
	window.title:SetText(title or "Wowhead")
	window.edit:SetText(url)
	if infoLines and #infoLines > 0 then
		window.info:SetText(table.concat(infoLines, "\n"))
		window.info:Show()
		window:SetHeight(WINDOW_HEIGHT + 8 + (window.info:GetStringHeight() or 0))
	else
		window.info:SetText("")
		window.info:Hide()
		window:SetHeight(WINDOW_HEIGHT)
	end
	window:Show()
	-- With the gamepad UI on, focusing from addon code taints Blizzard's
	-- navigation (Questie avoids it too): there focus comes from a click.
	if SmartNavigation and SmartNavigation.IsShown and SmartNavigation:IsShown() then
		window.hint:SetText(L.COPY_HINT_GAMEPAD)
	else
		window.hint:SetText(L.COPY_HINT)
		window.edit:SetFocus()
		window.edit:HighlightText()
	end
	if DB then DB.last = url end
end

---------------------------------------------------------------------------
-- Units and quests
---------------------------------------------------------------------------
local function QuestURL(questID)
	return BASE .. "quest=" .. questID
end

local function SearchURL(text)
	return BASE .. "search?q=" .. UrlEncode(text)
end

-- Reads a unit without ever comparing a secret value.
-- Returns nil when there is nothing useful (no unit, or a player).
local function ReadUnit(unit)
	local exists = UnitExists(unit)
	if IsSecret(exists) then return { kind = "secret" } end
	if not exists then return nil end

	local isPlayer = UnitIsPlayer(unit)
	if IsSecret(isPlayer) then return { kind = "secret" } end
	if isPlayer then return nil end

	local name = UnitName(unit)
	if IsSecret(name) then name = nil end

	local guid = UnitGUID(unit)
	if guid ~= nil and not IsSecret(guid) then
		local unitType, _, _, _, _, id = strsplit("-", guid)
		id = tonumber(id)
		if id and (unitType == "Creature" or unitType == "Vehicle") then
			return { kind = "npc", id = id, name = name }
		elseif id and unitType == "GameObject" then
			return { kind = "object", id = id, name = name }
		elseif unitType == "Pet" then
			return nil
		end
	end
	if name then return { kind = "search", name = name } end
	return { kind = "secret" }
end

local function OpenUnit(data)
	if not data then
		Print(L.NO_UNIT)
		return
	end
	if data.kind == "npc" then
		ShowURL(BASE .. "npc=" .. data.id .. "#drops", (data.name or L.NPC:format(data.id)) .. " · " .. L.LOOT)
	elseif data.kind == "object" then
		ShowURL(BASE .. "object=" .. data.id .. "#contains", (data.name or L.OBJECT:format(data.id)) .. " · " .. L.CONTENTS)
	elseif data.kind == "search" then
		ShowURL(SearchURL(data.name), data.name .. " · " .. L.SEARCH)
	else
		Print(L.UNIT_HIDDEN)
		Diag("secret unit")
	end
end

local function OpenTarget()
	local data = ReadUnit("target")
	-- Secret now but readable when it was targeted: use what was saved.
	if data and data.kind == "secret" and cachedTarget and cachedTarget.kind ~= "secret" then
		data = cachedTarget
	end
	OpenUnit(data)
end

---------------------------------------------------------------------------
-- Questie (optional): quest names and "can you take it?" requirements
---------------------------------------------------------------------------
local function QuestieModule(name)
	if not (QuestieLoader and QuestieLoader.ImportModule) then return nil end
	local ok, module = pcall(QuestieLoader.ImportModule, QuestieLoader, name)
	if ok and type(module) == "table" then return module end
end

local READY = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t "
local NOT_READY = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14|t "

local function IsQuestCompleted(questID)
	if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
		local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, questID)
		if ok and done ~= nil and not IsSecret(done) then return done == true end
	end
	local complete = Questie and Questie.db and Questie.db.char and Questie.db.char.complete
	return complete and complete[questID] and true or false
end

local function QuestieQuestName(db, questID)
	if not (db and db.QueryQuestSingle) then return nil end
	local ok, name = pcall(db.QueryQuestSingle, questID, "name")
	if ok and type(name) == "string" then return name end
end

-- Previous quests that Questie's database leaves out. Sources: the quest's "Series" box on
-- Wowhead (WoW Forever) or a Wowhead comment from a player who checked it in game.
-- Each listed quest is required on top of Questie's own pre-quests.
local MISSING_PREQUESTS = {
	-- Paladin, Sheath of Light chain.
	-- Battle at the Mannoroc Coven: Katherine the Pure only offers it after
	-- the Althalaxx Orb chain (the SoD Divine Storm quests), which ends in Return to Delgren.
	[96438] = { 78093 },
	[79939] = { 96438 }, -- The Broken Hammer
	-- Aeonas's Secret Refuge: Harold Riggs only offers it after Katherine the Pure's
	-- chain: Battle at the Mannoroc Coven, The Broken Hammer and A Lost Brother.
	[96449] = { 96438, 79939, 79940 },
	[79945] = { 96449 }, -- Orders from the Grand Crusader
	[79963] = { 79946 }, -- By The Light's Grace
	[79970] = { 79963 }, -- Aeonas the Vindicated
	-- Paladin, Katherine the Pure's later chains.
	[81764] = { 81762 }, -- The Mysterious Merchant
	[81765] = { 81764 }, -- Elrick, Paladin of the Silver Hand
	[96476] = { 81766 }, -- In Search of Aeonas
	-- Dead Drop chain (The Horn of Xelthos).
	[78699] = { 78261 }, -- The Eye of Bhossca
	[80453] = { 80411 }, -- Best Laid Plans
	[80454] = { 80453 }, -- One Last Drop
	[80455] = { 80454 }, -- Biding Our Time
	-- Other chains.
	[81919] = { 81917 }, -- Brought to Heel
	[82135] = { 81885 }, -- The Price of Hope
	[84138] = { 84137 }, -- Frosty Favors
	[84319] = { 84318 }, -- Oh No Ye Don't!
	[84330] = { 84319 }, -- A Wee Bit O' Necromancy
	[84414] = { 84330 }, -- Send Me On Me Way
	[84332] = { 84414 }, -- A Thane's Gratitude
	-- Found in the 2026-11-22 review of every Forever/SoD quest without pre-quests in Questie.
	-- Paladin chains.
	[90902] = { 98601 }, -- Rediscovering the Light (player comment: The Mindless Ones, A Difficult Path, then this)
	[91209] = { 91208 }, -- Continue Your Training
	[94971] = { 97022 }, -- A Paladin's Steed
	[97175] = { 97174 }, -- Due Sacrifice
	[97177] = { 97175 }, -- Acts of Mercy
	[97176] = { 97177 }, -- Exorcising Terrordale
	[97179] = { 97178 }, -- Collection of Goods
	[97184] = { 97183 }, -- The Divination Scryer
	[97185] = { 97184 }, -- Justice and Retribution
	[99187] = { 93030 }, -- The Reliquary of Tyr
	-- Felwood, Timbermaw chains (Rageroar).
	[86791] = { 86752 }, -- Missing Blackmaw Scouts
	[86798] = { 86797 }, -- Timbermaw Reinforcements
	[87346] = { 86798 }, -- Chieftain Bloodmaw
	[86814] = { 87346 }, -- Blackmaw Counter-Offensive
	[92065] = { 86814 }, -- Blackmaw Reclamation
	[86804] = { 86799 }, -- An Unlikely Source
	[86925] = { 86804 }, -- Toil and Trouble
	[86926] = { 86925 }, -- Felfire Burn, Cauldron Bubble
	[86927] = { 86926 }, -- Running Firewater
	[86812] = { 86927 }, -- Transmuted Tincture
	[86813] = { 86812 }, -- Potential Panacea
	-- New race starts.
	[94947] = { 94946 }, -- Welcome to Azeroth
	[95350] = { 95349 }, -- Welcome to Azeroth
	[96996] = { 97205 }, -- Your First Riding Galestrider
	-- Other chains.
	[84146] = { 84135 }, -- Red Bag Blues (player comment)
	[84212] = { 84211 }, -- Bookin' it Back (player comment)
	[92008] = { 96796 }, -- Premiere Parts
	[92465] = { 92464 }, -- Agitators
	[92702] = { 92094 }, -- Branch Out
	[93787] = { 93786 }, -- Food for the Taking
	[95284] = { 95283 }, -- The Elite of the Elite
	[95809] = { 95647 }, -- Heartwoven
	[95817] = { 95816 }, -- Rotgath Stonebeard
	[97169] = { 97168 }, -- The Darkreaver Menace
	[97242] = { 97246 }, -- Yelmak's Medley
	[97883] = { 84377 }, -- End of the Dark Horde
}

-- Same, for quests reached from either of two chains: any one listed quest is enough.
local MISSING_ONE_PREQUESTS = {
	[3517] = { 91734, 91735 }, -- Stealing Knowledge (either Remote Contact)
	[86797] = { 86777, 86792 }, -- Return to Rageroar (Master Feardred or Thinning Their Forces)
}

-- Questie's pre-quests that must all be done, plus the missing ones above.
-- pending: one of the missing ones is not done, so Questie's verdict is wrong.
local function RequiredGroup(quest, questID)
	local extra = MISSING_PREQUESTS[questID]
	if not extra then return quest.preQuestGroup, false end
	local group, pending = {}, false
	if type(quest.preQuestGroup) == "table" then
		for _, id in ipairs(quest.preQuestGroup) do group[#group + 1] = id end
	end
	for _, id in ipairs(extra) do
		group[#group + 1] = id
		if not IsQuestCompleted(id) then pending = true end
	end
	return group, pending
end

-- Questie's one-of pre-quests plus the missing ones above.
-- pending: none of them is done, so Questie's verdict is wrong.
local function RequiredSingle(quest, questID)
	local extra = MISSING_ONE_PREQUESTS[questID]
	if not extra then return quest.preQuestSingle, false end
	local single, done = {}, false
	if type(quest.preQuestSingle) == "table" then
		for _, id in ipairs(quest.preQuestSingle) do single[#single + 1] = id end
	end
	for _, id in ipairs(extra) do single[#single + 1] = id end
	for _, id in ipairs(single) do
		if IsQuestCompleted(math.abs(id)) then done = true end
	end
	return single, not done
end

-- Profession skill the quest needs (Clamlette Surprise: Cooking 225), with the player's rank.
local function SkillRequirement(quest)
	local skill = quest.requiredSkill
	if type(skill) ~= "table" or type(skill[1]) ~= "number" or type(skill[2]) ~= "number" then return nil end
	local professions = QuestieModule("QuestieProfessions")
	local mine
	if professions and professions.GetPlayerProfessions then
		local ok, known = pcall(professions.GetPlayerProfessions, professions)
		if ok and type(known) == "table" and type(known[skill[1]]) == "table" then mine = known[skill[1]] end
	end
	local rank = mine and type(mine[2]) == "number" and mine[2] or 0
	local name = mine and type(mine[1]) == "string" and mine[1] -- the client's own name
	if not name and professions and professions.GetProfessionName then
		local ok, english = pcall(professions.GetProfessionName, professions, skill[1])
		if ok and type(english) == "string" then
			local l10n = QuestieModule("l10n")
			local okText, text = false, nil
			if l10n then okText, text = pcall(l10n, english) end
			name = okText and type(text) == "string" and text or english
		end
	end
	name = name or L.SKILL:format(skill[1])
	return (rank >= skill[2] and READY or NOT_READY) .. L.REQ_SKILL:format(name, skill[2], rank)
end

-- Lines that tell whether the player can take the quest, from Questie's database.
local function QuestRequirements(db, questID)
	if not (db and db.GetQuest) then return nil end
	local ok, quest = pcall(db.GetQuest, questID)
	if not ok or type(quest) ~= "table" then return nil end

	local group, missingPending = RequiredGroup(quest, questID)
	local single, onePending = RequiredSingle(quest, questID)
	local lines = { "|cffffd100" .. L.REQ_TITLE .. "|r" }
	if db.IsDoableVerbose and not missingPending and not onePending then
		local okText, text = pcall(db.IsDoableVerbose, questID, false, true, true)
		if okText and type(text) == "string" and text ~= "" then lines[#lines + 1] = text end
	end

	local level = quest.requiredLevel
	local mine = UnitLevel("player")
	if type(level) == "number" and level > 1 and type(mine) == "number" and not IsSecret(mine) then
		lines[#lines + 1] = (mine >= level and READY or NOT_READY) .. L.REQ_LEVEL:format(level, mine)
	end
	local skill = SkillRequirement(quest)
	if skill then lines[#lines + 1] = skill end

	local function AddQuests(list, label)
		if type(list) ~= "table" or not next(list) then return false end
		lines[#lines + 1] = label
		for _, id in ipairs(list) do
			local preID = math.abs(id) -- negative entries only skip Questie's exclusive check
			local name = QuestieQuestName(db, preID) or L.QUEST:format(preID)
			lines[#lines + 1] = "   " .. (IsQuestCompleted(preID) and READY or NOT_READY) .. name
		end
		return true
	end
	local hasAll = AddQuests(group, L.REQ_ALL)
	local hasOne = AddQuests(single, L.REQ_ONE)
	if not hasAll and not hasOne then lines[#lines + 1] = READY .. L.REQ_NONE end
	return lines
end

-- withoutRequirements: just the link, as for quest items.
local function OpenQuest(questID, withoutRequirements)
	if not questID or IsSecret(questID) or questID == 0 then
		Print(L.NO_QUEST)
		return
	end
	local title
	if C_QuestLog and C_QuestLog.GetTitleForQuestID then
		local ok, t = pcall(C_QuestLog.GetTitleForQuestID, questID)
		if ok and t ~= nil and not IsSecret(t) then title = t end
	end
	local db = QuestieModule("QuestieDB")
	title = title or QuestieQuestName(db, questID)
	local info
	local onQuest = C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(questID)
	if not withoutRequirements and onQuest ~= true then -- requirements only matter for quests not taken yet
		local ok, lines = pcall(QuestRequirements, db, questID)
		if ok then info = lines else Diag("requirements: " .. tostring(lines)) end
	end
	ShowURL(QuestURL(questID), title or L.QUEST:format(questID), info)
end

-- Key bindings (Bindings.xml)
function WowheadForeverLink_Target() Safe("binding target", OpenTarget) end
function WowheadForeverLink_Mouseover()
	Safe("binding mouseover", function()
		local data = ReadUnit("mouseover")
		if not data then
			Print(L.NO_MOUSEOVER)
			return
		end
		OpenUnit(data)
	end)
end
BINDING_HEADER_WOWHEADFOREVERLINK = "Wowhead Forever Link"
BINDING_NAME_WOWHEADFOREVERLINK_TARGET = L.BINDING_TARGET
BINDING_NAME_WOWHEADFOREVERLINK_MOUSEOVER = L.BINDING_MOUSEOVER

---------------------------------------------------------------------------
-- Tooltip helper
---------------------------------------------------------------------------
local function ShowTooltip(owner, ...)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	for i, line in ipairs({ ... }) do
		if i == 1 then
			GameTooltip:SetText(line, 1, 1, 1)
		else
			GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true)
		end
	end
	GameTooltip:Show()
end

local function HideTooltip() GameTooltip:Hide() end

---------------------------------------------------------------------------
-- Button next to the target frame
---------------------------------------------------------------------------
local targetButton

local function PlaceTargetButton()
	local b = targetButton
	b:ClearAllPoints()
	if DB.x and DB.y then
		b:SetPoint("CENTER", TargetFrame, "BOTTOMLEFT", DB.x, DB.y)
	else
		local portrait = TargetFrame.TargetFrameContainer and TargetFrame.TargetFrameContainer.Portrait
		if portrait then
			b:SetPoint("CENTER", portrait, "BOTTOMLEFT", 6, 6)
		else
			b:SetPoint("TOPRIGHT", TargetFrame, "TOPRIGHT", -4, -4)
		end
	end
end

local function UpdateTargetButton()
	if not targetButton then return end
	cachedTarget = ReadUnit("target")
	if cachedTarget then targetButton:Show() else targetButton:Hide() end
end

local function CreateTargetButton()
	if not TargetFrame then
		Diag("no TargetFrame")
		return
	end
	local b = CreateFrame("Button", "WowheadForeverLinkTargetButton", TargetFrame)
	b:SetSize(22, 22)
	b:SetFrameLevel(TargetFrame:GetFrameLevel() + 20)
	b:RegisterForClicks("LeftButtonUp")
	b:RegisterForDrag("LeftButton")

	local t = b:CreateTexture(nil, "ARTWORK")
	t:SetAllPoints()
	t:SetTexture(ICON)
	b:SetHighlightTexture(ICON, "ADD")

	b:SetScript("OnClick", function() Safe("target button", OpenTarget) end)
	b:SetScript("OnEnter", function(self)
		ShowTooltip(self, L.TARGET_BUTTON_TITLE, L.TARGET_BUTTON_CLICK, L.TARGET_BUTTON_MOVE)
	end)
	b:SetScript("OnLeave", HideTooltip)

	-- Own drag: the position is saved relative to the target frame, so the
	-- button follows it when the frame is moved in Edit Mode.
	b:SetScript("OnDragStart", function(self)
		if not IsShiftKeyDown() then return end
		self:SetScript("OnUpdate", function(me)
			local cx, cy = GetCursorPosition()
			local scale = me:GetEffectiveScale()
			local left, bottom = TargetFrame:GetLeft(), TargetFrame:GetBottom()
			if left == nil or bottom == nil or IsSecret(left) or IsSecret(bottom) then return end
			DB.x = math.floor(cx / scale - left + 0.5)
			DB.y = math.floor(cy / scale - bottom + 0.5)
			PlaceTargetButton()
		end)
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

	targetButton = b
	PlaceTargetButton()
	UpdateTargetButton()
end

---------------------------------------------------------------------------
-- Quest log (world map) and the NPC quest window
---------------------------------------------------------------------------
local function CreateQuestIcon(parent, size, getQuestID, tooltip)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size, size)
	local t = b:CreateTexture(nil, "ARTWORK")
	t:SetAllPoints()
	t:SetTexture(ICON)
	b:SetHighlightTexture(ICON, "ADD")
	b:SetScript("OnClick", function(self)
		Safe("quest icon", function() OpenQuest(getQuestID(self)) end)
	end)
	b:SetScript("OnEnter", function(self) ShowTooltip(self, tooltip or L.QUEST_TOOLTIP) end)
	b:SetScript("OnLeave", HideTooltip)
	return b
end

local function DecorateQuestList()
	if not (QuestScrollFrame and QuestScrollFrame.titleFramePool) then return end
	for button in QuestScrollFrame.titleFramePool:EnumerateActive() do
		if not button.wowheadForeverLink then
			local icon = CreateQuestIcon(button, 13, function(self) return self:GetParent().questID end)
			if button.TagTexture then
				icon:SetPoint("RIGHT", button.TagTexture, "LEFT", -2, 0)
			else
				icon:SetPoint("RIGHT", button, "RIGHT", -40, 0)
			end
			icon:SetFrameLevel(button:GetFrameLevel() + 5)
			button.wowheadForeverLink = icon
		end
		button.wowheadForeverLink:SetShown(button.questID ~= nil)
	end
end

local function HookQuestFrames()
	if not hooked.questList and type(QuestLogQuests_Update) == "function" then
		hooksecurefunc("QuestLogQuests_Update", function() Safe("quest list", DecorateQuestList) end)
		hooked.questList = true
		Safe("quest list", DecorateQuestList)
	end

	local details = QuestMapFrame and QuestMapFrame.DetailsFrame
	if not hooked.questDetails and details and details.BackFrame and details.BackFrame.BackButton then
		local b = CreateFrame("Button", "WowheadForeverLinkDetailsButton", details.BackFrame, "UIPanelButtonTemplate")
		b:SetSize(84, 22)
		b:SetText("Wowhead")
		b:SetPoint("LEFT", details.BackFrame.BackButton, "RIGHT", 4, 0)
		b:SetScript("OnClick", function()
			Safe("details button", function() OpenQuest(QuestMapFrame.DetailsFrame.questID) end)
		end)
		hooked.questDetails = true
	end

	-- NPC window when offering, asking for or turning in a quest.
	if not hooked.questFrame and QuestFrame then
		local b = CreateQuestIcon(QuestFrame, 20, function()
			return GetQuestID and GetQuestID() or nil
		end, L.QUEST_TOOLTIP_NPC)
		if QuestFrame.CloseButton then
			b:SetPoint("RIGHT", QuestFrame.CloseButton, "LEFT", -2, 0)
		else
			b:SetPoint("TOPRIGHT", QuestFrame, "TOPRIGHT", -28, -2)
		end
		b:SetFrameLevel(QuestFrame:GetFrameLevel() + 10)
		hooked.questFrame = true
	end
end

---------------------------------------------------------------------------
-- Questie map icons (world map and minimap): Alt + click opens the quest.
-- Questie uses Shift (hide quest) and Ctrl (TomTom) on its icons; Alt is free.
---------------------------------------------------------------------------
local function DecorateQuestieIcon(frame)
	if type(frame) ~= "table" or frame.wowheadForeverLink or not frame.HookScript then return end
	frame.wowheadForeverLink = true
	frame:HookScript("OnClick", function(self, button)
		if button ~= "LeftButton" or not IsAltKeyDown() then return end
		local id = self.data and self.data.Id
		if type(id) == "number" then Safe("questie icon", OpenQuest, id) end
	end)
end

-- Extra tooltip lines for a hovered Questie icon: for an available quest ("!"),
-- whether the player can take it; for any quest icon, the Alt+click hint.
local function AppendQuestieTooltip(tooltip, icon)
	local data = icon and icon.data
	local id = data and data.Id
	if type(id) ~= "number" then return end
	if data.Type == "available" then
		local ok, lines = pcall(QuestRequirements, QuestieModule("QuestieDB"), id)
		if ok and lines then
			tooltip:AddLine(" ")
			for _, line in ipairs(lines) do tooltip:AddLine(line, 1, 1, 1) end
		elseif not ok then
			Diag("tooltip requirements: " .. tostring(lines))
		end
	end
	tooltip:AddLine(L.QUESTIE_ALT_CLICK, 0.22, 0.75, 0.93)
	tooltip:Show()
end

-- Questie draws map icon tooltips in MapIconTooltip.ShowOnTooltip and redraws
-- them with Tooltip._Rebuild when a modifier key changes: add our lines both times.
local function HookQuestieTooltip()
	if hooked.questieTooltip then return end
	local module = QuestieModule("MapIconTooltip")
	if not (module and type(module.ShowOnTooltip) == "function") then return end
	hooksecurefunc(module, "ShowOnTooltip", function(icon, tooltip)
		Safe("questie tooltip", function()
			if type(tooltip) ~= "table" or tooltip._owner ~= icon then return end -- Questie skipped this show
			-- Questie assigns a new _Rebuild on every show: wrap each new one once.
			local rebuild = tooltip._Rebuild
			if type(rebuild) == "function" and rebuild ~= tooltip.wowheadForeverLinkRebuild then
				local wrapper = function(tt, ...)
					rebuild(tt, ...)
					Safe("questie tooltip", AppendQuestieTooltip, tt, tt._owner)
				end
				tooltip._Rebuild = wrapper
				tooltip.wowheadForeverLinkRebuild = wrapper
			end
			AppendQuestieTooltip(tooltip, icon)
		end)
	end)
	hooked.questieTooltip = true
end

-- Questie names its icons QuestieFrame1, QuestieFrame2...: covers icons created before the hook.
local scannedQuestieFrames = 0
local function ScanQuestieIcons()
	local i = scannedQuestieFrames + 1
	while _G["QuestieFrame" .. i] do
		DecorateQuestieIcon(_G["QuestieFrame" .. i])
		scannedQuestieFrames = i
		i = i + 1
	end
end

local function HookQuestieMap()
	if hooked.questie then return end
	local pool = QuestieModule("QuestieFramePool")
	if not (pool and type(pool.GetFrame) == "function") then return end
	local original = pool.GetFrame
	pool.GetFrame = function(...)
		local frame = original(...)
		Safe("questie icon", DecorateQuestieIcon, frame)
		return frame
	end
	if WorldMapFrame and WorldMapFrame.HookScript then
		WorldMapFrame:HookScript("OnShow", function() Safe("questie scan", ScanQuestieIcons) end)
	end
	ScanQuestieIcons()
	hooked.questie = true
end

---------------------------------------------------------------------------
-- Quest items (bags, chat links, loot): Alt + click an item that a quest not
-- taken yet asks for, or that starts one, opens that quest with its requirements.
-- The data comes from LibQuestieDB, installed with Questie. It lists the items of
-- each quest, so the item -> quests index is built once per session, a few
-- quests per frame.
---------------------------------------------------------------------------
local QUESTIEDB_CONTRACT = 2
local OBJECTIVE_ITEMS = 3 -- position of the item group in a quest's objectives
local QUESTS_PER_TICK = 40
local INDEX_DELAY = 10 -- seconds after login: Questie loads its own data first

local itemQuests -- [itemID] = { questID, ... }; nil until built
local indexState = "none" -- none, building, ready

local function QuestieLib()
	local lib = LibQuestieDB
	if type(lib) ~= "table" or type(lib.Quest) ~= "table" or type(lib.Item) ~= "table" then return nil end
	if type(lib.RequireContract) == "function" then
		local ok, fits = pcall(lib.RequireContract, QUESTIEDB_CONTRACT)
		if not (ok and fits) then return nil end
	end
	return lib
end

local function AddItemQuest(index, itemID, questID)
	if type(itemID) ~= "number" or itemID <= 0 then return end
	local list = index[itemID]
	if not list then
		index[itemID] = { questID }
		return
	end
	for _, known in ipairs(list) do
		if known == questID then return end
	end
	list[#list + 1] = questID
end

local function IndexQuest(lib, index, questID)
	local objectives = lib.Quest.Get(questID, "objectives")
	local items = type(objectives) == "table" and objectives[OBJECTIVE_ITEMS]
	if type(items) == "table" then
		for _, entry in ipairs(items) do
			-- Entries are { itemID, ... } tuples, or a bare ID.
			AddItemQuest(index, type(entry) == "table" and entry[1] or entry, questID)
		end
	end
	-- Needed to start the quest without being an objective.
	local needed = lib.Quest.Get(questID, "requiredSourceItems")
	if type(needed) == "table" then
		for _, itemID in ipairs(needed) do AddItemQuest(index, itemID, questID) end
	end
end

local function BuildItemIndex()
	if indexState ~= "none" then return end
	local lib = QuestieLib()
	if not (lib and type(lib.Quest.GetAllIds) == "function" and C_Timer and C_Timer.NewTicker) then return end
	local ok, ids = pcall(lib.Quest.GetAllIds)
	if not ok or type(ids) ~= "table" then
		Diag("item index: " .. tostring(ids))
		return
	end
	indexState = "building"
	local index, position, failed = {}, 1, 0
	local ticker
	ticker = C_Timer.NewTicker(0.05, function()
		for _ = 1, QUESTS_PER_TICK do
			local questID = ids[position]
			if questID == nil then
				ticker:Cancel()
				itemQuests = index
				indexState = "ready"
				if failed > 0 then Diag("item index: " .. failed .. " quests unreadable") end
				return
			end
			position = position + 1
			if not pcall(IndexQuest, lib, index, questID) then failed = failed + 1 end
		end
	end)
end

local function ItemIDFromLink(link)
	if type(link) ~= "string" or IsSecret(link) then return nil end
	return tonumber(link:match("item:(%d+)"))
end

-- The quest an item is for: one not taken yet first, then one in the log.
-- Done quests and quests of other races or classes do not count.
local function ItemQuest(itemID)
	local lib = QuestieLib()
	if not lib or type(itemID) ~= "number" then return nil end
	local player = QuestieModule("QuestiePlayer")
	local inLog
	local function Pending(questID)
		if type(questID) ~= "number" or IsQuestCompleted(questID) then return false end
		if player then
			if player.HasRequiredRace and not player.HasRequiredRace(lib.Quest.Get(questID, "requiredRaces")) then return false end
			if player.HasRequiredClass and not player.HasRequiredClass(lib.Quest.Get(questID, "requiredClasses")) then return false end
		end
		local onQuest = C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(questID)
		if not IsSecret(onQuest) and onQuest == true then
			inLog = inLog or questID
			return false
		end
		return true
	end
	local candidates = {}
	local ok, starts = pcall(lib.Item.Get, itemID, "startQuest")
	if ok then candidates[1] = starts end
	for _, questID in ipairs(itemQuests and itemQuests[itemID] or {}) do candidates[#candidates + 1] = questID end
	for _, questID in ipairs(candidates) do
		local okP, pending = pcall(Pending, questID)
		if okP and pending then return questID end
	end
	return inLog
end

-- Alt + click on an item: the page of its quest, or of the item itself.
local function OpenItem(link)
	local itemID = ItemIDFromLink(link)
	if not itemID then return end
	local questID = ItemQuest(itemID)
	if questID then
		OpenQuest(questID, true)
		return
	end
	local name = link:match("|h%[(.-)%]|h")
	ShowURL(BASE .. "item=" .. itemID, name or L.ITEM:format(itemID))
end

local function AppendItemTooltip(tooltip, itemID)
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end -- not the comparison ones
	if type(itemID) ~= "number" or IsSecret(itemID) then return end
	if not ItemQuest(itemID) then return end
	tooltip:AddLine(L.ITEM_ALT_CLICK, 0.22, 0.75, 0.93)
	tooltip:Show()
end

local function HookQuestItems()
	if not hooked.itemClick and type(HandleModifiedItemClick) == "function" then
		-- Bags, chat links, loot and merchant buttons all go through this on a modified click.
		hooksecurefunc("HandleModifiedItemClick", function(link)
			if not IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown() then return end
			local button = GetMouseButtonClicked and GetMouseButtonClicked()
			if button and button ~= "LeftButton" then return end
			Safe("item", OpenItem, link)
		end)
		hooked.itemClick = true
	end

	if not hooked.itemTooltip then
		if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
			TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
				Safe("item tooltip", AppendItemTooltip, tooltip, data and data.id)
			end)
			hooked.itemTooltip = true
		elseif GameTooltip and GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetItem") then
			for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
				tooltip:HookScript("OnTooltipSetItem", function(self)
					Safe("item tooltip", function()
						local _, link = self:GetItem()
						AppendItemTooltip(self, ItemIDFromLink(link))
					end)
				end)
			end
			hooked.itemTooltip = true
		end
	end

	if C_Timer and C_Timer.After then
		C_Timer.After(INDEX_DELAY, function() Safe("item index", BuildItemIndex) end)
	end
end

---------------------------------------------------------------------------
-- RareScanner (optional): a Wowhead icon on its "rare found" alert.
-- The alert is a secure button, so the icon is a separate child button
-- created out of combat at login; it reads what the alert is showing.
---------------------------------------------------------------------------
local function OpenRareScannerEntity(alert)
	local id, name = alert.entityID, alert.name
	if type(name) ~= "string" or IsSecret(name) then name = nil end
	id = tonumber(id)
	local atlas = type(alert.atlasName) == "string" and alert.atlasName:lower() or ""
	if id and atlas:find("loot", 1, true) then
		OpenUnit({ kind = "object", id = id, name = name })
	elseif id and not atlas:find("event", 1, true) then
		OpenUnit({ kind = "npc", id = id, name = name })
	elseif name then -- events have no Wowhead page of their own
		ShowURL(SearchURL(name), name .. " · " .. L.SEARCH)
	end
end

local function HookRareScanner()
	if hooked.rareScanner then return end
	local alert = _G.RARESCANNER_BUTTON
	if type(alert) ~= "table" or not alert.GetObjectType then return end
	local b = CreateFrame("Button", "WowheadForeverLinkRareButton", alert)
	b:SetSize(18, 18)
	b:SetPoint("TOPRIGHT", alert, "TOPRIGHT", -4, -4)
	b:SetFrameLevel(alert:GetFrameLevel() + 10)
	b:RegisterForClicks("LeftButtonUp")
	local t = b:CreateTexture(nil, "ARTWORK")
	t:SetAllPoints()
	t:SetTexture(ICON)
	b:SetHighlightTexture(ICON, "ADD")
	b:SetScript("OnClick", function(self) Safe("rare button", OpenRareScannerEntity, self:GetParent()) end)
	b:SetScript("OnEnter", function(self) ShowTooltip(self, L.RARE_BUTTON) end)
	b:SetScript("OnLeave", HideTooltip)
	hooked.rareScanner = true
end

---------------------------------------------------------------------------
-- Right-click on a portrait: entry in Blizzard's unit menu
---------------------------------------------------------------------------
-- Tags from UnitPopupShared ("MENU_UNIT_" .. which). An NPC in the target
-- frame is "TARGET"; focus and boss frames have their own menus.
local MENUS = { "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS", "MENU_UNIT_BOSS" }

local function HookUnitMenus()
	if hooked.menus then return end
	if not (Menu and Menu.ModifyMenu) then
		Diag("no Menu.ModifyMenu")
		return
	end
	for _, tag in ipairs(MENUS) do
		Menu.ModifyMenu(tag, function(_, root, context)
			Safe("menu " .. tag, function()
				local unit = context and context.unit
				if type(unit) ~= "string" then return end
				local data = ReadUnit(unit)
				if not data then return end
				-- Read when the menu opens: if it is secret by click time, this is used.
				root:CreateDivider()
				root:CreateButton("|T" .. ICON .. ":14|t " .. L.MENU_ENTRY, function()
					Safe("menu click", function()
						local now = ReadUnit(unit)
						if not now or now.kind == "secret" then now = data end
						OpenUnit(now)
					end)
				end)
			end)
		end)
	end
	hooked.menus = true
end

---------------------------------------------------------------------------
-- Slash commands (English and Spanish keywords work in every locale)
---------------------------------------------------------------------------
local function Help()
	Print("v" .. VERSION .. " · " .. L.HELP[1])
	for i = 2, #L.HELP do print(L.HELP[i]) end
end

local function SlashCommand(text)
	text = strtrim(text or "")
	local cmd, rest = text:match("^(%S+)%s*(.-)$")
	cmd = cmd and cmd:lower()

	if text == "" then
		OpenTarget()
	elseif cmd == "help" or cmd == "ayuda" or cmd == "?" then
		Help()
	elseif cmd == "q" or cmd == "quest" or cmd == "m" or cmd == "mision" or cmd == "misión" then
		local id = tonumber(rest)
		if id then OpenQuest(id) else Print(L.QUEST_USAGE) end
	elseif cmd == "last" or cmd == "ultima" or cmd == "última" then
		if DB.last then ShowURL(DB.last, L.LAST_LINK) else Print(L.NO_LINK_YET) end
	elseif cmd == "app" or cmd == "exe" or cmd == "programa" then
		ShowURL(COMPANION_URL, L.COMPANION_TITLE:format(COMPANION_VERSION))
	elseif cmd == "reset" then
		DB.x, DB.y = nil, nil
		if targetButton then PlaceTargetButton() end
		Print(L.RESET_DONE)
	elseif cmd == "diag" then
		DB.status = {
			version = VERSION,
			client = select(4, GetBuildInfo()),
			locale = ns.locale,
			base = BASE,
			targetButton = targetButton ~= nil,
			targetButtonShown = targetButton ~= nil and targetButton:IsShown() or false,
			questList = hooked.questList or false,
			questDetails = hooked.questDetails or false,
			questFrame = hooked.questFrame or false,
			menus = hooked.menus or false,
			questie = hooked.questie or false,
			questieTooltip = hooked.questieTooltip or false,
			itemClick = hooked.itemClick or false,
			itemTooltip = hooked.itemTooltip or false,
			itemIndex = indexState,
			rareScanner = hooked.rareScanner or false,
			target = cachedTarget and cachedTarget.kind or "none",
		}
		for k, v in pairs(DB.status) do print("  " .. k .. " = " .. tostring(v)) end
		Print(L.DIAG_SAVED)
	else
		ShowURL(SearchURL(text), text .. " · " .. L.SEARCH)
	end
end

SLASH_WOWHEADFOREVERLINK1 = "/wh"
SLASH_WOWHEADFOREVERLINK2 = "/wowhead"
SlashCmdList.WOWHEADFOREVERLINK = function(text) Safe("command", SlashCommand, text) end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON_NAME then
			WowheadForeverLinkDB = WowheadForeverLinkDB or {}
			DB = WowheadForeverLinkDB
			DB.diag = DB.diag or {}
		elseif DB and not (hooked.questList and hooked.questDetails and hooked.questFrame) then
			-- The map or the quest window may load later.
			Safe("hooks", HookQuestFrames)
		end
	elseif event == "PLAYER_LOGIN" then
		Safe("target button", CreateTargetButton)
		Safe("hooks", HookQuestFrames)
		Safe("menus", HookUnitMenus)
		Safe("questie", HookQuestieMap)
		Safe("questie tooltip", HookQuestieTooltip)
		Safe("quest items", HookQuestItems)
		Safe("rarescanner", HookRareScanner)
		Print(L.READY)
		if DB.companionSeen ~= COMPANION_VERSION then
			Print(L.COMPANION_UPDATED:format(COMPANION_VERSION))
			DB.companionSeen = COMPANION_VERSION
		end
	elseif event == "PLAYER_TARGET_CHANGED" then
		Safe("target changed", UpdateTargetButton)
	end
end)
