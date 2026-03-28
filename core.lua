local _G = _G
local ElvUI = _G.ElvUI
local LibStub = _G.LibStub
local SlashCmdList = _G.SlashCmdList

local E = unpack(ElvUI)
local NP = E:GetModule('NamePlates')
local EP = LibStub('LibElvUIPlugin-1.0')
local addonName = ...

local strlower = string.lower
local tinsert = table.insert

local UnitExists = _G.UnitExists
local UnitName = _G.UnitName
local UnitThreatSituation = _G.UnitThreatSituation
local UnitClass = _G.UnitClass
local GetTime = _G.GetTime
local CreateFrame = _G.CreateFrame
local GetPartyAssignment = _G.GetPartyAssignment
local GetNumPartyMembers = _G.GetNumPartyMembers
local GetNumRaidMembers = _G.GetNumRaidMembers
local RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS
local CUSTOM_CLASS_COLORS = _G.CUSTOM_CLASS_COLORS

local ADDON_DB = 'ElvUIThreatPlatesDB'

local DEFAULTS = {
    enabled = true,
    autoMainTanks = true,
    onlyInGroup = false,
    preferPlayerPrimary = true,
    debug = false,
    borderSize = 3,
    borderAlpha = 0.95,
    overlayEnabled = true,
    overlayAlpha = 0.18,
    useCustomColor = false,
    customColors = {
        {
            r = 0.2,
            g = 0.6,
            b = 1,
        },
        {
            r = 1,
            g = 0.45,
            b = 0.15,
        },
    },
    customColorAssignments = {},
}

local COLOR_CACHE_TTL = 1

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == 'table' then
            if type(dst[k]) ~= 'table' then
                dst[k] = {}
            end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function GetClassColor(unit)
    local _, classFile = UnitClass(unit)
    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local color = classFile and colors and colors[classFile]
    if color then
        return { r = color.r, g = color.g, b = color.b }
    end

    return { r = 0.2, g = 0.6, b = 1 }
end

local function ParseArgs(msg)
    local args = {}
    for token in tostring(msg or ''):gmatch('%S+') do
        tinsert(args, token)
    end
    return args
end

local function GetUnitKey(name)
	name = tostring(name or '')
	if name == '' then
		return nil
	end

	return strlower(name)
end

-- Create a new module for this plugin
local MOD = E:NewModule('ElvUIThreatPlates', 'AceHook-3.0', 'AceEvent-3.0')

function MOD:InitDB()
    _G[ADDON_DB] = _G[ADDON_DB] or {}
    local legacyCustomColor = _G[ADDON_DB].customColor
    CopyDefaults(DEFAULTS, _G[ADDON_DB])
    if legacyCustomColor then
        _G[ADDON_DB].customColors = _G[ADDON_DB].customColors or {}
        _G[ADDON_DB].customColors[1] = _G[ADDON_DB].customColors[1] or {}
        _G[ADDON_DB].customColors[1].r = legacyCustomColor.r or DEFAULTS.customColors[1].r
        _G[ADDON_DB].customColors[1].g = legacyCustomColor.g or DEFAULTS.customColors[1].g
        _G[ADDON_DB].customColors[1].b = legacyCustomColor.b or DEFAULTS.customColors[1].b
        _G[ADDON_DB].customColor = nil
    end
    _G[ADDON_DB].tanks = nil
    self.db = _G[ADDON_DB]
	self.CustomColorCache = self.CustomColorCache or {}
end

function MOD:DebugPrint(message)
	if not (self.db and self.db.debug) then return end
	E:Print(('ElvUIThreatPlates Debug: %s'):format(tostring(message)))
end

function MOD:GetCustomColorForSlot(slot)
    local colors = self.db and self.db.customColors
    local color = colors and colors[slot]
    local fallback = DEFAULTS.customColors[slot] or DEFAULTS.customColors[1]
    color = color or fallback
    return { r = color.r or fallback.r, g = color.g or fallback.g, b = color.b or fallback.b }
end

function MOD:GetAssignedTankNameForSlot(slot)
    if not (self.db and self.db.customColorAssignments) then
        return nil
    end

    local tanksByKey = {}
    self:ForEachConfiguredTankUnit(function(tankUnit, tankName)
        local key = GetUnitKey(tankName)
        if key then
            tanksByKey[key] = tankName or tankUnit
        end
    end)

    for key, assignedSlot in pairs(self.db.customColorAssignments) do
        if assignedSlot == slot then
            return tanksByKey[key] or key
        end
    end

    return nil
