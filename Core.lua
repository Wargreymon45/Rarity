local _, addonTable = ...

local FORCE_PROFILE_RESET_BEFORE_REVISION = 1 -- Set this to one higher than the Revision on the line above this

-- Set DEBUG flag to never cause a profile reset while testing, even in the case of errors with the above version calculation. Can also be used for other things later, though I haven't thought of anything in particular just yet...
local isDebugVersion = false
--@debug@
isDebugVersion = true
--@end-debug@

local L = LibStub("AceLocale-3.0"):GetLocale("Rarity")
local R = Rarity
local lbz = LibStub("LibBabble-Zone-3.0"):GetUnstrictLookupTable()
local lbsz = LibStub("LibBabble-SubZone-3.0"):GetUnstrictLookupTable()
local lbb = LibStub("LibBabble-Boss-3.0"):GetUnstrictLookupTable()
local hbd = LibStub("HereBeDragons-2.0")

---


--[[
      VARIABLES ----------------------------------------------------------------------------------------------------------------
  ]]

R.modulesEnabled = {}

local npcs = {}
local items = {}
local bagitems = {}
local tempbagitems = {}
local used = {}
local fishzones = {}
local rarity_stats = {}
Rarity.mount_sources = {}
Rarity.pet_sources = {}
Rarity.lockouts = {}
Rarity.lockouts_detailed = {}
Rarity.lockouts_holiday = {}
Rarity.holiday_textures = {}
Rarity.ach_npcs_isKilled = {}
Rarity.ach_npcs_achId = {}
Rarity.stats_to_scan = {}
Rarity.items_with_stats = {}
Rarity.collection_items = {}
Rarity.itemInfoCache = {}

local bankOpen = false
local guildBankOpen = false
local auctionOpen = false
local tradeOpen = false
local tradeSkillOpen = false
local mailOpen = false

