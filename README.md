# QuestMaster Companion

Small helper addon for **QuestMaster** on **WoW Forever**.

`0.8.3` is cleaned up for the newest QuestMaster update. QuestMaster is doing a lot more of the routing work itself now, so the Companion is back to only filling the few gaps we still care about.

## What is still here

### World marker opacity

QuestMaster normally fades its world marker hard when you get close to the target. The Companion adds **Far marker opacity** and **Arrival marker opacity** sliders directly under QuestMaster's existing World Marker settings.

The two values are the ends of the same fade. If both are 100%, the marker stays bright all the way in. If Far is 100% and Arrival is 60%, it smoothly fades toward 60% as you get close. QuestMaster's normal arrival-distance setting still decides where that close-range fade happens.

This does not change marker position, size, the arrival sparkle, or the navigation arrow.

### Blizzard live locations first

If Blizzard has a usable location for the quest you're actually doing, the Companion lets that win before an older/learned fallback.

This is mainly for Forever quests where the game map knows the real objective or hand-in but Discovery only has something broad like the old pickup/start point.

### Route import paste fix

WoW can hand pasted route text back out of an EditBox with `|` and `\` escaped. That can make a normal `QMROUTE|1` look broken before QuestMaster even gets to the real package.

The Companion only removes that one UI escape layer when it clearly sees an escaped QMROUTE, then gives the text right back to QuestMaster's normal decoder/checksum/validation.


### Coordinate-free route pickups

QuestMaster's route format allows an `ACCEPT` step to omit coordinates, but the current route engine asks the objective resolver when that happens instead of its existing quest-start resolver.

The Companion connects that missing seam. A coordinate-free `ACCEPT` uses QuestMaster's own `GetQuestStartLocations()` data (bundled DB first, then Discovery), preferring a pickup on the player's current map and then the nearest known pickup. Authored coordinates still win when a route deliberately includes them.

This lets normal quest steps stay location-free while trainer, travel, grind, vendor, and other deliberate route points can keep authored coordinates.

### Imported route ACCEPT sync

If an imported route is sitting on an `ACCEPT` step, Blizzard's live quest log gets first say when the quest was actually picked up.

`QUEST_ACCEPTED` can also move the current matching step along if QuestMaster's own quest cache is a little behind.

### Imported route waypoint hold

This is rebuilt for the newest QuestMaster instead of wrapping the whole auto-waypoint selector.

When QuestMaster sets a waypoint for the current imported-route step, the Companion tags it as a route waypoint. While that exact route step is still current, QuestMaster's normal manual-waypoint check treats it as valid.

So something like:

`Accept The Damned -> Accept Hallowed Scroll`

should stay on **Hallowed Scroll** instead of normal quest auto-navigation jumping over to a bat objective just because Hallowed is not in the quest log yet.

Once the route moves on, stops, or you manually pick something else, normal QuestMaster behavior takes over again.

### Imported route post-quest navigation

The newest QuestMaster also does a delayed normal-Guide navigation pass after accepting or turning in a quest. Normally that is useful, but it can replace an imported route's next pickup with an objective from the quest you just accepted.

While an imported route is running, the Companion lets the route re-check itself at that moment and keeps navigation on the route's current step. With no route running, QuestMaster's normal behavior is untouched.

### Remove imported route packages

QuestMaster already has `Library:Remove()` but still does not expose it in the normal route UI.

The Companion adds a small red `x` to user/imported packages in the Route Library and the Route Editor's Published list. Click it, confirm it, and QuestMaster's own remove function does the work.

Bundled/demo packages are left alone.

## What got removed in 0.8.0

The newest QuestMaster now handles the Guide-side stuff we were helping with, so the Companion no longer touches it:

- closest-useful-next-step Guide sorting
- pickup scan refreshes
- pickup clustering
- Guide rebuild nudges
- the old arrow cache refresh hack from 0.7.4

QuestMaster's current `UpdateArrow()` already refreshes its target cache correctly, so the Companion does not need to fake that anymore.

## Modules

```text
QuestMasterCompanion/
├─ Core.lua
├─ Modules/
│  ├─ LiveQuestData.lua
│  ├─ ObjectivePriority.lua
│  ├─ TurnInPriority.lua
│  ├─ RouteImportFix.lua
│  ├─ RouteRuntimeSync.lua
│  ├─ RouteAcceptLocation.lua
│  ├─ RouteWaypointSync.lua
│  ├─ RouteEventNavigation.lua
│  ├─ RouteLibraryRemove.lua
│  └─ WorldMarkerOpacity.lua
├─ Diagnostics.lua
├─ Commands.lua
├─ README.md
└─ CHANGELOG.md
```

Still modular. If QuestMaster picks one of these up later, that one module can come right back out.

## Commands

`/qmc status`  
Shows what is hooked and whether the Companion has actually had to step in.

`/qmc test <questID>`  
Shows Blizzard's live objective/turn-in answer beside QuestMaster's answer.

`/qmc off` / `/qmc on`  
Disables or enables the Companion hooks.

`/qmc notify on|off`  
Turns the small live-location notices on or off.

## Install

Put `QuestMasterCompanion` beside `QuestMaster` in:

```text
World of Warcraft/_classic_beta_/Interface/AddOns/
```

Enable both addons and `/reload`.
