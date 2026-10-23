Config = {}

-- ================= SCHEDULER =================
Config.AutoEvents = true
Config.EventInterval = { min = 30, max = 60 } -- minutes bin events (random)
Config.AnnounceBefore = 10                    -- announce X min 9bal el event
Config.Duration = 15                          -- event duration (minutes)

-- ================= LOCATIONS =================
Config.Locations = {
    { label = 'Ocean Docks',         coords = vector3(842.31, -2079.42, 30.87), radius = 100.0 },
    { label = 'Grapeseed Farm',      coords = vector3(2444.32, 4969.51, 42.35), radius = 120.0 },
    { label = 'Sandy Shores Hangar', coords = vector3(1732.01, 3286.71, 41.29), radius = 100.0 },
    { label = 'Paleto Bay Beach',    coords = vector3(-243.21, 6337.23, 32.36), radius = 120.0 },
    { label = 'Mount Chiliad Base',  coords = vector3(452.53, 5567.14, 781.12), radius = 80.0  },
}

-- ================= NPCs =================
Config.NPCs = {
    model    = 'g_m_m_chigoon_01',
    health   = 200,
    armor    = 100,
    weapon   = 'WEAPON_ASSAULTRIFLE',
    accuracy = 40,              -- % hit rate
    count    = { min = 4, max = 8 },
    spread   = 40.0,             -- meters mte3 spawn random fel zone
}

-- ================= REWARDS (winner = most kills) =================
Config.Rewards = {
    cash = { min = 5000, max = 15000 },
    items = {
        { item = 'weapon_pistol',    amount = 1, chance = 100 },
        { item = 'advancedlockpick', amount = 2, chance = 50  },
        { item = 'gold_bar',         amount = 1, chance = 25  },
    },
}

-- ================= SECURITY (anti-exploit) =================
Config.Security = {
    maxKillDistance  = 200.0, -- killer lazem 9rib lel victim (meters)
    killRateLimitMs  = 400,   -- min wa9t bin kills per player
    maxKillsPerEvent = 50,    -- cap el kills per player per event
}