end

function MOD:RefreshCustomColorAssignments(tanks)
    if not self.db then return end

    local previousAssignments = self.db.customColorAssignments or {}
    local nextAssignments = {}
    local usedSlots = {}
    local playerName = UnitExists('player') and UnitName('player') or nil
    local playerKey = GetUnitKey(playerName)

    if self.db.preferPlayerPrimary and playerKey then
        for i = 1, #tanks do
            local tank = tanks[i]
            if tank.key == playerKey then
                nextAssignments[playerKey] = 1
                usedSlots[1] = true
                break
            end
        end
    end

    for i = 1, #tanks do
        local tank = tanks[i]
        local slot = tank.key and previousAssignments[tank.key]
        if slot and slot >= 1 and slot <= 2 and not usedSlots[slot] then
            nextAssignments[tank.key] = slot
            usedSlots[slot] = true
        end
    end

    for i = 1, #tanks do
        local tank = tanks[i]
        if tank.key and not nextAssignments[tank.key] then
            for slot = 1, 2 do
                if not usedSlots[slot] then
                    nextAssignments[tank.key] = slot
                    usedSlots[slot] = true
                    break
                end
            end
        end
    end

    self.db.customColorAssignments = nextAssignments
end

function MOD:GetConfiguredTankColor(unit, unitName)
    if self.db and self.db.useCustomColor then
        local key = GetUnitKey(unitName)
        local slot = key and self.db.customColorAssignments and self.db.customColorAssignments[key]
        if slot then
            return self:GetCustomColorForSlot(slot)
        end

        return self:GetCustomColorForSlot(1)
    end

    return GetClassColor(unit)
end

function MOD:IsGroupContextActive()
    local raidMembers = GetNumRaidMembers and GetNumRaidMembers() or 0
    local partyMembers = GetNumPartyMembers and GetNumPartyMembers() or 0
    return raidMembers > 0 or partyMembers > 0
end

function MOD:IsPreviewActive()
    return self.PreviewUntil and GetTime() < self.PreviewUntil
end

function MOD:GetPreviewColor()
    local previewColor = self:GetSingleTankColor()
    if previewColor then
        return previewColor
    end

    if UnitExists('player') then
        return self:GetConfiguredTankColor('player', UnitName('player'))
    end

    return { r = 1, g = 0.82, b = 0.2 }
end

function MOD:StopPreview(forceRefresh)
    self.PreviewUntil = nil
    if self.PreviewFrame then
        self.PreviewFrame:SetScript('OnUpdate', nil)
    end

    if forceRefresh then
        self:ForceUpdatePlates()
    end
end

function MOD:StartPreview(duration)
    duration = duration or 5
    self.PreviewUntil = GetTime() + duration

    if not self.PreviewFrame then
        self.PreviewFrame = CreateFrame('Frame')
    end

    self.PreviewFrame:SetScript('OnUpdate', function()
        if not MOD:IsPreviewActive() then
            MOD:StopPreview(true)
        end
    end)

    self:ForceUpdatePlates()
end

function MOD:ApplyPreset(preset)
    if preset == 'subtle' then
        self.db.borderSize = 2
        self.db.borderAlpha = 0.7
        self.db.overlayEnabled = true
        self.db.overlayAlpha = 0.08
    elseif preset == 'strong' then
        self.db.borderSize = 4
        self.db.borderAlpha = 1
        self.db.overlayEnabled = true
        self.db.overlayAlpha = 0.25
    elseif preset == 'border' then
        self.db.borderSize = 3
        self.db.borderAlpha = 1
        self.db.overlayEnabled = false
        self.db.overlayAlpha = 0
    elseif preset == 'overlay' then
        self.db.borderSize = 1
        self.db.borderAlpha = 0.25
        self.db.overlayEnabled = true
        self.db.overlayAlpha = 0.32
    end

    self:ClearAllCachedColors()
    self:ForceUpdatePlates()
end

function MOD:ClearAllCachedColors()
	for key in pairs(self.CustomColorCache) do
		self.CustomColorCache[key] = nil
	end
end

function MOD:EnsurePlateSetup(nameplate)
    if not nameplate then return end
    self:InstallThreatWrapper(nameplate)
    self:InstallBorderIndicator(nameplate)
end

