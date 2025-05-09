--[[

    *******************
    * Hunt Log Doer  *
    *******************

    *************************
    *  Version -> 0.0.1.0  *
    *************************

    Version Notes:
    0.1.0.0  ->    Turbocharged for reliability: checks to see if it gets stuck in many places, mount selector, added fate support, etc.
    0.0.1.0  ->    The official versioning of this script begins now. I spent time getting the actual coordinates for the GC log mobs, but the class log mobs still use publicly available coordinates, which are highly inaccurate. pot0to cleaned up a bunch of things, especially a bug that was causing errors with the job to class conversion. I streamlined the pathing process. Originally it used node pathing from Mootykins.

    ***************
    * Description *
    ***************

    A SND Lua script that allows you to loop through all the incomplete mobs in your hunt log for a given class/GC and rank.
 
    ****************
    *    Agenda    *
    ****************
    Requires manual or AR postprocess activation.
    Could be faster.
    Ignores mobs before arriving to flag.
    *********************
    *    Requirements   *
    *********************
    -> Chat Coordinates:
    -> Pandora [Make sure to enable Auto teleport to map coords with pandora (white list the echo channel)]:
    -> vnavmesh: https://puni.sh/api/repository/veyn
    -> RSR:
    -> vbm : https://puni.sh/api/repository/veyn
    -> SomethingNeedDoing (Expanded Edition) [Make sure to press the lua button when you import this] -> https://puni.sh/api/repository/croizat
    -> Teleporter:
    -> VAC functions, lists and (optionally) char_list - https://github.com/WigglyMuffin/SNDScripts/tree/main

    *****************************
    *  Required Plugin Settings *
    *****************************
    -> Pandora:
                1. Make sure to enable Auto teleport to map coords with pandora (white list the echo channel
    -> SomethingNeedDoing (Expanded Edition):
                1. Make sure to press the lua button when you import this
                2. Make sure to set up your paths. Use the Lua path setting in the SND help config.
    -> RSR:
                1. Change RSR to attack ALL enemies when solo, or previously engaged.
                2. Disable "Treat 1hp target as invincible"
                
    ***********
    * Credits *
    ***********

    Author(s): CacahuetesManu | pot0to | Friendly
    Functions borrowed from: McVaxius, Umbra, LeafFriend, plottingCreeper, Mootykins and WigglyMuffin
]] --[[
********************************
*  Helper Functions and Files  *
********************************
]] -- JSON handler is from https://github.com/Egor-Skriptunoff/json4lua/blob/master/json.lua
local json = require("json")

-- I made this territories dictionary to quickly change between zone ID and zone name.
require("Territories")
-- Monster log is from Hunty Plugin https://github.com/Infiziert90/Hunty/tree/mas
open = io.open
monsters = open(os.getenv("appdata") .. "\\XIVLauncher\\pluginConfigs\\SomethingNeedDoing\\monsters.json")
local stringmonsters = monsters:read "*a"
monsters:close()
-- VAC stuff
use_external_character_list = true
char_list = "vac_char_list.lua"
SNDConfigFolder = os.getenv("appdata") .. "\\XIVLauncher\\pluginConfigs\\SomethingNeedDoing\\"
LoadFunctionsFileLocation = SNDConfigFolder .. "vac_functions.lua"
LoadFunctions = loadfile(LoadFunctionsFileLocation)()
LoadFileCheck()
if use_external_character_list then
    local char_data = dofile(SNDConfigFolder .. char_list)
    character_list = char_data.character_list
end
-- VAC stuff end

--[[
**************
*  Settings  *
**************
]]

-- Choose either "class" to do your class log or "GC" to do your Grand Company Log
local route = "GC"
-- Choose what rank to start 1,2, 3, 4 or 5
local rankToDo = 1
-- Walk or Fly?
local mount = true -- have you unlocked mounts yet?
local mount_name = '"SDS Fenrir"' -- Company Chocobo/SDS Fenrir
local move_type = "walk"
-- These variables help with pathing and are used for unstucking
local interval_rate = 0.3 -- if you set this lower and it creates a bug, set it higher
local timeout_threshold = 3
local ping_radius = 20
local killtimeout_threshold = 30
--[[
************************
*  Required Functions  *
************************
]]

-- Call user provided input to figure out if we should work on Class Log or Hunt Log

if route == "class" then
    if GetClassJobId() > 18 and GetClassJobId() < 25 then
        ClassID = GetClassJobId() - 18
    elseif GetClassJobId() == 26 or GetClassJobId() == 27 or GetClassJobId() == 28 then
        ClassID = 26
    elseif GetClassJobId() == 29 or GetClassJobId() == 30 then
        ClassID = 29
    else
        ClassID = GetClassJobId()
    end

    LogFinder = tostring(ClassID)
elseif route == "GC" then
    LogFinder = tostring(GetPlayerGC() + 10000)
end

-- This Function is used within json.traverse to figure out where in the JSON we want to extract data.

local function my_callback(path, json_type, value)
    if #path == 4 and path[#path - 2] == LogFinder and path[#path - 1] == rankToDo then
        CurrentLog = value
        return true
    end
end

function Truncate1Dp(num)
    return truncate and ("%.1f"):format(num) or num
end

function ParseNodeDataString(string)
    return Split(string, ",")
end

function GetDistanceToNode(node)
    local given_node = ParseNodeDataString(node)
    return GetDistanceToPoint(tonumber(given_node[2]), tonumber(given_node[3]), tonumber(given_node[4]))
end

function Split(inputstr, sep)
    if sep == nil then
        sep = "%s"
    end
    local t = {}
    for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
        table.insert(t, str)
    end
    return t
end

function SquaredDistance(x1, y1, z1, x2, y2, z2)
    local success, result = pcall(function()
        local dx = x2 - x1
        local dy = y2 - y1
        local dz = z2 - z1
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        return math.floor(dist + 0.5)
    end)
    if success then
        return result
    else
        return nil
    end
end

function WithinThreeUnits(x1, y1, z1, x2, y2, z2)
    local dist = SquaredDistance(x1, y1, z1, x2, y2, z2)
    if dist then
        return dist <= 3
    else
        return false
    end
end

function CheckNavmeshReady()
    was_ready = NavIsReady()
    while not NavIsReady() do
        yield("/echo Building navmesh, currently at " .. Truncate1Dp(NavBuildProgress() * 100) .. "%")
        yield("/wait " .. (interval_rate * 10 + 0.0193))
    end
end

function MountFly()
    if HasFlightUnlocked(GetZoneID()) then
        while not GetCharacterCondition(4) do
            yield("/mount " .. mount_name)
            repeat
                yield("/wait " .. interval_rate + 0.00193)
            until not IsPlayerCasting() and not GetCharacterCondition(57)
        end
        if not GetCharacterCondition(81) and GetCharacterCondition(4) and not GetCharacterCondition(77) and
            not (IsInZone(146) or IsInZone(180)) then -- vnavmesh has problems flying around Outer La Noscea, Southern Thanalan, and Central Coerthas Highlands
            repeat
                yield("/echo Jumping to mount")
                yield("/gaction jump")
                yield("/wait " .. interval_rate + 0.00209)
            until GetCharacterCondition(77) and not GetCharacterCondition(48)
        end
    end
end

function StopMoveFly()
    PathStop()
    while PathIsRunning() do
        Sleep(interval_rate + 0.00218)
    end
end

function Mount()
    if not (IsQuestComplete(66236) or IsQuestComplete(66237) or IsQuestComplete(66238)) then
        Echo('You do not have a mount unlocked, please consider completing the "My Little Chocobo" quest.')
        mount = false
    end
    local counter = 0
    while not GetCharacterCondition(4) do
        repeat
            Sleep(0.10230)
        until IsPlayerAvailable() and not IsPlayerCasting() and not GetCharacterCondition(26)
        yield("/mount " .. mount_name)
        repeat
            Sleep(interval_rate + 0.0234)
            counter = counter + 1
            if counter > 20 then
                yield("/echo Mounting failed, trying again.")
                yield("/tpm " .. ZoneName)
                Sleep(10.239)
                repeat
                    Sleep(0.10241)
                until IsPlayerAvailable() and not IsPlayerCasting()
                Sleep(0.50243)
                counter = 0
            end
        until not IsPlayerCasting() and not GetCharacterCondition(57)
    end
end

function Dismount()
    if GetCharacterCondition(77) then
        local random_j = 0
        ::DISMOUNT_START::
        CheckNavmeshReady()

        local land_x
        local land_y
        local land_z
        local i = 0
        while not land_x or not land_y or not land_z do
            land_x = QueryMeshPointOnFloorX(GetPlayerRawXPos() + math.random(0, random_j),
                GetPlayerRawYPos() + math.random(0, random_j), GetPlayerRawZPos() + math.random(0, random_j), false, i)
            land_y = QueryMeshPointOnFloorY(GetPlayerRawXPos() + math.random(0, random_j),
                GetPlayerRawYPos() + math.random(0, random_j), GetPlayerRawZPos() + math.random(0, random_j), false, i)
            land_z = QueryMeshPointOnFloorZ(GetPlayerRawXPos() + math.random(0, random_j),
                GetPlayerRawYPos() + math.random(0, random_j), GetPlayerRawZPos() + math.random(0, random_j), false, i)
            i = i + 1
        end
        NodeMoveFly("land," .. land_x .. "," .. land_y .. "," .. land_z)

        local timeout_start = os.clock()
        repeat
            Sleep(interval_rate + 0.00266)
            if os.clock() - timeout_start > timeout_threshold then
                random_j = random_j + 1
                goto DISMOUNT_START
            end
        until not PathIsRunning()

        yield("/mount " .. mount_name)

        timeout_start = os.clock()
        repeat
            Sleep(interval_rate + 0.00277)
            if os.clock() - timeout_start > timeout_threshold then
                random_j = random_j + 1
                goto DISMOUNT_START
            end
        until not GetCharacterCondition(77)
    end
    if GetCharacterCondition(4) then
        yield("/mount " .. mount_name)
        repeat
            Sleep(interval_rate + 0.00287)
        until not GetCharacterCondition(4)
    end
end

function NodeMoveFly()
    CheckNavmeshReady()
    if mount == true and move_type == "fly" then
        MountFly()
        yield("/vnav flyflag")
    elseif mount == true and move_type == "walk" then
        Mount()
        yield("/vnav moveflag")
    else
        yield("/vnav moveflag")
    end
end

function TargetMoveFly()
    CheckNavmeshReady()
    if HasTarget() then
        if mount == true and move_type == "fly" and GetDistanceToTarget() > 15 then
            MountFly()
            PathfindAndMoveTo(GetTargetRawXPos(), GetTargetRawYPos(), GetTargetRawZPos())
        elseif mount == true and move_type == "walk" and GetDistanceToTarget() > 15 then
            Mount()
            PathfindAndMoveTo(GetTargetRawXPos(), GetTargetRawYPos(), GetTargetRawZPos())
        else
            PathfindAndMoveTo(GetTargetRawXPos(), GetTargetRawYPos(), GetTargetRawZPos())
        end
    end
end


function unstuckflag()
    if PathIsRunning() then
        local retry_timer = 0
        while PathIsRunning() do
            local success1, x1 = pcall(GetPlayerRawXPos)
            local success2, y1 = pcall(GetPlayerRawYPos)
            local success3, z1 = pcall(GetPlayerRawZPos)
            if not (success1 and success2 and success3) then
                goto continue
            end
            Sleep(1.60351)
            local success4, x2 = pcall(GetPlayerRawXPos)
            local success5, y2 = pcall(GetPlayerRawYPos)
            local success6, z2 = pcall(GetPlayerRawZPos)
            if not (success4 and success5 and success6) then
                goto continue
            end
            if WithinThreeUnits(x1, y1, z1, x2, y2, z2) and PathIsRunning() then
                retry_timer = retry_timer + 1
                if retry_timer > 7 then
                    yield("/vnav stop")
                    yield("/echo Pathing failed, abandoning hunt and returning home")
                    -- Go back home somewhere
                    Teleporter("auto", "li")
                    yield("/snd stop")
                elseif retry_timer == 5 then
                    yield("/vnav rebuild")
                    NodeMoveFly()
                elseif retry_timer > 2 then
                    for i = 1, 3 do
                        yield("/gaction jump")
                        Sleep(0.80329)
                    end
                    yield("/vnav reload")
                    NodeMoveFly()
                else
                    yield("/vnav reload")
                    NodeMoveFly()
                end
            else
                retry_timer = 0
            end
            ::continue::
        end
    end
end

function unstucktarget()
    if PathIsRunning() then
        local retry_timer = 0
        while PathIsRunning() do
            local success1, x1 = pcall(GetPlayerRawXPos)
            local success2, y1 = pcall(GetPlayerRawYPos)
            local success3, z1 = pcall(GetPlayerRawZPos)
            if not (success1 and success2 and success3) then
                goto continue
            end
            Sleep(1.30373)
            local success4, x2 = pcall(GetPlayerRawXPos)
            local success5, y2 = pcall(GetPlayerRawYPos)
            local success6, z2 = pcall(GetPlayerRawZPos)
            if not (success4 and success5 and success6) then
                goto continue
            end
            if WithinThreeUnits(x1, y1, z1, x2, y2, z2) and PathIsRunning() then
                retry_timer = retry_timer + 1
                if retry_timer > 7 then
                    yield("/vnav stop")
                    yield("/echo Pathing failed, abandoning hunt and returning home")
                    -- Go back home somewhere
                    Teleporter("auto", "li")
                    yield("/snd stop")
                elseif retry_timer == 5 then
                    yield("/vnav rebuild")
                    TargetMoveFly()
                elseif retry_timer > 2 then
                    yield("/gaction jump")
                    Sleep(0.80329)
                    yield("/vnav reload")
                    TargetMoveFly()
                else
                    yield("/vnav reload")
                    TargetMoveFly()
                end
            else
                retry_timer = 0
            end
            ::continue::
        end
    end
end

function MountandMovetoFlag()
    if IsInZone(GetFlagZone()) == true then
        LogInfo("Position acquired X= " .. rawX .. ", Y= " .. rawY .. ", Z= " .. rawZ)
        if HasFlightUnlocked(GetZoneID()) and not (IsInZone(146) or IsInZone(180)) then -- vnavmesh has problems in Outer La Noscea and Southern Thanalan
            yield("/gaction jump")
        end
        Sleep(0.20416)
        MountFly()
        local rng_offset = 0
        ::APPROXPATH_START::
        CheckNavmeshReady()

        local node = string.format("NAMENOTGIVEN,%1.f,%1.f,%1.f", rawX, rawY, rawZ)

        repeat
            NodeMoveFly()
            Sleep(interval_rate * 3 + 0.00277)
            unstuckflag()
        until GetDistanceToNode(node) < ping_radius
        StopMoveFly()
        Dismount()
        return true
    end
end

function ClassorGCID()
    if GetClassJobId() > 18 and GetClassJobId() < 25 then
        ClassID = GetClassJobId() - 18
    elseif GetClassJobId() == 26 or GetClassJobId() == 27 or GetClassJobId() == 28 then
        ClassID = 26
    elseif GetClassJobId() == 29 or GetClassJobId() == 30 then
        ClassID = 29
    else
        ClassID = GetClassJobId()
    end

    GCID = GetPlayerGC()

    if route == "class" then
        LogFinder = tostring(ClassID)
    elseif route == "GC" then
        LogFinder = tostring(GCID + 10000)
    end
end

function loadupHuntlog()
    ClassID = GetClassJobId()
    rank = rankToDo - 1
    Sleep(1.0482)
    if ClassID == 1 or ClassID == 19 then
        pcallClassID = 0 -- Gladiator
    elseif ClassID == 2 or ClassID == 20 then
        pcallClassID = 1 -- Pugilist
    elseif ClassID == 3 or ClassID == 21 then
        pcallClassID = 2 -- Marauder
    elseif ClassID == 4 or ClassID == 22 then
        pcallClassID = 3 -- Lancer
    elseif ClassID == 5 or ClassID == 23 then
        pcallClassID = 4 -- Archer
    elseif ClassID == 6 or ClassID == 24 then
        pcallClassID = 6 -- Conjurer
    elseif ClassID == 7 or ClassID == 25 then
        pcallClassID = 7 -- Thaumaturge
    elseif ClassID == 26 or ClassID == 27 or ClassID == 28 then
        pcallClassID = 8 -- Arcanist
    elseif ClassID == 29 or ClassID == 30 then
        pcallClassID = 5 -- Rogue
    end

    if route == "GC" then
        yield("/callback MonsterNote true 3 9 " .. GCID) -- this is not really needed, but it's to make sure it's always working
        yield("/wait 1.0477")
    elseif route == "class" then
        yield("/callback MonsterNote true 0 " .. pcallClassID) -- this will swap tabs
        yield("/wait 1.0480")
    end
    yield("/callback MonsterNote true 1 " .. rank) -- this will swap rank pages
    yield("/wait 1.0483")
    yield("/callback MonsterNote false 2 2") -- this will change it to show incomplete
end

-- Wrapper handling to show incomplete targets
function IncompleteTargets()
    if GetNodeText("MonsterNote", 2, 18, 4) == "Heckler Imp" then
        NextIncompleteTarget = GetNodeText("MonsterNote", 2, 21, 4)
    elseif GetNodeText("MonsterNote", 2, 18, 4) == "Temple Bee" then
        NextIncompleteTarget = GetNodeText("MonsterNote", 2, 20, 4)
    elseif GetNodeText("MonsterNote", 2, 18, 4) == "Doctore" then
        NextIncompleteTarget = GetNodeText("MonsterNote", 2, 21, 4)
    elseif GetNodeText("MonsterNote", 2, 18, 4) == "Sand Bat" then
        NextIncompleteTarget = GetNodeText("MonsterNote", 2, 21, 4)
    elseif GetNodeText("MonsterNote", 2, 18, 4) == "Temple Bat" then
        NextIncompleteTarget = GetNodeText("MonsterNote", 2, 21, 4)
    else
        if IsNodeVisible("MonsterNote", 1, 46, 5, 2) == false then
            NextIncompleteTarget = GetNodeText("MonsterNote", 2, 18, 4)
        elseif IsNodeVisible("MonsterNote", 1, 46, 5, 2) == true and IsNodeVisible("MonsterNote", 1, 46, 51001, 2) ==
            false then
            NextIncompleteTarget = GetNodeText("MonsterNote", 2, 19, 4)
        elseif IsNodeVisible("MonsterNote", 1, 46, 5, 2) == true and IsNodeVisible("MonsterNote", 1, 46, 51001, 2) ==
            true then
            NextIncompleteTarget = GetNodeText("MonsterNote", 2, 20, 4)
        end
    end

    yield("/wait 0.509")
    return NextIncompleteTarget
end

function OpenHuntlog()
    if IsNodeVisible("MonsterNote", 1) == false then
        yield("/hlog")
    end
end

function hlogRefresh()
    if (os.clock() - killtimeout_start > killtimeout_threshold) then
        killtimeout_start = os.clock()
        yield("/hlog")
        yield("/wait 0.523")
        OpenHuntlog()
    end
end

function DeathHandler()
    if GetCharacterCondition(2) then
        repeat
            Sleep(0.1)
            if IsAddonVisible("SelectYesno") then
                yield("/callback SelectYesno true 0")
                Sleep(0.1)
            end
        until not GetCharacterCondition(2)
        ZoneTransitions()
        Sleep(2)
        yield("/tpm " .. ZoneName)
        Sleep(10.239)
        repeat
            Sleep(0.10241)
        until IsPlayerAvailable() and not IsPlayerCasting()
    end
end

--[[
*******************
*  Start of Code  *
*******************
]]

yield("Doing the hunt log! Looking for next available mob.")

-- This function traverses through the JSON and saves the data we want into a more specific table called "CurrentLog"
ClassorGCID()
json.traverse(stringmonsters, my_callback)

-- Now we loop through the table and extract each mob, territory, location and kills needed in order to execute our hunt log doer

for i = 1, #CurrentLog do
    OpenHuntlog()
    loadupHuntlog()
    for j = 1, #CurrentLog[i].Monsters do
        mobName = CurrentLog[i].Monsters[j].Name
        if IncompleteTargets() == mobName then
            KillsDone = 0
            KillsNeeded = CurrentLog[i].Monsters[j].Count
            mobZone = CurrentLog[i].Monsters[j].Locations[1].Terri
            mobX = CurrentLog[i].Monsters[j].Locations[1].xCoord
            mobY = CurrentLog[i].Monsters[j].Locations[1].yCoord
            mobZ = CurrentLog[i].Monsters[j].Locations[1].zCoord
            ZoneName = Territories[tostring(mobZone)]

            yield("/echo " .. mobName .. " in " .. ZoneName .. " is next! We need " .. KillsNeeded)

            if IsInZone(tonumber(mobZone)) then
                -- Here we use a plugin called ChatCoordinates to make a flag and teleport to the zone
                if mobZ then
                    SetMapFlag(mobZone, mobX, mobY, mobZ)
                    yield("/echo Using better coordinates.")
                else
                    yield("/coord " .. mobX .. " " .. mobY .. " :" .. ZoneName)
                    yield("/wait 0.567")
                end
                -- If you are in the same zone, no need to teleport
            else
                if mobZ then
                    SetMapFlag(mobZone, mobX, mobY, mobZ)
                    yield("/wait 0.573")
                    yield("/echo Using better coordinates.")
                    yield("/tpm " .. ZoneName)
                    yield("/wait 10.576")
                    repeat
                        Sleep(0.1)
                    until IsPlayerAvailable() and not IsPlayerCasting()
                else
                    while not IsInZone(tonumber(mobZone)) do -- addresses getting attacked during tp
                        yield("/ctp " .. mobX .. " " .. mobY .. " :" .. ZoneName)
                        yield("/wait 10.583")
                        repeat
                            Sleep(0.1)
                        until IsPlayerAvailable() and not IsPlayerCasting()
                        while GetCharacterCondition(26) do
                            yield("/battletarget") -- if other mobs are attacking you
                            Sleep(0.10673)
                            TargetMoveFly()
                            while PathIsRunning() or PathfindInProgress() do
                                yield("/echo Attacking " .. mobName .. " moving closer.")
                                while GetDistanceToTarget() > 3.9 do
                                    Sleep(1.0678)
                                    if GetDistanceToTarget() > 15 then
                                        unstucktarget()
                                    end
                                end
                            end
                        end
                    end
                end
            end
            -- Now convert those simple map coordinates to RAW coordinates that vnav uses

            if mobZ then
                rawX = mobX
                rawY = mobY
                rawZ = mobZ
            else
                rawX = GetFlagXCoord()
                rawY = 1024
                rawZ = GetFlagYCoord()
            end

            if GetZoneID() == 139 and GetPlayerRawXPos() > -306 then -- avoid swimming in Upper La Noscea
                if mobName == "Kobold Footman" or mobName == "Kobold Pickman" then -- these two mobs are on the west side of Upper La Noscea
                    Movement(283.750, 46.000, -212.500)
                    Movement(-334.194, 51.997, -64.813)
                end
            end

            -- you're in the zone now, moving to flag

            MountandMovetoFlag()

            -- Wait until you stop moving and when you reach your destination, dismount

            while IsMoving() == true or PathIsRunning() == true or PathfindInProgress() == true do
                yield("/echo Moving to next area...")
                yield("/wait 1.0627")
            end

            if IsMoving() == false then
                yield("/wait 0.10631")
                if GetCharacterCondition(4) == true then
                    yield("/vnavmesh stop")
                    yield("/gaction dismount")
                    PathStop()
                    yield("/vnavmesh stop")
                    yield("/wait 1.0637")
                    yield("/gaction dismount")
                end
            end

            yield("/rotation manual")
            yield("/vbmai on")
            yield("/vbmai followtarget on")
            yield("/vbmai followoutofcombat on")
            yield("/vbmai followcombat on")

            OpenHuntlog()
            loadupHuntlog()
            killtimeout_start = os.clock()
            while IncompleteTargets() == mobName do
                LogInfo("Killing " .. mobName .. "s in progress...")
                OpenHuntlog()
                loadupHuntlog()
                if not GetCharacterCondition(26) then
                    yield("/target \"" .. mobName .. "\"")
                    Sleep(0.10671)
                    TargetMoveFly()
                    while PathIsRunning() or PathfindInProgress() do
                        yield("/echo Found " .. mobName .. " moving closer.")
                        while GetDistanceToTarget() > 3.9 do
                            Sleep(1.0676)
                            yield("/vnav movetarget")
                            if GetDistanceToTarget() > 15 then
                                unstucktarget()
                            end
                        end
                    end
                    if IsInFate() and not IsLevelSynced() then
                        yield("/lsync")
                    end
                    Sleep(0.10662)
                    yield("/vnav movetarget")                   
                    yield("/gaction dismount")
                    yield('/action "Auto-attack"')
                    Sleep(0.10665)
                end 
                while GetCharacterCondition(26) do
                    yield("/echo In combat against " .. GetTargetName())
                    yield("/wait 0.10670")
                    if IsInFate() and not IsLevelSynced() then
                        yield("/lsync")
                    end
                    if not HasTarget() then
                        yield("/battletarget") -- if other mobs are attacking you
                        Sleep(0.10673)
                        TargetMoveFly()
                        while PathIsRunning() or PathfindInProgress() do
                            yield("/echo Attacking " .. mobName .. " moving closer.")
                            while GetDistanceToTarget() > 3.9 do
                                Sleep(1.0678)
                                if GetDistanceToTarget() > 15 then
                                    unstucktarget()
                                end
                            end
                        end
                    end
                end
                yield("/vnav stop")
                hlogRefresh()
                yield("/wait 1.0689")
            end
        end
    end
end
yield("/echo Finished hunt log for Rank " .. rankToDo .. "!")
LogInfo("Finished hunt log for Rank " .. rankToDo .. "!")
if (GetZoneID() ~= 177 and GetZoneID() ~= 178 and GetZoneID() ~= 179) then
    Teleporter("inn", "li")
end