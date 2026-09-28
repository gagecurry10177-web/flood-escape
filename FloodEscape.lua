-- Discord: societyss | Roblox: hyypes
-- Highwater City is a multiplayer flood survival map with a shared flood, city rooftops, escape routes, and an evac helipad.
-- Put this Script in ServerScriptService. Everything for the game gets made by this script.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")

local CONFIG = {
    intermission = 15,
    roundLength = 48,
    waterStartTop = 0,
    waterEndTop = 88,
    lobby = CFrame.new(0, 62, 0),
    start = CFrame.new(20, 20, 0),
}

local arena = Instance.new("Folder")
arena.Name = "FloodEscapeArena"
arena.Parent = workspace

local playerData = {}
local roundPlayers = {}
local phase = "Waiting"
local roundStartedAt = 0
local currentWaterTween
local sweepHazards = {}

local function part(properties)
    local object = Instance.new("Part")
    object.Anchored = true
    object.TopSurface = Enum.SurfaceType.Smooth
    object.BottomSurface = Enum.SurfaceType.Smooth
    for property, value in pairs(properties) do
        object[property] = value
    end
    object.Parent = properties.Parent or arena
    return object
end

local function label(adornee, text, color, offset)
    local gui = Instance.new("BillboardGui")
    gui.Adornee = adornee
    gui.Size = UDim2.fromOffset(260, 56)
    gui.StudsOffsetWorldSpace = offset or Vector3.new(0, 5, 0)
    gui.AlwaysOnTop = true
    gui.Parent = adornee

    local textLabel = Instance.new("TextLabel")
    textLabel.BackgroundTransparency = 1
    textLabel.Size = UDim2.fromScale(1, 1)
    textLabel.Font = Enum.Font.GothamBold
    textLabel.Text = text
    textLabel.TextScaled = true
    textLabel.TextColor3 = color
    textLabel.TextStrokeTransparency = 0.35
    textLabel.Parent = gui
end

local function characterParts(player)
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not character or not humanoid or not root or humanoid.Health <= 0 then
        return nil
    end
    return humanoid, root
end

local function status(player, text)
    local data = playerData[player]
    if data then
        data.status.Value = text
    end
end

local function teleport(player, target)
    local _, root = characterParts(player)
    if root then
        root.CFrame = target
        root.AssemblyLinearVelocity = Vector3.zero
    end
end

-- Buildings are made from the same function so the city looks connected instead of like random separate blocks.
local function building(name, position, height, color)
    local body = part({
        Name = name,
        Size = Vector3.new(34, height, 34),
        CFrame = CFrame.new(position.X, height / 2, position.Z),
        Color = color,
        Material = Enum.Material.Concrete,
    })

    local roof = part({
        Name = name .. "Roof",
        Size = Vector3.new(38, 2, 38),
        CFrame = CFrame.new(position.X, height + 1, position.Z),
        Color = Color3.fromRGB(50, 58, 72),
        Material = Enum.Material.Metal,
    })

    for _, side in ipairs({-1, 1}) do
        local windows = part({
            Name = name .. "Windows",
            Size = Vector3.new(0.3, math.max(7, height - 8), 18),
            CFrame = CFrame.new(position.X + side * 17.2, height / 2 + 2, position.Z),
            Color = Color3.fromRGB(70, 180, 255),
            Material = Enum.Material.Neon,
        })
        windows.Transparency = 0.25
    end

    local antenna = part({
        Name = name .. "Antenna",
        Size = Vector3.new(1, 10, 1),
        CFrame = roof.CFrame + Vector3.new(0, 6, 0),
        Color = Color3.fromRGB(180, 185, 195),
        Material = Enum.Material.Metal,
    })

    return roof
end