function MOD:ProcessPendingPlateUnits(elapsed)
    self.PendingPlateElapsed = (self.PendingPlateElapsed or 0) + elapsed
    if self.PendingPlateElapsed < 0.05 then
        return
    end

    self.PendingPlateElapsed = 0

    local hasPending
    for unit, expiresAt in pairs(self.PendingPlateUnits or {}) do
        hasPending = true
        if GetTime() >= expiresAt then
            self.PendingPlateUnits[unit] = nil
        else
            for nameplate in pairs(NP.Plates or {}) do
                if nameplate and nameplate.unit == unit then
                    self:EnsurePlateSetup(nameplate)
                    self:RefreshPlateColor(nameplate)
                    self.PendingPlateUnits[unit] = nil
                    break
                end
            end
        end
    end

    if (not hasPending) and self.PendingPlateFrame then
        self.PendingPlateFrame:SetScript('OnUpdate', nil)
    end
end

function MOD:QueuePlateUnitRefresh(unit)
    if not unit then return end
    self.PendingPlateUnits = self.PendingPlateUnits or {}
    self.PendingPlateUnits[unit] = GetTime() + 1

    if not self.PendingPlateFrame then
        self.PendingPlateFrame = CreateFrame('Frame')
    end

    self.PendingPlateElapsed = 0
    self.PendingPlateFrame:SetScript('OnUpdate', function(_, elapsed)
        MOD:ProcessPendingPlateUnits(elapsed)
    end)
end

function MOD:GetTankSourceColor(unit, unitName)
    if self.db.autoMainTanks and GetPartyAssignment and GetPartyAssignment('MAINTANK', unit) then
        self:DebugPrint(('MAINTANK match: %s (%s)'):format(unitName or 'unknown', unit or 'nil'))
        return self:GetConfiguredTankColor(unit, unitName), unitName, 'maintank'
    end

    return nil
end

function MOD:ForceUpdatePlates()
    if not (NP and NP.Plates) then return end
    for nameplate in pairs(NP.Plates) do
        if nameplate then
            self:EnsurePlateSetup(nameplate)
        end

        if nameplate and nameplate.UpdateAllElements then
            nameplate:UpdateAllElements('ForceUpdate')
        end

        self:RefreshPlateColor(nameplate)
    end
end

function MOD:RefreshPlateColor(nameplate)
    if not (nameplate and nameplate.Health and nameplate.unit) then return end
    self:EnsurePlateSetup(nameplate)

    if nameplate.Health.ForceUpdate then
        nameplate.Health:ForceUpdate()
    end

    self:ApplyTankColor(nameplate, nameplate.unit)
end

function MOD:RefreshAllPlateColors()
    if not (NP and NP.Plates) then return end
    for nameplate in pairs(NP.Plates) do
        self:RefreshPlateColor(nameplate)
    end
end

function MOD:GetSingleTankColor()
    local tankCount = 0
    local singleColor, singleName

    self:ForEachConfiguredTankUnit(function(_, tankName, color)
        tankCount = tankCount + 1
        if tankCount == 1 then
            singleColor = color
            singleName = tankName
        end
    end)

    if tankCount == 1 then
        return singleColor, singleName
    end

    return nil
end

function MOD:ForEachConfiguredTankUnit(func)
    if not func then return end
	local seen = {}
	local tanks = {}

    if UnitExists('player') then
        local playerName = UnitName('player')
		local key = GetUnitKey(playerName)
		if key and not seen[key] and self.db.autoMainTanks and GetPartyAssignment and GetPartyAssignment('MAINTANK', 'player') then
			seen[key] = true
            tinsert(tanks, { unit = 'player', unitName = playerName, key = key, configuredName = playerName, source = 'maintank' })
        end
    end

    for i = 1, 4 do
        local unit = 'party' .. i
        if UnitExists(unit) then
            local unitName = UnitName(unit)
			local key = GetUnitKey(unitName)
			if key and not seen[key] and self.db.autoMainTanks and GetPartyAssignment and GetPartyAssignment('MAINTANK', unit) then
				seen[key] = true
                tinsert(tanks, { unit = unit, unitName = unitName, key = key, configuredName = unitName, source = 'maintank' })
            end
        end
    end

    for i = 1, 40 do
        local unit = 'raid' .. i
        if UnitExists(unit) then
            local unitName = UnitName(unit)
			local key = GetUnitKey(unitName)
			if key and not seen[key] and self.db.autoMainTanks and GetPartyAssignment and GetPartyAssignment('MAINTANK', unit) then
				seen[key] = true
                tinsert(tanks, { unit = unit, unitName = unitName, key = key, configuredName = unitName, source = 'maintank' })
            end
        end
    end

	if self.db and self.db.useCustomColor then
		self:RefreshCustomColorAssignments(tanks)
	end

	for i = 1, #tanks do
		local tank = tanks[i]
		func(tank.unit, tank.unitName, self:GetConfiguredTankColor(tank.unit, tank.unitName), tank.configuredName, tank.source)
	end
