-- AutoRefill owns the "Refill Booster" toggle (saved as ResetOnBoostOut) and
-- the boost watcher behind it: when the EXP or drop boost runs out, the
-- character is reset so the game refills it.
return {
    Name = "AutoRefill",
    IsFeature = true,
    Dependencies = {"Runtime", "SaveConfig", "ProfileManager", "Components"},
    Start = function(Context)
        local Runtime = Context.Runtime
        local Player = Context.Player
        local FeatureState = Context.Feature
        local AICFeature = Context.AICFeature
        local AICUI = Context.AICUI

        --// Saved under its original name so existing profiles and exported
        --// text keep their value.
        local FEATURE_NAME = "ResetOnBoostOut"
        local BOOST_NAMES = { "Boost", "BoostDrops" }

        local Feature = {
            Name = "AutoRefill",
            IsFeature = true,
        }

        local function ResetOnBoostOut(Boost)
            --// The connection lives for the whole session, so the toggle is
            --// read when the boost changes, not when it was connected.
            if not FeatureState[FEATURE_NAME].Enabled or Boost.Value ~= 0 then
                return
            end

            --// Resolved at fire time. The connection outlives respawns, so a
            --// Humanoid captured at setup would be the dead one.
            local _, Humanoid = Runtime:GetCharacter()

            if Humanoid then
                Humanoid.Health = 0
            end
        end

        function Feature.AutoRefillBooster()
            task.spawn(function()
                local PlayerStats = Player:WaitForChild("PlayerStats")

                for _, BoostName in ipairs(BOOST_NAMES) do
                    local Boost = PlayerStats:FindFirstChild(BoostName)

                    if Boost then
                        table.insert(
                            AICFeature.S.BoosterConnections,
                            Boost:GetPropertyChangedSignal("Value"):Connect(function()
                                ResetOnBoostOut(Boost)
                            end)
                        )
                    end
                end
            end)
        end

        AICFeature.AutoRefillBooster = Feature.AutoRefillBooster

        function Feature:Update()
            --// Event driven: the watcher is connected once at start. Calling
            --// it from here added new connections on every Heartbeat.
        end

        AICUI.BindFeatureToggle(FEATURE_NAME, "Refill Booster")
        Feature.AutoRefillBooster()

        --// Also holds Safe Booster Reset's watcher; PlayerStats outlives this run.
        Context.Lifetime.OnEnd(function()
            Context.Lifetime.Disconnect(AICFeature.S.BoosterConnections)
        end)

        return Feature
    end,
}
