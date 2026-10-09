return {
    Name = "AutoFind",
    IsFeature = true,
    Dependencies = {"Runtime", "SaveConfig", "Components"},

    Start = function(Context)
        local AICFeature = Context.AICFeature
        local AICCombat = Context.AICCombat
        local AICUI = Context.AICUI

        local Feature = {
            Name = "AutoFind",
            IsFeature = true,
        }

        function Feature:Update()
        end

        AICUI.BindFeatureToggle("AutoFind", "Auto Find", function(Enabled)
            AICFeature.S.WaypointEnabled = not Enabled
            AICCombat.S.ClosestTarget = nil
            table.clear(AICCombat.S.ValidMobs)
            table.clear(AICCombat.S.CombatGroupCache)
            AICCombat.ResetTargetReposition()
            AICCombat.UpdateValidMobs()
            AICCombat.S.ClosestTarget = AICCombat.AcquireCombatTarget(os.clock())
        end)

        return Feature
    end,
}
