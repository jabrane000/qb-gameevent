local QBCore = exports['qb-core']:GetCoreObject()

local eventActive = false
local eventCoords, eventRadius, eventLabel = nil, nil, nil
local eventEndsAt = 0
local eventNetIds = {}
local npcsAlive = 0
local blip, radiusBlip = nil, nil
local configuredPeds = {}
local enemyGroup = nil

-- ═══════════ LOADED FEEDBACK (v1.0.2) ═══════════
AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    print('^2[qb-gameevent] client v1.0.2 loaded OK^0')
    TriggerEvent('chat:addMessage', { color = { 0, 200, 0 }, args = { '[qb-gameevent]', 'client v1.0.2 loaded OK' } })
end)

-- ═══════════ HELPERS ═══════════
local function removeBlips()
    if blip then RemoveBlip(blip) blip = nil end
    if radiusBlip then RemoveBlip(radiusBlip) radiusBlip = nil end
end

local function getEnemyGroup()
    if enemyGroup then return enemyGroup end
    local ok, _, gh = pcall(AddRelationshipGroup, 'EVENT_TERRORISTS_CL')
    enemyGroup = (ok and gh and gh ~= 0) or GetHashKey('EVENT_TERRORISTS_CL')
    pcall(function()
        local pg = GetHashKey('PLAYER')
        SetRelationshipBetweenGroups(5, enemyGroup, pg)
        SetRelationshipBetweenGroups(5, pg, enemyGroup)
    end)
    return enemyGroup
end

-- [v1.0.2] ped config local (client owner) — fallback ken server natives ma famech
local function configurePed(ped)
    if configuredPeds[ped] then return end
    configuredPeds[ped] = true
    pcall(function()
        SetPedRelationshipGroupHash(ped, getEnemyGroup())
        GiveWeaponToPed(ped, joaat(Config.NPCs.weapon), 500, false, true)
        SetPedArmour(ped, Config.NPCs.armor or 0)
        SetPedAccuracy(ped, Config.NPCs.accuracy)
        SetPedCombatAttributes(ped, 46, true)
        SetPedCombatAttributes(ped, 5, true)
        SetPedFleeAttributes(ped, 0, false)
    end)
end

local function getNearestPlayerToPed(ped, maxDist)
    local pedCoords = GetEntityCoords(ped)
    local closest, closestDist = nil, maxDist
    for _, playerId in ipairs(GetActivePlayers()) do
        local pPed = GetPlayerPed(playerId)
        if pPed ~= ped and not IsPedDeadOrDying(pPed, true) then
            local d = #(GetEntityCoords(pPed) - pedCoords)
            if d < closestDist then closest, closestDist = pPed, d end
        end
    end
    return closest
end

local function setupBlips(label, coords, radius)
    removeBlips()
    blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, 437)
    SetBlipColour(blip, 1)
    SetBlipScale(blip, 1.2)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Game Event: ' .. label)
    EndTextCommandSetBlipName(blip)

    radiusBlip = AddBlipForRadius(coords.x, coords.y, coords.z, radius)
    SetBlipColour(radiusBlip, 1)
    SetBlipAlpha(radiusBlip, 80)
end

-- ═══════════ EVENTS ═══════════
RegisterNetEvent('qb-gameevent:client:announce', function(msg)
    QBCore.Functions.Notify(msg, 'primary', 10000)
    TriggerEvent('chat:addMessage', { color = { 255, 180, 0 }, args = { '[GAME EVENT]', msg } })
end)

