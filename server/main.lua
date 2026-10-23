local QBCore = exports['qb-core']:GetCoreObject()

local eventState = {
    active = false,
    coords = nil,
    radius = nil,
    label = nil,
    endsAt = 0,
    npcTotal = 0,
    killed = 0,
    pedNetIds = {},
    participants = {},
    startedAt = 0,
}
local groupHash = nil
local lastKillAt = {}

-- [v1.0.2] pcall guard: ken 7atta native ta3et, el event MA yo9ofch
local function safeCall(name, fn)
    local ok, a, b = pcall(fn)
    if not ok then
        print(('^1[qb-gameevent] native "%s" failed: %s^0'):format(name, tostring(a)))
    end
    return ok, a, b
end

-- ═══════════ STARTUP DIAGNOSTICS ═══════════
AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    CreateThread(function()
        Wait(2000)
        print('^2[qb-gameevent] ===== DIAGNOSTICS v1.0.2 =====^0')
        local okPed, ped = safeCall('CreatePed', function()
            return CreatePed(4, joaat('a_m_m_socenlat_01'), 0.0, 0.0, -1000.0, 0, true, true)
        end)
        local ready = false
        if okPed and ped and ped ~= 0 then
            local t = 0
            while t < 3000 and not DoesEntityExist(ped) do Wait(50) t = t + 50 end
            ready = DoesEntityExist(ped)
        end
        if ready then
            print('^2[qb-gameevent] OK: CreatePed server-side works (OneSync OK)^0')
            DeleteEntity(ped)
        else
            print('^1[qb-gameevent] FAIL: CreatePed server-side (OneSync OFF or artifacts < 5181)^0')
            print('^1  -> server.cfg: `set onesync on` BEFORE all ensure lines, then FULL restart^0')
            print('^1  -> txAdmin: Settings -> OneSync -> Infinity -> Save -> Restart server^0')
        end
        local okRel, _, gh = safeCall('AddRelationshipGroup', function()
            return AddRelationshipGroup('EVENT_TERRORISTS')
        end)
        if okRel and gh and gh ~= 0 then
            groupHash = gh
            print('^2[qb-gameevent] OK: Relationship group ready^0')
        else
            print('^3[qb-gameevent] NOTE: relationship natives not available server-side -> client fallback active^0')
        end
        print('^2[qb-gameevent] Command ready: /gameevent start — if "insufficient permissions" -> add `add_principal group.admin qb-gameevent.command.gameevent` to server.cfg^0')
        print('^2[qb-gameevent] ===============================^0')
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
    local ok, _, gh = safeCall('AddRelationshipGroup', function()
        return AddRelationshipGroup('EVENT_TERRORISTS')
    end)
    if ok and gh and gh ~= 0 then
        groupHash = gh
        pcall(function()
            local pg = GetHashKey('PLAYER')
            SetRelationshipBetweenGroups(5, groupHash, pg)
            SetRelationshipBetweenGroups(5, pg, groupHash)
        end)
    else
        groupHash = GetHashKey('EVENT_TERRORISTS')
    end
    return groupHash
end

-- ═══════════ SPAWN (v1.0.2: async-safe + pcall per native) ═══════════
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

        if not (ok and ped and ped ~= 0) then
            print('^1[qb-gameevent] CreatePed returned invalid handle - check OneSync (see diagnostics)^0')
        else
            -- [v1.0.2] OneSync: el ped yet-cree async - n-sennou
            local t = 0
            while t < 2000 and not DoesEntityExist(ped) do Wait(50) t = t + 50 end
            if not DoesEntityExist(ped) then
                print('^1[qb-gameevent] Ped not created after 2s (async fail)^0')
            else
                safeCall('SetPedRelationshipGroupHash', function() SetPedRelationshipGroupHash(ped, groupHash) end)
                safeCall('GiveWeaponToPed', function() GiveWeaponToPed(ped, weaponHash, 500, false, true) end)
                safeCall('SetPedMaxHealth', function() SetPedMaxHealth(ped, Config.NPCs.health) end)
                safeCall('SetEntityHealth', function() SetEntityHealth(ped, Config.NPCs.health) end)
                safeCall('SetPedArmour', function() SetPedArmour(ped, Config.NPCs.armor or 0) end)
                safeCall('SetPedAccuracy', function() SetPedAccuracy(ped, Config.NPCs.accuracy) end)
                safeCall('SetPedCombatAttributes', function() SetPedCombatAttributes(ped, 46, true) end)
                safeCall('SetPedCombatAttributes2', function() SetPedCombatAttributes(ped, 5, true) end)
                safeCall('SetPedFleeAttributes', function() SetPedFleeAttributes(ped, 0, false) end)

                eventState.npcTotal = eventState.npcTotal + 1
                eventState.pedNetIds[NetworkGetNetworkIdFromEntity(ped)] = true
            end
        end
    end
    return eventState.npcTotal
end

-- ═══════════ REGISTER KILL ═══════════
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
        print('[qb-gameevent] startEvent blocked: already active')
        return
    end

    local loc = Config.Locations[math.random(#Config.Locations)]
    eventState.active = true
    eventState.coords = loc.coords
    eventState.radius = loc.radius
    eventState.label = loc.label
    eventState.endsAt = os.time() + (Config.Duration or 15) * 60
    eventState.participants = {}
    eventState.startedAt = os.time()

    spawnEventPeds()

    local pedNetIds = {}
    for netId in pairs(eventState.pedNetIds) do pedNetIds[netId] = true end

    -- [v1.0.2] el broadcast dima yetb3ath — 7atta ken 0 NPCs, el zone/timer ybano
    -- (el NPCs y-configurew client-side 3ala 7sab el fallback)
    TriggerClientEvent('qb-gameevent:client:startEvent', -1, {
        label = loc.label,
        coords = loc.coords,
        radius = loc.radius,
        npcCount = eventState.npcTotal,
        pedNetIds = pedNetIds,
        endsAt = eventState.endsAt,
    })

    if eventState.npcTotal == 0 then
        print('^3[qb-gameevent] WARNING: 0 NPCs spawned (zone visible anyway) - check diagnostics above^0')
    else
        print(('^2[qb-gameevent] Event STARTED at %s (%d NPCs, ends in %d min)^0'):format(
            loc.label, eventState.npcTotal, Config.Duration or 15))
    end

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
        endsAt = eventState.endsAt,
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