end

function MOD:ResolveThreatMobUnit(nameplate, unit)
    local mobGUID = (nameplate and nameplate.unitGUID) or (unit and UnitGUID(unit))
    if not mobGUID then return nil end

    local staticUnits = {
        'target',
        'focus',
        'mouseover',
        'pettarget',
        'playertargettarget',
    }

    for _, mobUnit in pairs(staticUnits) do
        if UnitExists(mobUnit) and UnitGUID(mobUnit) == mobGUID then
            return mobUnit
        end
    end

    for i = 1, 4 do
        local mobUnit = 'party' .. i .. 'target'
        if UnitExists(mobUnit) and UnitGUID(mobUnit) == mobGUID then
            return mobUnit
        end
    end

    for i = 1, 40 do
        local mobUnit = 'raid' .. i .. 'target'
        if UnitExists(mobUnit) and UnitGUID(mobUnit) == mobGUID then
            return mobUnit
        end
    end

    return nil
end

function MOD:GetTankThreatColor(nameplate, unit)
    local mobUnit = (unit and UnitExists(unit) and unit) or self:ResolveThreatMobUnit(nameplate, unit)
    if not mobUnit then
        self:DebugPrint(('No mob unit resolved for plate %s'):format(nameplate and (nameplate.unitGUID or nameplate.unit or 'unknown') or 'unknown'))
        return nil
    end

    local bestStatus, bestColor, bestTankName, bestTankUnit, bestTankSource

    self:ForEachConfiguredTankUnit(function(tankUnit, tankName, color, _, source)
        local status = UnitThreatSituation(tankUnit, mobUnit)

        if status and status >= 2 and (not bestStatus or status > bestStatus) then
            bestStatus = status
            bestColor = color
            bestTankName = tankName
            bestTankUnit = tankUnit
            bestTankSource = source
        end
    end)

    if bestTankName then
		self:DebugPrint(('Threat owner %s on %s with status %s via %s'):format(bestTankName, mobUnit, tostring(bestStatus), bestTankSource or 'unknown'))
	end

    return bestColor, bestTankName, bestStatus, bestTankUnit, mobUnit, bestTankSource
end

function MOD:GetPlateCacheKey(nameplate, unit)
    return (nameplate and (nameplate.unitGUID or nameplate.unit)) or unit
end

function MOD:GetCachedColor(nameplate, unit)
    local key = self:GetPlateCacheKey(nameplate, unit)
    local cache = key and self.CustomColorCache[key]
    if not cache then return nil end
    if (GetTime() - cache.timestamp) > COLOR_CACHE_TTL then
        self.CustomColorCache[key] = nil
        return nil
    end
    return cache
end

function MOD:SetCachedColor(nameplate, unit, color, tankName, status, mobUnit, source)
    local key = self:GetPlateCacheKey(nameplate, unit)
    if not key then return end
    self.CustomColorCache[key] = {
        color = color,
        tankName = tankName,
        status = status,
        mobUnit = mobUnit,
        source = source,
        timestamp = GetTime(),
    }
end

function MOD:ClearCachedColor(nameplate, unit)
    local key = self:GetPlateCacheKey(nameplate, unit)
    if key then
        self.CustomColorCache[key] = nil
    end
end

function MOD:InstallBorderIndicator(nameplate)
    if not (nameplate and nameplate.Health) then return end
    if nameplate.__ElvUIThreatPlatesBorder then return end

    local border = CreateFrame('Frame', nil, nameplate)
    border:SetFrameLevel(nameplate.Health:GetFrameLevel() + 5)
    border:SetBackdrop({ edgeFile = 'Interface\\Buttons\\WHITE8x8', edgeSize = self.db.borderSize or 3 })
    border:SetBackdropBorderColor(0, 0, 0, 0)
    border:Hide()

    local overlay = nameplate.Health:CreateTexture(nil, 'OVERLAY')
    overlay:SetTexture('Interface\\Buttons\\WHITE8x8')
    overlay:SetAllPoints(nameplate.Health)
    overlay:Hide()

    nameplate.__ElvUIThreatPlatesBorder = border
    nameplate.__ElvUIThreatPlatesOverlay = overlay