RegisterNetEvent('qb-gameevent:client:startEvent', function(data)
    eventActive = true
    eventCoords = data.coords
    eventRadius = data.radius
    eventLabel = data.label
    eventEndsAt = data.endsAt or (os.time() + (Config.Duration or 15) * 60)
    eventNetIds = data.pedNetIds or {}
    npcsAlive = data.npcCount or 0
    configuredPeds = {}

    setupBlips(data.label, data.coords, data.radius)

    QBCore.Functions.Notify(('GAME EVENT: %s - %d enemies!'):format(data.label, npcsAlive), 'success', 10000)
    TriggerEvent('chat:addMessage', { color = { 255, 60, 60 }, args = { '[GAME EVENT]', ('%s - %d enemies!'):format(data.label, npcsAlive) } })
    PlaySoundFrontend(-1, 'Event_Start_Text', 'GTAO_FM_Events_Soundset', false)
end)

RegisterNetEvent('qb-gameevent:client:syncEvent', function(data)
    eventActive = true
    eventCoords = data.coords
    eventRadius = data.radius
    eventLabel = data.label
    eventEndsAt = data.endsAt or (os.time() + (Config.Duration or 15) * 60)
    eventNetIds = data.pedNetIds or {}
    npcsAlive = data.npcCount or 0
    setupBlips(data.label, data.coords, data.radius)
end)

RegisterNetEvent('qb-gameevent:client:updateNpcCount', function(count)
    npcsAlive = count
end)

RegisterNetEvent('qb-gameevent:client:endEvent', function(winner, reason, cash)
    eventActive = false
    eventCoords, eventRadius, eventLabel = nil, nil, nil
    eventEndsAt = 0
    eventNetIds = {}
    configuredPeds = {}
    removeBlips()

    if winner then
        QBCore.Functions.Notify(('Event end: %s | Winner: %s ($%d)'):format(reason, winner, cash or 0), 'primary', 8000)
    else
        QBCore.Functions.Notify('Event end: ' .. reason, 'error', 8000)
    end
    PlaySoundFrontend(-1, 'ScreenFlash', 'MissionEnd_Events', false)
end)

-- ═══════════ AI COMBAT LOOP ═══════════
CreateThread(function()
    while true do
        local sleep = 1500
        if eventActive and eventCoords then
            local myCoords = GetEntityCoords(PlayerPedId())
            if #(myCoords - eventCoords) < (eventRadius + 50.0) then
                sleep = 500
                for netId in pairs(eventNetIds) do
                    local ped = NetworkGetEntityFromNetworkId(netId)
                    if ped ~= 0 and DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                        configurePed(ped)
                        local target = getNearestPlayerToPed(ped, eventRadius + 50.0)
                        if target then TaskCombatPed(ped, target, 0, 16) end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

-- ═══════════ HUD v1.0.2: timer + zone sphere + enemies ═══════════
CreateThread(function()
    while true do
        local sleep = 500
        if eventActive and eventCoords then
            sleep = 0
            local myCoords = GetEntityCoords(PlayerPedId())
            local dist = #(myCoords - eventCoords)
            local inZone = dist < eventRadius

            -- [v1.0.2] el zone: sphere a7mar teraha ki tkoun 9rib
            if dist < (eventRadius + 200.0) then
                DrawMarker(28, eventCoords.x, eventCoords.y, eventCoords.z,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    eventRadius, eventRadius, eventRadius,
                    255, 50, 50, 60, false, false, 2, nil, nil, false)
            end

            -- [v1.0.2] countdown timer + enemies counter
            local remaining = math.max(eventEndsAt - os.time(), 0)
            local mins = math.floor(remaining / 60)
            local secs = remaining % 60
            SetTextFont(4)
            SetTextScale(0.42, 0.42)
            SetTextColour(255, 80, 80, 255)
            SetTextOutline()
            BeginTextCommandDisplayText('STRING')
            local line = ('GAME EVENT: %s  |  %02d:%02d'):format(eventLabel or '?', mins, secs)
            if inZone then line = line .. ('  |  Enemies: %d'):format(npcsAlive) end
            AddTextComponentSubstringPlayerName(line)
            EndTextCommandDisplayText(0.015, 0.72)
        end
        Wait(sleep)
    end
end)