-- Fire escapes use alternating ledges instead of a plain bridge, so crossing between towers needs real jump timing.
local function fireEscape(name, startPosition, endPosition)
    local direction = endPosition - startPosition
    local horizontal = Vector3.new(direction.X, 0, direction.Z).Unit
    local side = Vector3.yAxis:Cross(horizontal)
    local steps = 9

    for index = 1, steps do
        local alpha = index / (steps + 1)
        local zigZag = index % 2 == 0 and 4 or -4
        local point = startPosition:Lerp(endPosition, alpha) + side * zigZag
        local ledge = part({
            Name = name .. "Ledge" .. index,
            Size = Vector3.new(6, 1, 6),
            CFrame = CFrame.lookAt(point, point + horizontal),
            Color = Color3.fromRGB(104, 74, 48),
            Material = Enum.Material.WoodPlanks,
        })

        -- Every ledge collapses after a player touches it, then comes back so later players still have a route.
        local collapsing = false
        ledge.Touched:Connect(function(hit)
            local model = hit:FindFirstAncestorOfClass("Model")
            local player = model and Players:GetPlayerFromCharacter(model)
            if not player or collapsing then
                return
            end
            collapsing = true
            ledge.Color = Color3.fromRGB(255, 155, 70)
            task.delay(1.2, function()
                if not ledge.Parent then
                    return
                end
                ledge.CanCollide = false
                ledge.CanTouch = false
                TweenService:Create(ledge, TweenInfo.new(0.35), {Transparency = 1}):Play()
                task.wait(4)
                if not ledge.Parent then
                    return
                end
                ledge.Transparency = 0
                ledge.CanCollide = true
                ledge.CanTouch = true
                ledge.Color = Color3.fromRGB(104, 74, 48)
                collapsing = false
            end)
        end)

        if index == 5 then
            local info = TweenInfo.new(1.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
            TweenService:Create(ledge, info, {CFrame = ledge.CFrame + Vector3.new(0, 5, 0)}):Play()
        end
    end
end

local function checkpoint(index, roof)
    local pad = part({
        Name = "Checkpoint" .. index,
        Size = Vector3.new(16, 1, 16),
        CFrame = roof.CFrame + Vector3.new(0, 2, 0),
        Color = Color3.fromRGB(50, 180, 255),
        Material = Enum.Material.Neon,
    })
    label(pad, "SAFE ROOF " .. index, Color3.fromRGB(220, 248, 255))

    pad.Touched:Connect(function(hit)
        local model = hit:FindFirstAncestorOfClass("Model")
        local player = model and Players:GetPlayerFromCharacter(model)
        local data = player and playerData[player]
        if not data or not data.active or data.checkpoint >= index then
            return
        end
        data.checkpoint = index
        data.checkpointCFrame = pad.CFrame + Vector3.new(0, 5, 0)
        data.checkpointValue.Value = index
        data.status.Value = "Safe roof " .. index .. " reached"
        pad.Color = Color3.fromRGB(110, 255, 150)
    end)
end

-- Floating debris makes the lower part of the route feel alive while TweenService does the movement work.
local function debris(name, position, movement, seconds)
    local raft = part({
        Name = name,
        Size = Vector3.new(13, 1.5, 9),
        CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(12), math.rad(4)),
        Color = Color3.fromRGB(124, 82, 48),
        Material = Enum.Material.WoodPlanks,
    })
    local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
    TweenService:Create(raft, info, {CFrame = raft.CFrame + movement}):Play()
end

-- These sweep bars make the later roofs more dangerous than simply running across a flat platform.
local function makeSweepBar(name, position, length, speed)
    local pivot = part({
        Name = name .. "Pivot",
        Size = Vector3.new(2, 6, 2),
        CFrame = CFrame.new(position),
        Color = Color3.fromRGB(55, 58, 65),
        Material = Enum.Material.Metal,
    })
    local bar = part({
        Name = name,
        Size = Vector3.new(length, 0.8, 1.4),
        CFrame = pivot.CFrame,
        Color = Color3.fromRGB(255, 75, 85),
        Material = Enum.Material.Neon,
    })
    table.insert(sweepHazards, {bar = bar, origin = pivot.CFrame, angle = 0, speed = speed})
    bar.Touched:Connect(function(hit)
        local humanoid = hit.Parent and hit.Parent:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.Health = 0
        end
    end)
end

