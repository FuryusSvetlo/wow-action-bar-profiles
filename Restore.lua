local addonName, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)
local DEBUG = "|cffff0000Debug:|r "

local S2KFI = LibStub("LibS2kFactionalItems-1.0")

function addon:GetProfiles(filter, case)
    local list = self.db.profile.list
    local sorted = {}

    local name, profile

    for name, profile in pairs(list) do
        if not filter or name == filter or (case and name:lower() == filter:lower()) then
            profile.name = name
            table.insert(sorted, profile)
        end
    end

    if #sorted > 1 then
        local class = select(2, UnitClass("player"))

        table.sort(sorted, function(a, b)
            if a.class == b.class then
                return a.name < b.name
            else
                return a.class == class
            end
        end)
    end

    return unpack(sorted)
end

function addon:UseProfile(profile, check, cache)
    if type(profile) ~= "table" then
        local list = self.db.profile.list
        profile = list[profile]

        if not profile then
            return 0, 0
        end
    end

    cache = cache or self:MakeCache()

    local res = { fail = 0, total = 0 }

    if not profile.skipMacros then
        self:RestoreMacros(profile, check, cache, res)
    end

    -- hack: save talents
    local talents = cache.talents

    if not profile.skipTalents then
        self:RestoreTalents(profile, check, cache, res)
    end

    if not profile.skipActions then
        self:RestoreActions(profile, check, cache, res)
    end

    if not profile.skipPetActions then
        self:RestorePetActions(profile, check, cache, res)
    end

    if not profile.skipBindings then
        self:RestoreBindings(profile, check, cache, res)
    end

    -- hack: restore talents
    cache.talents = talents

    if not check then
        if PaperDollActionBarProfilesPane and PaperDollActionBarProfilesPane:IsShown() then
            self:ScheduleTimer(function()
                PaperDollActionBarProfilesPane:Update()
            end, 0.1)
        end
    end

    return res.fail, res.total
end

function addon:RestoreMacros(profile, check, cache, res)
    local fail, total = 0, 0

    if res then
        res.fail = res.fail + fail
        res.total = res.total + total
    end

    return fail, total
end

function addon:RestoreTalents(profile, check, cache, res)
    local fail, total = 0, 0

    -- hack: update cache
    local talents = { id = {}, name = {} }
    local rest = IsResting()

    local tier
    for tier = 1, MAX_TALENT_TIERS do
        local link = profile.talents[tier]
        if link then
            -- has action
            local ok
            total = total + 1

            local data, name = link:match("^|c.+|H(.+)|h%[(.+)%]|h|r$")
            link = link:gsub("|Habp:.+|h(%[.+%])|h", "%1")

            if data then
                local type, sub = strsplit(":", data, 3)
                local id = tonumber(sub)

                if type == "talent" then
                    local found = self:GetFromCache(cache.allTalents[tier], id, name, not check and link)
                    if found then
                        if rest or self:GetFromCache(cache.talents, id) then
                            ok = true

                            if rest then
                                -- hack: update cache
                                self:UpdateCache(talents, found, id, name)

                                if not check then
                                    LearnTalent(found)
                                end
                            end
                        else
                            self:cPrintf(not check, L.msg_cant_learn_talent, link)
                        end
                    else
                        self:cPrintf(not check, L.msg_talent_not_exists, link)
                    end
                else
                    self:cPrintf(not check, L.msg_bad_link, link)
                end
            else
                self:cPrintf(not check, L.msg_bad_link, link)
            end

            if not ok then
                fail = fail + 1
            end
        end
    end

    -- hack: update cache
    if rest then
        cache.talents = talents
    end

    if res then
        res.fail = res.fail + fail
        res.total = res.total + total
    end

    return fail, total
end

