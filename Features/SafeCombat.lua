return {
    Name = "SafeCombat",
    IsFeature = true,
    Dependencies = {"Runtime", "SaveConfig", "Components"},

    Start = function(Context)
        local AICCombat = Context.AICCombat
        local AICUI = Context.AICUI

        local Feature = {
            Name = "SafeCombat",
            IsFeature = true,
        }

        function Feature:Update()
        end

        AICUI.BindFeatureToggle("SafeCombat", "Safe Combat", function(Enabled)
            AICCombat.S.SafeCombatPositionEnabled = Enabled
            AICCombat.ResetTargetReposition()
        end)

        return Feature
    end,
}