-- Streets and side buildings fill out the city, even though the main escape route only uses five tall rooftops.
part({
    Name = "CityGround",
    Size = Vector3.new(430, 4, 310),
    CFrame = CFrame.new(135, -2, 0),
    Color = Color3.fromRGB(40, 43, 50),
    Material = Enum.Material.Asphalt,
})

for street = -120, 120, 60 do
    part({
        Name = "StreetLine",
        Size = Vector3.new(410, 0.15, 2),
        CFrame = CFrame.new(135, 0.1, street),
        Color = Color3.fromRGB(240, 200, 70),
        Material = Enum.Material.Neon,
    })
end

local startRoof = building("StartApartment", Vector3.new(20, 0, 0), 18, Color3.fromRGB(91, 104, 128))
local roofOne = building("OfficeOne", Vector3.new(75, 0, -35), 32, Color3.fromRGB(103, 88, 115))
local roofTwo = building("OfficeTwo", Vector3.new(135, 0, 15), 46, Color3.fromRGB(83, 107, 125))
local roofThree = building("Hotel", Vector3.new(195, 0, -30), 60, Color3.fromRGB(112, 100, 85))
local rescueRoof = building("EvacTower", Vector3.new(255, 0, 5), 74, Color3.fromRGB(99, 104, 111))

building("SideBlockA", Vector3.new(70, 0, 65), 15, Color3.fromRGB(90, 91, 101))
building("SideBlockB", Vector3.new(145, 0, -80), 24, Color3.fromRGB(95, 82, 91))
building("SideBlockC", Vector3.new(215, 0, 70), 29, Color3.fromRGB(80, 96, 105))
building("SideBlockD", Vector3.new(285, 0, -65), 37, Color3.fromRGB(99, 91, 83))

fireEscape("FireEscapeOne", startRoof.Position + Vector3.new(15, 4, -6), roofOne.Position + Vector3.new(-15, 4, 6))
fireEscape("FireEscapeTwo", roofOne.Position + Vector3.new(15, 4, 6), roofTwo.Position + Vector3.new(-15, 4, -6))
fireEscape("FireEscapeThree", roofTwo.Position + Vector3.new(15, 4, -6), roofThree.Position + Vector3.new(-15, 4, 6))
fireEscape("FireEscapeFour", roofThree.Position + Vector3.new(15, 4, 6), rescueRoof.Position + Vector3.new(-15, 4, -6))

checkpoint(1, roofOne)
checkpoint(2, roofTwo)
checkpoint(3, roofThree)

debris("DriftwoodA", Vector3.new(42, 10, 22), Vector3.new(0, 0, 25), 1.8)
debris("DriftwoodB", Vector3.new(104, 27, -14), Vector3.new(0, 0, -23), 2)
debris("DriftwoodC", Vector3.new(166, 43, 12), Vector3.new(0, 0, 20), 1.9)
makeSweepBar("RoofTwoSweep", Vector3.new(135, 51, 15), 24, 3.2)
makeSweepBar("HotelSweep", Vector3.new(195, 65, -30), 27, -2.7)

-- The final roof has a real helipad and the beacon can only be used after all three safe roofs.
local helipad = part({
    Name = "EvacHelipad",
    Size = Vector3.new(24, 1, 24),
    CFrame = rescueRoof.CFrame + Vector3.new(0, 3, 0),
    Color = Color3.fromRGB(225, 210, 70),
    Material = Enum.Material.Metal,
})
label(helipad, "EVACUATION HELIPAD", Color3.fromRGB(255, 245, 185))

local beacon = part({
    Name = "RescueBeacon",
    Shape = Enum.PartType.Ball,
    Size = Vector3.new(5, 5, 5),
    CFrame = helipad.CFrame + Vector3.new(0, 6, 0),
    CanCollide = false,
    Color = Color3.fromRGB(255, 235, 110),
    Material = Enum.Material.Neon,
})

local beaconLight = Instance.new("PointLight")
beaconLight.Color = beacon.Color
beaconLight.Brightness = 4
beaconLight.Range = 28
beaconLight.Parent = beacon