function addon:RestoreActions(profile, check, cache, res)
    local fail, total = 0, 0

    local slot
    for slot = 1, ABP_MAX_ACTION_BUTTONS do
        local link = profile.actions[slot]
        if link then
            -- has action
            local ok
            total = total + 1

            local data, name = link:match("^|c.+|H(.+)|h%[(.+)%]|h|r$")
            link = link:gsub("|Habp:.+|h(%[.+%])|h", "%1")

            if data then
                local type, sub, p1, p2, p7 = table.s2k_select({ strsplit(":", data) }, 1, 2, 3, 4, 8)
                local id = tonumber(sub)

                if type == "spell" then
                    if id == ABP_RANDOM_MOUNT_SPELL_ID then
                        ok = true

                        if not check then
                            self:PickupAndPlaceMount(slot, 0, link)
                        end
                    else
                        local found = self:FindSpellInCache(cache.spells, id, name, not check and link)
                        if found then
                            ok = true

                            if not check then
                                self:PickupAndPlaceSpell(slot, found, link)
                            end
                        end
                    end

                    self:cPrintf(not ok and not check, L.msg_spell_not_exists, link)

                elseif type == "talent" then
                    local found = self:GetFromCache(cache.talents, id, name, not check and link)
                    if found then
                        ok = true

                        if not check then
                            self:PickupAndPlaceTalent(slot, found, link)
                        end
                    end

                    self:cPrintf(not ok and not check, L.msg_spell_not_exists, link)

                elseif type == "item" then
                    if PlayerHasToy(id) then
                        ok = true

                        if not check then
                            self:PickupAndPlaceItem(slot, id, link)
                        end
                    else
                        local found = self:FindItemInCache(cache.equip, id, name, not check and link)
                        if found then
                            ok = true

                            if not check then
                                self:PickupAndPlaceInventoryItem(slot, found, link)
                            end
                        else
                            found = self:FindItemInCache(cache.bags, id, name, not check and link)
                            if found then
                                ok = true

                                if not check then
                                    self:PickupAndPlaceContainerItem(slot, found[1], found[2], link)
                                end
                            end
                        end
                    end

                    if not ok and not check then
                        self:PickupAndPlaceItem(slot, S2KFI:GetConvertedItemId(id) or id, link)
                    end

                    ok = true   -- sic!

                elseif type == "battlepet" then
                    local found = self:GetFromCache(cache.pets, p7, id, not check and link)
                    if found then
                        ok = true

                        if not check then
                            self:PickupAndPlacePet(slot, found, link)
                        end
                    end

                elseif type == "abp" then
                    id = tonumber(p1)

                    if sub == "flyout" then
                        local found = self:FindFlyoutInCache(cache.flyouts, id, name, not check and link)
                        if found then
                            ok = true

                            if not check then
                                self:PickupAndPlaceSpellBookItem(slot, found, BOOKTYPE_SPELL, link)
                            end
                        end

                        self:cPrintf(not ok and not check, L.msg_spell_not_exists, link)

                    elseif sub == "macro" then

                    elseif sub == "equip" then

                    else
                        self:cPrintf(not check, L.msg_bad_link, link)
                    end
                else
                    self:cPrintf(not check, L.msg_bad_link, link)
                end
            else
                self:cPrintf(not check, L.msg_bad_link, link)
            end

            if not ok then
                fail = fail + 1

                if not check then
                    self:ClearSlot(slot)
                end
            end
        else
            -- empty slot
            if not check then
                self:ClearSlot(slot)
            end
        end
    end

    if res then
        res.fail = res.fail + fail
        res.total = res.total + total
    end

    return fail, total
end

function addon:RestorePetActions(profile, check, cache, res)
    if not HasPetSpells() or not profile.petActions then
        return 0, 0
    end

    local fail, total = 0, 0

    local slot
    for slot = 1, NUM_PET_ACTION_SLOTS do
        local link = profile.petActions[slot]
        if link then
            -- has action
            local ok
            total = total + 1

            local data, name = link:match("^|c.+|H(.+)|h%[(.+)%]|h|r$")
            link = link:gsub("|Habp:.+|h(%[.+%])|h", "%1")

            if data then
                local type, sub, p1 = strsplit(":", data, 4)
                local id = tonumber(sub)

                if type == "spell" or (type == "abp" and sub == "pet") then
                    if type == "spell" then
                        name = GetSpellInfo(id) or name
                    else
                        id = -2
                        name = _G[name] or name
                    end

                    local found = self:GetFromCache(cache.petSpells, id, name, type == "spell" and link)
                    if found then
                        ok = true

                        if not check then
                            self:PickupAndPlacePetSpell(slot, found, link)
                        end
                    end
                else
                    self:cPrintf(not check, L.msg_bad_link, link)
                end
            else
                self:cPrintf(not check, L.msg_bad_link, link)
            end

            if not ok then
                fail = fail + 1

                if not check then
                    self:ClearPetSlot(slot)
                end
            end
        else
            -- empty slot
            if not check then
                self:ClearPetSlot(slot)
            end
        end
    end

    if res then
        res.fail = res.fail + fail
        res.total = res.total + total
    end

    return fail, total
