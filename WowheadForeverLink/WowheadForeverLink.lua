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

local function ShowURL(url, title)
	window = window or CreateWindow()
	window.generation = (window.generation or 0) + 1
	window.url = url
	window.title:SetText(title or "Wowhead")
	window.edit:SetText(url)
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

local function OpenQuest(questID)
	if not questID or IsSecret(questID) or questID == 0 then
		Print(L.NO_QUEST)
		return
	end
	local title
	if C_QuestLog and C_QuestLog.GetTitleForQuestID then
		local ok, t = pcall(C_QuestLog.GetTitleForQuestID, questID)
		if ok and t ~= nil and not IsSecret(t) then title = t end
	end
	ShowURL(QuestURL(questID), title or L.QUEST:format(questID))
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
		Print(L.READY)
	elseif event == "PLAYER_TARGET_CHANGED" then
		Safe("target changed", UpdateTargetButton)
	end
end)
