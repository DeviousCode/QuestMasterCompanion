# Changelog

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
