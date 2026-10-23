local QBCore = exports['qb-core']:GetCoreObject()

local eventState = {
    active = false,
    coords = nil,
    radius = nil,
    label = nil,
    npcTotal = 0,
    killed = 0,
    pedNetIds = {},    -- [netId] = true (NPCs mte3 el event)
    participants = {}, -- [citizenid] = { kills, src, name }
    startedAt = 0,
}
local groupHash = nil
local lastKillAt = {} -- [src] = timer (rate limit)

-- ═══════════ CLEANUP ═══════════
local function cleanupPeds()
    for netId in pairs(eventState.pedNetIds) do
        local ent = NetworkGetEntityFromNetworkId(netId)
        if ent and ent ~= 0 then DeleteEntity(ent) end
    end
    eventState.pedNetIds = {}
end

-- ═══════════ RELATIONSHIP GROUP (NPCs hostile lel players) ═══════════
local function getGroupHash()
    if groupHash then return groupHash end
    groupHash = AddRelationshipGroup('EVENT_TERRORISTS')
    local playerGroup = GetHashKey('PLAYER')
    SetRelationshipBetweenGroups(5, groupHash, playerGroup) -- 5 = Hate
    SetRelationshipBetweenGroups(5, playerGroup, groupHash)
    return groupHash
end

-- ═══════════ SPAWN (server-side, OneSync) ═══════════
local function spawnEventPeds()
    getGroupHash()
    eventState.npcTotal = 0
    eventState.killed = 0
    eventState.pedNetIds = {}

    local count = math.random(Config.NPCs.count.min, Config.NPCs.count.max)
    local modelHash = joaat(Config.NPCs.model)
    local weaponHash = joaat(Config.NPCs.weapon)
    local z = eventState.coords.z + 1.0

    for _ = 1, count do
        local angle = math.random() * math.pi * 2
        local dist = math.random() * (Config.NPCs.spread or 40.0)
        local x = eventState.coords.x + math.cos(angle) * dist
        local y = eventState.coords.y + math.sin(angle) * dist

        local ped = CreatePed(4, modelHash, x, y, z, math.random(360), true, true)
        if ped and ped ~= 0 then
            SetPedRelationshipGroupHash(ped, groupHash)
            GiveWeaponToPed(ped, weaponHash, 500, false, true)
            SetPedMaxHealth(ped, Config.NPCs.health)
            SetEntityHealth(ped, Config.NPCs.health)
            SetPedArmour(ped, Config.NPCs.armor or 0)
            SetPedAccuracy(ped, Config.NPCs.accuracy)
            SetPedCombatAttributes(ped, 46, true)  -- always fight
            SetPedCombatAttributes(ped, 5, true)   -- can use vehicles
            SetPedFleeAttributes(ped, 0, false)     -- ma yferrech

            eventState.npcTotal = eventState.npcTotal + 1
            eventState.pedNetIds[NetworkGetNetworkIdFromEntity(ped)] = true
        end
    end
    return eventState.npcTotal
end

-- ═══════════ REGISTER KILL (hardened) ═══════════
local function registerKill(src)
    -- [SECURITY] rate limit per player
    local now = GetGameTimer()
    if lastKillAt[src] and (now - lastKillAt[src]) < (Config.Security.killRateLimitMs or 400) then
        return
    end
    lastKillAt[src] = now

    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local cid = Player.PlayerData.citizenid
    local p = eventState.participants[cid]
    if not p then
        p = {
            kills = 0,
            src = src,
            name = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname,
        }
        eventState.participants[cid] = p
    end

    -- [SECURITY] cap el kills per player
    if p.kills >= (Config.Security.maxKillsPerEvent or 50) then return end
    p.kills = p.kills + 1

    TriggerClientEvent('QBCore:Notify', src, ('Kill! Total: %d'):format(p.kills), 'success', 4000)
end

-- ═══════════ END EVENT ═══════════
function endEvent(reason)
    if not eventState.active then return end
    eventState.active = false

    -- REWARDS (server-only)
    local best = nil
    for _, p in pairs(eventState.participants) do
        if not best or p.kills > best.kills then best = p end
    end

    local winner, cash = nil, 0
    if best and best.kills > 0 then
        winner = best.name
        local Player = QBCore.Functions.GetPlayer(best.src)
        if Player then
            cash = math.random(Config.Rewards.cash.min, Config.Rewards.cash.max)
            Player.Functions.AddMoney('cash', cash, 'game-event-win')
            for _, item in ipairs(Config.Rewards.items) do
                if math.random(100) <= item.chance then
                    Player.Functions.AddItem(item.item, item.amount)
                    TriggerClientEvent('inventory:client:ItemBox', best.src, QBCore.Shared.Items[item.item], 'add')
                end
            end
        end
    end

    cleanupPeds()

    TriggerClientEvent('qb-gameevent:client:endEvent', -1, winner, reason, cash)
    print(('[qb-gameevent] Ended (%s) | Winner: %s ($%s)'):format(reason, winner or 'none', cash))

    eventState.participants = {}
    eventState.coords = nil
    eventState.label = nil
    lastKillAt = {}
