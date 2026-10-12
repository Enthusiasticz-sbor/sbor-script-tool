-- SmithingMinigame plays the strike minigame the game opens after
-- CraftingStart: PlayerGui.CraftingGame.Main holds a moving line (Mover), a
-- target band (ClickArea) and the strike button (Action); Success or Failed
-- becomes visible when the round is over.
--
-- While running it checks every rendered frame and strikes when Mover
-- overlaps ClickArea. A direct click (firesignal / getconnections) runs the
-- game's handler in the same frame, so it strikes on the current overlap. A
-- synthetic click lands a frame later, so for those the overlap is checked
-- where Mover will be by then, from its speed.
--
-- The speed is only ever measured between two frames of the same sweep. The
-- game resets Mover for the next strike, so the frame just before and the
-- frame just after a strike (or after the minigame window comes and goes) are
-- not two samples of one movement: the reset itself would read as speed and
-- the next strike would be pressed early. Those frames only take the sample.
return {
    Name = "SmithingMinigame",
    Dependencies = {"Runtime", "GuiClick"},

    Start = function(Context)
        local Player = Context.Player
        local RunService = Context.Services.RunService
        local GuiClick = Context.GuiClick

        --// Pixels of slack around ClickArea, as in the proof of concept.
        local STRIKE_PADDING = 1
        --// Never strike twice within this, so one overlap is one strike.
        local STRIKE_COOLDOWN = 0.12
        --// The strike button listens to this signal.
        local STRIKE_SIGNALS = { "MouseButton1Click" }
        local DIRECT_METHODS = { getconnections = true, firesignal = true }

        local Minigame = {
            Name = "SmithingMinigame",
            S = {
                Connection = nil,
                LastStrike = 0,
                Strikes = 0,
                LastMoverPosition = nil,
                MoverVelocity = Vector2.zero,
                --// The click method that worked last; firesignal is what
                --// the proof of concept used.
                Method = "firesignal",
            },
        }

        local S = Minigame.S

        --// CraftingGame.Main, or nil while the minigame is not open.
        function Minigame:Find()
            local PlayerGui = Player:FindFirstChild("PlayerGui")
            local CraftingGame = PlayerGui and PlayerGui:FindFirstChild("CraftingGame")
            return CraftingGame and CraftingGame:FindFirstChild("Main")
        end

        --// "Success", "Failed", or nil while the round is still running.
        function Minigame:GetResult(Main)
            local Success = Main:FindFirstChild("Success")
            local Failed = Main:FindFirstChild("Failed")

            if Success and Success.Visible then
                return "Success"
            elseif Failed and Failed.Visible then
                return "Failed"
            end

            return nil
        end

        function Minigame:GetStrikes()
            return S.Strikes
        end

        local function Overlaps(A, APosition, B)
            local ASize = A.AbsoluteSize
            local BPosition = B.AbsolutePosition
            local BSize = B.AbsoluteSize

            return APosition.X < BPosition.X + BSize.X + STRIKE_PADDING
                and APosition.X + ASize.X + STRIKE_PADDING > BPosition.X
                and APosition.Y < BPosition.Y + BSize.Y + STRIKE_PADDING
                and APosition.Y + ASize.Y + STRIKE_PADDING > BPosition.Y
        end

        --// Forgets the mover's motion. Used wherever the next frame is not
        --// the continuation of the last one: the round ended, the minigame
        --// window came or went, or a strike was just pressed and the game is
        --// resetting the mover for the next strike.
        local function ForgetMover()
            S.LastMoverPosition = nil
            S.MoverVelocity = Vector2.zero
        end

        local function Step(DeltaTime)
            local Main = Minigame:Find()

            if not Main or Minigame:GetResult(Main) then
                ForgetMover()
                return
            end

            local ClickArea = Main:FindFirstChild("ClickArea")
            local Mover = Main:FindFirstChild("Mover")
            local Action = Main:FindFirstChild("Action")

            if not ClickArea or not Mover or not Action then
                ForgetMover()
                return
            end

            local Position = Mover.AbsolutePosition
            local Previous = S.LastMoverPosition
            S.LastMoverPosition = Position

            --// Without a frame before it there is no movement to measure, so
            --// this frame only takes the sample, and never strikes: it may be
            --// the frame the mover was reset on.
            if not Previous or DeltaTime <= 0 then
                S.MoverVelocity = Vector2.zero
                return
            end

            S.MoverVelocity = (Position - Previous) / DeltaTime

            local now = os.clock()

            if now - S.LastStrike < STRIKE_COOLDOWN then
                return
            end

            local CheckPosition = DIRECT_METHODS[S.Method]
                and Position
                or Position + S.MoverVelocity * DeltaTime

            if not Overlaps(Mover, CheckPosition, ClickArea) then
                return
            end

            --// Before the click: a synthetic click yields, and later frames
            --// run meanwhile and would strike again.
            S.LastStrike = now

            local Method = GuiClick.Click(Action, S.Method, STRIKE_SIGNALS)

            if Method then
                S.Method = Method
                S.Strikes += 1
            end

            --// The next strike is measured from the next strike's mover, not
            --// from the movement of the one just struck.
            ForgetMover()
        end

        --// Starts playing; idempotent. Runs on RenderStepped, where the GUI
        --// has its final position for the frame.
        function Minigame:Start()
            if S.Connection then
                return
            end

            S.Strikes = 0
            S.LastStrike = 0
            S.LastMoverPosition = nil
            S.MoverVelocity = Vector2.zero
            S.Connection = RunService.RenderStepped:Connect(Step)
        end

        function Minigame:Stop()
            if S.Connection then
                S.Connection:Disconnect()
                S.Connection = nil
            end
        end

        Context.Lifetime.OnEnd(function()
            Minigame:Stop()
        end)

        return Minigame
    end,
}