-- Maps spells of interest to their respective spell IDs (useful since both info is used by Blizzard APIs and the addon itself) - Only some of these are actually used right now, but who knows what the future will bring?
-- Note: Spell names are no longer needed, and dealing with them is actually more complicated after the 8.0.1 API changes. They're only used for readability's sake
Rarity.relevantSpells = {

	-- Tested (confirmed working in 8.0.1)
	[921] = "Pick Pocket",
	[3365] = "Opening",
	[13262] = "Disenchant",
	[22810] = "Opening - No Text",
	[30427] = "Extract Gas",
	[73979] = "Searching for Artifacts",
	[131474] = "Fishing",
	[158743] = "Fishing",
	[144528] = "Opening", -- Timeless Chest (Timeless Isle: Kukuru's Grotto)
	[195125] = "Skinning",
	[195258] = "Mother's Skinning Knife", -- Legion Toy with the same effect as regular skinning, but with a 40y range
	[231932] = "Opening", -- Wyrmtongue Cache (Broken Shore: Secret Treasure Lair)
	[265843] = "Mining",
	[265825] = "Herb Gathering",
	-- 8.2
	[6478] = "Opening", -- Pile of Coins (Mechagon Island: Armored Vaultbot)

	-- Not tested (but added just in case)
	[7731] = "Fishing",
	[7732] = "Fishing",
	[7620] = "Fishing",
	[18248] = "Fishing",
	[33095] = "Fishing",
	[51294] = "Fishing",
	[88868] = "Fishing",
	[110410] = "Fishing",
	[2575] = "Mining",
	[265853] = "Mining",
	[2575] = "Mining",
	[158754] = "Mining",
	[2576] = "Mining",
	[195122] = "Mining",
	[3564] = "Mining",
	[10248] = "Mining",
	[29354] = "Mining",
	[50310] = "Mining",
	[74517] = "Mining",
	[265837] = "Mining",
	[102161] = "Mining",
	[265845] = "Mining",
	[265841] = "Mining",
	[265839] = "Mining",
	[265847] = "Mining",
	[265849] = "Mining",
	[265851] = "Mining",
	[2366] = "Herb Gathering",
	[265835] = "Herb Gathering",
	[158745] = "Herb Gathering",
	[195114] = "Herb Gathering",
	[2368] = "Herb Gathering",
	[3570] = "Herb Gathering",
	[28695] = "Herb Gathering",
	[11993] = "Herb Gathering",
	[50300] = "Herb Gathering",
	[110413] = "Herb Gathering",
	[74519] = "Herb Gathering",
	[265819] = "Herb Gathering",
	[265821] = "Herb Gathering",
	[265823] = "Herb Gathering",
	[265827] = "Herb Gathering",
	[265829] = "Herb Gathering",
	[265831] = "Herb Gathering",
	[265834] = "Herb Gathering",
	[8613] = "Skinning",
	[8617] = "Skinning",
	[8618] = "Skinning",
	[32678] = "Skinning",
	[50305] = "Skinning",
	[74522] = "Skinning",
	[102216] = "Skinning",
	[158756] = "Skinning",

	-- Not tested (and disabled until they are needed)
	-- [1804] = "Pick Lock",
}

local tooltipLeftText1 = _G["GameTooltipTextLeft1"]
local fishing = false
local opening = false
local fishingTimer
local FISHING_DELAY = 22

local isPool = false
local lastNode

local itemCacheDebug = false

Rarity.itemsToPrime = {}
Rarity.itemsMasterList = {}
local initTimer
local numPrimeAttempts = 0

--[[
      CONSTANTS ----------------------------------------------------------------------------------------------------------------
  ]]

local CONSTANTS = addonTable.constants

-- Methods of obtaining
local NPC = "NPC"
local BOSS = "BOSS"
local ZONE = "ZONE"
local USE = "USE"
local FISHING = "FISHING"
local ARCH = "ARCH"
local SPECIAL = "SPECIAL"
local COLLECTION = "COLLECTION"

-- Sort modes
local SORT_NAME = "SORT_NAME"
local SORT_DIFFICULTY = "SORT_DIFFICULTY"
local SORT_PROGRESS = "SORT_PROGRESS"
local SORT_CATEGORY = "SORT_CATEGORY"
local SORT_ZONE = "SORT_ZONE"


--[[
      UPVALUES -----------------------------------------------------------------------------------------------------------------
  ]]

-- Lua APIs
local _G = getfenv(0)
local pairs = _G.pairs
local strlower = _G.strlower
local format = _G.format
local min = min
local tostring = tostring

-- WOW APIs
local UnitGUID = _G.UnitGUID
local UnitName = _G.UnitName
local UnitCanAttack = _G.UnitCanAttack
local UnitIsPlayer = _G.UnitIsPlayer
local UnitIsDead = _G.UnitIsDead
local GetNumLootItems = _G.GetNumLootItems
local GetLootSlotInfo = _G.GetLootSlotInfo
local GetLootSlotLink = _G.GetLootSlotLink
local GetItemInfo_Blizzard = _G.GetItemInfo
local GetItemInfo = function(id) return R:GetItemInfo(id) end
local GetRealZoneText = _G.GetRealZoneText
local GetContainerNumSlots = _G.GetContainerNumSlots
local GetContainerItemID = _G.GetContainerItemID
local GetContainerItemInfo = _G.GetContainerItemInfo
local GetNumArchaeologyRaces = _G.GetNumArchaeologyRaces
local GetArchaeologyRaceInfo = _G.GetArchaeologyRaceInfo
local GetStatistic = _G.GetStatistic
local GetLootSourceInfo = _G.GetLootSourceInfo
local GetBestMapForUnit = _G.C_Map.GetBestMapForUnit
local GetMapInfo = _G.C_Map.GetMapInfo
local C_Timer = _G.C_Timer
local IsSpellKnown = _G.IsSpellKnown
local CombatLogGetCurrentEventInfo = _G.CombatLogGetCurrentEventInfo

local NUM_BAG_SLOTS = _G.NUM_BAG_SLOTS
local COMBATLOG_OBJECT_AFFILIATION_MINE = _G.COMBATLOG_OBJECT_AFFILIATION_MINE
local COMBATLOG_OBJECT_AFFILIATION_PARTY = _G.COMBATLOG_OBJECT_AFFILIATION_PARTY
local COMBATLOG_OBJECT_AFFILIATION_RAID = _G.COMBATLOG_OBJECT_AFFILIATION_RAID

-- Addon APIs
local TSM_Interface = Rarity.Utils.TSM_Interface
local DebugCache = Rarity.Utils.DebugCache
local GetRealDropPercentage = Rarity.Statistics.GetRealDropPercentage
local FormatTime = Rarity.Utils.PrettyPrint.FormatTime
local GetDate = Rarity.Utils.Time.GetDate

do
	-- Set up the debug cache (TODO: Move to initialisation routine after the refactoring is complete)
	Rarity.Utils.DebugCache:SetOutputHandler(Rarity.Utils.PrettyPrint.DebugMsg)
end

--[[
      HELPERS ----------------------------------------------------------------------------------------------------------------
  ]]




-- Helper function (to look up map names more easily)
-- Returns the localized map name, or nil if the uiMapID is invalid
local function GetMapNameByID(uiMapID)
	local UiMapDetails = GetMapInfo(uiMapID)
	return UiMapDetails and UiMapDetails.name or nil
end


--[[
      LIFECYCLE ----------------------------------------------------------------------------------------------------------------
  ]]

function R:OnInitialize()
end


do
	local isInitialized = false

	function R:OnEnable()
		self:DoEnable()
	end

	function R:DoEnable()
		if isInitialized then return end
		isInitialized = true

		self:PrepareDefaults() -- Loads in any new items

		self.db = LibStub("AceDB-3.0"):New("RarityDB", self.defaults, true)
		self:SetSinkStorage(self.db.profile)

		self:RegisterChatCommand("rarity", "OnChatCommand")
		self:RegisterChatCommand("rare", "OnChatCommand")

		Rarity.GUI:RegisterDataBroker()

		-- Expose private objects
		R.npcs = npcs
		R.used = used
		R.tempbagitems = tempbagitems
		R.bagitems = bagitems
		R.fishzones = fishzones
		R.stats = rarity_stats

		-- LibSink still tries to call a non-existent Blizzard function sometimes
		if not CombatText_StandardScroll then CombatText_StandardScroll = 0 end
		if not UIERRORS_HOLD_TIME then UIERRORS_HOLD_TIME = 2 end
		if not CombatText_AddMessage then
		CombatText_AddMessage = function(text, _, r, g, b, sticky, _)
		UIErrorsFrame:AddMessage(text, r, g, b, 1, UIERRORS_HOLD_TIME)
		end
		end

		Rarity.GUI:InitialiseBar()

		Rarity.Collections:ScanExistingItems("INITIALIZING") -- Checks for items you already have
		self:ScanBags() -- Initialize our inventory list, as well as checking if you've obtained an item
		self:OnBagUpdate() -- This will update counters for collection items
		self:OnCurrencyUpdate("INITIALIZING") -- Prepare our currency list
		self:UpdateInterestingThings()
		Rarity.Tracking:FindTrackedItem()
		Rarity.Caching:SetReadyState(false)
		Rarity.GUI:UpdateText()
		Rarity.Caching:SetReadyState(true)
		Rarity.GUI:UpdateText()
		Rarity.GUI:UpdateBar()

		Rarity.Serialization:ImportFromBunnyHunter()

		Rarity.EventHandlers:Register()

		if R.Options_DoEnable then R:Options_DoEnable() end
		self.db.profile.lastRevision = R.MINOR_VERSION

		self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
		self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
		self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
		self.db.RegisterCallback(self, "OnProfileDeleted", "OnProfileChanged")

		RequestArtifactCompletionHistory() -- Request archaeology info from the server
		RequestRaidInfo() -- Request raid lock info from the server
		RequestLFDPlayerLockInfo() -- Request LFD data from the server; this is used for holiday boss detection
		C_Calendar.OpenCalendar() -- Request calendar info from the server

		-- Prepare a master list of all the items Rarity may need info for
		table.wipe(R.itemsMasterList)
		Rarity.Caching:SetPrimedItems(0)
		Rarity.Caching:SetItemsToPrime(0)
		for k, v in pairs(self.db.profile.groups) do
			if type(v) == "table" then
				for kk, vv in pairs(v) do
					if type(vv) == "table" then
						if vv.itemId then R.itemsMasterList[vv.itemId] = true end
						if vv.collectedItemId then
							if type(vv.collectedItemId) == "table" then
								for kkk, vvv in pairs(vv.collectedItemId) do R.itemsMasterList[vvv] = true end
							else
								R.itemsMasterList[vv.collectedItemId] = true
							end
						end
						if vv.items and type(vv.items) == "table" then
							for kkk, vvv in pairs(vv.items) do R.itemsMasterList[vvv] = true end
						end
					end
				end
			end
		end
		for k, v in pairs(self.db.profile.oneTimeItems) do
			if type(v) == "table" and v.itemId then R.itemsMasterList[v.itemId] = true end
		end
		for k, v in pairs(self.db.profile.extraTooltips.inventoryItems) do
			for kk, vv in pairs(v) do R.itemsMasterList[vv] = true end
		end
		local temp = {}
		for k, v in pairs(R.itemsMasterList) do
			Rarity.Caching:SetItemsToPrime(Rarity.Caching:GetItemsToPrime() + 1)
			temp[Rarity.Caching:GetItemsToPrime()] = k
		end
		R.itemsMasterList = temp

		-- Progressively prime our item cache over time instead of hitting Blizzard's API all at once
		Rarity.Caching:SetItemsToPrime(100) -- Just setting this temporarily to avoid a divide by zero
		self:ScheduleTimer(function()
			self:PrimeItemCache()
		end, 2)

		-- Scan instance locks 5 seconds after init
		self:ScheduleTimer(function()
			R:ScanInstanceLocks("DELAYED INIT")
		end, 5)

		-- Scan bags, currency, and instance locks 10 seconds after init
		self:ScheduleTimer(function()
			R:ScanBags()
			R:OnCurrencyUpdate("DELAYED INIT")
			R:OnBagUpdate()
			R:ScanInstanceLocks("DELAYED INIT 2")
		end, 10)

		-- Clean up session info
		for k, v in pairs(self.db.profile.groups) do
			if type(v) == "table" then
				for kk, vv in pairs(v) do
					if type(vv) == "table" then
						vv.session = nil
					end
				end
			end
		end

		-- Delayed calendar init a few times
		self:ScheduleTimer(function()
			if type(CalendarFrame) ~= "table" or not CalendarFrame:IsShown() then
				local CalendarTime = C_Calendar.GetDate()
				local month, year = CalendarTime.month, CalendarTime.year
				C_Calendar.SetAbsMonth(month, year)
			end
		end, 7)
		self:ScheduleTimer(function()
			if type(CalendarFrame) ~= "table" or not CalendarFrame:IsShown() then
				local CalendarTime = C_Calendar.GetDate()
				local month, year = CalendarTime.month, CalendarTime.year
				C_Calendar.SetAbsMonth(month, year)
			end
		end, 20)

		-- Update text again several times later - this helps get the icon right after login
		self:ScheduleTimer(function() R:DelayedInit() end, 10)
		self:ScheduleTimer(function() R:DelayedInit() end, 20)
		self:ScheduleTimer(function() R:DelayedInit() end, 30)
		self:ScheduleTimer(function() R:DelayedInit() end, 60)
		self:ScheduleTimer(function() R:DelayedInit() end, 120)
		self:ScheduleTimer(function() R:DelayedInit() end, 180)
		self:ScheduleTimer(function()
			self:ScanCalendar("FINAL INIT")
			Rarity.Collections:ScanExistingItems("FINAL INIT")
			Rarity.GUI:UpdateText()
		end, 240)

		self:Debug(L["Loaded (running in debug mode)"])

		if self.db.profile.verifyDatabaseOnLogin then self:VerifyItemDB() end

	end

end


function R:DelayedInit()
	self:ScanStatistics("DELAYED INIT")
	self:ScanCalendar("DELAYED INIT")
	Rarity.Collections:ScanToys("DELAYED INIT")
	Rarity.Collections:ScanTransmog("DELAYED INIT")
	Rarity.GUI:UpdateText()
	Rarity.GUI:UpdateBar()
end


function R:PrimeItemCache()
	numPrimeAttempts = numPrimeAttempts + 1
	if numPrimeAttempts >= 20 then
		self:Debug("Maximum number of cache prime attempts reached")
		return
	end

	-- This doesn't always fully work, so first build a list of which items we still need to obtain
	Rarity.Caching:SetItemsToPrime(1)
	Rarity.Caching:SetPrimedItems(0)
	table.wipe(R.itemsToPrime)
	for k, v in pairs(R.itemsMasterList) do
		if R.itemInfoCache[v] == nil then
			R.itemsToPrime[Rarity.Caching:GetItemsToPrime()] = v
			Rarity.Caching:SetItemsToPrime(Rarity.Caching:GetItemsToPrime() + 1)
		end
	end
	Rarity.Caching:SetItemsToPrime(Rarity.Caching:GetItemsToPrime() - 1)
	if Rarity.Caching:GetItemsToPrime() <= 0 then return end

	-- Prime the items
	self:Debug("Loading ".. Rarity.Caching:GetItemsToPrime() .." item(s) from server...")
	initTimer = self:ScheduleRepeatingTimer(function()
		if Rarity.Caching:GetPrimedItems() <= 0 then Rarity.Caching:SetPrimedItems(1) end
		for i = 1, 10 do
			GetItemInfo(R.itemsToPrime[Rarity.Caching:GetPrimedItems()])
			Rarity.Caching:SetPrimedItems(Rarity.Caching:GetPrimedItems() + 1)
			if Rarity.Caching:GetPrimedItems() > Rarity.Caching:GetItemsToPrime() then break end
		end
		if Rarity.Caching:GetPrimedItems() >= Rarity.Caching:GetItemsToPrime() then
			self:CancelTimer(initTimer)
			-- First-time initialization finished
			if not Rarity.Caching:IsReady() then
				Rarity.Caching:SetReadyState(false)
				-- Trigger holiday reminders
				self:ScheduleTimer(function()
					Rarity:ShowTooltip(true)
				end, 5)
			end
			-- Check how many items were not processed, rescanning if necessary
			local got = 0
			local totalNeeded = 0
			for k, v in pairs(R.itemInfoCache) do got = got + 1 end
			for k, v in pairs(R.itemsMasterList) do totalNeeded = totalNeeded + 1 end
			if got < totalNeeded then
				self:Debug("Initialization failed to retrieve "..(totalNeeded - got).." item(s)")
				self:ScheduleTimer(function()
					self:PrimeItemCache()
				end, 5)
			else
				self:Debug("Finished loading ".. Rarity.Caching:GetItemsToPrime() .." item(s) from server")
			end
		end
		Rarity.GUI:UpdateText()
	end, 0.1)
end




-- TODO: Move elsewhere (in the final refactoring pass)
function R:VerifyItemDB()

	local DBH = Rarity.Utils.DatabaseMaintenanceHelper
	local ItemDB = self.db.profile.groups.items
	local PetDB = self.db.profile.groups.pets
	local MountDB = self.db.profile.groups.mounts
	local UserDB = self.db.profile.groups.user
	local DB = { ItemDB, PetDB, MountDB }

	self:Print(L["Verifying item database..."])

	local numErrors = 0

	for category, entry in pairs(DB) do
		for item, fields in pairs(entry) do

			if type(fields) == "table" then

				self:Debug(format(L["Verifying entry: %s ..."], item))
				local isEntryValid = DBH:VerifyEntry(fields)
				if not isEntryValid then  -- Skip pseudo-groups... Another artifact that has to be worked around, I guess
					self:Print(format(L["Verification failed for entry: %s"], item))
					numErrors = numErrors + 1
				end

			end
		end
	end

	if numErrors == 0 then self:Print(L["Verification complete! Everything appears to be in order..."])
	else self:Print(format(L["Verfication failed with %d errors!"], numErrors)) end

end

function R:CheckForceReset(report)
	-- Require a profile reset after a hardcoded revision
	if (self.db.profile.lastRevision or 0) < FORCE_PROFILE_RESET_BEFORE_REVISION and not isDebugVersion then
		self.db:RegisterDefaults(self.defaults)

		-- Save as many settings as we can
		local minimap = self.db.profile.minimap.hide

		-- Reset the profile
		self.db:ResetProfile(false, true)
		self.db.profile.lastRevision = R.MINOR_VERSION

		-- Migrate settings across
		self.db.profile.minimap.hide = minimap

		Rarity.Collections:ScanExistingItems("FORCED PROFILE RESET")
		if report or report == nil then
			self:Print(format(L["Welcome to Rarity r%d. Your settings have been reset."], R.MINOR_VERSION))
		end
	end
end


--[[
      UTILITIES ----------------------------------------------------------------------------------------------------------------
  ]]


-- Item cache
function R:GetItemInfo(id)
	if id == nil then return end
	if R.itemInfoCache[id] ~= nil then
		return unpack(R.itemInfoCache[id])
	end
	if itemCacheDebug and Rarity.Caching:IsReady() == false then R:Debug("ItemInfo not cached for "..id) end
	local info = { GetItemInfo_Blizzard(id) }
	if #info > 0 then R.itemInfoCache[id] = info end
	if R.itemInfoCache[id] == nil then return nil end
	return unpack(R.itemInfoCache[id])
end





	-- Miscellaneous
	function R:tcopy(to, from)
		for k, v in pairs(from) do
			if type(v) == "table" then
				to[k] = {}
				R:tcopy(to[k], v)
			else
				to[k] = v
			end
		end
	end

local function table_contains(haystack, needle)

	if type(haystack) ~= "table" then return end

	for _, value in pairs(haystack) do
		if value == needle then return true end
	end

end

-- Location/Distance/Zone
function R:GetDistanceToItem(item)
	local distance = 999999999
	if item and type(item) == "table" and item.coords and type(item.coords) == "table" then
		local playerWorldX, playerWorldY, instance = hbd:GetPlayerWorldPosition()
		for k, v in pairs(item.coords) do
			if v and type(v) == "table" and v.m and v.i ~= true then
				local map = v.m
				local x = (v.x or 50) / 100
				local y = (v.y or 50) / 100
				local itemWorldX, itemWorldY = hbd:GetWorldCoordinatesFromZone(x, y, map, v.f or 1)
				if itemWorldX ~= nil then -- Library returns nil for instances
					local thisDistance = hbd:GetWorldDistance(instance, itemWorldX, itemWorldY, playerWorldX, playerWorldY)
					--R:Print("map: "..map..", x: "..x..", y: "..y..", itemWorldX: "..itemWorldX..", itemWorldY: "..itemWorldY..", playerWorldX: "..playerWorldX..", playerWorldY: "..playerWorldY..", thisDistance: "..thisDistance)
					if thisDistance < distance then distance = thisDistance end
				end
			end
		end
	end
	if distance ~= 999999999 then return distance end
	return nil
end


-- Prepares a set of lookup tables to let us quickly determine if we're interested in various things.
-- Many of the events we handle fire quite frequently, so speed is of the essence.
-- Any item that is not enabled for tracking won't show up in these lists.
function R:UpdateInterestingThings()
 self:Debug("Updating interesting things tables")

	-- Store an internal table listing every MapID
	if self.db.profile.mapIds == nil then self.db.profile.mapIds = {} else table.wipe(self.db.profile.mapIds) end
	for map_id = 1, 5000 do -- 5000 seems arbitrarily high; right now (8.0.1) there are barely 100 uiMapIDs... but it shouldn't matter if the misses are skipped
		if GetMapNameByID(map_id) ~= nil then self.db.profile.mapIds[map_id] = GetMapNameByID(map_id) end
	end

 table.wipe(npcs)
 table.wipe(Rarity.bosses)
 table.wipe(Rarity.zones)
 table.wipe(Rarity.items)
 table.wipe(Rarity.guids)
 table.wipe(Rarity.npcs_to_items)
 table.wipe(Rarity.items_to_items)
 table.wipe(used)
 table.wipe(fishzones)
 table.wipe(Rarity.architems)
	table.wipe(Rarity.stats_to_scan)
	table.wipe(Rarity.items_with_stats)
	table.wipe(Rarity.collection_items)

 for k, v in pairs(self.db.profile.groups) do
  if type(v) == "table" then
   for kk, vv in pairs(v) do
    if type(vv) == "table" then
					if vv.enabled ~= false and vv.statisticId and type(vv.statisticId) == "table" then
						local numStats = 0
						for kkk, vvv in pairs(vv.statisticId) do
							Rarity.stats_to_scan[vvv] = vv
							numStats = numStats + 1
						end
						if numStats > 0 then Rarity.items_with_stats[kk] = vv end
					end
     if vv.method == NPC and vv.npcs ~= nil and type(vv.npcs) == "table" then
      for kkk, vvv in pairs(vv.npcs) do
       npcs[vvv] = vv
       if Rarity.npcs_to_items[vvv] == nil then Rarity.npcs_to_items[vvv] = {} end
       table.insert(Rarity.npcs_to_items[vvv], vv)
      end
     elseif vv.method == BOSS and vv.npcs ~= nil and type(vv.npcs) == "table" then
      for kkk, vvv in pairs(vv.npcs) do
       Rarity.bosses[vvv] = vv
       if Rarity.npcs_to_items[vvv] == nil then Rarity.npcs_to_items[vvv] = {} end
       table.insert(Rarity.npcs_to_items[vvv], vv)
      end
     elseif vv.method == ZONE and vv.zones ~= nil and type(vv.zones) == "table" then
      for kkk, vvv in pairs(vv.zones) do
       if lbz[vvv] then Rarity.zones[lbz[vvv]] = vv end
       if lbsz[vvv] then Rarity.zones[lbsz[vvv]] = vv end
       Rarity.zones[vvv] = vv
      end
     elseif vv.method == USE and vv.items ~= nil and type(vv.items) == "table" then
      for kkk, vvv in pairs(vv.items) do
       used[vvv] = vv
       if Rarity.items_to_items[vvv] == nil then Rarity.items_to_items[vvv] = {} end
       table.insert(Rarity.items_to_items[vvv], vv)
      end
     elseif vv.method == FISHING and vv.zones ~= nil and type(vv.zones) == "table" then
      for kkk, vvv in pairs(vv.zones) do
       if lbz[vvv] then fishzones[lbz[vvv]] = vv end
       if lbsz[vvv] then fishzones[lbsz[vvv]] = vv end
       fishzones[vvv] = vv
      end
     elseif vv.method == ARCH and vv.itemId ~= nil then
      local itemName = GetItemInfo(vv.itemId)
      if itemName then Rarity.architems[itemName] = vv end
     end
     if vv.itemId ~= nil and vv.method ~= COLLECTION then Rarity.items[vv.itemId] = vv end
     if vv.itemId2 ~= nil and vv.method ~= COLLECTION then Rarity.items[vv.itemId2] = vv end
					if vv.method == COLLECTION and vv.collectedItemId ~= nil then
						if type(vv.collectedItemId) == "table" then
							for kkk, vvv in pairs(vv.collectedItemId) do
								Rarity.items[vvv] = vv
							end
						else
							Rarity.items[vv.collectedItemId] = vv
						end
						table.insert(Rarity.collection_items, vv)
					end

				if vv.tooltipNpcs and type(vv.tooltipNpcs) == "table" then -- Item has tooltipNpcs -> Check if they should be displayed

						local showTooltipNpcs = true -- If no filters exist, always show the tooltip for relevant NPCs

						if vv.showTooltipCondition and type(vv.showTooltipCondition) == "table" -- This item has filter conditions to help decide when the tooltipNpcs should be added
						and vv.showTooltipCondition.filter and type(vv.showTooltipCondition.filter) == "function" and vv.showTooltipCondition.value -- Filter has the correct format and can be applied
						then -- Check filter conditions to see if tooltipNpcs should be added

							showTooltipNpcs = false -- Hide the additional tooltip info by default (filters will overwrite this if they can find a match, below)

							-- Each filter requires separate handling here
							if vv.showTooltipCondition.filter == IsSpellKnown then -- Filter if a (relevant) spell with the given name is not known

								for spellID, spellName in pairs(Rarity.relevantSpells) do -- Try to find any match for the given spell (a single one will do)

									if spellName == vv.showTooltipCondition.value then -- The value is a relevant spell -> Check if filter condition is true

										--	Player hasn't learned the required spell -> Stop trying to find other matches and turn off the filter
										showTooltipNpcs = IsSpellKnown(spellID)
										if showTooltipNpcs then break end -- No point in checking the other spells; A single match is enough to decide to not filter them
									end
								end
							end

						-- There aren't any other Filter types at the moment... but there could be!
						end

						-- Check for post-processing via tooltip modifiers (additional logic contained in a database entry that requires special handling)
						-- This has to run last, as it is intended to update things on the fly where a filter isn't sufficient
						local tooltipModifier = vv.tooltipModifier

						if tooltipModifier ~= nil and type(tooltipModifier) == "table" and tooltipModifier.condition ~= nil and tooltipModifier.value ~= nil then -- Apply modifications where necessary

							local shouldApplyModification = type(tooltipModifier.condition) == "function" and tooltipModifier.condition()
							if shouldApplyModification and tooltipModifier.action and type(tooltipModifier.action) == "function" then -- Apply this action to the entry
								vv = tooltipModifier.action(vv, tooltipModifier.value) -- A tooltip modifier always returns the (modified) database entry to keep processing separate
							end

						end

						-- Add entries to the list of relevant NPCs for this item
						if showTooltipNpcs then
							for kkk, vvv in pairs(vv.tooltipNpcs) do
								if Rarity.npcs_to_items[vvv] == nil then Rarity.npcs_to_items[vvv] = {} end
								table.insert(Rarity.npcs_to_items[vvv], vv)
							end
						end
					end
				end
			end
		end
	end
end

function R:GetNPCIDFromGUID(guid)
	if guid then
		local unit_type, _, _, _, _, mob_id = strsplit('-', guid)
		if unit_type == "Pet" or unit_type == "Player" then return 0 end
		return (guid and mob_id and tonumber(mob_id)) or 0
	end
	return 0
end


function R:IsAttemptAllowed(item)
	-- No item supplied; assume it's okay
	if item == nil then return true end

	-- Check disabled classes
	if not Rarity.Caching:GetPlayerClass() then Rarity.Caching:SetPlayerClass(select(2, UnitClass("player"))) end
	if item.disableForClass and type(item.disableForClass == "table") and item.disableForClass[Rarity.Caching:GetPlayerClass()] == true then return false end

	-- No valid instance difficulty configuration; allow (this needs to be the second-to-last check)
	if item.instanceDifficulties == nil or type(item.instanceDifficulties) ~= "table" or next(item.instanceDifficulties) == nil then return true end

	-- Check instance difficulty (this needs to be the last check)
	local foundTrue = false
	for k, v in pairs(item.instanceDifficulties) do
		if v == true then foundTrue = true end
	end
	if foundTrue == false then return true end
	local name, type, difficulty, difficultyName, maxPlayers, playerDifficulty, isDynamicInstance, mapID, instanceGroupSize = GetInstanceInfo()
	if item.instanceDifficulties[difficulty] and item.instanceDifficulties[difficulty] == true then return true end
	return false
end









--[[
      OBTAIN DETECTION ---------------------------------------------------------------------------------------------------------
      -- Some easy, some fairly arcane methods to detect when we've obtained something we're looking for
  ]]



function R:OnEvent(event, ...)

	-------------------------------------------------------------------------------------
	-- You opened a loot window on a corpse or fishing node
	-------------------------------------------------------------------------------------
	if event == "LOOT_READY" then

		self:Debug("LOOT_READY with target: "..(UnitGUID("target") or "NO TARGET"))

		-- In 8.0.1, two LOOT_READY events fire when the loot window opens. We'll just ignore subsequent events for a short time to prevent double counting
		if Rarity.Session:IsLocked() then -- One attempt is already being counted and we don't want another one for this loot event -> Ignore this call
			Rarity:Debug("Session is locked; ignoring this LOOT_READY event")
			return
		else Rarity.Session:Lock(1) end

		local zone = GetRealZoneText()
		local subzone = GetSubZoneText()
		local zone_t = LibStub("LibBabble-Zone-3.0"):GetReverseLookupTable()[zone]
		local subzone_t = LibStub("LibBabble-SubZone-3.0"):GetReverseLookupTable()[subzone]

		if fishing and opening then
			self:Debug("Opened something")
		end

		if fishing and opening and lastNode then
			self:Debug("Opened a node: "..lastNode)
		end

  -- Handle opening Crane Nest
  if fishing and opening and lastNode and (lastNode == L["Crane Nest"]) then
	Rarity:Debug("Detected Opening on " .. L["Crane Nest"] .. " (method = SPECIAL)")
   local v = self.db.profile.groups.pets["Azure Crane Chick"]
   if v and type(v) == "table" and v.enabled ~= false then
    if v.attempts == nil then v.attempts = 1 else v.attempts = v.attempts + 1 end
    self:OutputAttempts(v)
   end
  end

  -- Handle opening Timeless Chest
  if fishing and opening and lastNode and (lastNode == L["Timeless Chest"]) then
 	Rarity:Debug("Detected Opening on " .. L["Timeless Chest"] .. " (method = SPECIAL)")
   local v = self.db.profile.groups.pets["Bonkers"]
   if v and type(v) == "table" and v.enabled ~= false then
    if v.attempts == nil then v.attempts = 1 else v.attempts = v.attempts + 1 end
    self:OutputAttempts(v)
   end
  end

  -- Handle opening Snow Mound
  if fishing and opening and lastNode and (lastNode == L["Snow Mound"]) and GetBestMapForUnit("player") == CONSTANTS.UIMAPIDS.FROSTFIRE_RIDGE then -- Make sure we're in Frostfire Ridge (there are Snow Mounds in other zones, particularly Ulduar in the Hodir room)
  	Rarity:Debug("Detected Opening on " .. L["Snow Mound"] .. " (method = SPECIAL)")
   local v = self.db.profile.groups.pets["Grumpling"]
   if v and type(v) == "table" and v.enabled ~= false then
    if v.attempts == nil then v.attempts = 1 else v.attempts = v.attempts + 1 end
    self:OutputAttempts(v)
   end
  end

		-- Handle opening Curious Wyrmtongue Cache
		if fishing and opening and lastNode and (lastNode == L["Curious Wyrmtongue Cache"]) then
  	local names = {"Scraps", "Pilfered Sweeper"}
			Rarity:Debug("Detected Opening on " .. L["Curious Wyrmtongue Cache"] .. " (method = SPECIAL)")
			for _, name in pairs(names) do
				local v = self.db.profile.groups.items[name] or self.db.profile.groups.pets[name]
				if v and type(v) == "table" and v.enabled ~= false then
					if v.attempts == nil then v.attempts = 1 else v.attempts = v.attempts + 1 end
					self:OutputAttempts(v)
				end
			end
		end

		-- Handle opening Arcane Chest
		if fishing and opening and lastNode and (lastNode == L["Arcane Chest"]) then
			local names = {"Eternal Palace Dining Set", "Ocean Simulator" }
				Rarity:Debug("Detected Opening on " .. L["Arcane Chest"] .. " (method = SPECIAL)")
				for _, name in pairs(names) do
					local v = self.db.profile.groups.items[name] or self.db.profile.groups.pets[name]
					if v and type(v) == "table" and v.enabled ~= false then
						if v.attempts == nil then v.attempts = 1 else v.attempts = v.attempts + 1 end
						self:OutputAttempts(v)
					end
				end
			end

		-- Handle opening Glimmering Chest
		if fishing and opening and lastNode and (lastNode == L["Glimmering Chest"]) then
			local names = {"Eternal Palace Dining Set", "Sandclaw Nestseeker"}
				Rarity:Debug("Detected Opening on " .. L["Glimmering Chest"] .. " (method = SPECIAL)")
				for _, name in pairs(names) do
					local v = self.db.profile.groups.items[name] or self.db.profile.groups.pets[name]
					if v and type(v) == "table" and v.enabled ~= false then
						if v.attempts == nil then v.attempts = 1 else v.attempts = v.attempts + 1 end
						self:OutputAttempts(v)
					end
				end
			end

		-- Handle opening Pile of Coins
		if fishing and opening and lastNode and (lastNode == L["Pile of Coins"]) then
			local names = { "Armored Vaultbot" }
				Rarity:Debug("Detected Opening on " .. L["Pile of Coins"] .. " (method = SPECIAL)")
				for _, name in pairs(names) do
					local v = self.db.profile.groups.items[name] or self.db.profile.groups.pets[name]
					if v and type(v) == "table" and v.enabled ~= false then
						if v.attempts == nil then v.attempts = 1 else v.attempts = v.attempts + 1 end
						self:OutputAttempts(v)
					end
				end
			end

		-- Handle opening Glimmering Treasure Chest
		if fishing and opening and lastNode and (lastNode == L["Glimmering Treasure Chest"]) and select(8, GetInstanceInfo()) == 1626 then -- Player is in Withered Army scenario and looted the reward chest
			local bigChest = false
			for _, slot in pairs(GetLootInfo()) do
				if slot.item == L["Ancient Mana"] and slot.quantity == 100 then
					bigChest = true
				end
			end

			if bigChest == true then
				self:Debug("Detected " .. lastNode .. ": Adding toy drop attempts")
				local names = {"Arcano-Shower", "Displacer Meditation Stone", "Kaldorei Light Globe", "Unstable Powder Box", "Wisp in a Bottle", "Ley Spider Eggs"}
				for _, name in pairs(names) do
					local v = self.db.profile.groups.items[name]
					if v and type(v) == "table" and v.enabled ~= false then
						if v.attempts == nil then v.attempts = 1 else v.attempts = v.attempts + 1 end
						self:OutputAttempts(v)
					end
				end

				v = self.db.profile.groups.mounts["Torn Invitation"]
				if v and type(v) == "table" and v.enabled ~= false then
					if v.attempts == nil then v.attempts = 1 else v.attempts = v.attempts + 1 end
					self:OutputAttempts(v)
				end
			end
		end

  -- HANDLE FISHING
  if fishing and opening == false then
   if isPool then self:Debug("Successfully fished from a pool")
   else self:Debug("Successfully fished") end
   if fishzones[tostring(GetBestMapForUnit("player"))] or fishzones[zone] or fishzones[subzone] or fishzones[zone_t] or fishzones[subzone_t] then
    -- We're interested in fishing in this zone; let's find the item(s) involved
	Rarity:Debug("We're interested in fishing in this zone; let's find the item(s) involved")
    for k, v in pairs(self.db.profile.groups) do
     if type(v) == "table" then
      for kk, vv in pairs(v) do
       if type(vv) == "table" then
        if vv.enabled ~= false then
         local found = false
         if vv.method == FISHING and vv.zones ~= nil and type(vv.zones) == "table" then
          for kkk, vvv in pairs(vv.zones) do
           if vvv == tostring(GetBestMapForUnit("player")) or vvv == zone or vvv == lbz[zone] or vvv == subzone or vvv == lbsz[subzone] or vvv == zone_t or vvv == subzone_t or vvv == lbz[zone_t] or vvv == subzone or vvv == lbsz[subzone_t] then
            if (vv.requiresPool and isPool) or not vv.requiresPool then
			Rarity:Debug("Found interesting item for this zone: " .. tostring(vv.name))
             found = true
            end
           end
          end
         end

		if (vv.excludedMaps and type(vv.excludedMaps) == "table" and vv.excludedMaps[GetBestMapForUnit("player")]) then
			Rarity:Debug("The current map is excluded for item: " .. tostring(vv.name) .. ". Attempts will not be counted")
			found = false
		end

         if found then
          if self:IsAttemptAllowed(vv) then
           if vv.attempts == nil then vv.attempts = 1 else vv.attempts = vv.attempts + 1 end
           self:OutputAttempts(vv)
          end
         end
        end
       end
      end
     end
    end
   end
  end
  if fishingTimer then self:CancelTimer(fishingTimer, true) end
  fishingTimer = nil
  fishing = false
  isPool = false

  -- Handle mining Elementium
  if Rarity.relevantSpells[Rarity.previousSpell] == "Mining" and (lastNode == L["Elementium Vein"] or lastNode == L["Rich Elementium Vein"]) then
		Rarity:Debug("Detected Mining on " .. lastNode .. " (method = SPECIAL)")
   local v = self.db.profile.groups.pets["Elementium Geode"]
   if v and type(v) == "table" and v.enabled ~= false then
    if v.attempts == nil then v.attempts = 1 else v.attempts = v.attempts + 1 end
    self:OutputAttempts(v)
   end
  end

  -- Handle skinning on Argus (Fossorial Bile Larva)
	if (Rarity.relevantSpells[Rarity.previousSpell] == "Skinning" or Rarity.relevantSpells[Rarity.previousSpell] == "Mother's Skinning Knife") -- Skinned something
	and (GetBestMapForUnit("player") == CONSTANTS.UIMAPIDS.KROKUUN or GetBestMapForUnit("player") == CONSTANTS.UIMAPIDS.MACAREE or GetBestMapForUnit("player") == CONSTANTS.UIMAPIDS.ANTORAN_WASTES) then -- Player is on Argus -> Can obtain the pet from skinning creatures
		Rarity:Debug("Detected skinning on Argus - Can obtain " .. L["Fossorial Bile Larva"] .. " (method = SPECIAL)")
		local v = self.db.profile.groups.pets["Fossorial Bile Larva"]
		if v and type(v) == "table" and v.enabled ~= false then -- Add an attempt
			v.attempts = v.attempts ~= nil and v.attempts + 1 or 1 -- Defaults to 1 if this is the first attempt
			self:OutputAttempts(v)
		end
	end

    -- Handle herb gathering on Argus (Fel Lasher)
	if Rarity.relevantSpells[Rarity.previousSpell] == "Herb Gathering" -- Gathered a herbalism node
	and (GetBestMapForUnit("player") == CONSTANTS.UIMAPIDS.KROKUUN or GetBestMapForUnit("player") == CONSTANTS.UIMAPIDS.MACAREE or GetBestMapForUnit("player") == CONSTANTS.UIMAPIDS.ANTORAN_WASTES) then -- Player is on Argus -> Can obtain the pet from gathering herbalism nodes
		Rarity:Debug("Detected herb gathering on Argus - Can obtain " .. L["Fel Lasher"] .. " (method = SPECIAL)")
		local v = self.db.profile.groups.pets["Fel Lasher"]
		if v and type(v) == "table" and v.enabled ~= false then -- Add an attempt
			v.attempts = v.attempts ~= nil and v.attempts + 1 or 1 -- Defaults to 1 if this is the first attempt
			self:OutputAttempts(v)
		end
	end

  -- HANDLE NORMAL NPC LOOTING
		local numItems = GetNumLootItems()
  local slotID

  -- Legacy support for pre-5.0 single-target looting
		local guid = UnitGUID("target")
		local name = UnitName("target")
		if not name or not guid then return end -- No target when looting
		if not UnitCanAttack("player", "target") then return end -- You targeted something you can't attack
		if UnitIsPlayer("target") then return end -- You targetted a player

		-- You're looting something that's alive -- this is only done for pickpocketing
		local requiresPickpocket = false
		if not UnitIsDead("target") then requiresPickpocket = true end

		-- Disallow "minus" NPCs; nothing good drops from them
		if UnitClassification(guid) == "minus" then return end -- (This doesn't actually work currently; UnitClassification needs a unit, not a GUID)

  local numChecked = 0
		self:Debug(numItems.." slot(s) to loot")
		for slotID = 1, numItems, 1 do -- Loop through all loot slots (for AoE looting)
   local guidlist
   if GetLootSourceInfo then
    guidlist = { GetLootSourceInfo(slotID) }
   else
    guidlist = { guid }
   end
   local guidIndex
   for k, v in pairs(guidlist) do -- Loop through all NPC Rarity.guids being looted (will be 1 for single-target looting pre-5.0)
    guid = v
    if guid and type(guid) == "string" then
     self:Debug("Checking NPC guid ("..(numChecked + 1).."): "..guid)
     self:CheckNpcInterest(guid, zone, subzone, zone_t, subzone_t, Rarity.currentSpell, requiresPickpocket) -- Decide if we should increment an attempt count for this NPC
     numChecked = numChecked + 1
    else
     --self:Debug("Didn't check guid: "..guid or "nil")
    end -- Loop through all NPC GUIDs being looted (will be 1 for single-target looting pre-5.0)
   end -- Haven't seen this corpse yet
  end -- Loop through all loot slots (for AoE looting)

  -- If we failed to scan anything, scan the current target
  if numChecked <= 0 then self:CheckNpcInterest(UnitGUID("target"), zone, subzone, zone_t, subzone_t, Rarity.currentSpell) end

  -- Scan the loot to see if we found something we're looking for
		local numItems = GetNumLootItems()
  local slotID
		for slotID = 1, numItems, 1 do
			local _, _, qty = GetLootSlotInfo(slotID)
			if (qty or 0) > 0 then -- Coins have quantity of 0, so skip those
				local itemLink = GetLootSlotLink(slotID)
    if itemLink then
				 local _, itemId = strsplit(":", itemLink)
     itemId = tonumber(itemId)
     if Rarity.items[itemId] ~= nil and Rarity.items[itemId].method ~= COLLECTION then
      self:OnItemFound(itemId, Rarity.items[itemId])
     end
    end
			end
		end


 -- Detect bank, guild bank, auction house, tradeskill, trade, and mail. This turns off item use detection.
 elseif event == "BANKFRAME_OPENED" then
  bankOpen = true
 elseif event == "GUILDBANKFRAME_OPENED" then
  guildBankOpen = true
 elseif event == "AUCTION_HOUSE_SHOW" then
  auctionOpen = true
 elseif event == "TRADE_SHOW" then
  tradeOpen = true
 elseif event == "TRADE_SKILL_SHOW" then
  tradeSkillOpen = true
 elseif event == "MAIL_SHOW" then
  mailOpen = true

 elseif event == "BANKFRAME_CLOSED" then
  bankOpen = false
 elseif event == "GUILDBANKFRAME_CLOSED" then
  guildBankOpen = false
 elseif event == "AUCTION_HOUSE_CLOSED" then
  auctionOpen = false
 elseif event == "TRADE_CLOSED" then
  tradeOpen = false
 elseif event == "TRADE_SKILL_CLOSE" then
  tradeSkillOpen = false
 elseif event == "MAIL_CLOSED" then
  mailOpen = false


	-- Instance lock info updated
	elseif event == "UPDATE_INSTANCE_INFO" then
		self:ScanInstanceLocks(event)
	elseif event == "LFG_UPDATE_RANDOM_INFO" then
		self:ScanInstanceLocks(event)

	-- Calendar updated
	elseif event == "CALENDAR_UPDATE_EVENT_LIST" then
		self:ScanCalendar(event)

	-- Toy box updated
	elseif event == "TOYS_UPDATED" then
		Rarity.Collections:ScanExistingItems(event)

	-- Pets updated
	elseif event == "COMPANION_UPDATE" then
		Rarity.Collections:ScanExistingItems(event)

 -- Logging out; end any open session
 elseif event == "PLAYER_LOGOUT" then
  if Rarity.Session:IsActive() then Rarity.Session:End() end


 end
end


function R:CheckNpcInterest(guid, zone, subzone, zone_t, subzone_t, curSpell, requiresPickpocket)
 if guid == nil then return end
 if type(guid) ~= "string" then return end
 if Rarity.guids[guid] ~= nil then return end -- Already seen this NPC

 local npcid = self:GetNPCIDFromGUID(guid)
 if npcs[npcid] == nil then -- Not an NPC we need, abort
		self:Debug("NPC ID not on the list of needed NPCs: "..(npcid or "nil"))

  if Rarity.zones[tostring(GetBestMapForUnit("player"))] == nil and Rarity.zones[zone] == nil and Rarity.zones[lbz[zone] or "."] == nil and Rarity.zones[lbsz[subzone] or "."] == nil and Rarity.zones[zone_t] == nil and Rarity.zones[subzone_t] == nil and Rarity.zones[lbz[zone_t] or "."] == nil and Rarity.zones[lbsz[subzone_t] or "."] == nil then -- Not a zone we need, abort
		self:Debug("Map ID not on the list of needed zones: " .. tostring(GetBestMapForUnit("player")))
		return
	end
 else
		self:Debug("NPC ID is one we need: "..(npcid or "nil"))
	end

 -- If the loot is the result of certain spell casts (mining, herbing, opening, pick lock, archaeology, disenchanting, etc), stop here -> This is to avoid multiple attempts, since those methods are handled separately!
 if Rarity.relevantSpells[curSpell] then
		self:Debug("Aborting because we were casting a disallowed spell: "..curSpell)
		return
	end

	-- If the loot is not from an NPC (could be from yourself or a world object), we don't want to process this
 local unitType, _, _, _, _, mob_id = strsplit('-', guid)
 if unitType ~= "Creature" and unitType ~= "Vehicle" then
		self:Debug("This loot isn't from an NPC; disregarding. Loot source identified as unit type: "..(unitType or "nil"))
		return
	end

	-- We're interested in this loot, process further
 Rarity.guids[guid] = true

 -- Increment attempt counter(s). One NPC might drop multiple things we want, so scan for them all.
 if Rarity.npcs_to_items[npcid] and type(Rarity.npcs_to_items[npcid]) == "table" then
  for k, v in pairs(Rarity.npcs_to_items[npcid]) do
   if v.enabled ~= false and (v.method == NPC or v.method == ZONE) then
    if self:IsAttemptAllowed(v) then
     -- Don't increment attempts if this NPC also has a statistic defined. This would result in two attempts counting instead of one.
     if not v.statisticId or type(v.statisticId) ~= "table" or #v.statisticId <= 0 then
						-- Don't increment attempts for unique items if you already have the item in your bags
						if not (v.unique == true and (bagitems[v.itemId] or 0) > 0) then
							-- Don't increment attempts for non-pickpocketed items if this item isn't being pickpocketed
							if (requiresPickpocket and v.pickpocket) or (requiresPickpocket == false and not v.pickpocket) then
								if v.attempts == nil then v.attempts = 1 else v.attempts = v.attempts + 1 end
								self:OutputAttempts(v)
							end
						end
     end
    end
   end
  end
 end

 -- Check for zone-wide items and increment them if needed
 for k, v in pairs(self.db.profile.groups) do
  if type(v) == "table" then
   for kk, vv in pairs(v) do
    if type(vv) == "table" then
     if vv.enabled ~= false then
      local found = false
      if vv.method == ZONE and vv.zones ~= nil and type(vv.zones) == "table" then
       for kkk, vvv in pairs(vv.zones) do
								if tonumber(vvv) ~= nil and tonumber(vvv) == GetBestMapForUnit("player") then found = true end
        if vvv == zone or vvv == lbz[zone] or vvv == subzone or vvv == lbsz[subzone] or vvv == zone_t or vvv == subzone_t or vvv == lbz[zone_t] or vvv == subzone or vvv == lbsz[subzone_t] then found = true end
       end
      end
      if found then
       if self:IsAttemptAllowed(vv) then
        if vv.attempts == nil then vv.attempts = 1 else vv.attempts = vv.attempts + 1 end
        self:OutputAttempts(vv)
       end
      end
     end
    end
   end
  end
 end
end


-------------------------------------------------------------------------------------
-- Something in your bags changed.
--
-- This is used for a couple things. First, for boss drops that require a group, you may not have obtained the item even if it dropped from the boss.
-- Therefore, we only say you obtained it when it appears in your inventory. Secondly, this is useful as a second line of defense in case
-- you somehow obtain an item without us noticing it. This event fires a lot, so we need to be fast.
--
-- We also store how many of every item you have on you at the moment. If we notice an item decreasing in quantity, and it's something we care
-- about, you just used an item or opened a container.
--
-- This event is bucketed because it tends to fire tons of times in a row rapidly, leading to innaccurate results.
-------------------------------------------------------------------------------------
function R:OnBagUpdate()
 self:Debug("BAG_UPDATE")

 -- Save a copy of your bags before this event
 table.wipe(tempbagitems)
 for k, v in pairs(bagitems) do
  tempbagitems[k] = v
 end

 -- Get a list of the items you have now, alerting if we find anything we're looking for
 self:ScanBags()

 if not bankOpen and not guildBankOpen and not auctionOpen and not tradeOpen and not tradeSkillOpen and not mailOpen then

		-- Check for a decrease in quantity of any items we're watching for
  for k, v in pairs(tempbagitems) do
   if (bagitems[k] or 0) < (tempbagitems[k] or 0) then -- An inventory item went down in count or disappeared
    if used[k] then -- It's an item we care about
					-- Scan through the whole item database now to find all items that could want this
					for _k, _v in pairs(self.db.profile.groups) do
						if type(_v) == "table" then
							for kk, vv in pairs(_v) do
								if type(vv) == "table" then
									if vv.enabled ~= false then
										if vv.method == USE and vv.items ~= nil and type(vv.items) == "table" then
											for kkk, vvv in pairs(vv.items) do
												if vvv == k then
													local i = vv
													if i.attempts == nil then i.attempts = 1 else i.attempts = i.attempts + 1 end
													self:OutputAttempts(i)
												end
											end
										end
									end
								end
							end
						end
					end
     -- End scan through all items
    end
   end
  end


		-- Check for an increase in quantity of any items we're watching for
  for k, v in pairs(bagitems) do

			-- Handle collection items
			if Rarity.items[k] then
				if Rarity.items[k].method == COLLECTION then
					local bagCount = (bagitems[k] or 0)

					-- Our items hashtable only saves one item for this collected item, so we have to scan to find them all now.
					-- Earlier, we pre-built a list of just the items that are COLLECTION items to save some time here.
					for kk, vv in pairs(Rarity.collection_items) do

						-- This item is a collection of several items; add them all up and check for attempts
						if type(vv.collectedItemId) == "table" then
							if vv.enabled ~= false then
								local total = 0
								local originalCount = (vv.attempts or 0)
								local goal = (vv.chance or 100)
								for kkk, vvv in pairs(vv.collectedItemId) do
									if (bagitems[vvv] or 0) > 0 then total = total + bagitems[vvv] end
								end
								if total > originalCount then
									vv.attempts = total
									if originalCount < goal and total >= goal then
										self:OnItemFound(vv.itemId, vv)
									elseif total > originalCount then
										self:OutputAttempts(vv)
									end
								end
							end

						-- This item is a collection of a single type of item
						else
							if vv.enabled
							and	(
								vv.collectedItemId == Rarity.items[k].collectedItemId
								or table_contains(Rarity.items[k].collectedItemId, vv.collectedItemId)
							)
							then
								local originalCount = (vv.attempts or 0)
								local goal = (vv.chance or 100)
								vv.lastAttempts = 0
								if vv.attempts ~= bagCount then
									vv.attempts = bagCount
								end
								if originalCount < bagCount and originalCount < goal and bagCount >= goal then
									self:OnItemFound(vv.itemId, vv)
								elseif originalCount < bagCount then
									self:OutputAttempts(vv)
								end
							end
						end

					end

				end
			end

			-- Other items
			if (bagitems[k] or 0) > (tempbagitems[k] or 0) then -- An inventory item went up in count
				if Rarity.items[k] and Rarity.items[k].enabled ~= false and Rarity.items[k].method ~= COLLECTION then
					self:OnItemFound(k, Rarity.items[k])
				end
			end

  end

 end

end


-------------------------------------------------------------------------------------
-- Scan your bags to see if you are in possession of any of the items we want. This is used for BOSS and FISHING methods,
-- and also works as a second line of defense in case other methods fail to notice the item.
-------------------------------------------------------------------------------------
function R:ScanBags()
 local i, ii
	table.wipe(bagitems)
	for i = 0, NUM_BAG_SLOTS do
		local numSlots = GetContainerNumSlots(i)
		if numSlots then
			for ii = 1, numSlots do
				local id = GetContainerItemID(i, ii)
				if id then
					local qty = select(2, GetContainerItemInfo(i, ii))
     if qty and qty > 0 then
						if not bagitems[id] then bagitems[id] = 0 end
						bagitems[id] = bagitems[id] + qty
     end
				end
			end
		end
	end
end


-------------------------------------------------------------------------------------
-- Gathering detection (fishing, mining, etc.)
-------------------------------------------------------------------------------------

function R:OnLootFrameClosed(event)
	Rarity.previousSpell, Rarity.currentSpell = nil, nil
	Rarity.foundTarget = false
 self:ScheduleTimer(function()
		R:Debug("Setting lastNode to nil")
		lastNode = nil
	end, 1)
end

function R:OnCursorUpdate(event)
	if Rarity.foundTarget then return end
	if (MinimapCluster:IsMouseOver()) then return end
	local t = tooltipLeftText1:GetText()
 if self.miningnodes[t] or self.fishnodes[t] or self.opennodes[t] then lastNode = t end
	if Rarity.relevantSpells[Rarity.previousSpell] then
		self:GetWorldTarget()
	end
end

function R:OnSpellcastStopped(event, unit)
	if unit ~= "player" then return end
	if Rarity.relevantSpells[Rarity.previousSpell] then
		self:GetWorldTarget()
	end
	Rarity.previousSpell, Rarity.currentSpell = Rarity.currentSpell, Rarity.currentSpell
end

function R:OnSpellcastFailed(event, unit)
	if unit ~= "player" then return end
	Rarity.previousSpell, Rarity.currentSpell = nil, nil
end

local function cancelFish()
 R:Debug("You didn't loot anything from that fishing. Giving up.")
 fishingTimer = nil
 fishing = false
 isPool = false
	opening = false
end

function R:OnSpellcastSent(event, unit, target, castGUID, spellID)
	if unit ~= "player" then return end
	Rarity.foundTarget = false
	ga ="No"

	Rarity:Debug("Detected UNIT_SPELLCAST_SENT for unit = player, spellID = " .. tostring(spellID) .. ", castGUID = " .. tostring(castGUID) .. ", target = " .. tostring(target)) -- TODO: Remove?

	if Rarity.relevantSpells[spellID] then -- An entry exists for this spell in the LUT -> It's one that needs to be tracked
		Rarity:Debug("Detected relevant spell: " .. tostring(spellID) .. " ~ " .. tostring(Rarity.relevantSpells[spellID]))
		Rarity.currentSpell = spellID
		Rarity.previousSpell = spellID
  if Rarity.relevantSpells[spellID] == "Fishing" or Rarity.relevantSpells[spellID] == "Opening" then
   self:Debug("Fishing or opening something")
			if Rarity.relevantSpells[spellID] == "Opening" then
				self:Debug("Opening detected")
				opening = true
			else
				opening = false
			end
   fishing = true
   if fishingTimer then self:CancelTimer(fishingTimer, true) end
   fishingTimer = self:ScheduleTimer(cancelFish, FISHING_DELAY)
		 self:GetWorldTarget()
  end
	else
		Rarity.previousSpell, Rarity.currentSpell = nil, nil
	end
end

function R:GetWorldTarget()
	if Rarity.foundTarget or not Rarity.relevantSpells[Rarity.currentSpell] then return end
	if (MinimapCluster:IsMouseOver()) then return end
	local t = tooltipLeftText1:GetText()
	if t and Rarity.previousSpell and t ~= Rarity.previousSpell and R.fishnodes[t] then
  self:Debug("------YOU HAVE STARTED FISHING A NODE ------")
		fishing = true
  isPool = true
  if fishingTimer then self:CancelTimer(fishingTimer, true) end
  fishingTimer = self:ScheduleTimer(cancelFish, FISHING_DELAY)
		Rarity.foundTarget = true
	end
end




--[[
      CORE FUNCTIONALITY -------------------------------------------------------------------------------------------------------
  ]]


local function RarityAchievementAlertFrame_SetUp(frame, itemId, attempts)
 local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture, itemSellPrice = GetItemInfo(itemId)
 if itemName == nil then return end
 if itemTexture == nil then itemTexture = [[Interface\Icons\INV_Misc_PheonixPet_01]] end

 -- The following code is adapted from Blizzard's AchievementAlertFrame_SetUp function found in FrameXML\AlertFrameSystems.lua [introduced in 7.0]

	local displayName = frame.Name;
	local shieldPoints = frame.Shield.Points;
	local shieldIcon = frame.Shield.Icon;
	local unlocked = frame.Unlocked;
	local oldCheevo = frame.OldAchievement;

	displayName:SetText(itemName);

	AchievementShield_SetPoints(0, shieldPoints, GameFontNormal, GameFontNormalSmall);

	if (frame.guildDisplay or frame.oldCheevo) then
		frame.oldCheevo = nil
		shieldPoints:Show();
		shieldIcon:Show();
		oldCheevo:Hide();
		frame.guildDisplay = nil;
		frame:SetHeight(88);
		local background = frame.Background;
		background:SetTexture("Interface\\AchievementFrame\\UI-Achievement-Alert-Background");
		background:SetTexCoord(0, 0.605, 0, 0.703);
		background:SetPoint("TOPLEFT", 0, 0);
		background:SetPoint("BOTTOMRIGHT", 0, 0);
		local iconBorder = frame.Icon.Overlay;
		iconBorder:SetTexture("Interface\\AchievementFrame\\UI-Achievement-IconFrame");
		iconBorder:SetTexCoord(0, 0.5625, 0, 0.5625);
		iconBorder:SetPoint("CENTER", -1, 2);
		frame.Icon:SetPoint("TOPLEFT", -26, 16);
		displayName:SetPoint("BOTTOMLEFT", 72, 36);
		displayName:SetPoint("BOTTOMRIGHT", -60, 36);
		frame.Shield:SetPoint("TOPRIGHT", -10, -13);
		shieldPoints:SetPoint("CENTER", 7, 2);
		shieldPoints:SetVertexColor(1, 1, 1);
		shieldIcon:SetTexCoord(0, 0.5, 0, 0.45);
		unlocked:SetPoint("TOP", 7, -23);
		frame.GuildName:Hide();
		frame.GuildBorder:Hide();
		frame.GuildBanner:Hide();
		frame.glow:SetTexture("Interface\\AchievementFrame\\UI-Achievement-Alert-Glow");
		frame.glow:SetTexCoord(0, 0.78125, 0, 0.66796875);
		frame.shine:SetTexture("Interface\\AchievementFrame\\UI-Achievement-Alert-Glow");
		frame.shine:SetTexCoord(0.78125, 0.912109375, 0, 0.28125);
		frame.shine:SetPoint("BOTTOMLEFT", 0, 8);
	end

	shieldIcon:SetTexture([[Interface\AchievementFrame\UI-Achievement-Shields-NoPoints]]);

	frame.Icon.Texture:SetTexture(itemTexture);

	if attempts == nil or attempts <= 0 then attempts = 1 end
	if item and item.method and item.method == COLLECTION then
		unlocked:SetText(L["Collection Complete"])
	else
		if attempts == 1 then unlocked:SetText(L["Obtained On Your First Attempt"])
		else unlocked:SetText(format(L["Obtained After %d Attempts"], attempts)) end
	end
	Rarity:ScheduleTimer(function()
		-- Put the achievement frame back to normal when we're done
		unlocked:SetText(ACHIEVEMENT_UNLOCKED);
	end, 10)

	frame.id = itemId;
	return true;
end


local RarityAchievementAlertSystem = AlertFrame:AddQueuedAlertFrameSubSystem("AchievementAlertFrameTemplate", RarityAchievementAlertFrame_SetUp, 2, 6);
RarityAchievementAlertSystem:SetCanShowMoreConditionFunc(function() return not C_PetBattles.IsInBattle() end);


-- test with: /run Rarity:ShowFoundAlert(32458, 5)
function R:ShowFoundAlert(itemId, attempts, item)

	trackedItem = Rarity.Tracking:GetTrackedItem()
	if item == nil then item = trackedItem end

 local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture, itemSellPrice = GetItemInfo(itemId)
 if itemName == nil then return end -- Server doesn't know this item, we can't award it
 if itemTexture == nil then itemTexture = [[Interface\Icons\INV_Misc_PheonixPet_01]] end

	-- Output to the sink
 if self.db.profile.enableAnnouncements ~= false and item.announce ~= false then
  local s
		if item.method == COLLECTION then
			s = format(L["%s: collection completed!"], itemName)
		else
			if attempts <= 1 then
				s = format(L["%s: Found on the first attempt!"], itemName)
			else
				s = format(L["%s: Found after %d attempts!"], itemName, attempts)
			end
		end
  self:Pour(s, nil, nil, nil, nil, nil, nil, nil, nil, itemTexture)
 end

 -- The following code is adapted from Blizzard's AlertFrameMixin:OnEvent function found in FrameXML\AlertFrames.lua [heavily updated in 7.0]

	if (IsKioskModeEnabled()) then
		return
	end

	if ( not AchievementFrame ) then
		AchievementFrame_LoadUI();
	end

	RarityAchievementAlertSystem:AddAlert(itemId, attempts);

 self:ScheduleTimer(function()
  -- Take a screenshot
	 if Rarity.db.profile.takeScreenshot then
			if ( ActionStatus:IsShown() ) then ActionStatus:Hide() end
			Screenshot()
		end
 end, 2)


 PlaySound(12891) -- UI_Alert_AchievementGained
end


hooksecurefunc("BonusRollFrame_StartBonusRoll", function(spellID, text, duration, currencyID)
	local self = Rarity
	if self.lastCoinItem and self.lastCoinItem.enableCoin and self.lastCoinItem.enabled ~= false then
		if self.lastCoinItem.itemId then
			if not currencyID then currencyID = BONUS_ROLL_REQUIRED_CURRENCY end
			local _, count, icon = GetCurrencyInfo(currencyID)
			if count == 0 then return end
			local name, link, quality, iLevel, reqLevel, class, subclass, maxStack, equipSlot, texture, vendorPrice = GetItemInfo(self.lastCoinItem.itemId)
			local _, _, _, fontString = StorePurchaseAlertFrame:GetRegions()
			fontString:SetText(L["Use your bonus roll for a chance at this item"])
			self:ScheduleTimer(function() fontString:SetText(BLIZZARD_STORE_PURCHASE_COMPLETE_DESC) end, duration + 2)
			StorePurchaseAlertFrame_ShowAlert(texture, link, self.lastCoinItem.itemId)
		end
	end
end)






function R:ScanCalendar(reason)
 self:Debug("Scanning calendar ("..reason..")")

	table.wipe(Rarity.holiday_textures)
	local dateInfo = C_Calendar.GetDate() -- This is the CURRENT date (always "today")
	local month, day, year = dateInfo.month, dateInfo.monthDay, dateInfo.year
	local monthInfo = C_Calendar.GetMonthInfo() -- This is the CALENDAR date (as selected)
	local curMonth, curYear = monthInfo.month, monthInfo.year -- It should be noted that this is the calendar's "current" month... the name may be misleading, but I'll keep it as it was
	local monthOffset = -12 * (curYear - year) + month - curMonth
	local numEvents = C_Calendar.GetNumDayEvents(monthOffset, day)
	local numLoaded = 0

	for i = 1, numEvents, 1 do
		local CalendarDayEvent = C_Calendar.GetDayEvent(monthOffset, day, i)
		local calendarType, texture = CalendarDayEvent.calendarType, CalendarDayEvent.iconTexture

		if calendarType == "HOLIDAY" and texture ~= nil then
			Rarity.holiday_textures[texture] = true
		end
	end
end


function R:ScanInstanceLocks(reason)
 self:Debug("Scanning instance locks ("..reason..")")

	table.wipe(Rarity.lockouts)
	local savedInstances = GetNumSavedInstances()
	for i = 1, savedInstances do
		local instanceName, instanceID, instanceReset, instanceDifficulty, locked, extended, instanceIDMostSig = GetSavedInstanceInfo(i)

		-- Legacy code (deprecated)
		if instanceReset > 0 then
			scanTip:ClearLines()
			scanTip:SetInstanceLockEncountersComplete(i)
			for i = 2, scanTip:NumLines() do
				local txtRight = _G["__Rarity_ScanTipTextRight"..i]:GetText()
				if txtRight then
					if txtRight == BOSS_DEAD then self.lockouts[_G["__Rarity_ScanTipTextLeft"..i]:GetText()] = true end
				end
			end
		end

		-- Detailed lockouts saving (stub - I'm leaving the legacy code above untouched, even if it's partly identical)
		if instanceReset > 0 then -- Lockout isn't expired -> Scan it and store the defeated encounter names
			scanTip:ClearLines()
			scanTip:SetInstanceLockEncountersComplete(i)
			for i = 2, scanTip:NumLines() do
				local txtRight = _G["__Rarity_ScanTipTextRight"..i]:GetText()
				if txtRight then
					if txtRight == BOSS_DEAD then

						local encounterName  = _G["__Rarity_ScanTipTextLeft"..i]:GetText()
						self.lockouts[encounterName] = true
						-- Create containers if this is the first lockout for a given instance
						self.lockouts_detailed[encounterName] = self.lockouts_detailed[encounterName] or {}
						self.lockouts_detailed[encounterName][instanceDifficulty] = self.lockouts_detailed[encounterName][instanceDifficulty] or {}
						-- Add this lockout to the container
						self.lockouts_detailed[encounterName][instanceDifficulty] = true

						end
				end
			end
		end

	end

	table.wipe(Rarity.lockouts_holiday)
	local num = GetNumRandomDungeons()
	for i = 1, num do
		local dungeonID, name = GetLFGRandomDungeonInfo(i)
		local _, _, _, _, _, _, _, _, _, _, _, _, _, desc, isHoliday = GetLFGDungeonInfo(dungeonID)
		if isHoliday and dungeonID ~= 828 then
			local doneToday = GetLFGDungeonRewards(dungeonID)
			self.lockouts_holiday[dungeonID] = doneToday
		end
	end

	-- This code lists every LFG dungeon ID in the game (up through 1000)
	--for instanceID = 0, 1000 do
	--	local dungeonName, typeId, subtypeId, minLvl, maxLvl, recLvl, minRecLvl, maxRecLvl, expansionId, groupId, textureName, difficulty, maxPlayers, dungeonDesc, isHoliday = GetLFGDungeonInfo(instanceID)
	--		if dungeonName then
	--			self:Print("instanceID = " .. instanceID .. " Name = " .. dungeonName .. " typeID = " .. tostring(typeId) .. " minLvl = " .. minLvl .. " maxLvl = " .. maxLvl .. " recLvl = " .. recLvl .. " groupId = " .. tostring(groupId) .." maxPlayers = " .. tostring(maxPlayers))
	--		end
	--end

end


function R:BuildStatistics(reason)
	self:ProfileStart2()
 --self:Debug("Building statistics table ("..reason..")")

 local tbl = {}
	Rarity.lastStatCount = 0

	for k, v in pairs(R.stats_to_scan) do
		local s = GetStatistic(k)
		tbl[k] = (tonumber(s or "0") or 0)
		if not Rarity.db.profile.accountWideStatistics then Rarity.db.profile.accountWideStatistics = {} end
		local charName = UnitName("player")
		local charGuid = UnitGUID("player")
		if charName and charGuid then
			if not Rarity.db.profile.accountWideStatistics[charGuid] then Rarity.db.profile.accountWideStatistics[charGuid] = {} end
			Rarity.db.profile.accountWideStatistics[charGuid].playerName = charName
			Rarity.db.profile.accountWideStatistics[charGuid].server = GetRealmName() or ""
			if not Rarity.db.profile.accountWideStatistics[charGuid].statistics then Rarity.db.profile.accountWideStatistics[charGuid].statistics = {} end
			Rarity.db.profile.accountWideStatistics[charGuid].statistics[k] = (tonumber(s or "0") or 0)
		end
		Rarity.lastStatCount = Rarity.lastStatCount + 1
	end

	self:ProfileStop2("BuildStatistics: %fms")
 return tbl
end


function R:ScanStatistics(reason)
	if InCombatLockdown() then return end -- Don't do this during combat as it has a tendency to run too long

	self:ProfileStart2()
 --self:Debug("Scanning statistics ("..reason..")")

 if rarity_stats == nil or (Rarity.lastStatCount or 0) <= 0 then
  self:Debug("Building initial statistics table")
  rarity_stats = self:BuildStatistics(reason)
 end

 local newStats = self:BuildStatistics(reason)

 for kk, vv in pairs(Rarity.items_with_stats) do
  if type(vv) == "table" then
   if (vv.requiresHorde and R.Caching:IsHorde()) or (vv.requiresAlliance and not R.Caching:IsHorde()) or (not vv.requiresHorde and not vv.requiresAlliance) then
    if vv.statisticId and type(vv.statisticId) == "table" then
     local count = 0
					local totalCrossAccount = 0

     for kkk, vvv in pairs(vv.statisticId) do
      local newAmount = newStats[vvv] or 0
      local oldAmount = rarity_stats[vvv] or 0
      count = count + newAmount

						-- Count up the total for this statistic across the entire account
						if Rarity.db.profile.accountWideStatistics then
							for playerGuid, playerData in pairs(Rarity.db.profile.accountWideStatistics) do
								if playerData.statistics then
									totalCrossAccount = totalCrossAccount + (Rarity.db.profile.accountWideStatistics[playerGuid].statistics[vvv] or 0)
								end
							end
						end

      -- One of the statistics has gone up; add one attempt for this item
      if newAmount > oldAmount then
							R:Debug("Statistics indicate a new attempt for "..vv.name)
       vv.attempts = (vv.attempts or 0) + 1
       self:OutputAttempts(vv, true)
      end

     end

     -- We've never seen any attempts for this yet; update to this player's statistic total
     if count > 0 and (vv.attempts or 0) <= 0 then
      vv.attempts = count
      self:OutputAttempts(vv, true)

     -- We seem to have gathered more attempts on this character than accounted for yet; update to new total
     elseif count > 0 and count > (vv.attempts or 0) and vv.doNotUpdateToHighestStat ~= true then -- Some items don't want us doing this (generally when Blizzard has a statistic overcounting bug)
						R:Debug("Statistics for "..vv.name.." are higher than current amount. Updating to "..count)
      vv.attempts = count
      self:OutputAttempts(vv, true)
     end

					-- Cross-account statistic total is higher than the one we have; update to new total
					if totalCrossAccount > (vv.attempts or 0) and vv.doNotUpdateToHighestStat ~= true then
						R:Debug("Account-wide statistics for "..vv.name.." are higher than current amount. Updating to "..totalCrossAccount)
      vv.attempts = totalCrossAccount
      self:OutputAttempts(vv, true)
					end

    end
   end
  end
 end

 -- Done with scan; update our saved table to the current scan
 rarity_stats = newStats

 if self.db.profile.debugMode then R.stats = rarity_stats end


	-- Scan rare NPC achievements
	table.wipe(Rarity.ach_npcs_isKilled)
	table.wipe(Rarity.ach_npcs_achId)
	for k, v in pairs(self.db.profile.achNpcs) do
		local count = GetAchievementNumCriteria(v)
		for i = 1, count do
			local description, type, completed = GetAchievementCriteriaInfo(v, i)
			Rarity.ach_npcs_achId[description] = v
			if completed then Rarity.ach_npcs_isKilled[description] = true end
		end
	end

	self:ProfileStop2("ScanStatistics: %fms")
end





function R:Update(reason)
 Rarity.Collections:ScanExistingItems(reason)
 self:UpdateInterestingThings(reason)
 Rarity.Tracking:FindTrackedItem()
 Rarity.GUI:UpdateText()
 --if self:InTooltip() then self:ShowTooltip() end
end
