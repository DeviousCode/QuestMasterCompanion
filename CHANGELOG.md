# Changelog

## 0.6.0 — 2026-10-04

- Added `GuideAssist.lua` to help QuestMaster a little with nearby quest pickups without messing with or replacing its normal route planner.
- Accepting, turning in, or removing a quest, leveling up, or changing zones can now refresh the pickup scan and let QuestMaster rebuild like normal.
- Added a small 5 second check for pickup steps the Guide already knows about. It isn't scanning the whole quest DB or rebuilding everything every 5 seconds.
- Nearby quest pickups should now get grouped together before it starts sending you off to do objectives. So if you're standing in a little quest hub, it should grab the quests around you first instead of sending you running off right away.
- Added `/qmc refresh` so I can manually refresh the pickup scan while testing stuff.
- Added a turn-in DB bridge so QuestMaster stuff that reads `DB:GetQuestTurnInLocations()` directly can still get the Companion fallback.
- Fixed the objective fallback shutting itself off just because one quest happened to work normally. Another quest can still hit the empty table problem.
- Same fix for the turn-in fallback.
- Live turn-in locations now get cleared when quest stuff changes or when entering the world so old locations don't just sit around.
- Updated `/qmc status` and `/qmc test` with the new Guide Assist and turn-in bridge info.

## 0.5.0 — 2026-10-04

- Protected a manually selected quest during the short zone-change window where QuestMaster's `activeQuests` cache can be empty.
- Merged verified ready turn-ins into every Guide rebuild for the current map, even when that map also contains normal accepts/objectives.
- Added destination-aware tracker filtering for cross-zone turn-ins and objectives.
- Added tracker destination status and counters to `/qmc status`.

## 0.4.0 — 2026-10-03

- Added sticky manual quest navigation across Guide rebuilds and zone/map changes.
- Added local ready-turn-in rescue for the current map.

## 0.3.0 — 2026-10-02

- Stopped using a quest's pickup/start point as a turn-in fallback.
- Added Blizzard live quest-map fallback using `GetQuestUiMapID()` and `C_QuestLog.GetQuestsOnMap()`.
- Added turn-in upstream-fix detection.

## 0.2.0 — 2026-10-01

- Added learned turn-in fallback for unknown quests.
- Made objective and turn-in wrappers retire independently.

## 0.1.0 — 2026-10-01

- Initial learned-objective fallback and compatibility checks.