end

function MOD:UpdateBorderIndicator(nameplate, color)
    local border = nameplate and nameplate.__ElvUIThreatPlatesBorder
    local overlay = nameplate and nameplate.__ElvUIThreatPlatesOverlay
    if not (border and overlay) then return end

    if not (nameplate and nameplate.Health and nameplate.Health:IsShown() and color) then
        border:Hide()
        overlay:Hide()
        return
    end

    local borderSize = self.db.borderSize or 3
    local borderAlpha = self.db.borderAlpha or 0.95
    local overlayAlpha = self.db.overlayAlpha or 0.18

    border:SetBackdrop({ edgeFile = 'Interface\\Buttons\\WHITE8x8', edgeSize = borderSize })
    border:ClearAllPoints()
    border:SetPoint('TOPLEFT', nameplate.Health, 'TOPLEFT', -borderSize, borderSize)
    border:SetPoint('BOTTOMRIGHT', nameplate.Health, 'BOTTOMRIGHT', borderSize, -borderSize)
    border:SetBackdropBorderColor(color.r, color.g, color.b, borderAlpha)

    if self.db.overlayEnabled then
        overlay:SetVertexColor(color.r, color.g, color.b, overlayAlpha)
        overlay:Show()
    else
        overlay:Hide()
    end

    border:Show()
end

function MOD:GetDesiredPlateColor(nameplate, unit)
    if not (self.db and self.db.enabled) then return nil end
    if not (nameplate and unit and nameplate.Health) then return nil end
    if nameplate.frameType ~= 'ENEMY_NPC' then
        self:ClearCachedColor(nameplate, unit)
        return nil
    end

	if self:IsPreviewActive() then
		return self:GetPreviewColor()
	end

	if self.db.onlyInGroup and not self:IsGroupContextActive() then
		self:ClearCachedColor(nameplate, unit)
		return nil
	end

    local color, tankName, status, _, mobUnit, source = self:GetTankThreatColor(nameplate, unit)
    if color and color.r and color.g and color.b then
        self:SetCachedColor(nameplate, unit, color, tankName, status, mobUnit, source)
        return color
    end

	local singleTankColor, singleTankName = self:GetSingleTankColor()
	local threatStatus = nameplate.__ElvUIThreatPlatesThreatStatus
	if singleTankColor and threatStatus and threatStatus >= 2 then
		self:DebugPrint(('Fallback color %s on plate %s with threat status %s'):format(singleTankName or 'unknown', unit or 'unknown', tostring(threatStatus)))
		self:SetCachedColor(nameplate, unit, singleTankColor, singleTankName, threatStatus, nil, 'single-tank-fallback')
		return singleTankColor
	end

    if mobUnit then
        self:ClearCachedColor(nameplate, unit)
        return nil
    end

    local cached = self:GetCachedColor(nameplate, unit)
    return cached and cached.color or nil
end

function MOD:HandlePlateEvent(event, unit)
    if event == 'NAME_PLATE_UNIT_ADDED' and unit then
        self:QueuePlateUnitRefresh(unit)
    end

    if not unit then
        return self:RefreshAllPlateColors()
    end

    if not (NP and NP.Plates) then return end
    for nameplate in pairs(NP.Plates) do
        if nameplate and nameplate.unit == unit then
            self:EnsurePlateSetup(nameplate)
            self:RefreshPlateColor(nameplate)
            return
        end
    end

    self:RefreshAllPlateColors()
end

function MOD:ApplyTankColor(nameplate, unit)
    local color = self:GetDesiredPlateColor(nameplate, unit)
    self:UpdateBorderIndicator(nameplate, color)
end

function MOD:InstallThreatWrapper(nameplate)
    if not (nameplate and nameplate.ThreatIndicator) then return end
    if nameplate.ThreatIndicator.__ElvUIThreatPlatesWrapped then return end

    local originalPostUpdate = nameplate.ThreatIndicator.PostUpdate
    nameplate.ThreatIndicator.PostUpdate = function(threatIndicator, unit, status, r, g, b)
        if threatIndicator.__owner then
			threatIndicator.__owner.__ElvUIThreatPlatesThreatStatus = status
		end

        if originalPostUpdate then
            originalPostUpdate(threatIndicator, unit, status, r, g, b)
        end

        MOD:RefreshPlateColor(threatIndicator.__owner)
    end

    nameplate.ThreatIndicator.__ElvUIThreatPlatesWrapped = true
