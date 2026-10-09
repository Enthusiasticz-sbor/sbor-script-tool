# AutoFarmV3 refactor

This revision explicitly separates the feature modules requested:

- AutoFarming.lua
- AutoBlock.lua
- AutoSmithing.lua (Crafting tab included; with SmithingRecipes.lua and SmithingMinigame.lua)
- AutoPatrol.lua
- ReturnToFarmZone.lua
- IgnoreFarmZone.lua
- AutoHeal.lua
- AutoMining.lua (Mining tab controls included; with Minezone.lua and WalkController.lua)
- AutoRefill.lua (Refill Booster: resets when a boost runs out)
- SafeBoosterReset.lua
- AntiAFK.lua
- EnemyPriority.lua
- AutoSkill.lua
- AutoFind.lua
- SafeCombat.lua
- ResetStats.lua
- DebugVisualizer.lua
- Waypoints.lua
- Farmzone.lua
- Deadzone.lua

Waypoints, Farmzone and Deadzone are spatial sections/modules and are not part of Profile Settings.

## Saved values and adding a feature

`Core/SaveConfig.lua` declares everything a profile saves: `Features` lists every toggle (default and export key) and `Settings` lists every setting (default, range or options). Runtime, ProfileManager and the UI read from it, so nothing else needs editing to save, load, export or refresh a value.

To add a feature with a saved toggle:

1. Create `Features/MyFeature.lua` returning `{ Name = "MyFeature", Dependencies = {...}, Start = function(Context) ... end }`.
2. Add `"Features/MyFeature.lua"` to `MODULES` in `Init.lua` (download list and start order).
3. Add `{ Name = "MyFeature", Default = false, Key = "<unused letter>" }` to `SaveConfig.Features`.
4. In `Start`, call `Context.AICUI.BindFeatureToggle("MyFeature", "My Feature", OnChanged)` and read `Context.Feature.MyFeature.Enabled`.

AutoSmithing implements crafting from the smithing proof of concept (CraftingStart + the strike minigame).

`Legacy/` contains the original reviewed files for comparison. `Core/Runtime.lua` is retained as a compatibility layer while the large legacy implementation is migrated feature-by-feature without silently inventing behavior.
"# Automated-Industry-Complex" 