local beaconPrompt = Instance.new("ProximityPrompt")
beaconPrompt.ActionText = "Signal Helicopter"
beaconPrompt.ObjectText = "Rescue Beacon"
beaconPrompt.KeyboardKeyCode = Enum.KeyCode.E
beaconPrompt.MaxActivationDistance = 12
beaconPrompt.RequiresLineOfSight = false
beaconPrompt.Parent = beacon

beaconPrompt.Triggered:Connect(function(player)
    local data = playerData[player]
    if phase ~= "Flooding" or not data or not data.active or data.escaped then
        return
    end
    if data.checkpoint < 3 then
        status(player, "The radio needs all 3 safe roofs")
        return
    end

    data.active = false
    data.escaped = true
    data.wins.Value += 1
    status(player, "RESCUED! You made it out.")

    local fireworks = Instance.new("ParticleEmitter")
    fireworks.Color = ColorSequence.new(beacon.Color)
    fireworks.Lifetime = NumberRange.new(1, 1.5)
    fireworks.Speed = NumberRange.new(20, 34)
    fireworks.Rate = 0
    fireworks.SpreadAngle = Vector2.new(180, 180)
    fireworks.Parent = beacon
    fireworks:Emit(90)
    Debris:AddItem(fireworks, 3)
end)

-- Water begins at street height, then gets a large obvious vertical tween all the way past the high roofs.
local water = part({
    Name = "FloodWater",
    Size = Vector3.new(450, 2, 330),
    CFrame = CFrame.new(135, -1, 0),
    CanCollide = false,
    CanTouch = false,
    Transparency = 0.32,
    Color = Color3.fromRGB(25, 135, 235),
    Material = Enum.Material.Glass,
})

local waterLight = Instance.new("PointLight")
waterLight.Color = water.Color
waterLight.Brightness = 1.5
waterLight.Range = 35
waterLight.Parent = water

local storm = Instance.new("ColorCorrectionEffect")
storm.Name = "FloodEscapeStorm"
storm.TintColor = Color3.fromRGB(150, 185, 255)
storm.Saturation = -0.3
storm.Contrast = 0.12
storm.Enabled = false
storm.Parent = Lighting

local function resetWater()
    if currentWaterTween then
        currentWaterTween:Cancel()
    end
    water.Size = Vector3.new(450, 2, 330)
    water.CFrame = CFrame.new(135, -1, 0)
end

local function riseWater()
    local finalHeight = CONFIG.waterEndTop - CONFIG.waterStartTop + 2
    currentWaterTween = TweenService:Create(water, TweenInfo.new(CONFIG.roundLength, Enum.EasingStyle.Linear), {
        Size = Vector3.new(450, finalHeight, 330),
        CFrame = CFrame.new(135, CONFIG.waterStartTop + finalHeight / 2 - 1, 0),
    })
    currentWaterTween:Play()
end

-- A safe lobby floats above the city so dead players can watch the water instead of respawning in it.
local lobby = part({
    Name = "SkyLobby",
    Size = Vector3.new(32, 2, 32),
    CFrame = CFrame.new(0, 56, 0),
    Color = Color3.fromRGB(68, 78, 104),
    Material = Enum.Material.Metal,
})
label(lobby, "HIGHWATER CITY", Color3.fromRGB(220, 235, 255))

local spawn = Instance.new("SpawnLocation")
spawn.Name = "FloodEscapeSpawn"
spawn.Size = Vector3.new(8, 1, 8)
spawn.CFrame = CFrame.new(0, 58, 0)
spawn.Neutral = true
spawn.Color = Color3.fromRGB(75, 160, 255)
spawn.Material = Enum.Material.Neon
spawn.Parent = arena

local function createData(player)
    local leaderstats = Instance.new("Folder")
    leaderstats.Name = "leaderstats"
    leaderstats.Parent = player

    local wins = Instance.new("IntValue")
    wins.Name = "Wins"
    wins.Parent = leaderstats

    local checkpointValue = Instance.new("IntValue")
    checkpointValue.Name = "Checkpoint"
    checkpointValue.Parent = leaderstats

    local survival = Instance.new("IntValue")
    survival.Name = "Survival"
    survival.Parent = leaderstats

    local text = Instance.new("StringValue")
    text.Name = "FloodStatus"
    text.Value = "Waiting for players"
    text.Parent = player

    playerData[player] = {
        wins = wins,
        checkpointValue = checkpointValue,
        survival = survival,
        status = text,
        active = false,
        escaped = false,
        checkpoint = 0,
        checkpointCFrame = CONFIG.start,
    }