end

-- ═══════════ KILL DETECTION (server-native, 0 client trust) ═══════════
AddEventHandler('entityDie', function(deadEntity)
    if not eventState.active or not DoesEntityExist(deadEntity) then return end

    local netId = NetworkGetNetworkIdFromEntity(deadEntity)
    if not eventState.pedNetIds[netId] then return end -- mouch NPC mte3na

    eventState.pedNetIds[netId] = nil
    eventState.killed = eventState.killed + 1

    local killerPed = GetPedSourceOfDeath(deadEntity)
    if killerPed and killerPed ~= 0 then
        -- [SECURITY] distance validation
        local victimCoords = GetEntityCoords(deadEntity)
        if #(GetEntityCoords(killerPed) - victimCoords) <= (Config.Security.maxKillDistance or 200.0) then
            for _, playerId in pairs(QBCore.Functions.GetPlayers()) do
                if GetPlayerPed(playerId) == killerPed then
                    registerKill(playerId)
                    break
                end
            end
        end
    end

    TriggerClientEvent('qb-gameevent:client:updateNpcCount', -1, eventState.npcTotal - eventState.killed)

    if eventState.npcTotal > 0 and eventState.killed >= eventState.npcTotal then
        endEvent('Zone cleared!')
    end
end)

-- ═══════════ START EVENT ═══════════
local function startEvent()
    if eventState.active then return end

    local loc = Config.Locations[math.random(#Config.Locations)]
    eventState.active = true
    eventState.coords = loc.coords
    eventState.radius = loc.radius
    eventState.label = loc.label
    eventState.participants = {}
    eventState.startedAt = os.time()

    spawnEventPeds()

    local pedNetIds = {}
    for netId in pairs(eventState.pedNetIds) do pedNetIds[netId] = true end

    TriggerClientEvent('qb-gameevent:client:startEvent', -1, {
        label = loc.label,
        coords = loc.coords,
        radius = loc.radius,
        npcCount = eventState.npcTotal,
        pedNetIds = pedNetIds,
    })

    print(('[qb-gameevent] Started at %s (%d NPCs)'):format(loc.label, eventState.npcTotal))

    SetTimeout((Config.Duration or 15) * 60 * 1000, function()
        if eventState.active then endEvent('Time up!') end
    end)
end

-- ═══════════ AUTO SCHEDULER ═══════════
local function scheduleNext()
    if not Config.AutoEvents then return end
    local waitMin = math.random(Config.EventInterval.min, Config.EventInterval.max)
    local announceMin = math.max(waitMin - (Config.AnnounceBefore or 10), 0)

    SetTimeout(announceMin * 60 * 1000, function()
        if not eventState.active then
            TriggerClientEvent('qb-gameevent:client:announce', -1,
                ('GAME EVENT fi %d min — 7ather rou7ek!'):format(Config.AnnounceBefore or 10))
        end
    end)

    SetTimeout(waitMin * 60 * 1000, function()
        if not eventState.active then startEvent() end
        scheduleNext()
    end)
end

CreateThread(function()
    Wait(30 * 1000)
    scheduleNext()
end)

-- ═══════════ SYNC LE PLAYERS EL JDOD ═══════════
RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    if not eventState.active then return end
    local src = source
    local pedNetIds = {}
    for netId in pairs(eventState.pedNetIds) do pedNetIds[netId] = true end
    TriggerClientEvent('qb-gameevent:client:syncEvent', src, {
        label = eventState.label,
        coords = eventState.coords,
        radius = eventState.radius,
        npcCount = eventState.npcTotal - eventState.killed,
        pedNetIds = pedNetIds,
    })
end)

-- ═══════════ ADMIN COMMANDS ═══════════
QBCore.Commands.Add('gameevent', 'Game Event (start/stop)', {
    { name = 'action', help = 'start | stop' }
}, true, function(source, args)
    local action = args[1]
    if action == 'start' then
        if eventState.active then
            TriggerClientEvent('QBCore:Notify', source, 'Event deja active!', 'error', 5000)
        else
            startEvent()
        end
    elseif action == 'stop' then
        endEvent('Stopped by admin')
    end
end, 'admin')

-- ═══════════ SAFETY: cleanup ki el resource yet7ebes ═══════════
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        eventState.active = false
        cleanupPeds()
    end
end)
