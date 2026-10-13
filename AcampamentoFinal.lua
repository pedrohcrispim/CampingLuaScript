--============================================================
-- SISTEMA DE CAMPING UNIFICADO (v4)
--============================================================

--------------------------------------------------------------
-- CONFIGURAÇÕES GERAIS
--------------------------------------------------------------
local ITEM_KIT       = 90002
local ITEM_FISHBOWL  = 90003

local CAMP_DURATION       = 900        -- 15 min (duração dos objetos do acampamento)
local BUFF_RADIUS         = 15         -- yards considerados "no acampamento"
local SHARED_COOLDOWN     = 3600       -- 1 hora — TODAS as features compartilham isso
local TICK_INTERVAL       = 10000      -- ms, só usado pra limpar o registro do acampamento

-- Objetos visuais
local GO_TENT      = 184592
local GO_ANVIL     = 900010   -- clone customizado (type = 10, Goober, data zerados)
local GO_CAMPFIRE  = 29784    

-- NPCs vendedores por facção
local NPC_ALLIANCE = 5178
local NPC_HORDE    = 3168

-- Skills
local SKILL_FISHING = 356
local MIN_FISHING   = 20

-- Buffs por profissão
local PROFESSION_BUFFS = {
    [164] = { name = "Blacksmithing",  spellId = 8076,  minSkill = 1 }, -- Str
    [165] = { name = "Leatherworking", spellId = 6673,  minSkill = 1 }, -- AP
    [171] = { name = "Alchemy",        spellId = 1459,  minSkill = 1 }, -- Int
    [197] = { name = "Tailoring",      spellId = 21562, minSkill = 1 }, -- Stam
}

local FISHBOWL_BUFF  = 25898   -- Blessing of Kings 

--------------------------------------------------------------
--------------------------------------------------------------
local ACTIVE_CAMPS   = {} -- [ownerGuid] = { mapId, x, y, z, expireAt }
local CAMP_COOLDOWNS = {} -- [playerGuid] = timestamp de expiração do cooldown compartilhado

--------------------------------------------------------------
--------------------------------------------------------------
local function CheckAndSetCampCooldown(player)
    local guid = player:GetGUIDLow()
    local now = os.time()

    if CAMP_COOLDOWNS[guid] and now < CAMP_COOLDOWNS[guid] then
        local remaining = CAMP_COOLDOWNS[guid] - now
        player:SendBroadcastMessage("Camping features are on cooldown for " .. remaining .. "s.")
        return false
    end

    CAMP_COOLDOWNS[guid] = now + SHARED_COOLDOWN
    return true
end

--------------------------------------------------------------
--------------------------------------------------------------
local function FindNearbyCamp(player)
    for _, c in pairs(ACTIVE_CAMPS) do
        if c.mapId == player:GetMapId() and player:GetDistance(c.x, c.y, c.z) <= BUFF_RADIUS then
            return c
        end
    end
    return nil
end

--------------------------------------------------------------
--------------------------------------------------------------
local function BroadcastProfessionBuff(triggeringPlayer, camp)
    local matched = nil
    for sId, data in pairs(PROFESSION_BUFFS) do
        if triggeringPlayer:GetSkillValue(sId) >= data.minSkill then
            matched = data
            break
        end
    end

    if not matched then
        triggeringPlayer:SendBroadcastMessage("You don't have a profession that can be used here.")
        return
    end

    local players = GetPlayersInWorld()
    for _, p in pairs(players) do
        if p:GetMapId() == camp.mapId and p:GetDistance(camp.x, camp.y, camp.z) <= BUFF_RADIUS then
            p:CastSpell(p, matched.spellId, true)
        end
    end

    triggeringPlayer:SendBroadcastMessage(
        string.format("You use your %s skills at the camp, granting everyone nearby a buff!", matched.name)
    )
end

--------------------------------------------------------------
--------------------------------------------------------------
local function OnUseAnvil(event, go, player)
    local camp = FindNearbyCamp(player)
    if camp and CheckAndSetCampCooldown(player) then
        BroadcastProfessionBuff(player, camp)
    end
    return true -- bloqueia qualquer ação padrão herdada
end
RegisterGameObjectEvent(GO_ANVIL, 14, OnUseAnvil) -- 14 = GAMEOBJECT_EVENT_ON_USE

--------------------------------------------------------------
--------------------------------------------------------------
local function SetupCamp(event, player, item, target)
    if not CheckAndSetCampCooldown(player) then
        return false
    end

    local x, y, z, o = player:GetLocation()
    local mapId = player:GetMapId()
    local guid = player:GetGUIDLow()

    local tentX = x - (4 * math.cos(o))
    local tentY = y - (4 * math.sin(o))
    player:SummonGameObject(GO_TENT, tentX, tentY, z, o, CAMP_DURATION)

    local anvilX = x + (3 * math.cos(o - 1.5))
    local anvilY = y + (3 * math.sin(o - 1.5))
    player:SummonGameObject(GO_ANVIL, anvilX, anvilY, z, o, CAMP_DURATION)

    local npcIdToSummon = NPC_ALLIANCE
    if player:GetTeam() == 1 then
        npcIdToSummon = NPC_HORDE
    end

    local npcX = x + (2 * math.cos(o + 1.5))
    local npcY = y + (2 * math.sin(o + 1.5))
    player:SpawnCreature(npcIdToSummon, npcX, npcY, z, o, 4, CAMP_DURATION * 1000)

    player:CastSpell(player, 818, true) -- invoca a fogueira (GO 29784) — UMA ÚNICA VEZ
    player:PerformEmote(15)
    player:SendBroadcastMessage("You have set up your camp!")

    local camp = {
        mapId = mapId,
        x = x, y = y, z = z,
        expireAt = os.time() + CAMP_DURATION
    }
    ACTIVE_CAMPS[guid] = camp

   
    player:RegisterEvent(function(eventId, delay, repeats, p)
        if os.time() >= camp.expireAt then
            ACTIVE_CAMPS[guid] = nil
            p:RemoveEventById(eventId)
        end
    end, TICK_INTERVAL, 0)

    return false
end
RegisterItemEvent(ITEM_KIT, 2, SetupCamp)

--------------------------------------------------------------
--------------------------------------------------------------
local function UseFishBowl(event, player, item, target)
    if player:GetSkillValue(SKILL_FISHING) < MIN_FISHING then
        player:SendBroadcastMessage("Requires Fishing (20).")
        return false
    end

    local fire = player:GetNearestGameObject(BUFF_RADIUS, GO_CAMPFIRE)
    if not fire then
        player:SendBroadcastMessage("Requires a Campfire nearby.")
        return false
    end

    if not CheckAndSetCampCooldown(player) then
        return false
    end

    local x, y, z = player:GetLocation()
    local players = GetPlayersInWorld()
    for _, p in pairs(players) do
        if p:GetMapId() == player:GetMapId() and p:GetDistance(x, y, z) <= BUFF_RADIUS then
            if p:GetStandState() == 6 then -- confirme esse valor testando in-game
                p:CastSpell(p, FISHBOWL_BUFF, true)
            end
        end
    end

    player:SendBroadcastMessage("You set up a small fish bowl. Sit nearby to gain the buff!")
    return true
end
RegisterItemEvent(ITEM_FISHBOWL, 2, UseFishBowl)
