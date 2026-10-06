# Changelog

## 0.8.3 — 2026-10-05

- Cleaned up a bunch of the Companion stuff now that the newer QuestMaster updates handle some of it on their own. Basically removed some old fixes we don't really need anymore.
- Updated the route stuff to work with the newer setup where every quest doesn't need coordinates manually added to it. If QuestMaster already knows where a quest starts, the Companion can just use that.
- Fixed pasted QMROUTE packages sometimes getting messed up by WoW when you paste them in, which was causing the schema error.
- Fixed imported routes sometimes kinda getting stuck after you accepted a quest because QuestMaster hadn't caught up yet.
- Also fixed QuestMaster's normal Guide trying to take over an imported route after accepting or turning something in.
- ACCEPT steps should stay on the quest you're actually doing now. So if the route says **Accept The Damned -> Accept Hallowed Scroll**, it shouldn't randomly decide you need to go kill bats halfway through lol.
- Cleaned up the syncing between the route step, the world marker, and the navigation arrow so they're hopefully all pointing at the same thing more consistently.
- Added a little **x** so you can delete imported/custom route packages from the Route Library and Published list. It'll ask before deleting it, and it won't mess with the routes that come with QuestMaster.
- Kept the live Blizzard objective/turn-in checking too. So if the game itself knows a better/current location than what QuestMaster has saved, it'll use that instead.
- Added **Far Marker Opacity** and **Arrival Marker Opacity** sliders under the World Marker settings. 
- Both are at **100% by default**, but now you can change them separately if you actually like some of the fading, saved me from Squinting :X

## 0.6.3 — 2026-10-04

- Changed the location order so Blizzard's live quest info gets first say when it actually has a usable point.
- Objectives now use the live Blizzard waypoint/map point first, then QuestMaster's normal data, then a real learned Discovery objective. The old broad map/start fallback is only the last resort.
- A quest pickup/start point is no longer treated like a real learned objective just because Discovery did not have the objective yet.
- Live Blizzard objective points only replace the objective Blizzard actually knows about, so good QuestMaster locations for the rest of the quest stay in place.
- Turn-ins use the same idea now: Blizzard live turn-in first, QuestMaster's normal answer second, learned turn-in after that.
- The raw turn-in DB bridge follows the same order so the arrow/tracker/map do not disagree with the public resolver.
- `/qmc test` now shows live Blizzard objective data, real learned objective data, and the weak Discovery fallback separately so it is easier to see who is feeding the location.

## 0.6.2 — 2026-10-04

- Added a small next-step check after QuestMaster does its normal Guide rebuild.
- It now looks at the pickups, unfinished objectives, and ready turn-ins QuestMaster already has and makes sure the next one is actually the closest useful thing.
- So if QuestMaster wants to send you 1,000 yards away but you still have stuff 200-700 yards away, the Companion can pull the closer one up first.
- The little 120-yard quest hub rule still comes first, so nearby pickups/hand-ins stay together before it starts sending you out on objectives.
- The five-second pulse is still just the cheap nearby pickup/hand-in check. It does not rebuild the Guide or keep shuffling objectives while you run.
- Manual quest picks still win. If you click something yourself, the Companion leaves it alone.
- Added a route-fix count to `/qmc status` so it is easier to tell when this part actually stepped in.

## 0.6.1 — 2026-10-04

- Fixed the Guide Assist only helping right away when QuestMaster already picked a pickup first. It now checks the nearby Guide steps after the normal rebuild too.
- Nearby ready turn-ins are included with pickups now, so it should not send you 600+ yards away while there is a hand-in or pickup sitting right beside you.
- The five-second check still stays cheap. It only looks at the Guide steps already there and does not rebuild or rescan the quest DB.
- Manual waypoint picks still win, so if you click a quest yourself the Companion will not yank the arrow away from it.

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