end

function addon:RestoreBindings(profile, check, cache, res)
    if check then
        return 0, 0
    end

    -- clear
    local index
    for index = 1, GetNumBindings() do
        local bind = { GetBinding(index) }
        if bind[3] then
            local key
            for key in pairs({ select(3, unpack(bind)) }) do
                SetBinding(key)
            end
        end
    end

    -- restore
    local cmd, keys
    for cmd, keys in pairs(profile.bindings) do
        local key
        for key in table.s2k_values(keys) do
            SetBinding(key, cmd)
        end
    end

    if LibStub("AceAddon-3.0"):GetAddon("Dominos", true) and profile.bindingsDominos then
        for index = 13, 60 do
            local key

            -- clear
            for key in table.s2k_values({ GetBindingKey(string.format("CLICK DominosActionButton%d:LeftButton", index)) }) do
                SetBinding(key)
            end

            -- restore
            if profile.bindingsDominos[index] then
                for key in table.s2k_values(profile.bindingsDominos[index]) do
                    SetBindingClick(key, string.format("DominosActionButton%d", index), "LeftButton")
                end
            end
        end
    end

    SaveBindings(GetCurrentBindingSet())

    return 0, 0
end

function addon:UpdateCache(cache, value, id, name)
    cache.id[id] = value

    if cache.name and name then
        cache.name[name] = value
    end
end

function addon:GetFromCache(cache, id, name, link)
    if cache.id[id] then
        return cache.id[id]
    end

    if cache.name and name and cache.name[name] then
        --self:cPrintf(link, DEBUG .. L.msg_found_by_name, link)
        return cache.name[name]
    end
end

function addon:FindSpellInCache(cache, id, name, link)
    name = GetSpellInfo(id) or name

    local found = self:GetFromCache(cache, id, name, link)
    if found then
        return found
    end

    local similar = ABP_SIMILAR_SPELLS[id]
    if similar then
        local alt
        for alt in table.s2k_values(similar) do
            local found = self:GetFromCache(cache, id)
            if found then
                return found
            end
        end
    end
end

function addon:FindFlyoutInCache(cache, id, name, link)
    name = GetFlyoutInfo(id) or name

    local found = self:GetFromCache(cache, id, name, link)
    if found then
        return found
    end
end

function addon:FindItemInCache(cache, id, name, link)
    local found = self:GetFromCache(cache, id, name, link)
    if found then
        return found
    end

    local alt = S2KFI:GetConvertedItemId(id)
    if alt then
        found = self:GetFromCache(cache, alt)
        if found then
            return found
        end
    end

    local similar = ABP_SIMILAR_ITEMS[id]
    if similar then
        for alt in table.s2k_values(similar) do
            found = self:GetFromCache(cache, alt)
            if found then
                return found
            end
        end
    end
end

function addon:MakeCache()
    local cache = {
        talents = { id = {}, name = {} },
        allTalents = {},

        spells = { id = {}, name = {} },
        flyouts = { id = {}, name = {} },

        equip = { id = {}, name = {} },
        bags = { id = {}, name = {} },

        pets = { id = {}, name = {} },

        petSpells = { id = {}, name = {} },
    }

    self:PreloadTalents(cache.talents, cache.allTalents)

    self:PreloadSpecialSpells(cache.spells)
    self:PreloadSpellbook(cache.spells, cache.flyouts)
    self:PreloadMountjournal(cache.spells)

    self:PreloadEquip(cache.equip)
    self:PreloadBags(cache.bags)

    self:PreloadPetJournal(cache.pets)

    self:PreloadPetSpells(cache.petSpells)

    return cache
end

