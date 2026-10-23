local QBCore = exports['qb-core']:GetCoreObject()

local eventActive = false
local eventCoords, eventRadius = nil, nil
local eventNetIds = {}
local npcsAlive = 0
local blip, radiusBlip = nil, nil

local function removeBlips()
    if blip then RemoveBlip(blip) blip = nil end
    if radiusBlip then RemoveBlip(radiusBlip) radiusBlip = nil end
end

-- a9rab player 9rib lel ped (bech el NPC ye7ajem el 9rib)
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

-- ═══════════ ANNOUNCE (X min 9bal) ═══════════
RegisterNetEvent('qb-gameevent:client:announce', function(msg)
    QBCore.Functions.Notify(msg, 'primary', 10000)
end)

-- ═══════════ START EVENT ═══════════
RegisterNetEvent('qb-gameevent:client:startEvent', function(data)
    eventActive = true
    eventCoords = data.coords
    eventRadius = data.radius
    eventNetIds = data.pedNetIds or {}
    npcsAlive = data.npcCount or 0

    setupBlips(data.label, data.coords, data.radius)

    QBCore.Functions.Notify(('GAME EVENT: %s — %d enemies!'):format(data.label, npcsAlive), 'success', 10000)
    PlaySoundFrontend(-1, 'Event_Start_Text', 'GTAO_FM_Events_Soundset', false)
end)

-- player dakhel w el event 9a3ed → sync
RegisterNetEvent('qb-gameevent:client:syncEvent', function(data)
    eventActive = true
    eventCoords = data.coords
    eventRadius = data.radius
    eventNetIds = data.pedNetIds or {}
    npcsAlive = data.npcCount or 0
    setupBlips(data.label, data.coords, data.radius)
end)

RegisterNetEvent('qb-gameevent:client:updateNpcCount', function(count)
    npcsAlive = count
end)

-- ═══════════ END EVENT ═══════════
RegisterNetEvent('qb-gameevent:client:endEvent', function(winner, reason, cash)
    eventActive = false
    eventCoords = nil
    eventRadius = nil
    eventNetIds = {}
    removeBlips()

    if winner then
        QBCore.Functions.Notify(('Event end: %s | Winner: %s ($%d)'):format(reason, winner, cash or 0), 'primary', 8000)
    else
        QBCore.Functions.Notify('Event end: ' .. reason, 'error', 8000)
    end
    PlaySoundFrontend(-1, 'ScreenFlash', 'MissionEnd_Events', false)
end)

-- ═══════════ AI COMBAT LOOP ═══════════
-- kol client 9rib el zone yse3mel TaskCombatPed lel NPC 3la a9rab player
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
                        local target = getNearestPlayerToPed(ped, eventRadius + 50.0)
                        if target then
                            TaskCombatPed(ped, target, 0, 16)
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

-- ═══════════ HUD (counter ki enta fel zone) ═══════════
CreateThread(function()
    while true do
        local sleep = 1000
        if eventActive and eventCoords and npcsAlive > 0 then
            local dist = #(GetEntityCoords(PlayerPedId()) - eventCoords)
            if dist < eventRadius then
                sleep = 0
                SetTextFont(4)
                SetTextScale(0.45, 0.45)
                SetTextColour(255, 80, 80, 255)
                BeginTextCommandDisplayText('STRING')
                AddTextComponentSubstringPlayerName(('GAME EVENT — Enemies: %d'):format(npcsAlive))
                EndTextCommandDisplayText(0.015, 0.75)
            end
        end
        Wait(sleep)
    end
end)
