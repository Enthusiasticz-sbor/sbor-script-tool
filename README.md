# AutoFarmV3 refactor

## How to run

`Init.lua` is the only file loaded by hand. Every other file is a module spec
(`{ Name, Dependencies, Start }`) that `Init.lua` downloads and `loadstring`s
itself, so pointing an executor at a single feature file does nothing.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Endmin1strator/Automated-Industry-Complex/refs/heads/main/Init.lua"))()
```

That fetches `UI/Utils.lua` plus the 60 modules in `MODULES` in parallel (62
requests), compiles them, starts them dependency-first, then hands
`Context.Features` to Heartbeat. It needs an executor (`loadstring`,
`game:HttpGet`, `LocalPlayer`/`PlayerGui`); `getgenv` only enables the
re-execution guard, so Studio uses the local path instead.

- **The download base is hardcoded.** `BASE` at the top of `Init.lua` points at
  `Endmin1strator/Automated-Industry-Complex`, branch `main`, so loading a fork's
  `Init.lua` still runs that repo's modules until the constant is changed.
  `Core/Runtime.lua` holds a second copy of the URL for `UI/Utils.lua`, used only
  when something other than `Init.lua` starts Runtime.
- **Pin a version** by replacing `main` with a commit SHA
  (`.../<user>/<repo>/<sha>/Init.lua`), so an exact build can be re-run even
after a later push.
- **Running it twice** stops the previous run (`getgenv().AICSession`). A build
  from before that guard cannot be stopped and asks for a rejoin instead.
- A module that fails to fetch or compile shows `LOAD FAILED  //  ...` on the
  loading window and raises the error.

**Studio** loads the same tree locally: keep `Init` a ModuleScript and it
`require`s the sibling ModuleScripts in the same folder layout, no HTTP at all.

For what each feature does, what it needs before it will act, and what its status
line means when nothing happens, see [USAGE.md](USAGE.md).

## Modules in this revision

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
