-- FollowerGuard notices someone who keeps ending up in your server and gets
-- the run out of there before a stranger watches a bot farm: the same player
-- seen in your servers again and again inside FOLLOWER_WINDOW is following
-- you, and on a trip ServerHop joins another public server, leaving them
-- behind with the farm still running. Only when that cannot happen -- no
-- other server, the server list could not be read, the teleport was refused
-- -- does the old hold come back: Auto Farm goes off and stays off. Only a
-- real click on the Auto Farm toggle turns it back on -- a profile load sets
-- the flag directly and is never obeyed while the hold is on -- and turning
-- it on by hand also moves the count's start, so the same old sightings
-- cannot trip it straight away.
--
--   Sighting    one player in one server: someone already here when the
--               guard starts ("present"), or someone joining while it runs
--               ("joined"). "Present" counts once per player and server for
--               as long as the log remembers it, so re-running the script in
--               the same server cannot make a bystander look like a follower.
--   Trip        FOLLOWER_TRIP_SIGHTINGS sightings of one player inside the
--               window. A trip leaves the server; the same player seen again
--               FOLLOWER_RETRIP_COOLDOWN later is left for again, so someone
--               who follows us to the next server is left there too.
--   Exempt      you, the Block Whitelist and the Party Leader -- those are
--               people who are meant to be around you (the Leader is even
--               followed on purpose).
--
-- Sightings and the hold live in FOLLOWER_FILE, shared by every profile and
-- PlaceId like MobDrops.json, so the window carries across server hops and
-- re-runs of the script. The player is never blocked or reported: the guard
-- only leaves.
return {
    Name = "FollowerGuard",
    IsFeature = true,
    Dependencies = {"Runtime", "SaveConfig", "Components", "ProfileManager", "AutoBlock", "ServerHop"},

    Start = function(Context)
        local Services = Context.Services
        local Players = Services.Players
        local HttpService = Services.HttpService
        local Player = Context.Player
        local Feature = Context.Feature
        local CONFIG = Context.CONFIG
        local AICFeature = Context.AICFeature
        local AICUI = Context.AICUI
        local AICProfile = Context.AICProfile
        local ServerHop = Context.ServerHop
        local NotifyAction = Context.NotifyAction
        local UIRef = Context.UIRef

        --// How far back sightings still count as "following you".
        local FOLLOWER_WINDOW = 30 * 60
        --// Sightings of one player inside the window that trip the guard.
        local FOLLOWER_TRIP_SIGHTINGS = 2
        --// One player is left for once per this: the sightings that tripped
        --// it are still inside the window, so seen again straight away is
        --// the same trip, not a new one. Someone who really followed us to
        --// the next server is left there too once this has passed.
        local FOLLOWER_RETRIP_COOLDOWN = 60
        --// The same player arriving in the same server again within this is
        --// one arrival seen twice (script re-run, replication hiccup), not
        --// two. Only "joined" sightings are deduped by it: "present" is
        --// already once per player and server.
        local SIGHTING_DEDUPE = 60
        --// Sightings older than this are forgotten on every write, so the
        --// file cannot grow without bound.
        local FOLLOWER_KEEP = 24 * 60 * 60
        --// Saved sightings and the hold, shared by every profile and PlaceId.
        local FOLLOWER_FILE = Context.PROFILE_FOLDER .. "/FollowerLog.json"
        local FOLLOWER_FILE_VERSION = 1

        local FollowerGuard = {
            Name = "FollowerGuard",
            IsFeature = true,
            S = {
                --// { UserId, Name, Time, JobId, Kind } oldest first.
                Sightings = {},
                --// Auto Farm was stopped for a follower and is held off
                --// until someone turns it on by hand. Only set when the
                --// guard could not leave the server for them.
                Latched = false,
                LatchedAt = 0,
                LatchedBy = {},
                --// Sightings from before this never trip again; moved to
                --// "now" when Auto Farm is turned on by hand.
                CountFrom = 0,
                --// UserId -> os.time() of its last trip, so the sightings
                --// that tripped the guard cannot trip it again at once.
                Tripped = {},
                --// The roster is scanned once the profile (and with it the
                --// whitelist) is loaded, not before.
                Scanned = false,
                --// Last seen toggle value: a profile load can switch it on
                --// without firing the bind's callback, so the off -> on
                --// edge is also watched in Update.
                WasEnabled = nil,
                SaveQueued = false,
                NoticeAt = 0,
            },
        }

        local S = FollowerGuard.S

        --// The Auto Block whitelist and the Party Leader are never counted.
        local function IsExempt(OtherPlayer)
            if OtherPlayer == Player then
                return true
            end

            if AICFeature.IsWhitelisted ~= nil and AICFeature.IsWhitelisted(OtherPlayer.UserId) == true then
                return true
            end

            local Leader = CONFIG.PARTY_LEADER

            return type(Leader) == "table" and tonumber(Leader.UserId) == OtherPlayer.UserId
        end

        --// Sightings older than FOLLOWER_KEEP are dropped; anything malformed
        --// in the file is dropped with them rather than trusted.
        local function NormalizeSightings(Value)
            local Result = {}

            for _, Entry in ipairs(type(Value) == "table" and Value or {}) do
                local UserId = type(Entry.UserId) == "string" and Entry.UserId or nil
                local Time = tonumber(Entry.Time)
                local JobId = type(Entry.JobId) == "string" and Entry.JobId or nil
                local Kind = Entry.Kind

                if UserId and Time and JobId and (Kind == "present" or Kind == "joined") then
                    table.insert(Result, {
                        UserId = UserId,
                        Name = type(Entry.Name) == "string" and Entry.Name or UserId,
                        Time = Time,
                        JobId = JobId,
                        Kind = Kind,
                    })
                end
            end

            return Result
        end

        local function WriteLog()
            if not AICProfile.CanUseFileStorage() then
                return false
            end

            AICProfile.EnsureProfileFolder()

            --// Prune as the log is written: nothing old enough to have aged
            --// out is kept, and the pair check ("present" once per server)
            --// only ever looks at what is still remembered.
            local Now = os.time()
            local Kept = {}

            for _, Entry in ipairs(S.Sightings) do
                if Now - Entry.Time <= FOLLOWER_KEEP then
                    table.insert(Kept, Entry)
                end
            end

            S.Sightings = Kept

            local Success, Raw = pcall(function()
                return HttpService:JSONEncode({
                    Version = FOLLOWER_FILE_VERSION,
                    Latched = S.Latched,
                    LatchedAt = S.LatchedAt,
                    LatchedBy = S.LatchedBy,
                    CountFrom = S.CountFrom,
                    Sightings = S.Sightings,
                })
            end)

            if not Success then
                warn("AutoFarm follower log encode failed:", Raw)
                return false
            end

            local WriteSuccess, WriteError = pcall(writefile, FOLLOWER_FILE, Raw)

            if not WriteSuccess then
                warn("AutoFarm follower log save failed:", WriteError)
                return false
            end

            S.SaveQueued = false
            return true
        end

        local function QueueLog()
            S.SaveQueued = true
        end

        --// A queued write must not die with the run.
        Context.Lifetime.OnEnd(function()
            if S.SaveQueued then
                WriteLog()
            end
        end)

        local function LoadLog()
            if not AICProfile.CanUseFileStorage() then
                return
            end

            local CheckSuccess, Exists = pcall(isfile, FOLLOWER_FILE)

            if not CheckSuccess or not Exists then
                return
            end

            local Success, Decoded = pcall(function()
                return HttpService:JSONDecode(readfile(FOLLOWER_FILE))
            end)

            if not Success or type(Decoded) ~= "table" then
                warn("AutoFarm follower log read failed:", Decoded)
                return
            end

            S.Sightings = NormalizeSightings(Decoded.Sightings)
            S.Latched = Decoded.Latched == true
            S.LatchedAt = tonumber(Decoded.LatchedAt) or 0
            S.LatchedBy = type(Decoded.LatchedBy) == "table" and Decoded.LatchedBy or {}
            S.CountFrom = tonumber(Decoded.CountFrom) or 0
        end

        --// Sightings of this player that still count: inside the window and
        --// from the current era (after the last by-hand re-enable).
        local function CountSightings(UserId, Now)
            local Count = 0

            for _, Entry in ipairs(S.Sightings) do
                if Entry.UserId == UserId
                    and Entry.Time >= math.max(S.CountFrom, Now - FOLLOWER_WINDOW)
                    and Entry.Time <= Now
                then
                    Count += 1
                end
            end

            return Count
        end

        --// Turns Auto Farm off now instead of waiting for the next frame,
        --// and saves the profile so what is on disk says off too. Update
        --// keeps it off for as long as the hold is set.
        local function StopFarm()
            if AICFeature.S.Enabled then
                AICFeature.S.Enabled = false
                AICUI.updateButton()
                AICProfile.SaveActiveProfile()
            end
        end

        --// The guard could not get us out of the server: fall back to the
        --// hold, so a follower is never farmed in front of. This notice is
        --// never cooled down like the trip's: it arrives right after it, and
        --// it is the one that says the farm has stopped.
        local function HoldInstead(OtherPlayer, Reason)
            S.Latched = true
            S.LatchedAt = os.time()
            S.LatchedBy = { UserId = tostring(OtherPlayer.UserId), Name = OtherPlayer.Name }
            QueueLog()
            StopFarm()

            NotifyAction(
                "FOLLOWER GUARD",
                string.format(
                    "@%s is following you and this server could not be left (%s) - Auto Farm is off until you turn it on",
                    OtherPlayer.Name,
                    Reason or "unavailable"
                ),
                8
            )
        end

        local function Trip(OtherPlayer, Count, Now)
            --// Nothing to save here: a trip that leaves changes no field of
            --// the log, and one that cannot leave saves through HoldInstead.
            S.Tripped[tostring(OtherPlayer.UserId)] = Now

            --// The trip's job is to get us out of this server rather than to
            --// stop the farm: ServerHop joins another public server and the
            --// farm carries on there. Only a hop that was started and then
            --// failed falls back to the hold; a false return means another
            --// hop is already on its way, which is leaving all the same.
            local Leaving = ServerHop:Hop(function(Reason)
                HoldInstead(OtherPlayer, Reason)
            end)

            if Now - S.NoticeAt >= 8 then
                S.NoticeAt = Now
                NotifyAction(
                    "FOLLOWER GUARD",
                    string.format(
                        "@%s has joined your servers %d times in %d minutes - %s",
                        OtherPlayer.Name,
                        Count,
                        FOLLOWER_WINDOW / 60,
                        Leaving and "leaving this server" or "a hop is already on its way"
                    ),
                    8
                )
            end
        end

        local function Evaluate(OtherPlayer, Now)
            if not Feature.FollowerGuard.Enabled then
                return
            end

            local UserId = tostring(OtherPlayer.UserId)
            local LastTrip = S.Tripped[UserId]

            --// Left for them recently: the sightings that tripped it are
            --// still inside the window, so seeing them again now is the same
            --// trip. They are left for again once the cooldown has passed.
            if LastTrip and Now - LastTrip < FOLLOWER_RETRIP_COOLDOWN then
                return
            end

            local Count = CountSightings(UserId, Now)

            if Count >= FOLLOWER_TRIP_SIGHTINGS then
                Trip(OtherPlayer, Count, Now)
            end
        end

        --// Records one sighting of one player. Kind is "present" (here when
        --// the guard looked) or "joined" (arrived while it runs).
        local function Observe(OtherPlayer, Kind)
            if not Feature.FollowerGuard.Enabled or IsExempt(OtherPlayer) then
                return
            end

            local Now = os.time()
            local UserId = tostring(OtherPlayer.UserId)
            local JobId = tostring(game.JobId or "")
            local LastPair

            for _, Entry in ipairs(S.Sightings) do
                if Entry.UserId == UserId and Entry.JobId == JobId then
                    if Kind == "present" then
                        --// Already known in this server: a script re-run is
                        --// not a second sighting.
                        return
                    end

                    LastPair = Entry
                end
            end

            if Kind == "joined" and LastPair and Now - LastPair.Time <= SIGHTING_DEDUPE then
                return
            end

            table.insert(S.Sightings, {
                UserId = UserId,
                Name = OtherPlayer.Name,
                Time = Now,
                JobId = JobId,
                Kind = Kind,
            })

            QueueLog()
            Evaluate(OtherPlayer, Now)
        end

        --// Everyone here counts once the profile is loaded (the whitelist is
        --// part of it); also runs when the toggle is switched on mid-session.
        local function ScanRoster()
            for _, OtherPlayer in ipairs(Players:GetPlayers()) do
                Observe(OtherPlayer, "present")
            end
        end

        Context.Connect(Players.PlayerAdded, function(OtherPlayer)
            --// Joins before the first scan are covered by the scan itself,
            --// which has the whitelist loaded; this keeps a stranger joined
            --// in that gap from being counted twice or counted blind.
            if S.Scanned then
                Observe(OtherPlayer, "joined")
            end
        end)

        --// Called by AutoFarming's Auto Farm toggle callback, which runs only
        --// on a real click: profiles and this guard set AICFeature.S.Enabled
        --// straight and never come through here. This is the one way the hold
        --// is lifted, and with it the era changes so older sightings are
        --// never able to trip the guard again. It also clears every trip, so
        --// turning the farm back on by hand is never answered with a hop for
        --// a player the guard has already left for.
        AICFeature.NotifyManualAutoFarmToggle = function(Value)
            if not Value then
                return
            end

            S.Latched = false
            S.LatchedAt = 0
            S.LatchedBy = {}
            S.CountFrom = os.time()
            table.clear(S.Tripped)
            QueueLog()
        end

        function FollowerGuard:Update()
            if not S.Scanned then
                --// First heartbeat is after Finalize, so the profile and the
                --// whitelist are loaded by now.
                S.Scanned = true
            end

            local Enabled = Feature.FollowerGuard.Enabled == true

            --// Scanned on the first frame and on every off -> on edge, so a
            --// toggle coming from a profile load is covered too (present
            --// sightings are once per player and server, so a rescan is free).
            if Enabled and S.WasEnabled ~= true then
                ScanRoster()
            end

            S.WasEnabled = Enabled

            --// The hold is enforced every frame and outlives the toggle:
            --// whatever sets Auto Farm on (a profile load does) is turned
            --// back off until someone clicks the Auto Farm toggle itself.
            --// Reached only when a trip could not leave the server.
            if S.Latched and AICFeature.S.Enabled then
                StopFarm()
            end

            if S.SaveQueued then
                WriteLog()
            end
        end

        LoadLog()

        AICUI.BindFeatureToggle("FollowerGuard", "Follower Guard", function(Enabled)
            if Enabled then
                ScanRoster()
            end
        end, UIRef.ServerSafetySection)

        if UIRef.ServerSafetySection then
            UIRef.ServerSafetySection:AddLabel("Leaves the server when one player keeps joining yours")
        end

        return FollowerGuard
    end,
}