end

function MOD:UpdateThreatIndicatorHook(nameplate)
    self:InstallThreatWrapper(nameplate)
    self:InstallBorderIndicator(nameplate)
end

function MOD:PrintHelp()
    E:Print('ElvUIThreatPlates commands:')
    E:Print('  /etp refresh')
    E:Print('  /etp enable | disable')
    E:Print('  /etp automt               (toggle auto raid Main Tanks)')
    E:Print('  /etp preview              (show current style for 5 seconds)')
    E:Print('  /etp debug                (toggle debug output)')
end

function MOD:HandleSlash(msg)
    local args = ParseArgs(msg)
    local cmd = args[1] and strlower(args[1]) or nil

    if not cmd or cmd == '' or cmd == 'help' then
        return self:PrintHelp()
    end

    if cmd == 'enable' then
        self.db.enabled = true
        self:ClearAllCachedColors()
        self:ForceUpdatePlates()
        E:Print('ElvUIThreatPlates: enabled')
        return
    elseif cmd == 'disable' then
        self.db.enabled = false
        self:ClearAllCachedColors()
        self:ForceUpdatePlates()
        E:Print('ElvUIThreatPlates: disabled')
        return
    elseif cmd == 'automt' or cmd == 'maintanks' then
		self.db.autoMainTanks = not self.db.autoMainTanks
		self:ClearAllCachedColors()
		self:ForceUpdatePlates()
		E:Print(('ElvUIThreatPlates: auto raid Main Tanks %s'):format(self.db.autoMainTanks and 'enabled' or 'disabled'))
		return
    elseif cmd == 'debug' then
        self.db.debug = not self.db.debug
        E:Print(('ElvUIThreatPlates: debug %s'):format(self.db.debug and 'enabled' or 'disabled'))
        return
    elseif cmd == 'preview' or cmd == 'test' then
		self:StartPreview(5)
		E:Print('ElvUIThreatPlates: preview started for 5 seconds')
		return
    elseif cmd == 'refresh' then
        self:ClearAllCachedColors()
        self:ForceUpdatePlates()
        E:Print('ElvUIThreatPlates: refreshed plates')
        return
    end

    self:PrintHelp()
end

function MOD:SetupSlashCommands()
    SLASH_ELVUITHREATPLATES1 = '/etp'
    SLASH_ELVUITHREATPLATES2 = '/euitp'
    SlashCmdList.ELVUITHREATPLATES = function(msg)
        MOD:HandleSlash(msg)
    end
end

