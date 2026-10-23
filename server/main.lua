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

-- ═══════════ STARTUP DIAGNOSTICS (v1.0.1) ═══════════
local function safeCall(name, fn)
    local ok, result = pcall(fn)
    if not ok then
        print(('^1[qb-gameevent] ERROR: native "%s" failed: %s^0'):format(name, tostring(result)))
    end
    return ok, result
end

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    CreateThread(function()
        Wait(2000)
        print('^2[qb-gameevent] ===== DIAGNOSTICS v1.0.1 =====^0')
        local okPed, ped = safeCall('CreatePed', function()
            return CreatePed(4, joaat('a_m_m_socenlat_01'), 0.0, 0.0, -1000.0, 0, true, true)
        end)
        if okPed and ped and ped ~= 0 then
            print('^2[qb-gameevent] OK: CreatePed server-side works (OneSync OK)^0')
            DeleteEntity(ped)
        else
            print('^1[qb-gameevent] FAIL: CreatePed server-side failed!^0')
            print('^1  -> Check: `set onesync on` in server.cfg (no quotes) BEFORE any `ensure` line^0')
            print('^1  -> Check: server artifacts 5181+ (txAdmin -> Dashboard -> version)^0')
        end
        local okGroup = safeCall('AddRelationshipGroup', function()
            groupHash = AddRelationshipGroup('EVENT_TERRORISTS')
            local playerGroup = GetHashKey('PLAYER')
            SetRelationshipBetweenGroups(5, groupHash, playerGroup)
            SetRelationshipBetweenGroups(5, playerGroup, groupHash)
        end)
        if okGroup then print('^2[qb-gameevent] OK: Relationship group created^0') end
        print('^2[qb-gameevent] /gameevent command registered. If chat says "Access denied": add `add_principal group.admin qb-gameevent.command.gameevent` to server.cfg and restart.^0')
        print('^2[qb-gameevent] ================================^0')
    end)
end)

-- ═══════════ CLEANUP ═══════════
local function cleanupPeds()
    for netId in pairs(eventState.pedNetIds) do
        local ent = NetworkGetEntityFromNetworkId(netId)
        if ent and ent ~= 0 then DeleteEntity(ent) end
    end
    eventState.pedNetIds = {}
end

-- ═══════════ RELATIONSHIP GROUP ═══════════
local function getGroupHash()
    if groupHash then return groupHash end
    groupHash = AddRelationshipGroup('EVENT_TERRORISTS')
    local playerGroup = GetHashKey('PLAYER')
    SetRelationshipBetweenGroups(5, groupHash, playerGroup)
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

        local ok, ped = safeCall('CreatePed', function()
            return CreatePed(4, modelHash, x, y, z, math.random(360), true, true)
        end)
        if ok and ped and ped ~= 0 then
            SetPedRelationshipGroupHash(ped, groupHash)
            GiveWeaponToPed(ped, weaponHash, 500, false, true)
            SetPedMaxHealth(ped, Config.NPCs.health)
            SetEntityHealth(ped, Config.NPCs.health)
            SetPedArmour(ped, Config.NPCs.armor or 0)
            SetPedAccuracy(ped, Config.NPCs.accuracy)
            SetPedCombatAttributes(ped, 46, true)
            SetPedCombatAttributes(ped, 5, true)
            SetPedFleeAttributes(ped, 0, false)

            eventState.npcTotal = eventState.npcTotal + 1
            eventState.pedNetIds[NetworkGetNetworkIdFromEntity(ped)] = true
        else
            print('^1[qb-gameevent] FAIL: NPC spawn failed - check OneSync + artifacts (see diagnostics)^0')
        end
    end
    return eventState.npcTotal
end

-- ═══════════ REGISTER KILL (hardened) ═══════════
local function registerKill(src)
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

    if p.kills >= (Config.Security.maxKillsPerEvent or 50) then return end
    p.kills = p.kills + 1

    TriggerClientEvent('QBCore:Notify', src, ('Kill! Total: %d'):format(p.kills), 'success', 4000)
end

-- ═══════════ END EVENT ═══════════
function endEvent(reason)
    if not eventState.active then return end
    eventState.active = false

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

-- ═══════════ KILL DETECTION ═══════════
AddEventHandler('entityDie', function(deadEntity)
    if not eventState.active or not DoesEntityExist(deadEntity) then return end

    local netId = NetworkGetNetworkIdFromEntity(deadEntity)
    if not eventState.pedNetIds[netId] then return end

    eventState.pedNetIds[netId] = nil
    eventState.killed = eventState.killed + 1

    local killerPed = GetPedSourceOfDeath(deadEntity)
    if killerPed and killerPed ~= 0 then
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
    if eventState.active then
        print('[qb-gameevent] startEvent blocked: event already active')
        return
    end

    local loc = Config.Locations[math.random(#Config.Locations)]
    eventState.active = true
    eventState.coords = loc.coords
    eventState.radius = loc.radius
    eventState.label = loc.label
    eventState.participants = {}
    eventState.startedAt = os.time()

    spawnEventPeds()

    if eventState.npcTotal == 0 then
        print('^1[qb-gameevent] START FAILED: 0 NPCs spawned - event aborted. Check diagnostics in console.^0')
        eventState.active = false
        eventState.coords = nil
        return
    end

    local pedNetIds = {}
    for netId in pairs(eventState.pedNetIds) do pedNetIds[netId] = true end

    TriggerClientEvent('qb-gameevent:client:startEvent', -1, {
        label = loc.label,
        coords = loc.coords,
        radius = loc.radius,
        npcCount = eventState.npcTotal,
        pedNetIds = pedNetIds,
    })

    print(('^2[qb-gameevent] Event STARTED at %s (%d NPCs, %d players notified)^0'):format(
        loc.label, eventState.npcTotal, #QBCore.Functions.GetPlayers()))

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
                ('GAME EVENT fi %d min - 7ather rou7ek!'):format(Config.AnnounceBefore or 10))
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
    print(('[qb-gameevent] /gameevent called by source %s, action=%s'):format(tostring(source), tostring(action)))
    if action == 'start' then
        if eventState.active then
            TriggerClientEvent('QBCore:Notify', source, 'Event deja active!', 'error', 5000)
        else
            startEvent()
        end
    elseif action == 'stop' then
        endEvent('Stopped by admin')
    else
        TriggerClientEvent('QBCore:Notify', source, 'Usage: /gameevent start|stop', 'error', 5000)
    end
end, 'admin')

-- ═══════════ SAFETY ═══════════
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        eventState.active = false
        cleanupPeds()
    end
end)
