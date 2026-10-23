# qb-gameevent

QBCore Game Event script (Terrorist Hunt style) — 100% server-authoritative.

## Requirements
- qb-core
- OneSync enabled (`set onesync on` in server.cfg)
- Server artifacts 5181+ (server-side CreatePed)

## Install
1. Copy folder `qb-gameevent` to `resources/[qb]/`
2. In server.cfg add AFTER qb-core: `ensure qb-gameevent`

## Commands
- `/gameevent start` — force start (admin)
- `/gameevent stop` — force stop (admin)

## Features
- Auto events (random 30-60 min interval, announce 10 min before)
- Random location (5 configurable zones) + random NPC count (4-8)
- Hostile NPCs (assault rifle, health/armor/accuracy configurable)
- Live HUD counter inside the zone + blip + radius on map
- Winner = most kills -> random cash + configurable item rewards
- New players joining mid-event get synced automatically

## Security (server-authoritative)
- NPCs spawned server-side (OneSync) — no ghost peds
- Kill detection: native `entityDie` + `GetPedSourceOfDeath` (0 client trust)
- Kill rate limit (400ms) + max kill distance (200m) + kill cap (50/event)
- Rewards only via server `AddMoney`/`AddItem`
- Full ped cleanup on event end AND resource stop/restart (no orphan peds)

## Config
Everything in `config.lua`: locations, NPC stats, rewards, timing, security thresholds.