function addon:PreloadSpecialSpells(spells)
    local level = UnitLevel("player")
    local class = select(2, UnitClass("player"))
    local faction = UnitFactionGroup("player")
    local spec = GetSpecializationInfo(GetSpecialization())

    local id, info
    for id, info in pairs(ABP_SPECIAL_SPELLS) do
        if (not info.level or level >= info.level) and
            (not info.class or class == info.class) and
            (not info.faction or faction == info.faction) and
            (not info.spec or spec == info.spec)
        then
            self:UpdateCache(spells, id, id)

            if info.altSpellIds then
                local alt
                for alt in table.s2k_values(info.altSpellIds) do
                    self:UpdateCache(spells, id, alt)
                end
            end
        end
    end
end

function addon:PreloadSpellbook(spells, flyouts)
    local tabs = {}

    local book
    for book = 1, GetNumSpellTabs() do
        local offset, count, _, spec = select(3, GetSpellTabInfo(book))

        if spec == 0 then
            table.insert(tabs, { type = BOOKTYPE_SPELL, offset = offset, count = count })
        end
    end

    local prof
    for prof in table.s2k_values({ GetProfessions() }) do
        if prof then
            local count, offset = select(5, GetProfessionInfo(prof))

            table.insert(tabs, { type = BOOKTYPE_PROFESSION, offset = offset, count = count })
        end
    end

    local tab
    for tab in table.s2k_values(tabs) do
        local index
        for index = tab.offset + 1, tab.offset + tab.count do
            local type, id = GetSpellBookItemInfo(index, tab.type)
            local name = GetSpellBookItemName(index, tab.type)

            if type == "FLYOUT" then
                self:UpdateCache(flyouts, index, id, name)
            else
                self:UpdateCache(spells, id, id, name)
            end
        end
    end
end

function addon:PreloadMountjournal(mounts)
    local all = C_MountJournal.GetMountIDs()
    local faction = (UnitFactionGroup("player") == "Alliance" and 1) or 0

    local mount
    for mount in table.s2k_values(all) do
        local name, id, required, collected = table.s2k_select({ C_MountJournal.GetMountInfoByID(mount) }, 1, 2, 9, 11)

        if collected and (not required or required == faction) then
            self:UpdateCache(mounts, id, id, name)
        end
    end
end

function addon:PreloadTalents(talents, all)
    local tier
    for tier = 1, MAX_TALENT_TIERS do
        all[tier] = all[tier] or { id = {}, name = {} }

        if GetTalentTierInfo(tier, 1) then

            local column
            for column = 1, NUM_TALENT_COLUMNS do
                local id, name, _, selected = GetTalentInfo(tier, column, 1)

                if selected then
                    self:UpdateCache(talents, id, id, name)
                end

                self:UpdateCache(all[tier], id, id, name)
            end
        end
    end
end

function addon:PreloadEquip(equip)
    local slot
    for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        local id = GetInventoryItemID("player", slot)
        if id then
            self:UpdateCache(equip, slot, id, GetItemInfo(id))
        end
    end
end

function addon:PreloadBags(bags)
    local bag
    for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
        local index
        for index = 1, GetContainerNumSlots(bag) do
            local id = GetContainerItemID(bag, index)
            if id then
                self:UpdateCache(bags, { bag, index }, id, GetItemInfo(id))
            end
        end
    end
end

function addon:PreloadPetJournal(pets)
    local saved = self:SavePetJournalFilters()

    C_PetJournal.ClearSearchFilter()

    C_PetJournal.SetFilterChecked(LE_PET_JOURNAL_FILTER_COLLECTED, true)
    C_PetJournal.SetFilterChecked(LE_PET_JOURNAL_FILTER_NOT_COLLECTED, false)

    C_PetJournal.SetAllPetSourcesChecked(true)
    C_PetJournal.SetAllPetTypesChecked(true)

    local index
    for index = 1, C_PetJournal:GetNumPets() do
        local id, species = C_PetJournal.GetPetInfoByIndex(index)
        self:UpdateCache(pets, id, id, name)
    end

    self:RestorePetJournalFilters(saved)
end

function addon:PreloadPetSpells(spells)
    if HasPetSpells() then
        local index
        for index = 1, HasPetSpells() do
            local type, id = GetSpellBookItemInfo(index, BOOKTYPE_PET)
            local name = GetSpellBookItemName(index, BOOKTYPE_PET)

            if type == "PETACTION" then
                self:UpdateCache(spells, index, -1, name)
            else
                self:UpdateCache(spells, index, id, name)
            end
        end
    end