end

local function startRound()
    phase = "Flooding"
    roundStartedAt = os.clock()
    roundPlayers = {}
    storm.Enabled = true
    resetWater()
    riseWater()

    for _, player in ipairs(Players:GetPlayers()) do
        local data = playerData[player]
        if data then
            data.active = true
            data.escaped = false
            data.checkpoint = 0
            data.checkpointCFrame = CONFIG.start
            data.checkpointValue.Value = 0
            data.survival.Value = 0
            table.insert(roundPlayers, player)
            status(player, "Flood started! Get to the helipad.")
            teleport(player, CONFIG.start)
        end
    end
end

local function finishRound()
    phase = "Intermission"
    storm.Enabled = false
    resetWater()

    for _, player in ipairs(roundPlayers) do
        local data = playerData[player]
        if data then
            data.active = false
            if not data.escaped then
                status(player, "Round ended. Try a faster route.")
            end
            teleport(player, CONFIG.lobby)
        end
    end
end

local function connectPlayer(player)
    if playerData[player] then
        return
    end
    createData(player)

    player.CharacterAdded:Connect(function(character)
        local root = character:WaitForChild("HumanoidRootPart", 8)
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local data = playerData[player]
        if not root or not humanoid or not data then
            return
        end
        task.wait(0.15)

        if phase == "Flooding" and data.active then
            root.CFrame = data.checkpointCFrame
        else
            root.CFrame = CONFIG.lobby
        end

        humanoid.Died:Connect(function()
            if phase == "Flooding" and data.active then
                data.active = false
                status(player, "Swept away by the flood")
            end
        end)
    end)

    if player.Character then
        local _, root = characterParts(player)
        if root then
            root.CFrame = CONFIG.lobby
        end
    end
end

Players.PlayerAdded:Connect(connectPlayer)
Players.PlayerRemoving:Connect(function(player)
    playerData[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
    connectPlayer(player)
end

-- The water's visual tween and the drowning check use the same elapsed time, so what players see matches the danger.
RunService.Heartbeat:Connect(function(deltaTime)
    for _, hazard in ipairs(sweepHazards) do
        hazard.angle += hazard.speed * deltaTime
        hazard.bar.CFrame = hazard.origin * CFrame.Angles(0, hazard.angle, 0)
    end

    if phase ~= "Flooding" then
        return
    end

    local elapsed = os.clock() - roundStartedAt
    local level = CONFIG.waterStartTop + (CONFIG.waterEndTop - CONFIG.waterStartTop) * math.clamp(elapsed / CONFIG.roundLength, 0, 1)

    for _, player in ipairs(roundPlayers) do
        local data = playerData[player]
        local humanoid, root = characterParts(player)

        if data and data.active and humanoid and root then
            data.survival.Value = math.floor(elapsed)
            if root.Position.Y <= level then
                humanoid.Health = 0
            end
        end
    end
end)

task.spawn(function()
    while true do
        while #Players:GetPlayers() == 0 do
            phase = "Waiting"
            task.wait(1)
        end

        phase = "Intermission"
        for seconds = CONFIG.intermission, 1, -1 do
            for _, player in ipairs(Players:GetPlayers()) do
                status(player, "Flood starts in " .. seconds .. " seconds")
            end
            task.wait(1)
        end

        startRound()

        for _ = 1, CONFIG.roundLength do
            local activeCount = 0
            for _, player in ipairs(roundPlayers) do
                local data = playerData[player]
                if data and data.active then
                    activeCount += 1
                end
            end
            if activeCount == 0 then
                break
            end
            task.wait(1)
        end

        finishRound()
        task.wait(5)
    end
end)

