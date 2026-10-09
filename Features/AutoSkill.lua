return {
    Name = "AutoSkill",
    IsFeature = true,
    Dependencies = {"Runtime", "SaveConfig", "Components"},

    Start = function(Context)
        local AICUI = Context.AICUI

        local Feature = {
            Name = "AutoSkill",
            IsFeature = true,
        }

        function Feature:Update()
        end

        --// Read by PerformCombatActions through Feature.AutoSkill.Enabled.
        AICUI.BindFeatureToggle("AutoSkill", "Auto Skill")

        return Feature
    end,
}