function MOD:InsertOptions()
    if not (E.Options and E.Options.args) then return end

    E.Options.args.elvuiThreatPlates = {
        order = 100,
        type = 'group',
        name = '|cff1784d1Threat Plates|r',
        get = function(info)
            return self.db[info[#info]]
        end,
        set = function(info, value)
            self.db[info[#info]] = value
            if info[#info] == 'enabled' then
                self:ClearAllCachedColors()
                self:ForceUpdatePlates()
            end
        end,
        args = {
            intro = {
                order = 1,
                type = 'description',
                name = 'Mark enemy threat plates with a border in the active Main Tank class color.',
                fontSize = 'medium',
                width = 'full',
            },

            general = {
                order = 2,
                type = 'group',
                name = 'General',
                guiInline = true,
                args = {
                    generalInfo = {
                        order = 1,
                        type = 'description',
                        name = 'Enable the addon and decide whether raid Main Tank assignments should be detected automatically.',
                        fontSize = 'medium',
                        width = 'full',
                    },
                    enabled = {
                        order = 2,
                        type = 'toggle',
                        name = 'Enable',
                        desc = 'Turn the threat border and overlay system on or off.',
                        width = 'half',
                    },
                    autoMainTanks = {
						order = 3,
						type = 'toggle',
                        name = 'Auto MTs',
						desc = 'Use current raid Main Tank assignments as the threat color source.',
                        width = 'full',
						set = function(info, value)
							self.db[info[#info]] = value
							self:ClearAllCachedColors()
							self:ForceUpdatePlates()
						end,
					},
                    onlyInGroup = {
                        order = 4,
                        type = 'toggle',
                        name = 'Only Group/Raid',
                        desc = 'Only show threat markers while you are in a party or raid.',
                        width = 'full',
                        set = function(info, value)
                            self.db[info[#info]] = value
                            self:ClearAllCachedColors()
                            self:ForceUpdatePlates()
                        end,
                    },
                    preferPlayerPrimary = {
                        order = 5,
                        type = 'toggle',
                        name = 'Player = MT1',
                        desc = 'If you are one of the detected Main Tanks, always assign yourself to Tank 1.',
                        width = 'full',
                        set = function(info, value)
                            self.db[info[#info]] = value
                            self:ClearAllCachedColors()
                            self:ForceUpdatePlates()
                        end,
                    },
                },
            },

            appearance = {
                order = 3,
                type = 'group',
                name = 'Appearance',
                guiInline = true,
                args = {
                    appearanceInfo = {
                        order = 1,
                        type = 'description',
                        name = 'Adjust how strongly the threat marker appears around each enemy nameplate.',
                        fontSize = 'medium',
                        width = 'full',
                    },
                    overlayEnabled = {
                        order = 2,
                        type = 'toggle',
                        name = 'Enable Overlay',
                        desc = 'Adds a soft class-colored fill across the health bar.',
                        width = 'full',
                        set = function(info, value)
                            self.db[info[#info]] = value
                            self:ForceUpdatePlates()
                        end,
                    },
                    borderSize = {
                        order = 7,
                        type = 'range',
                        name = 'Border Size',
                        desc = 'Controls the thickness of the outer threat border.',
                        min = 1,
                        max = 8,
                        step = 1,
                        width = 0.9,
                        set = function(info, value)
                            self.db[info[#info]] = value
                            self:ForceUpdatePlates()
                        end,
                    },
                    borderAlpha = {
                        order = 8,
                        type = 'range',
                        name = 'Border Opacity',
                        desc = 'Controls how visible the outer threat border is.',
                        min = 0.1,
                        max = 1,
                        step = 0.01,
                        isPercent = true,
                        width = 0.9,
                        set = function(info, value)
                            self.db[info[#info]] = value
                            self:ForceUpdatePlates()
                        end,
                    },
                    overlayAlpha = {
                        order = 9,
                        type = 'range',
                        name = 'Overlay Opacity',
                        desc = 'Controls how strong the health bar overlay appears.',
                        min = 0,
                        max = 1,
                        step = 0.01,
                        isPercent = true,
                        width = 0.9,
                        disabled = function() return not self.db.overlayEnabled end,
                        set = function(info, value)
                            self.db[info[#info]] = value
                            self:ForceUpdatePlates()
                        end,
                    },
                    useCustomColor = {
                        order = 10,
                        type = 'toggle',
                        name = 'Use Custom Colors',
                        desc = 'Use one custom color for tank 1 and another for tank 2 instead of class colors.',
                        width = 'full',
                        set = function(info, value)
                            self.db[info[#info]] = value
                            self:ClearAllCachedColors()
                            self:ForceUpdatePlates()
                        end,
                    },
                    customColorInfo = {
                        order = 11,
                        type = 'description',
                        name = 'Custom colors are assigned to the first and second detected Main Tanks. If Player Always MT1 is enabled, your character stays on Tank 1 whenever you are one of them.',
                        fontSize = 'medium',
                        width = 'full',
                        hidden = function() return not self.db.useCustomColor end,
                    },
                    presetSubtle = {
                        order = 3,
                        type = 'execute',
                        name = 'Subtle',
                        width = 0.7,
                        func = function()
                            self:ApplyPreset('subtle')
                        end,
                    },
                    presetStrong = {
                        order = 4,
                        type = 'execute',
                        name = 'Strong',
                        width = 0.7,
                        func = function()
                            self:ApplyPreset('strong')
                        end,
                    },
                    presetBorderOnly = {
                        order = 5,
                        type = 'execute',
                        name = 'Border Only',
                        width = 0.9,
                        func = function()
                            self:ApplyPreset('border')
                        end,
                    },
                    presetOverlayOnly = {
                        order = 6,
                        type = 'execute',
                        name = 'Overlay Only',
                        width = 0.9,
                        func = function()
                            self:ApplyPreset('overlay')
                        end,
                    },
                    presetSpacer = {
                        order = 6.5,
                        type = 'description',
                        name = ' ',
                        width = 'full',
                    },
                    tankOneGroup = {
                        order = 12,
                        type = 'group',
                        guiInline = true,
                        name = function()
                            local tankName = self:GetAssignedTankNameForSlot(1) or 'Unassigned'
                            return ('Tank 1: %s'):format(tankName)
                        end,
                        width = 'half',
                        hidden = function() return not self.db.useCustomColor end,
                        args = {
                            color = {
                                order = 1,
                                type = 'color',
                                name = ' ',
                                desc = 'Custom color used for the first detected Main Tank.',
                                width = 'full',
                                get = function()
                                    local colors = self.db.customColors or DEFAULTS.customColors
                                    local color = colors[1] or DEFAULTS.customColors[1]
                                    return color.r, color.g, color.b
                                end,
                                set = function(_, r, g, b)
                                    self.db.customColors = self.db.customColors or {}
                                    self.db.customColors[1] = self.db.customColors[1] or {}
                                    self.db.customColors[1].r = r
                                    self.db.customColors[1].g = g
                                    self.db.customColors[1].b = b
                                    self:ClearAllCachedColors()
                                    self:ForceUpdatePlates()
                                end,
                            },
                        },
                    },
                    tankTwoGroup = {
                        order = 13,
                        type = 'group',
                        guiInline = true,
                        name = function()
                            local tankName = self:GetAssignedTankNameForSlot(2) or 'Unassigned'
                            return ('Tank 2: %s'):format(tankName)
                        end,
                        width = 'half',
                        hidden = function() return not self.db.useCustomColor end,
                        args = {
                            color = {
                                order = 1,
                                type = 'color',
                                name = ' ',
                                desc = 'Custom color used for the second detected Main Tank.',
                                width = 'full',
                                get = function()
                                    local colors = self.db.customColors or DEFAULTS.customColors
                                    local color = colors[2] or DEFAULTS.customColors[2]
                                    return color.r, color.g, color.b
                                end,
                                set = function(_, r, g, b)
                                    self.db.customColors = self.db.customColors or {}
                                    self.db.customColors[2] = self.db.customColors[2] or {}
                                    self.db.customColors[2].r = r
                                    self.db.customColors[2].g = g
                                    self.db.customColors[2].b = b
                                    self:ClearAllCachedColors()
                                    self:ForceUpdatePlates()
                                end,
                            },
                        },
                    },
                },
            },

            tools = {
                order = 4,
                type = 'group',
                name = 'Tools',
                guiInline = true,
                args = {
                    toolsInfo = {
                        order = 1,
                        type = 'description',
                        name = 'Debugging and manual refresh tools for testing visible plates.',
                        fontSize = 'medium',
                        width = 'full',
                    },
                    debug = {
						order = 2,
						type = 'toggle',
						name = 'Debug Output',
						desc = 'Print diagnostic messages in chat while testing.',
                        width = 'full',
					},
                    refresh = {
                        order = 3,
                        type = 'execute',
                        name = 'Refresh Plates',
                        desc = 'Force all visible nameplates to redraw immediately.',
                        width = 'full',
                        func = function()
                            self:ClearAllCachedColors()
                            self:ForceUpdatePlates()
                        end,
                    },
                    preview = {
                        order = 4,
                        type = 'execute',
                        name = 'Preview/Test',
                        desc = 'Temporarily show the current style on visible enemy plates.',
                        width = 'full',
                        func = function()
                            self:StartPreview(5)
                        end,
                    },
                    info = {
                        order = 5,
                        type = 'description',
                        name = 'Use Preview/Test to check the style instantly, or Refresh Plates if you want to force all visible nameplates to redraw immediately after changing settings.',
                        fontSize = 'medium',
                        width = 'full',
                    },
                },
            },
        }
    }
end

function MOD:Initialize()
    self:InitDB()
    self:SetupSlashCommands()
    EP:RegisterPlugin(addonName, function() self:InsertOptions() end)

    -- Ensure ElvUI Nameplates are enabled before installing hooks.
    if not (E.private and E.private.nameplates and E.private.nameplates.enable) then return end

    -- Ensure every nameplate gets our PostUpdate wrapper around ThreatIndicator.
    self:SecureHook(NP, 'Update_ThreatIndicator', 'UpdateThreatIndicatorHook')

	self:RegisterEvent('NAME_PLATE_UNIT_ADDED', 'HandlePlateEvent')
	self:RegisterEvent('UNIT_TARGET', 'HandlePlateEvent')
    self:RegisterEvent('UNIT_THREAT_LIST_UPDATE', 'HandlePlateEvent')
    self:RegisterEvent('UNIT_THREAT_SITUATION_UPDATE', 'HandlePlateEvent')

    self:ClearAllCachedColors()
    self:ForceUpdatePlates()
end

-- Register the module with ElvUI
E:RegisterModule(MOD:GetName())