end

function addon:ClearSlot(slot)
    ClearCursor()
    PickupAction(slot)
    ClearCursor()
end

function addon:PlaceToSlot(slot)
    PlaceAction(slot)
    ClearCursor()
end

function addon:ClearPetSlot(slot)
    ClearCursor()
    PickupPetAction(slot)
    ClearCursor()
end

function addon:PlaceToPetSlot(slot)
    PickupPetAction(slot)
    ClearCursor()
end

function addon:PickupAndPlaceSpell(slot, id, link, count)
    count = count or ABP_PICKUP_RETRY_COUNT

    ClearCursor()
    PickupSpell(id)

    if not CursorHasSpell() then
        if count > 0 then
            self:ScheduleTimer(function()
                self:PickupAndPlaceSpell(slot, id, link, count - 1)
            end, ABP_PICKUP_RETRY_INTERVAL)
        else
            self:cPrintf(link, DEBUG .. L.msg_cant_place_spell, link)
        end
    else
        self:PlaceToSlot(slot)
    end
end

function addon:PickupAndPlaceSpellBookItem(slot, id, tab, link, count)
    count = count or ABP_PICKUP_RETRY_COUNT

    ClearCursor()
    PickupSpellBookItem(id, tab)

    if not CursorHasSpell() then
        if count > 0 then
            self:ScheduleTimer(function()
                self:PickupAndPlaceSpellBookItem(slot, id, tab, link, count - 1)
            end, ABP_PICKUP_RETRY_INTERVAL)
        else
            self:cPrintf(link, DEBUG .. L.msg_cant_place_spell, link)
        end
    else
        self:PlaceToSlot(slot)
    end
end

function addon:PickupAndPlaceTalent(slot, id, link, count)
    count = count or ABP_PICKUP_RETRY_COUNT

    ClearCursor()
    PickupTalent(id)

    if not CursorHasSpell() then
        if count > 0 then
            self:ScheduleTimer(function()
                self:PickupAndPlaceTalent(slot, id, link, count - 1)
            end, ABP_PICKUP_RETRY_INTERVAL)
        else
            self:cPrintf(link, DEBUG .. L.msg_cant_place_spell, link)
        end
    else
        self:PlaceToSlot(slot)
    end
end

function addon:PickupAndPlaceMount(slot, id, link, count)
    ClearCursor()
    C_MountJournal.Pickup(id)

    self:PlaceToSlot(slot)
end

function addon:PickupAndPlaceItem(slot, id, link, count)
    ClearCursor()
    PickupItem(id)

    self:PlaceToSlot(slot)
end

function addon:PickupAndPlaceInventoryItem(slot, id, link, count)
    count = count or ABP_PICKUP_RETRY_COUNT

    ClearCursor()
    PickupInventoryItem(id)

    if not CursorHasItem() then
        if count > 0 then
            self:ScheduleTimer(function()
                self:PickupAndPlaceInventoryItem(slot, id, link, count - 1)
            end, ABP_PICKUP_RETRY_INTERVAL)
        else
            self:cPrintf(link, DEBUG .. L.msg_cant_place_item, link)
        end
    else
        self:PlaceToSlot(slot)
    end
end

function addon:PickupAndPlaceContainerItem(slot, bag, id, link, count)
    count = count or ABP_PICKUP_RETRY_COUNT

    ClearCursor()
    PickupContainerItem(bag, id)

    if not CursorHasItem() then
        if count > 0 then
            self:ScheduleTimer(function()
                self:PickupAndPlaceContainerItem(slot, id, link, count - 1)
            end, ABP_PICKUP_RETRY_INTERVAL)
        else
            self:cPrintf(link, DEBUG .. L.msg_cant_place_item, link)
        end
    else
        self:PlaceToSlot(slot)
    end
end

function addon:PickupAndPlacePet(slot, id, link, count)
    ClearCursor()
    C_PetJournal.PickupPet(id)

    self:PlaceToSlot(slot)
end

function addon:PickupAndPlacePetSpell(slot, id, link, count)
    ClearCursor()
    PickupSpellBookItem(id, BOOKTYPE_PET)

    self:PlaceToPetSlot(slot)
end