-- SMARL Race Control V2.0
-- By Seraph
-- RaceControl.lua
--[[
	-- set Race parameters, stop and start the race from here
]]

-- TODO: Store and set/load multi camera positions (save in bp?)
dofile "globals.lua"
dofile "Timer.lua" 

ZOOM_INSTRUCTIONS = MOD_FOLDER .. "/JsonData/zoomControls.json"
DECK_INSTRUCTIONS = MOD_FOLDER .. "/JsonData/cameraInput.json" -- TODO: Rename to keyInput.json
API_INSTRUCTIONS = MOD_FOLDER .. "/JsonData/apiInstructs.json"
QUALIFYING_DATA = MOD_FOLDER .. "/JsonData/raceOutput/qualifyingData.json" --
OUTPUT_DATA = MOD_FOLDER .. "/JsonData/RaceOutput/raceData.json" -- All race data
FINISH_DATA = MOD_FOLDER .. "/JsonData/raceOutput/finishData.json"
QUALIFYING_FLIGHT_DATA = MOD_FOLDER .. "/JsonData/qualifying_flight_" -- depreciated?
MAP_DATA = MOD_FOLDER .. "/JsonData/TrackData/"
RACER_DATA = MOD_FOLDER .. "/JsonData/RacerData/"

Control = class( nil )
Control.maxChildCount = -1
Control.maxParentCount = -11
Control.connectionInput = sm.interactable.connectionType.logic
Control.connectionOutput = sm.interactable.connectionType.logic
Control.colorNormal = sm.color.new( 0xffc0cbff )
Control.colorHighlight = sm.color.new( 0xffb6c1ff )
local clock = os.clock --global clock to benchmark various functional speeds ( for fun)
--[[ old dropdown wiget code
<Widget type="Widget" skin="PanelEmpty" position_real="0 0 1 0.1">
                    <Widget type="TextBox" skin="TextBox" name="DraftText" position_real="0 0 0.350877 1">
                        <Property key="Caption" value="Drafting Enabled:" />
                        <Property key="FontName" value="SM_TextLabel" />
                        <Property key="TextAlign" value="Left VCenter" />
                        <Property key="NeedMouse" value="false" />
                    </Widget>
                    <Widget type="Widget" skin="ActiveButton" name="DraftModeCollapsed" position_real="0.318421 0 0.525 0.85">
                        <Property key="NeedKey" value="false" />
                        <Property key="NeedMouse" value="true" />
                        <Widget type="TextBox" skin="TextBox" name="DraftValue" position_real="0.0138889 0.117647 0.888889 0.764706">
                            <Property key="Caption" value="- Draft Mode -" />
                            <Property key="FontName" value="SM_ListItem" />
                            <Property key="TextAlign" value="Center" />
                            <Property key="TextColour" value="1 0.831373 0.290196" />
                            <Property key="NeedMouse" value="true" />
                        </Widget>
                        <Widget type="Button" skin="PanelEmpty" name="DraftBtn" position_real="0 0 1 1" />
                        <Widget type="Button" skin="DropDownExpand" name="DraftBtn" position_real="0.888889 0 0.111111 1">
                            <Property key="Caption" value="V" />
                            <Property key="FontName" value="InventoryTitle" />
                        </Widget>
                    </Widget>
                </Widget>

]]

--[[
    Pre Race: (SM)
    1. Create track tile (save two versions, Raw and Final)
    2. Create new World with Final Tile inside (decorate accordingly)
    3. Load new Creative Game with new Track World
    4. Scan Track with RaceLineGenerator (ensure no errors and racing line makes sense with crouch interaction)
    5. Edit Final Tile with decorations as needed (changes show up in save)
    6. Load back into Creative game and place race cameras
    7. Test track with cars (place down race control)
    Race Steps (SM,Discord,Putty)
    1. Create Race in discord: `-!-createrace {track_name} {league_id}`
    2. Set self.qualifying = true (RaceControl.lua) -- For qualifying
    3. Open sharedData.py in overlay folder
    4.  Edit RaceTitle, RaceLocation, SeasonID, RaceID,league_id To current race info (sharedData.py)
    5. SSH into Abberhub and screen -ls to check both SMARLBOT and SMARLAPI are running
    6. Go into Mod folder's JsonData and run startScript.bat (python key reader for streamdeck)
    7. Start Game and load into Creative Game Track Save
    8. Place all Cars in according to Race's league (no easy way to do this yet)
    9. Run SMAR Overlay and reader with startOverlay.bat
    Qualifying: 
    1. (Ensure Qualifying = true & outputRealTime = true in racecontrol) Set laps = 3 and handicap = 2? in race control through normal interaction
    2. Pull in SMAR Camera tool and crouch interact to load into camera
    3. Start Race and auto camera switching (go to finish results before all cars finish)
    4. Commentate
    Race:
    1. Reset by Stopping race ( DO NOT STOP RACE BEFORE GETTING BROLL of Qualifying)
    2. Make sure race control is at 10 laps and 1.5? handicap
    3. Load Smar Camera tool and enter camera
    4. Record and Commentate (load finish overlay before all cars finish)
    5. If yellow flags then do so
    Post Race:
    1. Finalize Points in discord `-!-finalizerace`
    2. Record and display season Status 
    3. Remux, Edit Upload Premiere
]]


-- Local helper functions utilities
function round( value )
	return math.floor( value + 0.5 )
end

function Control.client_onCreate( self ) 
	self:client_init()
	--print("Created Race Control CL")
end

function Control.server_onCreate( self ) 
	self:server_init()
	--print("Created Race Control SV")
end

function Control.client_onDestroy(self)
    --print("Race control destroyed")
    --self:stopVisualization() -- Necessary?
    if self.RaceMenu then
		self.RaceMenu:close()
		self.RaceMenu:destroy()
	end
    if self.smarCamLoaded or true then
        self:client_exitCamera()
    end
end

function Control.server_onDestroy(self)
    --print("Race control destroyed SV")
    RACE_CONTROL = nil 
    --self:stopVisualization() -- Necessary?
end

function Control.client_init( self ) 
	-- metadata
    self.targetLaps = 10
    self.handiCapMultiplier = 0.5
    self.handiCapEnabled = true
    self.draftStrength = 3 -- how strong the draft can be
    self.draftingEnabled = true 

    self.raceStatus = 0
    
    self.currentLap = 0
    self.raceFinished = false

    self.aPressed = false
    self.dPressed = false
    self.sPressed = false
    self.wPressed = false
    self.zoomIn = false
    self.zoomOut = false
    -- Chat command Binding?...
    RACE_CONTROL = self -- move to function?
    -- Bind race stuff to chat commands --TODO: cannot do without game script edding -_-
	--sm.game.bindChatCommand( "/start", {}, "cl_onChatCommand", "Starts SMAR Cars" ) -- has to be called on game star in stuff
    --sm.game.bindChatCommand( "/stop", {}, "cl_onChatCommand", "Stop SMAR Cars" )
    --sm.game.bindChatCommand( "/chatcontrol", { { "bool", "enable", true } }, "cl_onChatCommand", "Toggles the usage of a power interactable vs chat commands to start/stop races" )
    -- UI Things:
    self.DropDownList = {
    DraftMode = { "Yes", "No" }
    --RaidGUIStyle = { "RaidWarningOn", "RaidWarningOff", "RaidAdjustSizeOn", "RaidAdjustSizeOff" }
    }
    self.PopUpYNOpen = false

    -- Race setup Menu
    self.RaceMenu = sm.gui.createGuiFromLayout( MOD_FOLDER.."Gui/Layouts/RaceMenu.layout",false ) -- TODO: Add Race status GUI too
        self.DraftExpanded = false
        --self.RaceMenu:setButtonCallback( "DraftBtn", "client_buttonPress" )
        --self.RaceMenu:setButtonCallback( "DraftYes", "client_buttonPress" )
        --self.RaceMenu:setButtonCallback( "DraftNo", "client_buttonPress" )

        -- Time Limit callbac NOTE: SLIDERS DO NOT WORK
        --self.RaceMenu:setSliderCallback( "TimeSlider", "cl_onSliderChange" )
        --self.RaceMenu:setButtonCallback( "TimeSlider", "client_buttonPress" )
        --self.RaceMenu:setVisible("TimeSlider",false)

        self.RaceMenu:setButtonCallback( "DraftBtnAdd", "client_buttonPress" )
        self.RaceMenu:setButtonCallback( "DraftBtnSub", "client_buttonPress" )

        self.RaceMenu:setButtonCallback( "LapBtnAdd", "client_buttonPress" )
        self.RaceMenu:setButtonCallback( "LapBtnSub", "client_buttonPress" )

        -- Game Point win callback here
        self.RaceMenu:setButtonCallback( "HandiBtnAdd", "client_buttonPress" )
        self.RaceMenu:setButtonCallback( "HandiBtnSub", "client_buttonPress" )

        -- etc...

        self.RaceMenu:setButtonCallback( "ResetRace", "client_buttonPress" )

        self.RaceMenu:setButtonCallback("PopUpYNYes", "client_buttonPress")
        self.RaceMenu:setButtonCallback("PopUpYNNo", "client_buttonPress")

        self.RaceMenu:setOnCloseCallback( "client_onRaceMenuClose" )

        -- Behavior Menue Setup
       


        self.BehaviorMenu = sm.gui.createGuiFromLayout( MOD_FOLDER.."Gui/Layouts/BehaviorEdit.layout",false ) -- TODO: Add Race status GUI too
        -- Set Defaults
        self.BehaviorMenu:setTextAcceptedCallback("WallDistV", "client_editAccepted")
        self.BehaviorMenu:setTextChangedCallback("WallDistV", "client_textChanged")

-- Camera things
    self.smarCamLoaded = false
    self.externalControlsEnabled = true -- TODO: remove on release
    self.viewIngCamera = false -- whether camera is being viewed
    self.cameraMode = 0 -- camera viewing mode: 0 = free cam, 1 = race cam

    self.currentCameraIndex = 1 -- Which camera index is currently being active, If there are no cameras, then just skip
	self.currentCamera = nil --Current Camera MetaData
	self.cameraActive = false -- if any Cameras Are being used ( redundent)
	self.onBoardActive = false -- If onboard camera is active

	
	self.focusedRacerID = nil -- ID of racer all cameras are being focused on
	self.focusedRacePos = nil -- The position of the racer all cameras are being focused on
	self.focusPos = false -- Keep camera focused on car set by focusedRacePos
	self.focusRacer = false -- Keep camera focused on Car set by racerID, nomatter the pos
	
	self.droneLocation = nil -- virtual location of the drone
    self.droneOffset = sm.vec3.new(10,10,40) -- virtual offset/movement of drone
    self.droneDirOffset =  sm.vec3.new(0,0,0) -- offsetting direction of drone (use on mousemove n stuff)
	self.droneActive = false -- if viewing drone cam

	self.droneFollowRacerID = nil -- Drone following racer
	self.droneFollowRacePos = nil -- Drone Following racePosition
	self.droneFocusRacerID = nil -- Drone Focus on racer
	self.droneFocusRacePos = nil -- Drone focus on racePos

	self.droneFollowPos = false -- Drone keep focused on following by racePosition
	self.droneFollowRacer = false -- Drone keep focused on following by racerID
	self.droneFocusPos = false -- Keep Drone Focused on focusing by racePos
	self.droneFocusRacer = false -- Keep Drone Focused on focusing by racerID
	
	self.focusedRacerData = nil -- All of the specified focused racer data
    self.followedRacerData = nil -- the racer that is specified for drone follo
	-- Followed racer data?
	--self.raceStatus = getRaceStatus()
	
    self.freecamSpeed = 2
	self.finishCameraActive = false -- If it is currently focusing on finish camera DEPRECIATED

	-- Error states to prevent spam
	self.errorShown = false
	self.hasError = false

    self.dt = 0
    self.camTransTimer = 1
    self.frameCountTime = 0 -- how many frames counted
    self.lastCamSwitch = self.frameCountTime -- last time camera was switched 
    self.noLos = 0
	--print("Camera Control Init")

end

function Control.server_init(self)
    self.debug = false
    self.raceStatus = 0 -- 0 is stopped, 1 is formation? 2 is race 3 is caution?, -1 is reset to posStart
    self.timers = {}
    self.powered = false
    self.chatToggle = false -- whether RC uses powered interactable or chat commands to start/stop cars
    self.handiCapEnabled = true
    self.draftingEnabled = true 
    self.started = CLOCK()
    self.targetLaps = 10
    self.currentLap = 0 -- whichever lap leader is on
    self.finishTime = 0 -- point at which leader finishes
    self.raceFinished = false -- Whether race is finished or not

    self.controllerSwitch = nil -- interactable that is connected to swtcgh


    -- Car Behavioral Defaults (loaded from Memory
    self.trackLimPad = 7
    self.trackLimStr = 0.1

    self.oppAvoidDst = 4
    self.oppAvoidStr = 0.1
    self.draftDistance = 70


    -- Car Importing behavior
    self.racerImportQue = {}



    -------------------- QUALIFYING SETUP -----------------
    self.qualifying = false -- whether we are qualifying or not -- dynamic
    self.qualifyingFlight = 1 -- which flight to store data as
    self.totalFlights = 1 -- choose how many flights there are (can automate but eh)
    -----------------------------------------------------
    -- Exportables
    self.finishResults = {}
    self.qualifyingResults = {}
    self.raceMetaData = {["status"]=0, ["lapsLeft"]=self.targetLaps, ['qualifying'] = string.format("%s",self.qualifying)}
    self.leaderID = nil -- race leader id
    self.leaderTime = 0 -- takes splits from leader
    self.leaderNode = 0 -- ? keeps track of which node leader is on
    self.trackName = "Test Oval"
    self.trackID = 1


    self.resetCarTimer = Timer()
    self.resetCarTimer:start(5)

    self.dataOutputTimer = Timer() -- MS TICKs so 1 = 1/40
    self.dataOutputTimer:start(1)
    self.outputRealTime = true  -- USE TO OUTPUT DATA TO SERVERS
    
    -- Camera automation
    self.autoCameraFocus = false
    self.autoCameraSwitch = false -- toggle automated camera things
    self.autoFocusDelay = 20
    self.autoSwitchDelay = 15

    self.autoFocusTimer = Timer()
    self.autoFocusTimer:start(self.autoFocusDelay) -- Set auto camera time here
    self.autoSwitchTimer = Timer()
    self.autoSwitchTimer:start(self.autoSwitchDelay) -- Set auto camera time here

    self.timeSplitArray = {} -- each node makes rough split

    self.draftStrength = 3 -- TODO: implement
    self.handiCapOn = false
    self.handiCapThreshold = 15 -- how far away before handicap starts
    self.handiCapStrength = 100
    self.handiCapMultiplier = 0.5 -- multiplies handicap by ammount
    self.maxHandiCap = 100 -- maximum slow down
    self.curHandiCap = 100
    RACE_CONTROL = self 
    -- TODO: Make lap count based off of totalNodes too, not just crossing line 
    self.sortedDrivers = {} -- Sorted list by race position of drivers, necessary? for printing?
    self.raceResultsShown = false
    self:updateRacers()

    -- just cam things
    self.smarCamLoaded = false
    self.externalControlsEnabled = true -- TODO: set false for releases
    self.viewIngCamera = false -- whether camera is being viewed
    

    -- Load previous quaifying data
    self.qualifyingResults = (self:sv_ReadQualJson() or {})


    -- Export current track
    self:sv_export_current_mapChain()
end

function Control.client_onRefresh( self )
	self:client_onDestroy()
	self:client_init()
end

function Control.server_onRefresh( self )
	self:server_onDestroy()
	self:server_init()
end



function sleep(n)  -- n: seconds freezes game?
  local t0 = clock()
  while clock() - t0 <= n do end
end

function Control.asyncSleep(self,func,timeout)
    --print("weait",self.globalTimer,self.gotTick,timeout)
    if timeout == 0 or (self.gotTick and self.globalTimer % timeout == 0 )then 
        --print("timeout",self.globalTimer,self.gotTick,timeout)
        local fin = func(self) -- run function
        return fin
    end
end

function runningAverage(self, num)
	local runningAverageCount = 5
	if self.runningAverageBuffer == nil then self.runningAverageBuffer = {} end
	if self.nextRunningAverage == nil then self.nextRunningAverage = 0 end
	
	self.runningAverageBuffer[self.nextRunningAverage] = num 
	self.nextRunningAverage = self.nextRunningAverage + 1 
	if self.nextRunningAverage >= runningAverageCount then self.nextRunningAverage = 0 end
	
	local runningAverage = 0
	for k, v in pairs(self.runningAverageBuffer) do
	  runningAverage = runningAverage + v
	end
	--if num < 1 then return 0 end
	return runningAverage / runningAverageCount;
end


function Control.updateRacers(self)
    local drivers = getAllDrivers()
    if #drivers > 0 then
        --print("RC updating drivers")
        for k=1, #drivers do local driver=drivers[k]
            if driver ~= nil then
                if driver.raceControlError then
                    --print("Pushing driver",driver.id)
                    driver:try_raceControl()
                end
            end
        end
    end
end


-- Saving and loading? --- TODO: THe Racecontrol will be only one that loads nodechain (might reduce lag?)
function Control.saveRacingLine(self) -- Saves nodeChain, may freeze game
end

function Control.sv_saveData(self,data) -- is it possible to save nodeChain into race control, save that object and import it to new worlds?
    debugPrint(self.debug,"Saving data")
    debugPrint(self.debug,data)
    local channel = data.channel
    data = self.simpNodeChain -- was data.raceLine --{hello = 1,hey = 2,  happy = 3, hopa = "hdjk"}
    print("saving Track")
    sm.storage.save(channel,data) -- track was channel
    saveData(data,channel) -- worldID?
    print("Track Saved")
end

function Control.loadData(self,channel) -- Loads any data?
    local data = self.network:sendToServer("sv_loadData",channel)
    if data == nil then
        print("Data not found?",channel)
        if data == nil then
            print("all data gone",data)
        end
    end
    return data
end


function Control.loadTrackData(self) -- loads in any track data from the world
    --print('loadTrackData network send')
    local data = self.network:sendToServer("sv_loadData",TRACK_DATA) -- Will be good
end

function Control.sv_loadData(self,channel)
    --print("svb_loadData")
    local data = sm.storage.load(channel)
    if data == nil then
        --print("Server did not find track data") 
        if self.trackLoadError then
        else
            print("Track Data not found")
            self.trackLoadError = true
        end
    else
        --print("Server found track data") 
        if self.trackLoadError then
            print("Track Loaded")
            self.trackLoadError = false
        else
            --print("Track Loaded, initial")
        end
    end
    self:on_trackLoaded(data) -- callback to confirm load
end

function Control.on_trackLoaded(self,data) -- Callback for when track data is actually loaded
    --print('on_trackLoaded')
    if data == nil then
        self.trackLoaded = false
    else
        self.trackLoaded = true
        self.nodeChain = data
        --print(self.nodeChain[1])
        if self.nodeMap == nil then
            --print("generating NodeMap")
            self.nodeMap = generateNodeMap(self.nodeChain)
        end
        local lastNode = getNextItem(self.nodeChain,1,-1)
        self.totalSegments = lastNode.segID
        if self.totalSegments <= 5 then
            print("Oval Track??",self.totalSegments)
            self.ovalTrack = true
        end
        --print("total segments",self.totalSegments)
    end
end

function Control.checkForClearTrack(self,nodeID) -- Checks for any cars within 50? nodes on node chain
    local clearFlag = true
    local clearThreshold = distance -- make dynamic?
    --local minNode = getNextItem(self.nodeChain,nodeID,-50)
    local maxNode = getNextItem(self.nodeChain,nodeID,5)
    --print("MinNode",minNode.id)
    for k=1, #ALL_DRIVERS do local v=ALL_DRIVERS[k]
        if v.id ~= self.id then 
            --print("scanning",v.id,v.stuck,v.rejoining,v.currentNode.id)
            if not (v.stuck or v.rejoining) then -- If its not stuck
                if v.currentNode ~= nil and v.speed > 0 then 
                    local node = v.currentNode.id
                    local nodeDist = getNodeDistBackward(#self.nodeChain,maxNode.id,node)
                    if nodeDist < 35 then
                        --print("not clear")
                        clearFlag = false
                    end
                end
            end
        end
    end
    return clearFlag
end

function Control.sv_setDraft(self,mode) -- enables or disables drafte
    self.draftingEnabled = mode
end

function Control.sv_sendCommand(self,command) -- sends a command to Driver Command Structure: {Car [id or -1/0? for all], type [racestatus..etc], value [0,1]}
    -- parse recipients
    local recipients = command.car
    if recipients[1] == -1 then -- send all
        local allDrivers = getAllDrivers()
        for k=1, #allDrivers do local v=allDrivers[k]
            v:sv_recieveCommand(command)
        end
    else -- send to just one
        local drivers = getDriversFromIdList(command.car)
        for k=1, #drivers do local v=drivers[k]
            v:sv_recieveCommand(command)
        end
    end
end

-- Car/Creation Managment
function Control.sv_delete_racer(self,racer_id)
    -- removes creation
    print("Deleting racer",racer_id)
    local racer  = getDriverFromMetaId(racer_id)
    if racer == nil then print(" no racer found") return end
    local all_shapes = racer.body:getCreationShapes()
    if all_shapes then
        for k=1, #all_shapes  do local s = all_shapes[k]
            s:destroyShape()
        end
    end
end

function Control.sv_delete_racer_id(self,driver_id) -- uses main body id instead (for non metadata racers)
    -- removes creation
    print("Deleting racer",driver_id)
    local racer  = getDriverFromId(driver_id)
    if racer == nil then print(" no racer found") return end
    local all_shapes = racer.body:getCreationShapes()
    if all_shapes then
        for k=1, #all_shapes  do local s = all_shapes[k]
            s:destroyShape()
        end
    end
end

function Control.sv_delete_all_racers(self)
    print("Deleting all racers")
    for k=1, #ALL_DRIVERS  do local r = ALL_DRIVERS[k]
        if r.id then
            self:sv_delete_racer_id(r.id)
        end 
    end
end


function Control.sv_racer_import_loop(self) -- Keeps tracks and imports racers when ready
    if self.racerImportQue and #self.racerImportQue > 0 then
        local racerID = self.racerImportQue[1] -- placeholder first car only removes when spawned
        local result = self:sv_import_racer(racerID)
        if result == true then
            table.remove(self.racerImportQue,1) -- pulls first in queue
        else
            -- waiting, possibly shift spawn points?
            -- Table insert alternative: t[#t+1] = i
        end
    end

end

function Control.sv_add_racer_to_import_queue(self,racer_id) -- does what it says
    print("Adding Racer to Queue",racer_id)
    -- Check if racer is already in queue or racer already on track
    local isInQueue = findValue(self.racerImportQue,racer_id)
    if isInQueue then 
        print("Racer already in queue",racer_id)
        return
    end

    local isInRace = findKeyValue(getAllDrivers(),'meta_id',racer_id)
    if isInRace then
        print("Racer already in race",racer_id)
        return
    end

    table.insert(self.racerImportQue,racer_id)
end


function Control.sv_import_racer(self,racer_id) -- uses reacer META ID
    local dataFile = RACER_DATA .. racer_id .. ".json"
    -- Set location to first point after finish line
    local spawnLocation = sm.vec3.new(0,0,10)
    local spawnRotation = nil
    local spawnNodeID = 8
    if self.nodeChain then
        local targetNode = self.nodeChain[spawnNodeID]
        if targetNode then
            spawnLocation = targetNode.mid + sm.vec3.new(0,0,.5)
             -- Make Sure spawn wih clear tracks behind and a padding ahead for slow cars
            isClear = self:checkForClearTrack(spawnNodeID,self.nodeChain)
            if isClear == false then
                --print("waiting for clear track before spawn")
                return false
            end
            spawnRotation = sm.vec3.getRotation(sm.vec3.new(-1,0,0),sm.vec3.new(targetNode.outVector.x,targetNode.outVector.y,0))
            --sm.quat.fromEuler(targetNode.outVector:rotateX(90))
        end

        local world = sm.world.getCurrentWorld()
        if sm.json.fileExists(dataFile) then
            print("Importing Creation",dataFile,spawnRotation)
            sm.creation.importFromFile(world,dataFile,spawnLocation,spawnRotation)
            return true
        else
            print("Racer Data file not found",dataFile)
            return true -- Remove car from list anyway
        end
    else
        print("no race control nodechain defined")
    end

    return false
end

function Control.sv_import_racers(self,racer_list) -- imports racers based of meta ID and an array
    print("importing racers")
    local carPadding = 3 -- How many nodes of padding to buffer cars out
    local frontNodeID = (#racer_list * carPadding) + carPadding
    local world = sm.world.getCurrentWorld()
    print("spawning",frontNodeID,racer_list)
    for k=1, #racer_list  do local r = racer_list[k]
        if self.nodeChain then
            local targetNodeID = frontNodeID - (k*carPadding)
            if targetNodeID <= 1 then
                print("ran out of spawn room")
                break
            end
            local targetNode = self.nodeChain[targetNodeID]
            if targetNode then
                spawnLocation = targetNode.mid + sm.vec3.new(0,0,.5)
                spawnRotation = sm.vec3.getRotation(sm.vec3.new(-1,0,0),sm.vec3.new(targetNode.outVector.x,targetNode.outVector.y,0))
                --sm.quat.fromEuler(targetNode.outVector:rotateX(90))
            end
        
            local dataFile = RACER_DATA .. r .. ".json"
            if sm.json.fileExists(dataFile) then
                print("Importing Creation",dataFile,spawnRotation)
                sm.creation.importFromFile(world,dataFile,spawnLocation,spawnRotation)
            else
                print("Racer Data file not found",dataFile)
            end
        end
    end
end


function Control.sv_import_league(self,league_id)
    local a_league = {1,2,3,5,6,7,8,9,10,11,12,13,15,16,17,18}
    local b_league = {14,19,20,21,22,23,24,25,26,27,28,30,31,33}
    local leagues = {a_league,b_league}
    print("importing League",league_id)
    self:sv_import_racers(leagues[league_id])
end
 



-- CAMERA THINGS
function Control.cl_sendCameraCommand(self,command) --client sends a command obj {com, val} to camera
    --print("sending cam",self.smarCamLoaded,command)
    --print(getSmarCam())
    if self.smarCamLoaded then
        getSmarCam():cl_recieveCommand(command)
    end
end

function Control.sv_sendCameraCommand(self,command) --server sends a command obj {com, val} to camera
    --print("sv sending cam")
    if self.smarCamLoaded then
        getSmarCam():sv_recieveCommand(command)
    end
end

function Control.cl_setZoomInState(self,state)
    --print("zoomIn = ",state)
    self.zoomIn = state
end

function Control.cl_setZoomOutState(self,state)
    --print("zoomOut = ",state)
    self.zoomOut = state
end

function Control.sv_setZoomInState(self,val)
    local state = false
    if val == 1 then
        state = true
    end
    self.network:sendToClients("cl_setZoomInState",state) --TODO maybe have pcall here for aborting versus stopping -- TODO: Find out how often this is called
end


function Control.sv_setZoomOutState(self,val)
    local state = false
    if val == 1 then
        state = true
    end
    self.network:sendToClients("cl_setZoomOutState",state) --TODO maybe have pcall here for aborting versus stopping -- make efficient
end

function Control.cl_setZoom(self)
    --print(self.zoomIn,self.zoomOut)
    local zoomSpeed = 0.1
    if (self.zoomIn and self.zoomOut) or  (not self.zoomIn and not self.zoomOut) then -- add self.zooming attribute, indicate zoom
        self:cl_sendCameraCommand({command="SetZoom",value=0})
    end
    if self.zoomIn then
        --print("send zoom in")
        self:cl_sendCameraCommand({command="SetZoom",value=zoomSpeed})
    end

    if self.zoomOut then
        self:cl_sendCameraCommand({command="SetZoom",value=-zoomSpeed})
    end
end

function Control.cl_moveCamera(self)
    local moveVec = sm.vec3.new(0,0,0)
    if self.aPressed then 
        moveVec = (moveVec - sm.camera.getRight())
    end
    if self.dPressed then -- rip
        moveVec = (moveVec + sm.camera.getRight())
    end

    if self.wPressed then 
        moveVec = (moveVec + sm.camera.getDirection()) 
    end

    if self.sPressed then
        moveVec = (moveVec - sm.camera.getDirection()) 
    end

    if self.spacePressed then -- move up -- Why do I care about shiftpressed? [...and not self.shiftPressed]
        moveVec = sm.vec3.new(moveVec["x"], moveVec["y"], moveVec["z"] + 1) 
    end

    if self.ePressed then -- move up
        moveVec = sm.vec3.new(moveVec["x"], moveVec["y"], moveVec["z"] - 1)
    end 

    --print("movement",self.aPressed,self.dPressed,self.wPressed,self.sPressed,self.spacePressed,self.ePressed)
    return moveVec * self.freecamSpeed
end

---
function  Control.sv_recieveCommand( self,command ) -- recieves command/data from car (similar structure as send, but just received)
   --print("Race Control recieved command",command)
    if command.type == "add_racer" then -- adding car to race, send back race status as ack
        self:sv_sendCommand({car = command.car, type = "raceStatus", value = self.raceStatus})
    end
    if command.type == "get_raceStatus" then --
        self:sv_sendCommand({car = command.car, type = "raceStatus", value = self.raceStatus})
    end

    if command.type == "lap_cross" then -- racer has crossed lap
        self:processLapCross(command.car,command.value)
    end

    if command.type == "set_caution_pos" then -- racer has crossed lap
        self:setCautionPositions(command.car,command.value)
    end

    if command.type == "set_formation_pos" then -- racer has crossed lap
        self:setFormationPositions(command.car,command.value)
    end

   

end

function Control.sv_checkReset(self) -- checks if the car can reset
    --print("can reset car?",self.resetCarTimer:done(),self.resetCarTimer:remaining())
    return self.resetCarTimer:done()
end

function Control.sv_resetCar(self) -- resetc acar timer
    --print("resetting car reset countown")
    self.resetCarTimer:start(3)
end

function Control.sv_setHandicaps(self)
    --print('hc')
    local allDrivers = getAllDrivers()
    local firstNode = 0
    local firtstPlace = nil
    for k=1, #allDrivers do local driver=allDrivers[k] --- find first 
        if driver.racePosition == 1  then
            firstNode = driver.totalNodes
        end
    end
    for k=1, #allDrivers do local driver=allDrivers[k]
        local nodeDif = firstNode - driver.totalNodes
        local handicap = nodeDif 
        if nodeDif < self.handiCapThreshold or self.raceStatus > 1 then -- caution or formation
            handicap = 0
        elseif nodeDif > self.handiCapStrength then
            handicap = self.handiCapStrength
        end
        --self:sv_sendCommand({car = driver.id, type="handicap", value=handiCap) honesty unecessary...
        if handicap == nil then handicap = 1 end
        driver.handicap = handicap * self.handiCapMultiplier
        --print(driver.handicap,self.handiCapMultiplier )
        
    end
end

function Control.sv_setHandicaps2(self) -- just based on position
    local allDrivers = getAllDrivers()
    local firstNode = 0
    
    for k=1, #allDrivers do local driver=allDrivers[k] --- find first 
        if driver.racePosition == 1  then
            firstNode = driver.totalNodes
        end
    end
    local maxNodeDif = 0
    local numInFight = 0
    for k=1, #allDrivers do local driver=allDrivers[k]
        if driver == nil then return end
        if self.raceStatus > 1 then -- just shortcut this if caution or formation
            driver.handicap = 0
        else
            local nodeDif = (firstNode - driver.totalNodes) * 1.2
            local handicap = 0
            maxNodeDif = math.max(nodeDif,maxNodeDif) -- add on to max
            if nodeDif <= self.handiCapThreshold then -- if nodedif less than 5 (close to leader)
                -- reduce leader handicap the more there is close
                handicap = self.curHandiCap -- First gets highest possible handicap
                numInFight = numInFight + 1
            else -- if node dif further awway from leader
                handicap = self.curHandiCap - nodeDif -- reduces handicap by number of nodes away
            end
            if handicap < -20 then -- clamp handicap if too fast... Shouldnt be an issue but here anyways
                handicap = -20
            end
            if handicap == nil then handicap = 1 end
            driver.handicap = handicap * self.handiCapMultiplier
            --print(driver.racePosition,nodeDif,driver.handicap)
        end
    end
    -- maxHandiCap gets adjusted by the number of cars close
    local maxHandiCap = self.maxHandiCap
    local inRangeAdjust = (maxHandiCap*(numInFight/#allDrivers))*0.99 -- Adjusts handicap to basically be 0 if all cars are in the fight
    local nodeDifAdjust = maxNodeDif * 1.8

    self.curHandiCap = mathClamp(0,self.maxHandiCap,self.maxHandiCap - inRangeAdjust + nodeDifAdjust) -- clamp so we dont have an overpowered handicap
end



function Control.sv_toggleRaceMode(self,mode) -- starts 
    --print("toggling race mode")
    
    if mode == 0 then --
        print("stopping race")
        self:sv_stopRace()
    elseif mode == 1 then
        print("starting race")
        self:sv_startRace()
    elseif mode == 2 then
        print("Yellow flag")
        self:sv_cautionFormation()
    elseif mode == 3 then 
        print("formation lap")
        self:sv_startFormation()
    end
    -- format and output status streing
    local lapsLeft = getLapsLeft()
    if lapsLeft == nil then
        lapsLeft = "--"
    end
    self.raceMetaData = {["status"]=mode, ["lapsLeft"]=lapsLeft,['qualifying'] = string.format("%s",self.qualifying)}
    --self:sv_output_data(output)
end

function Control.sv_startRace(self) -- race status 1
    --print("Race Start!") -- introduce delay?
    self:sv_sendAlert("Race Started")
    self.raceStatus = 1
    -- check if active or not first
    self:sv_sendCommand({car = {-1},type = "raceStatus", value = 1 })
    self:sv_sendCameraCommand({command ="setRaceMode", value = 1 })
    --self.controllerSwitch:setActive(true) TODO: find proper workaround otherwise just remove the switch
end


function Control.sv_stopRace(self) -- race status 0
    self:sv_sendAlert("Race Stopped")
    self.raceStatus = 0
    self:sv_sendCommand({car = {-1},type = "raceStatus", value = 0 })
    self:sv_sendCameraCommand({command ="setRaceMode", value = 0 })
    -- check if active or not
    --self.controllerSwitch:setActive(false)
    if self.raceFinished then
        print("Stopping finished race: auto reset")
        self:sv_resetRace()
    end
end

function Control.sv_startFormation(self) -- race status 3
    print("Beggining formation lap")
    -- set formation pos
    self:setFormationPositions()
    self:sv_sendAlert("Starting Formation Lap")
    self.raceStatus = 3
    self:sv_sendCommand({car = {-1},type = "raceStatus", value = 3 })
    --self:sv_sendCameraCommand({command ="setRaceMode", value = 3 }) TODO: uncomment when white box added

end


function Control.sv_cautionFormation(self) -- race status 2
    self:sv_sendAlert("#FFFF00Caution Flag")
    self.raceStatus = 2
    self:sv_sendCommand({car = {-1},type = "raceStatus", value = 2 })
    self:sv_sendCameraCommand({command ="setRaceMode", value = 2 })
end

function Control.setCautionPositions(self) -- sv sets all driver caution positions to their current positions
    for k=1, #ALL_DRIVERS do local v=ALL_DRIVERS[k]
        local curPos = self.cautionPos
        v.cautionPos = v.racePosition
        
    end
end


function Control.setFormationPositions(self) -- sv sets all driver caution positions to their current positions
    qualData = self.qualifyingResults --self:sv_ReadQualJson()

    -- Properly update driver positions
    if qualData and #qualData == #ALL_DRIVERS then 
        for k=1, #qualData do local v=qualData[k] -- sets driver formation position based on data
            local id = v.racer_id
            local driver = getDriverFromMetaId(id)
            if driver ~= nil then
                driver.formationPos = v.position
            else
                print("missing",v.racer_name)
            end
        end 
    else
        for k=1, #ALL_DRIVERS do local v=ALL_DRIVERS[k] -- sets driver formation position based index placed
            v.formationPos = k
        end 
    end
end
    --print("Set caution Positions")

function Control.cl_resetRace(self) -- sends commands to all cars and then resets self
    self.aPressed = false
    self.dPressed = false
    self.sPressed = false
    self.wPressed = false
    self.zoomIn = false
    self.zoomOut = false

    self.network:sendToServer("sv_resetRace")
    --self:client_onRefresh()
end

-- TODO: do not do a full reset, just reset some values
function Control.sv_resetRace(self) -- sends commands to all cars and then resets self
    print("Resetting race")
    self:sv_sendCommand({car = {-1}, type = "resetRace", value = 0}) -- extra data in value just in ccase?
    self:sv_sendAlert("Race Reset")
    --self:server_onRefresh()
    self.finishResults = {}
    self.qualifyingResults = {}
    self.raceMetaData = {["status"]=0, ["lapsLeft"]=self.targetLaps, ['qualifying'] = string.format("%s",self.qualifying)}
    self.leaderID = nil -- race leader id
    self.leaderTime = 0 -- takes splits from leader
    self.leaderNode = 0 -- ? keeps track of which node leader is on

    self.autoCameraFocus = false
    self.autoCameraSwitch = false -- toggle automated camera things

    self.timeSplitArray = {} 
    self:updateRacers()
    self.qualifyingResults = (self:sv_ReadQualJson() or {})
    
    
end

function Control.cl_ChangeDraft(self,mode) -- adjusts metaData to switch game modes
    if mode == nil then return end -- NO switch necesary
    if mode == "DraftYes" then -- FFA mode
        print("Enabled draft")
        self.network:sendToServer("sv_setDraft",true)
    elseif mode == "DraftNo" then -- Teams
        print("Disabled draft")
        self.network:sendToServer("sv_setDraft",false)
    else
        print("WAT?")
    end
end

function Control.sv_changeLapCount(self,ammount) -- changes the game time by ammount
    if ammount == nil then return end
    self.targetLaps = self.targetLaps + ammount
    if self.targetLaps <= 1 then
        self.targetLaps = 1
    end
    self.network:setClientData(self.targetLaps) -- send tagetLaps to clients
end

function Control.sv_changeHandiCap(self,ammount) -- changes the game time by ammount
    if ammount == nil then return end
    
    if self.handiCapMultiplier <= 0.05 and ammount <0 then
        print("disabled handicap")
        self.handiCapMultiplier = 0
    else
        self.handiCapMultiplier = self.handiCapMultiplier + ammount
    end
    --print("change handimul",self.handiCapMultiplier)
    self.network:setClientData(self.handiCapMultiplier)
end


function Control.sv_changeDraft(self,ammount) -- changes the game time by ammount
    if ammount == nil then return end
    --print(self.draftStrength)
    if self.draftStrength <= 0.05 and ammount <0 then
        print("disabled Draft")
        self.draftStrength = 0
        self.draftingEnabled = false
    else
        if self.draftingEnabled == false then
            print("enbled draft")
            self.draftingEnabled = true
        end
        self.draftStrength = self.draftStrength + ammount
    end
    --print("change handimul",self.handiCapMultiplier)
    self.network:setClientData(self.draftStrength) 
end


function Control.findSplitNode(self,nodeNum) -- finds node id out of timesplit node (Need to have better way to find to prevent for loops, Could use a constantly updating nodeID offset)
    for k, v in pairs(self.timeSplitArray) do
        if v.id == nodeNum then
            return v
        end
    end
    return nil
end

function Control.sv_insertSplitNode(self,nodeNum,node) -- generates node and inserts into timesplit table
    local timeSplitNode = { ['id'] = nodeNum,
                            ['node_id'] = node.id,
                            ['time'] = CLOCK()
                        }
    table.insert(self.timeSplitArray, timeSplitNode)
    --print("added",nodeNum, #self.timeSplitArray)
end

function Control.sv_removeSplitNode(self,nodeNum) -- TODO: adjust so it deletes all things before this, not just one node
    for k, v in pairs(self.timeSplitArray) do
        if v.id <= nodeNum then
            table.remove(self.timeSplitArray, k)
            --print("removed",#self.timeSplitArray)
        end
    end
end

function Control.sv_getNodeSplit(self,nodeNum) -- Returns node split from leader based off of node id and array
    local node = self:findSplitNode(nodeNum)
    if node == nil then
        --print("Not in array?",nodeNum,#self.timeSplitArray)
        return nil -- default 0
    else
        local splitTime =  CLOCK() - node.time
        return splitTime
    end
end

function Control.processLapCross(self,car,time) -- processes what to do when car crosses lap [server]
    local driver = getDriverFromId(car)
    if driver == nil then return end 
    if driver.racePosition == 1 then -- if car in front
        --print("driver lap",driver.currentLap)
        self.currentLap = driver.currentLap
        self.leaderTime = time
        self.leaderID = car
        if self.currentLap > self.targetLaps and self.raceFinished == false then
            print("Race finished!",driver.tagText, "wins!")
            self.raceFinished = true
            driver.raceFinished = true
            self.finishTime = time
            -- TODO: Send Chat message with complete stats nicely formatted
            if self.qualifying then
                -- Reset already populated qualResults
                if self.qualifyingResults == nil or (self.qualifyingResults and #self.qualifyingResults >= 1) then
                    self.qualifyingResults = {}
                end
            end
        end
        -- reduce laps left
        local lapsLeft = getLapsLeft() -- shortcut with driver racepos
        if lapsLeft == nil then
            lapsLeft = "--"
        end
        if self.raceStatus == nil then
            self.raceStatus = 1
        end
        self.raceMetaData = {["status"]= self.raceStatus, ["lapsLeft"] = lapsLeft, ['qualifying'] = string.format("%s",self.qualifying)}
        --self:sv_output_data(output)
    end

    if self.currentLap <= self.targetLaps  then -- race on going -- or qualifying
        if self.currentLap >= 1 and self.handiCapEnabled == true then -- second lap, Enable drafting and handicap
            self.handiCapOn = true
            --self.draftingEnabled = true
        end

        if self.currentLap  == self.targetLaps - 1 then -- last laps
            driver.passAggression = -0.2 -- more agggressive passes?
            driver.skillLevel = driver.skillLevel + 3
        end
            --TODO: Investigate why car tied with 10th of second between them theoretically
        self.raceFinished = false
    else
        if self.currentLap == self.targetLaps + 1 then -- only run when car has reached one lap over
            self.raceFinished = true
            if driver.carData['metaData'] == nil then return end
            local time_split = string.format("%.3f",driver.raceSplit)
            local finishData = {
                ['position'] = driver.racePosition,
                ['body_id'] = driver.id, -- TODO: FIx this so it can hold cars with no metadata too
                ['racer_id'] = driver.carData['metaData']["ID"],
                ['racer_name'] = driver.carData['metaData']["Car_Name"],
                ['best_lap'] = driver.bestLap,
                ['split'] = time_split
            }
            if self.qualifying then -- insert qualifyingData
                
                --print("Qualifyind data inserted",finishData)
                table.insert(self.qualifyingResults,finishData)
                if self.qualifyingResults ~= {} then
                    --print("Saving Qualifying Results")
                    sm.json.save(self.qualifyingResults,QUALIFYING_DATA)
                end
            else -- store in finish results 
                table.insert(self.finishResults,finishData) -- also store in finishResults
            end
            --print("Finished:",#self.finishResults, #ALL_DRIVERS)
            
        end
    end
    
    if driver.raceFinished ~= self.raceFinished then -- send message to driver to slow? variable slow speeds?
        driver.raceFinished = self.raceFinished
        --self:sv_output_data(outputString) export here too?
    end

end

function Control.manualOutputData(self)
    local outputString = 'finish_data= [ {"id": "6", "bestLap": "61.518", "place": "1", "split": "0.000"},{"id": "15", "bestLap": "62.501", "place": "2", "split": "0.653"},{"id": "1", "bestLap": "61.421", "place": "3", "split": "0.901"},{"id": "17", "bestLap": "62.649", "place": "4", "split": "1.883"},{"id": "9", "bestLap": "62.935", "place": "5", "split": "2.203"},{"id": "11", "bestLap": "61.171", "place": "6", "split": "2.886"},{"id": "3", "bestLap": "62.302", "place": "7", "split": "3.650"},{"id": "18", "bestLap": "62.702", "place": "8", "split": "5.783"},{"id": "8", "bestLap": "62.487", "place": "9", "split": "9.954"},{"id": "13", "bestLap": "61.567", "place": "10", "split": "10.950"},{"id": "7", "bestLap": "60.429", "place": "11", "split": "11.599"},{"id": "2", "bestLap": "62.145", "place": "12", "split": "11.750"},{"id": "12", "bestLap": "61.768", "place": "13", "split": "22.334"},{"id": "5", "bestLap": "62.902", "place": "14", "split": "23.050"},{"id": "16", "bestLap": "61.532", "place": "15", "split": "29.734"},{"id": "10", "bestLap": "61.384", "place": "16", "split": "62.782"}]'
    self:sv_output_data(outputString)
end

function Control.findLogicCon(self) -- returns connection that is logic
    local parents = self.interactable:getParents()
    if #parents == 0 then
        --no parents
    elseif  #parents == 1 then 
        -- one parent
    end

	for k=1, #parents do local v=parents[k]--for k, v in pairs(parents) do
		local parentColor =  tostring(sm.shape.getColor(v:getShape()))
        if v:hasOutputType(sm.interactable.connectionType.logic) then -- found switch
            return v
        else
            --
        end
    end
end

function Control.server_onFixedUpdate(self)
    local startTime = os.clock()
    self:tickClock()
    self:ms_tick() -- 1 tick is 1 tick
    if getSmarCam() ~= nil and getSmarCam() ~= -1 then -- either constanlty check or only check when flag is false
        if not self.smarCamLoaded then
            self.smarCamLoaded = true
            print("smar cam loaded",getSmarCam()~= -1)
        end
    else
        if self.smarCamLoaded then
            print("smar cam Lost",self.smarCamLoaded)
            self.smarCamLoaded = false
        else
            --print("no cam loaded")
        end
    end

    if self.externalControlsEnabled then
        self:sv_ReadDeck()
        self:sv_readZoomJson()
        self:sv_readAPI()
    end

    -- TODO: Check count of parent, throws error if more than one
    local switch = self:findLogicCon() -- Check if switch on
    if switch == nil then
        if self.powered or self.raceStatus ~= 0 then
            --print("switch destroyed while things on i think")
        end 
    else
        if self.controllerSwitch == nil then
            self.controllerSwitch = switch
        end
        local power = switch:isActive() -- Lets have switch control but also not cont
        
        if power == nil and self.powered == true then -- turn off
            if self.powered or self.raceStatus ~= 0 then
                self:sv_stopRace()
            end
        elseif power and self.powered == false then -- switch on
            if self.raceStatus == 0 or self.powered == false then
                self:sv_startRace()
            end
        elseif power == false and self.powered == true then
            if self.powered or self.raceStatus ~= 0 then
                self:sv_stopRace()
            end
        else -- Do nothing
            --print("HUH?",self.powered,power)
        end
        self.powered = power -- update after checks (TODO: only run when discrepancy)
    end
    if self.handiCapOn then
        --self:sv_setHandicaps()
        self:sv_setHandicaps2()
    end
    -- Determine if self exists
    local raceControl = getRaceControl()
    if raceControl == nil then -- turn error on
        print("Defining RC")
        RACE_CONTROL = self
    else -- TUrn error off
        
        --print("defined RC")
    end

    -- Check race positions
    if self.raceFinished and not self.raceResultsShown then -- show more stuff after all cars done?
        --print("race done")
        self:sv_sendAlert("Race Finished")
        self.raceResultsShown = true
    end
    self.lastClientUpdateTime = CLOCK()

    local endTime = os.clock()
    local timeDif = endTime - startTime 
    --print("rcTD",timeDif)
end

function Control.client_onFixedUpdate(self) -- key press readings and what not clientside
   -- MOve
   -- If freeCam on then
    --print("RC cl fixedBefore")
    --print(self.smarCamLoaded,self.viewIngCamera,self.cameraMode)
    if self.smarCamLoaded then
        if self.viewIngCamera then
            self:cl_setZoom()
            if self.droneActive or self.onBoardActive then -- if drone mode active, overide
                
                local movement = self:cl_moveCamera()
                --print(movement:length())
                if movement ~= nil and movement:length() ~= 0 then 
                    --print("changin moves",movement) 
                    self.droneOffset = self.droneOffset + (movement/2) -- TODO: Somehow have orientation lock?
                end
            
            elseif self.cameraMode == 0 then -- and in free cam mode
                local movement = self:cl_moveCamera()
                if movement ~= 0 and movement ~= nil then
                    --print("Camera mode 0 Setting Pos")
                    self:cl_sendCameraCommand({command = "MoveCamera", value=movement})
                end
            elseif self.cameraMode == 1 then -- raceCamMode -- TODO: probably just remove all of thie
                
                if self.autoSwitchTimer:status() >= 1 and self.autoCameraSwitch == true then --TODO: figure this one out, currently  checking after 2 ticks
                    if self.currentCamera then
                        local dis = getDistance(self.currentCamera.location,self.focusedRacerData.location)
                        local los = get_los(self.currentCamera,self.focusedRacerData)
                        if los == true then 
                            self.noLos = 0  -- Reset los timeout
                        else 
                            self.noLos = self.noLos + 1 -- increment los timeout
                        end 
                        --print("checking",dis,los)
                        if dis > 185 then
                            --print('car no sseeee?',dis,los)
                            --print('a3',self.autoCameraSwitch)
                            --print("emergency distance cam switch")
                            self.network:sendToServer("sv_performAutoSwitch")
                        elseif los == false and self.noLos >= 8 then -- TODO: Add lOS fail timeout so it must fail x times before auto switch
                            --print("emergency LOS cam switch")
                            self.network:sendToServer("sv_performAutoSwitch")
                        end
                            
                    end
                end
                              
                    
                
                if #ALL_CAMERAS > 0 and self.currentCamera == nil then
                    --print("swittchingto camera 1")
                    self:switchToCameraIndex(1) -- go to first camera
                end
            end
        end

    end
    --print("RC cl fixedAfter")
    
end

function Control.client_onUpdate(self,dt)
    --print("RC cl onUpdate before")
    if self.viewIngCamera then
        sm.gui.setInteractionText( "" )
        sm.gui.setInteractionText( "" )
    end
    self.frameCountTime =  self.frameCountTime + 1
    local goalOffset = nil
    self.dt = dt
    local camDir = sm.camera.getDirection()
    -- TODO; just have updateCameraPos called once and have each mode set the goaloffsets
    if self.cameraMode == 1 and not (self.droneActive or self.onBoardActive) then -- raceCam
        --print("on raceCam",self.currentCamera.location)
        if self.currentCamera == nil then return end -- just ccut off
        goalOffset = self:getFutureGoal(self.currentCamera.location)
        --print("Calculating goalOffset",self.currentCamera.cameraID,goalOffset,sm.camera.getDirection())
        
        if goalOffset == nil then
            return
        end
        if self.focusRacer then
            self:calculateFocus()
        end
        --print("update pos",goalOffset)
        self:updateCameraPos(goalOffset,dt)
    elseif self.droneActive then

        self:droneExecuteFollowRacer()
        -- used self.droneLocation, what if we used current camera location instead?
        local camPos = sm.camera.getPosition()
        if self.camTransTimer == 1 then -- within the frame of goal
            camPos = self.droneLocation -- TODO: figure out why this
        end
        -- hold off on currentCamDir until after a few frames, use droneLocation at first
        --print("Getting goal",self.camTransTimer,camPos)
        goalOffset = self:getFutureGoal(camPos)
        self:updateCameraPos(goalOffset,dt) -- can just moive duplicates outside of ifelse
    elseif self.onBoardActive then
        --TODO: perform checking foer valid car funcion and what not
        local camPos = sm.camera.getPosition() -- Can move this up outside of function
        goalOffset = self:getFutureGoal(camPos)
        self:updateCameraPos(goalOffset,dt)
    end


    if self.RaceMenu then
        if self.draftingEnabled then
            self.RaceMenu:setText("DraftValue", "Yes" )
        else
            self.RaceMenu:setText("DraftValue", "No"  )
        end
    end

    local raceStat = " - "
    local lapStat = " - "
    local statusText = ""
    if self.raceStatus == 1 then
        raceStat = "Race Status: #11ee11Racing"
    elseif self.raceStatus == 0 then
        raceStat = "Race Status: #ff2222Stopped"
    elseif self.raceStatus == 2 then
        raceStat = "Race Status: #ffff11Caution"
    
    elseif self.raceStatus == 3 then
        raceStat = "Race Status: #fafafaFormation"
    
    end
    if self.raceFinished then
        raceStat = "Race Status: #99FF99Finished"
    end    

    if self.currentLap ~= nil then
        lapStat = "Lap ".. self.currentLap .. " of " .. self.targetLaps
    end
    

    if self.RaceMenu then
        self.RaceMenu:setText("StatusText", raceStat )
        self.RaceMenu:setText("LapStat", lapStat )
    end

    
    if self.RaceMenu then
        self.RaceMenu:setText("LapValue", tostring(self.targetLaps) )
        
        local handiValue = string.format("%.1f",self.handiCapMultiplier)
        if self.handiCapMultiplier <= 0.05 then
            handiValue = "Off"
        end
        self.RaceMenu:setText("HandiValue", tostring(handiValue) )
        local draftValue = string.format("%.1f",self.draftStrength)
        if self.draftStrength <= 0.05 then
            draftValue = "Off"
        end
        self.RaceMenu:setText("DraftValue", tostring(draftValue) )
    end

    camDir = sm.camera.getDirection() -- ???

    local dt = string.format("%.4f",dt)
    --print("dt:",dt)
end

-- networking
function Control.sv_ping(self,ping) -- get ing
    print("rc got sv piong",ping)
end

function Control.cl_ping(self,ping) -- get ing
    print("rc got cl ping",ping)
    self.network:sendToServer("sv_ping",ping)
end

function Control.client_showMessage( self, params )
	sm.gui.chatMessage( params )
end

function Control.cl_onChatCommand( self, params )
	if params[1] == "/start" then -- start racers
        -- maybe have timer?? idk
        console.log("CL_Starting Race") -- maybe alert client too?
		
		self.network:sendToServer( "sv_n_onChatCommand", params )
	elseif params[1] == "/stop" then -- stop racers
		console.log("CL_Stopping Race") -- may
        self.network:sendToServer( "sv_n_onChatCommand", params )

	elseif params[1] == "/chatcontrol" then -- toggles chat command controls
		console.log("CL_toggling controls") -- check if server client
        self.network:sendToServer( "sv_n_onChatCommand", params )
	else
        print("SM Command not recognized")
		--self.network:sendToServer( "sv_n_onChatCommand", params )
	end
end

function Control.sv_n_onChatCommand( self, params, player )
	if params[1] == "/start" then -- start racers
        -- maybe have timer?? idk
        if self.chatToggle then 
            self:sv_startRace()
        else
            self.network:sendToClients( "client_showMessage", "Chat controls are disabled, enable with /chatcontrol") -- TODO: Make individual client and not all?
        end
	elseif params[1] == "/stop" then -- stop racers
        if self.chatToggle then 
            self:sv_stopRace()
        else
            self.network:sendToClients( "client_showMessage", "Chat controls are disabled, enable with /chatcontrol") -- TODO: Make individual client and not all?
        end

	elseif params[1] == "/chatcontrol" then -- toggles chat command controls
		self.chatToggle = ( not self.chatToggle)
        self.network:sendToClients( "client_showMessage", "Chat controls are disabled, enable with /chatcontrol") -- TODO: Make individual client and not all?
        print("Chat controls set to "..self.chatToggle)
        self.network:sendToClients( "client_showMessage", "Chat Control is  " .. ( self.chatToggle and "Enabled" or "Disabled" ) ) -- TODO: Make individual client and not all?
	end


end

function Control.sv_sendAlert(self,msg) -- sends alert message to all clients (individual clients not recognized yet)
    --self.network:sendToClients("cl_showAlert",msg) --TODO maybe have pcall here for aborting versus stopping
end

function Control.cl_showAlert(self,msg) -- client recieves alert
    print("Displaying",msg)
    sm.gui.displayAlertText(msg,3) --TODO: Uncomment this before pushing to production
end


function Control.ms_tick(self) -- frame tick
    self.dataOutputTimer:tick()
    if self.dataOutputTimer:done()then
        self:sv_performTimedFuncts()
        self.dataOutputTimer:start(15) -- TODO: set to 1
    end

end

function Control.tickClock(self) -- Just ticks by secconds
    local floorCheck = math.floor(clock() - self.started) 
        --print(floorCheck,self.globalTimer)
    if self.globalTimer ~= floorCheck then
        self.gotTick = true
        self.resetCarTimer:tick()
        self.globalTimer = floorCheck
        --self.dataOutputTimer:tick()
        self.autoFocusTimer:tick()
        self.autoSwitchTimer:tick()
        --print(self.autoFocusTimer:remaining(),self.autoSwitchTimer:remaining())
        --if self.dataOutputTimer:done()then
        --    self:sv_performTimedFuncts()
        --    self.dataOutputTimer:start(1) -- TODO: set to 1
        --end
        if self.autoCameraFocus and self.autoFocusTimer:done() then
            self:sv_performAutoFocus()
            --self:sv_performAutoSwitch()
        end
        if self.autoCameraSwitch and self.autoSwitchTimer:done() then
            self:sv_performAutoSwitch()
            -- randomly add or decrease switch time
        end

        --TODO check  if session is open
        self:sv_racer_import_loop()
        
    else
        self.gotTick = false
        self.globalTimer = floorCheck
    end
    if self.debug then
    end
            
end

function Control.sv_performTimedFuncts(self)
    --print("doing tick thing")
    if self.outputRealTime then -- only do so when wanted
        self:sv_output_allRaceData()
        --self:manualOutputData()
    end
end

function Control.sv_performAutoFocus(self) -- auto camera focusing
    --print("auto focus")
    local sorted_drivers = getDriversByCameraPoints()
    if sorted_drivers == nil then return end
    if #sorted_drivers < 1 then return end
    local firstDriver = getDriverFromId(sorted_drivers[1].driver)
    --print("got winning driver",firstDriver.tagText,sorted_drivers[1]['points'])
    -- If firstdriver is the same as last first driver (current focus, do not reset timer)
    if self.focusedRacerID and self.focusedRacerID == firstDriver.id then
        --print("repeat driver",firstDriver.tagText) -- does not change focus or reset timer
    else
        --print("Auto Focus",firstDriver.tagText)
        self.network:sendToClients("cl_setCameraFocus",firstDriver.id)
        --print("restart timer",self.autoFocusDelay)
        --self.autoSwitchTimer:start(9) -- restart switch timer but not as long
        self.autoFocusTimer:start(self.autoFocusDelay)
    end
    -- else set driver as focus and reset autocamTimer
end


function Control.sv_performAutoSwitch(self) -- auto camera switching to closest or different view -- TODO: add param of input
    --print('auto switch')
    if self.focusedRacerData then -- TODO: just add func break and remove layer
        local focusRacerPos = self.focusedRacerData.location
        local camerasInDist = self:getCamerasClose(focusRacerPos) -- returns list of cameras close to specified distance
       
        local camIndex = 1
        local closestCam = camerasInDist[camIndex]
        if closestCam == nil then return end
        local carNode = self.focusedRacerData.currentNode
        local minNode = getNextItem(self.focusedRacerData.nodeChain,carNode.id,7) -- finds cams at least nodes ahead
        local distError = false
        for i = 1, #camerasInDist do local cam = camerasInDist[i]
            local camera = cam.camera
            local closestNode = camera.nearestNode
            --print('closestNode',closestNode.id,carNode.id,minNode.id)
            --local hasLos = sm.raycast. raycast and if can se thing thn
            
            if closestNode.id >= minNode.id and get_los(camera,self.focusedRacerData)  then 
                camIndex = i
                break
            else
                --print('skipped',i,closestNode.id,minNode.id,getDistance(focusRacerPos,camera.location),get_los(camera,self.focusedRacerData))
            end
            if i >= #camerasInDist - 1 then
                --print('safe to assume no closecam',i)
                distError = true
            end
        end
        closestCam = camerasInDist[camIndex]
        

        --print('found closest',camIndex,closestCam.id)
        local distFromCamera = closestCam.distance
        local chosenCamera = closestCam.camera
        --print(self.focusedRacerData.tagText,"Dist from cam",distFromCamera,chosenCamera.cameraID)
        -- Get more race like camera:
        -- auto zoom
        local distanceCutoff = 150 -- threshold from camera to switch to drone
        
        if distFromCamera > distanceCutoff or distError then
            local mode = math.random(0, 3) -- random for now but can add heuristic to switch
            --print("random switch",mode,distFromCamera,distError)
            if mode <= 2 then mode = 1 end
            --print("sending random toggle mode",mode)
            self:sv_toggleCameraMode(mode)
             -- originally wasnt here and broke every time
        else

            if self.currentCamera and self.currentCamera.cameraID == chosenCamera.cameraID then
                --print("same camera")
            else
                --print('switching cam')
                self.network:sendToClients("cl_switchCamera",chosenCamera.cameraID)
                --print("restarting cam",self.autoSwitchDelay)
                self.autoFocusTimer:start(13) -- restart focus timer but not as long
            end
        end
        self.autoSwitchTimer:start(self.autoSwitchDelay + math.random(-3,9)) -- re does delay anyways
    end
end

-- TODO: Create autoZoom that zooms in on "further racers"

function Control.sv_setAutoFocus(self,value)
    self.autoCameraFocus = value
    print("Setting auto focus",self.autoCameraFocus)
end

function Control.sv_setAutoSwitch(self,value)
    self.autoCameraSwitch = value
    print("Setting auto switch",self.autoCameraSwitch)
end


function Control.client_onInteract(self,character,state)
    --sm.camera.setShake(1)
    -- sm.gui.setInteractionText( "" ) TODO: add this when going in camera mode onUpdate
    
    if ALL_CAMERAS then
        --print(" cam sort")
        sortCameras()
    end
    
    if state then
        if character:isCrouching() then -- ghetto way to load into camera mode
            --print(state,self.smarCamLoaded)
             if self.smarCamLoaded then
                --print("start viewing cam")
                --getSmarCam():cl_ping("Viewing")
                self:cl_sendCameraCommand({command="EnterCam", value = true})
                sm.localPlayer.getPlayer():getCharacter():setLockingInteractable(self.interactable) -- wokrs??
                self.viewIngCamera = true
                self.frameCountTime = 0
                self.camTransTimer = 1
             end
        else
             --self.network:sendToServer("sv_Test",1)
             --print('displaying hud's)
            -- Check whats going on in /after game
            if self.RaceMenu then 
                self.RaceMenu:open()
            else
                print("no menue??")
            end
        end
    end
end

function Control.sv_exitCamera(self)
    self.network:sendToClients('client_exitCamera')
end

function Control.client_exitCamera(self) -- stops viewing camera
    self:cl_sendCameraCommand({command="ExitCam", value = false})
    sm.localPlayer.getPlayer():getCharacter():setLockingInteractable(nil) -- wokrs??
    sm.camera.setCameraState(1)
    self.viewIngCamera = false
    self.finishCameraActive = false
    print("exiting cam mode")
end

function Control.client_onAction(self, key, state) -- On Keypress. Only used for major functions, the rest will be read by the camera
	--if not sm.isHost then -- Just avoid anythign that isnt the host for now TODO: Figure out why its lagging...
	--	return
	--end
    --print("got keypress",state,key)
	if key == 0 then -- Shift key/alt key/any unrecognized key
	 self.shiftPressed = state -- REMOVE THIS! will have keypress reader
	elseif key == 1 then -- A key
		if self.spacePressed and self.shiftPressed then
            self.aPressed = state
		elseif self.spacePressed then
            self.aPressed = state
		elseif self.shiftPressed then
            self.aPressed = state
		else
            self.aPressed = state
		end
	elseif key == 2 then -- D Key
		if self.spacePressed and self.shiftPressed then
            self.dPressed = state
		elseif self.spacePressed then
            self.dPressed = state 
		elseif self.shiftPressed then
            self.dPressed = state
		else
            self.dPressed = state -- lol
		end
	elseif key == 3 then -- W Key
		if self.spacePressed and self.shiftPressed then
            self.wPressed = state
		elseif self.spacePressed then
            self.wPressed = state
		elseif self.shiftPressed then
            self.wPressed = state
		else -- None pressed
            self.wPressed = state
		end
	elseif key == 4 then -- S Key
		if self.spacePressed and self.shiftPressed then
            self.sPressed = state
		elseif self.spacePressed then
            self.sPressed = state
		elseif self.shiftPressed then
            self.sPressed = state
		else
            self.sPressed = state
		end

	elseif key >= 5 and key <= 14 and state then -- Number Keys 1-0
		local convertedIndex = key - 4
		if self.spacePressed and self.shiftPressed then
		elseif self.spacePressed then 
		elseif self.shiftPressed then
            local shifter = 0
            if convertedIndex < 4 then shifter = 0 end
            if convertedIndex >=4 then shifter = 3 end
            if convertedIndex >=7 then shifter = 7 end
            local racePos = convertedIndex + shifter
            self.network:sendToServer("sv_setAutoFocus",false)
            self:focusCameraOnPos(racePos)
		else -- Direct switch to camera number (up to 10)
            self.camTransTimer = 1
            self.network:sendToServer("sv_setAutoSwitch",false)
            self:switchToCameraIndex(convertedIndex)
		end
		
	elseif key == 15 then -- 'E' Pressed
		if self.spacePressed and self.shiftPressed then -- Finish Cam?
            self.ePressed = state
		elseif self.spacePressed then
            self.ePressed = state
		elseif self.shiftPressed then
            self.ePressed = state
		else -- nothing pressed
            self.ePressed = state
		end

	elseif key == 16 then -- SpacePressed
		self.spacePressed = state
	elseif key == 18 and state then -- Right Click,
		if self.spacePressed and self.shiftPressed then
            self.network:sendToServer('sv_exitCamera')
		elseif self.spacePressed then
		elseif self.shiftPressed then
		else
		end
	elseif key == 19 and state then -- Left Click, 
		if self.spacePressed and self.shiftPressed then
		elseif self.spacePressed then
		elseif self.shiftPressed then
		else
		end
		
	elseif key == 20 then -- Scroll wheel up/ X 
        if self.freecamSpeed < 0.099 then
            self.freecamSpeed = self.freecamSpeed + 0.01
        elseif self.freecamSpeed < 49.99 then
            self.freecamSpeed = self.freecamSpeed + 0.1
        end
		if self.spacePressed and self.shiftPressed then -- optional for more functionality
            --self.zoomIn = state
		elseif self.spacePressed then
            --self.zoomIn = state
		elseif self.shiftPressed then
           -- self.zoomIn = state
		else -- None pressed
		end
	elseif key == 21 then --scrool wheel down % C Pressed  freecam move speed
        if self.freecamSpeed > 0.19 then
            self.freecamSpeed = self.freecamSpeed - 0.1
        elseif self.freecamSpeed > 0.019 then
            self.freecamSpeed = self.freecamSpeed - 0.01
        elseif self.freecamSpeed > 0.001 then
            self.freecamSpeed = self.freecamSpeed - 0.001
        end

		if self.spacePressed and self.shiftPressed then -- Optional just in case something happens
            --self.zoomOut = state 
		elseif self.spacePressed then
            --self.zoomOut = state 
		elseif self.shiftPressed then
            --self.zoomOut = state 
		else -- None pressed
		end
	end
	return true
end



-- JSON 
function Control.sv_readZoomJson(self) -- BETTER IDEA: only begin reading when keypress unrecognized
    --print("RC readZoomJson")
    local status, instructions =  pcall(sm.json.open,ZOOM_INSTRUCTIONS) -- Could pcall whole function
    if status == false then -- Error doing json open
        --print("Got error reading zoom JSON")
        return nil
    else
        --print("got instruct",instructions)
        if instructions ~= nil then --0 Possibly only trigger when not alredy there (will need to read client zoomState)
            zoomIn = instructions['zoomIn']
            zoomOut = instructions['zoomOut']
            if zoomIn == "true" then
                --print("zooming in")
                self:sv_setZoomInState(1)
            else
                self:sv_setZoomInState(0)
            end

            if zoomOut == "true" then
                --print("zooming out")
                self:sv_setZoomOutState(1)
            else
                self:sv_setZoomOutState(0)
            end

            return
        else
            print("zoom Instructions are nil??")
            return nil
        end
    end
    --print("RC read zoomJSON after")
end

-- Data exporting 
function Control.sv_exportRealTime(self) -- Returns all data necessary for realtime information
    -- data format:
    --[[
        {
            id,
            locx,
            locy,
            lastLap,
            bestLap,
            lapNum,
            place,
            timeSplit,
            isFocused,
            speed
        }
    ]]
    local realtimeOutput = {}
    for k=1, #ALL_DRIVERS do local v=ALL_DRIVERS[k]
		if v ~= nil then
            local noCardata = false
            local noMeta = false
            if v.carData == nil then noCardata = true end
            if v.carData['metaData'] == nil then noMeta = true end
            v:determineRacePosBySplit()
            local time_split = string.format("%.3f",v.raceSplit)
            local isFocused = string.format("%s",v.isFocused)
            local data = {} -- dumb but works
			if noCardata or noMeta then 
                data = {["id"]= v.id , ["locX"]= v.location.x, [ "locY"]=v.location.y,
                ["lastLap"]= v.lastLap, ["bestLap"]=v.bestLap, ["lapNum"]=v.currentLap, ["place"]=v.racePosition,
                ["timeSplit"]= time_split, ["isFocused"]=isFocused, ["speed"]=v.speed}
            else
                data = {["id"]= (v.carData['metaData']["ID"] or v.id) , ["locX"]= v.location.x, [ "locY"]=v.location.y,
                ["lastLap"]= v.lastLap, ["bestLap"]=v.bestLap, ["lapNum"]=v.currentLap, ["place"]=v.racePosition,
                ["timeSplit"]= time_split, ["isFocused"]=isFocused, ["speed"]=v.speed}
            end
			table.insert(realtimeOutput,data)
		end
	end
    return realtimeOutput
end

function Control.sv_exportQualifyingData(self)
     return self.qualifyingResults -- should just return whatever exists
end

function Control.sv_exportFinishData(self)
    return self.finishResults -- should just return whatever exists can format iif mneeded
end

function Control.sv_exportRaceMetaData(self)
    return self.raceMetaData

end
-- NOTE?TODO: Place RT in separate file to reduce load?
function Control.sv_output_allRaceData(self) -- Outputs race data into a  big list
    local realtimeData = self:sv_exportRealTime() -- minimized realtime data?
    local qualifyingData = self:sv_exportQualifyingData() -- minimized quali data
    local finishData = self:sv_exportFinishData() -- minimized race finish data
    local metaData = self:sv_exportRaceMetaData() -- minimized race metaData
    -- Add race que and session data??
    local outputData = {
        ["rt"]=realtimeData,
        ["qd"]=qualifyingData,
        ["fd"]=finishData,
        ["md"]=metaData
    }

    if outputData ~= {} then
        sm.json.save(outputData,OUTPUT_DATA)
    end

end


function Control.sv_output_data(self,outputString) -- logs data
    print()
    sm.log.info(outputString)
end


function Control.sv_ReadQualJson(self)
    --print("RC sv readjson before")
    local status, data =  pcall(sm.json.open,QUALIFYING_DATA) -- Could pcall whole function
    if status == false then -- Error doing json open
        print("Got error reading qualifying JSON") -- try again?
        return nil
    else
        print("Got Qual data",#data)
        -- send data to cars
        if data == nil then
            print("qualifying data not found")
        end
        return data
    end
end


function Control.sv_ReadDeck(self) -- Reads commands (keyboard input) from streamdeck
    --print("RC sv readjson before")
    local status, instructions =  pcall(sm.json.open,DECK_INSTRUCTIONS) -- Could pcall whole function
    if status == false then -- Error doing json open
        --print("Got error reading instructions JSON")
        return nil
    else
        --print("got instruct",instructions)
        sm.json.save("[]", DECK_INSTRUCTIONS) -- technically not just camera instructions
        if instructions ~= nil then --0 Possibly only trigger when not alredy there (will need to read client zoomState)
            local instruction = instructions['command']
            if instruction == "exit" then
                self:sv_exitCamera()
            elseif instruction == "focusCycle" then
                local direction = instructions['value']
                --print("focus cycing",direction)
                self:sv_cycleFocus(direction)
            elseif instruction == "camCycle" then
                local direction = instructions['value']
                print("cam cycing",direction)
                self:sv_cycleCamera(direction)
            elseif instruction == "cMode" then
                local mode = tonumber(instructions['value'])
                --print("toggle camera mode") 
                self.autoCameraFocus = false
                self.autoCameraSwitch = false
                self:sv_toggleCameraMode(mode)
            elseif instruction == "raceMode" then -- 0 is stop, 1 is go, 2 is caution? 3 is formation
                local raceMode = tonumber(instructions['value'])
                --print("changing mraceMode",raceMode,sv_toggleRaceMode)
                self:sv_toggleRaceMode(raceMode)
            elseif instruction == "autoFocus" then -- turn on/off auto focus
                print('set auto focus',instructions)
                local mode = tonumber(instructions['value'])
                if mode == 1 then -- turn on auto switch
                    self.autoCameraFocus = true
                elseif mode == 2 then -- just run auto focus function once ( or turn off if useless)
                    self:sv_performAutoFocus()
                end
            elseif instruction == "autoSwitch" then
                print("auto switch",instructions)
                local mode = tonumber(instructions['value'])
                if mode == 1 then -- turn on auto switch
                    self.autoCameraSwitch = true
                elseif mode == 2 then -- just run auto switch function once ( or turn off if useless)
                    print('a2',self.autoCameraSwitch)
                    self:sv_performAutoSwitch()
                end

            elseif instruction == "delRM" then -- delete racer by meta ID
                self:sv_delete_racer(tonumber(instructions['value']))
            elseif instruction == "delID" then -- delete racer by body ID
                self:sv_delete_racer_id(tonumber(instructions['value']))
            elseif instruction == "delALL" then -- deletes all raceers (both meta and non)
                self:sv_delete_all_racers()
            end

            return
        else
            print("camera Instructions are nil??")
            return nil
        end
    end
    --print("RC sv readjson after")
end



function Control.sv_execute_instruction(self,instruction)
    local cmd = instruction['cmd'] -- even more shorter form? c,v
    local value = instruction['val']

    print("Executing instruction",cmd,value)


    if cmd == "delMID" then -- delete racer by meta ID
        self:sv_delete_racer(tonumber(value))
    elseif cmd == "delBID" then -- delete racer by body ID
        self:sv_delete_racer_id(tonumber(value))
    elseif cmd == "delALL" then -- deletes all raceers (both meta and non)
        self:sv_delete_all_racers()
    elseif cmd == "impLEG" then -- imports league
        self:sv_import_league(tonumber(value))
    elseif cmd == "impCAR" then -- import racer (by metaID)
        self:sv_add_racer_to_import_queue(tonumber(value))
    elseif cmd == "edtSES" then -- Eddit session to (Session type)
        self:sv_edit_session(tonumber(value))
    elseif cmd == "setSES" then -- Sets session to (open,closed)
        self:sv_set_session(tonumber(value))
    elseif cmd == "setRAC" then -- Set Race to (Race setting)
        self:sv_set_race(tonumber(value))
    elseif cmd == "resCAR" then -- RESETS driver (Driver ID)
        self:sv_reset_driver(tonumber(value))
    end
end

function Control.sv_readAPI(self) -- Reads API instructions
    local status, instructions =  pcall(sm.json.open,API_INSTRUCTIONS) -- Could pcall whole function
    if status == false then -- Error doing json open
        print("Got error reading instructions JSON",status,instructions)
        sm.json.save("[]", API_INSTRUCTIONS)
        return nil
    else
        --print("got instruct",instructions)
        sm.json.save("[]", API_INSTRUCTIONS) -- deletes all known instructions
        -- TODO: pcall this in cased theres an error clearing it?
        if instructions == nil then
            print("no instructions")
            return nil
        end

        for k=1,#instructions do local instruction = instructions[k]
            if instruction ~= nil then --Perform instruction
                self:sv_execute_instruction(instruction)
                return
            end
        end
    end
    --print("RC sv readjson after")
end

-- camera and car following stuff
function Control.sv_cycleFocus(self,direciton) -- calls iterate camera
    -- turn off automated if on
    self.autoCameraFocus = false
    self.network:sendToClients("cl_cycleFocus",direciton)
    -- remove isFocused (should be SV)
end 

function Control.sv_setFocused(self,last_racerID) -- sv conflicting race condition sometimes??
    if last_racerID ~= nil then
        local racer = getDriverFromId(last_racerID)
        if racer then
            racer.isFocused = false
        end
    end
    
    if self.focusedRacerData ~= nil then
        local racer = getDriverFromId(self.focusedRacerData.id)
        if racer then
            racer.isFocused = true
        end
    end
end


function Control.cl_cycleFocus(self,direction) -- Cycle Which racer to Focus on ( NON Drone Function), Itterates by position
	if self.focusedRacePos == nil then 
		print("Defaulting RacePos Focus to 1")
		self.focusedRacePos = 1
	end
	local totalRacers = #ALL_DRIVERS
	
	local nextRacerPos = self.focusedRacePos + direction
	--print(self.focusedRacePos + direction)
	if nextRacerPos == 0 or nextRacerPos > totalRacers then
		print("Iterate focus On Pos Overflow/UnderFlow Error",nextRacerPos) 
		nextRacerPos = self.focusedRacePos -- prevent from index over/underflow by keeping still, cycling could create confusion
		return
	end
	--print("Iterating Focus to next Pos:",nextRacerPos)
	local nextRacer = getDriverByPos(nextRacerPos)
	--print(nextRacer)
	if nextRacer == nil then
		--print(Error getting next racer)
		-- Means that the racers POS are 0 or error
		return
	end
    self.network:sendToServer("sv_setFocused",self.focusedRacerID) -- sends to server driver focus stats
	self.focusedRacerData = nextRacer
	self.focusedRacePos = nextRacerPos
	self.focusedRacerID =nextRacer.id
	self.focusPos = true
	self.focusRacer = false
	-- Also sets drone? or have it separate, Both focuses and follows drone
	self.droneFollowRacerID = nextRacer.id 
	self.droneFollowRacePos = nextRacerPos
	self.droneFocusRacerID = nextRacer.id 
	self.droneFocusRacePos = nextRacerPos 

	self.droneFollowPos = true 
	self.droneFollowRacer = false 
	self.droneFocusPos = true 
	self.droneFocusRacer = false 

    

	self:focusAllCameras(nextRacer) -- TODO: get this
end

function Control.focusCameraOnPos(self,racePos) -- CL Grabs Racers from racerData by RacerID, pulls racer
	--print("finding drive rby pos",racePos)
    local racer = getDriverByPos(racePos) -- Racer Index is just populated as they are added in
	if racer == nil then
		racer = getDriverByPos(0) -- Defaults to 0?
		return
	end
	if racer.racePosition == nil then
		print("Racer has no RacePos",racer)
		return
	end
    self.network:sendToServer("sv_setFocused",self.focusedRacerID)
    --*print("Settinf focus on pos",racer.id)
	self.focusedRacerData = racer
	self.focusedRacePos = racer.racePosition
	self.focusedRacerID = racer.id
	self.focusPos = true
	self.focusRacer = false
	-- Also sets drone? or have it separate, Both focuses and follows drone
	self.droneFollowRacerID = racer.id 
	self.droneFollowRacePos = racer.racePosition
	self.droneFocusRacerID = racer.id 
	self.droneFocusRacePos = racer.racePosition

	self.droneFollowPos = true 
	self.droneFollowRacer = false 
	self.droneFocusPos = true 
	self.droneFocusRacer = false
	self:focusAllCameras(racer)
end

function Control.focusCameraOnRacerIndex(self,id) -- CL Grabs Racers from racerData by RacerID, pulls racer
	local racer = getDriverFromId(id) -- Racer Index is just populated as they are added in
	if racer == nil then
		print("Camera Focus on racer index Error")
		return
	end
	if racer.racePosition == nil then
		print("Racer has no RacePos",racer.id)
		return
	end
    self.network:sendToServer("sv_setFocused",self.focusedRacerID)
	self.focusedRacerData = racer
	self.focusedRacePos = racer.racePosition
	self.focusedRacerID = racer.id
	self.focusPos = false
	self.focusRacer = true
	-- Also sets drone? or have it separate, Both focuses and follows drone
	self.droneFollowRacerID = racer.id 
	self.droneFollowRacePos = racer.racePosition
	self.droneFocusRacerID = racer.id 
	self.droneFocusRacePos = racer.racePosition

	self.droneFollowPos = false 
	self.droneFollowRacer = true 
	self.droneFocusPos = false 
	self.droneFocusRacer = true

	self:focusAllCameras(racer)
end

function Control.setDroneFollowRacerIndex(self,id) -- Tells the drone to follow whatever index it is
	local racer = getDriverFromId(id) -- Racer Index is just populated as they are added in
	if racer == nil then
		print("Drone follow racer index Error",id)
		return
	end
	if racer.racePosition == nil then
		print("Drone Racer has no RacePos",racer.id)
		return
	end

	-- Also sets drone? or have it separate, Both focuses and follows drone
	self.droneFollowRacerID = racer.id 
	self.droneFollowRacePos = racer.racePosition

	self.droneFollowPos = false 
	self.droneFollowRacer = true 

	self.droneData:setFollow(racer)
end

function Control.setDroneFollowFocusedRacer(self) -- Tells the drone to follow whatever Car it is focused on
	local racer = getDriverFromId(self.focusedRacerID) -- Racer Index is just populated as they are added in
	if racer == nil then
		print("Drone follow Focused racer index Error",self.focusedRacerID)
        
		return
	end
	if racer.racePosition == nil then
		print("Drone Racer has no RacePos",racer.id)
		return
	end
    self.droneLocation = racer.location + self.droneOffset -- default offset set on init -- puts initial location a bit off and higher than racer`
	-- Also sets drone? or have it separate, Both focuses and follows drone
	self.droneFollowRacerID = racer.id 
	self.droneFollowRacePos = racer.racePosition

	self.droneFollowPos = false 
	self.droneFollowRacer = true
end

function Control.droneExecuteFollowRacer(self) -- runs onfixedupdate and focuses on drone
    local racer = getDriverFromId(self.focusedRacerID) -- OR self. followedRacerID
	if racer == nil then
		print("Drone follow Focused racer index Error",self.focusedRacerID)
		return
	end
	if racer.racePosition == nil then
		print("Drone Racer has no RacePos",racer.id)
		return
	end
    -- If self.droneFollowRacer vs pos?
    --print(self.droneOffset)
    --local rotationDif = vectorAngleDiff(sm.vec3.new(0,1,0) , racer.shape:getAt())
    --print("defr2",self.droneOffset,rotationDif)
    self.droneLocation = racer.shape:getWorldPosition() + self.droneOffset
    -- TODO: Figure out the right math for thisrotateAroundPoint(racer.shape:getWorldPosition(), self.droneOffset,rotationDif) -- puts initial location a bit off and higher than racer`
	
end

function Control.focusAllCameras(self, racer) --Sets all Cameras to focus on a racer
	local racerID = racer.id
	local racePos = racer.racePosition

	if racer.id == nil then
		print("Setting Camera focus nill/invalid racer")
		return
	end 
	--[[Drone Focusing is be done inside getter goal.
	--for k=1, #ALL_CAMERAS do local v=ALL_CAMERAS[k]-- Foreach camera, set their individual focus/power
		if v.focusID ~= racerID then
			--print(v.power,racePos)
			v:setFocus(racerID)
		end
	end]]
end

function Control.switchToFinishCam(self) -- Unsure if to make separate cam for this?
	self.finishCameraActive = true
    -- send command to switch to camera
end

function Control.toggleDroneCam(self) -- Sets Camera and posistion for drone cam, (no longer toggle, only on)     
    --print("switching to drone")
    --TODO: FAULT, Switching directly from drone mode to Race mode (on sDeck) causes the focus/Goal to be offset. 
    if self.droneLocation == nil then
        --print("Initializing Drone")
        if self.focusedRacerID == nil then -- no racer focused
            local driver = getAllDrivers()[1] -- just grab first driver out of all -- TDODOERRORCASE if no drivers will break
            if driver == nil then -- could not find drivers
                print("drone init error, no focusable drivers")
                -- set location to 0 0 0
                self.droneLocation = sm.vec3.new(0,0,25) + self.droneOffset -- have it reset to focused somewhere aat all times
                return -- just return error
            else 
                print("Set up new follow drone")
                self.droneLocation = driver.location
                print("set up dronelocation",self.droneLocation) -- set up focus Racer()
            end
        else -- ound focused racer
            print("Settind drone to follow focused racer")
            self:setDroneFollowFocusedRacer()
        end 

    end
    
    if self.focusedRacerData == nil then
        print("Drone Error focus on racer")
        return
    end
    --*print("focusing",self.focusedRacerData.location,self.droneLocation)
    local racerlocation = self.focusedRacerData.location
    if racerlocation == nil then 
        print("Drone racer removed")
        self.focusedRacerData = nil
    end
    --local droneLocation = self.droneData.location
    local camPos = sm.camera.getPosition()
    local goalOffset = self:getFutureGoal(self.droneLocation)
    
    local camDir = sm.camera.getDirection() -- TODO: Just remove these and let the main loop handle it
    dirMovement1 = sm.vec3.lerp(camDir,goalOffset,1) -- COuld probably just hard code as 1
    self.lastCamSwitch = self.frameCountTime
    --print("Switching to Drone",self.frameCountTime)
    --self:cl_sendCameraCommand({command="setPos",value=self.droneLocation}) -- lerp drone location>?
	--self:cl_sendCameraCommand({command="setDir",value=dirMovement1}) -- TODO: get this to get focus on car and send directions to cam
    --print("set dronelocation",self.droneLocation)
end

function Control.loadDroneData(self) -- Just checks and grabs Drone Data [Unused so far]
	if droneInfo then -- Scalablility?
		if #droneInfo == 1 then
			self.droneData = droneInfo[1]
			if self.droneData == nil then print("Error Reading Drone Data") end
		else
			print("No Drones Found")
		end
	else
		print("Drone Info Table not created")
	end
end

function Control.toggleOnBoardCam(self) -- Toggles on board for whichever racer is focused
    if self.focusedRacerData == nil then -- no racer focused
        print("Initializing onBOard")
        self:focusCameraOnPos(1)
    else -- ound focused racer
        -- already init
    end 
    local racer = self.focusedRacerData
    if racer == nil then return end
    if racer.shape == nil then return end
    local location = racer.shape:getWorldPosition() -- old
    local rvel = racer.velocity
    local carDir = racer.shape:getAt()
    --print("locZ",newLoc)
    --local newCamPos = location + (carDir / 10) + (rvel * 1) + sm.vec3.new(0,0,1.4)
    local rotation  =  racer.carDimensions['center']['rotation'] * racer.shape:getAt()
    location = racer.shape:getWorldPosition() + (rotation * racer.carDimensions['center']['length']) -- centerlcoation
    local rearLength = racer.carDimensions['rear']:length() *0.9 -- mor padding
    local rearLoc = location + (carDir*-rearLength) -- whats freecam speed supposed to do?
    local newCamPos = rearLoc + sm.vec3.new(0,0,3)
    --locMovement = sm.vec3.lerp(camLoc,newCamPos,dt)
    --dirMovement = sm.vec3.lerp(camDir,carDir,1)
    --print(dirMovement)
    --print("Setting Onboard Cam")
    self.lastCamSwitch = self.frameCountTime
    --self:cl_sendCameraCommand({command="setPos",value=newCamPos})
    --self:cl_sendCameraCommand({command="setDir",value=carDir})
   
end


function Control.switchToCamera(self,camera) -- Client Switches to camera based on object
    --print("switching to camera",camera)
    if camera == nil then 
		print("Camera not found",camera)
		return
	end
    if camera.cameraID == nil then
		print("Error when switching to camera",camera)
		return
	end
    self.onBoardActive = false
	self.droneActive = false
	self.currentCameraIndex = getCameraIndexFromId(camera.cameraID)
    self.lastCamSwitch = self.frameCountTime
	--print("switching to camera:",self.currentCameraIndex)
	self:setNewCamera(camera)
end

function Control.switchToCameraIndex(self, cameraIndex) -- Client switches to certain cameras based on  inddex (up to 10) 0-9
	--cameraIndex = cameraIndex + 1 -- Accounts for stupid non zero indexed arrays
	--print("Doing camIndex",cameraIndex)
    local totalCams = #ALL_CAMERAS
	if cameraIndex > #ALL_CAMERAS or cameraIndex <= 0 then
		print("Camera Switch Indexing Error",cameraIndex)
		cameraIndex = 1
	end
	local camera = ALL_CAMERAS[cameraIndex]
	if camera == nil then 
		print("Camera not found",cameraIndex)
		return
	end
	if camera.cameraID == nil then
		print("Error when switching to camera",camera,cameraIndex)
		return
	end
    --print("switching to cam",camera)

	self.onBoardActive = false
	self.droneActive = false
	self.currentCameraIndex = cameraIndex - 1
	--print("switching to camera:",cameraIndex,self.currentCameraIndex)
	self:setNewCameraIndex(cameraIndex - 1)
end

function Control.sv_cycleCamera(self,direciton) -- calls iterate camera
    self.autoCameraSwitch = false -- turn off auto switching
    self.network:sendToClients("cl_cycleCamera",direciton)
end

function Control.cl_setCameraFocus(self,id) -- calls to set camera to focus on id
    self:focusCameraOnRacerIndex(id)
end

function Control.cl_switchCamera(self,id)
    local camera = getCameraFromId(id)
    
    self:switchToCamera(camera)
end

function Control.cl_cycleCamera(self, direction)
    self.camTransTimer = 1
	if self.droneActive then
		print("exit Cycle Drone")
		self.droneActive = false
		self.onBoardActive = false

	end
	if self.onBoardActive then
		self.onBoardActive = false
	end
	local totalCam = #ALL_CAMERAS
	--print(totalCam,self.currentCameraIndex)
	local nextIndex = (self.currentCameraIndex + direction ) %totalCam
	--print("next index",nextIndex)
	if nextIndex > totalCam then
		print("Camera Index Error")
		return
	end
	self:setNewCameraIndex(nextIndex)
	
end

function Control.setNewCameraIndex(self, cameraIndex) -- Switches to roadside camera based off of its index
    --print(self.currentCameraIndex,cameraIndex)D
    --print("\n\n'")
    local avg_dt = 0.016666
    self.currentCameraIndex = cameraIndex
	if ALL_CAMERAS == nil or #ALL_CAMERAS == 0 then
		print("No Cameras Found")
		return
	end
	local cameraToView = ALL_CAMERAS[self.currentCameraIndex + 1]
	--print("viewing cam", self.currentCameraIndex + 1) -- use cam dir?
	if cameraToView == nil then
		print("Error connecting to road Cam",self.currentCameraIndex)
		return
	end
	self.currentCamera = cameraToView
	local camLoc = cameraToView.location
	--camLoc.z = camLoc.z + 2.1 -- Offsets it to be above cam
    goalOffset = self:getFutureGoal(camLoc)
    goalSet1 = self:getGoal()

    if goalOffset == nil then 
        print("bad goal")
        return 
    end

    local camDir = sm.camera.getDirection()
    dirMovement1 = sm.vec3.lerp(camDir,goalOffset,self.camTransTimer) -- COuld probably just hard code as 1
    --print("Setitng new cam Index")
    self.lastCamSwitch = self.frameCountTime
    self:cl_sendCameraCommand({command="setPos",value=camLoc})
	self:cl_sendCameraCommand({command="setDir",value=dirMovement1}) -- TODO: get this to get focus on car and send directions to cam
end

function Control.setNewCamera(self, camera) -- Switches to roadside camera directly
    local avg_dt = 0.016666 -- ???
	if camera == nil then
		print("Error connecting to road Cam",self.currentCameraIndex,camera)
		return
	end
	self.currentCamera = camera
	local camLoc = camera.location
	--camLoc.z = camLoc.z + 2.1 -- Offsets it to be above cam
    goalOffset = self:getFutureGoal(camLoc)
    goalSet1 = self:getGoal()

    local camDir = sm.camera.getDirection()
    dirMovement1 = sm.vec3.lerp(camDir,goalOffset,self.camTransTimer) -- COuld probably just hard code as 1
    --print("setting newCam Pos and Dir")
    self:cl_sendCameraCommand({command="setPos",value=camLoc})
	self:cl_sendCameraCommand({command="setDir",value=dirMovement1}) -- TODO: get this to get focus on car and send directions to cam
end


function Control.getCamerasClose(self,position) -- returns cameras in position
    if ALL_CAMERAS == nil or #ALL_CAMERAS == 0 then
		print("No Cameras Found")
		return {}
	end
    local sortedCameras = {}
    for k=1, #ALL_CAMERAS do local v=ALL_CAMERAS[k]-- Foreach camera, set their individual focus/power
		local dis = getDistance(position,v.location)
        table.insert(sortedCameras,{camera=v,distance=dis})
    end
    --print("sorting cameras close",sortedCameras)
    sortedCameras = sortCamerasByDistance(sortedCameras)
    --print("sorted cameras",sortedCameras)
    return sortedCameras
end


-- CameraMovement functions
function Control.sv_toggleCameraMode(self,mode) -- toggles between race and free cam - Drone cam will be separate toggle
    self.network:sendToClients("cl_toggleCameraMode",mode)
end

function Control.cl_toggleCameraMode(self,mode) -- client side toggles it
    if not self.focusedRacerData then
        --print("finding racer")
        self:focusCameraOnPos(1)
    end
    if mode == 0 then --race cam
        self.droneActive = false
        self.onBoardActive = false 
        self.cameraMode = 1
        self.camTransTimer = 1 -- Change this to be on toggle anyways?
        self.frameCountTime = 0
        --print("setting to race cam",self.currentCameraIndex)
        self:switchToCameraIndex((self.currentCameraIndex or 1))
    elseif mode == 1 and not self.droneActive then -- Drone cam
        self.droneActive = true
        self.onBoardActive = false 
        self.cameraMode = 1
        self.camTransTimer = 1 -- Change this to be on toggle anyways?
        self.frameCountTime = 0
        self:toggleDroneCam()
    elseif mode == 2 then -- Freee cam
        self.droneActive = false
        self.onBoardActive = false 
        self.cameraMode = 0
        self.camTransTimer = 1 -- Change this to be on toggle anyways?
        self.frameCountTime = 0
    elseif mode == 3 and not self.onBoardActive then -- Onboard cam
        --print("Activate dash cam")
        self.onBoardActive = true
        self.droneActive = false
        self.cameraMode = 1
        self.camTransTimer = 1 -- Change this to be on toggle anyways?
        self.frameCountTime = 0
        self:toggleOnBoardCam()
    end

    
    self:cl_sendCameraCommand({command="setMode", value=self.cameraMode})
end

function Control.calculateFocus(self)
	local racer = self.focusedRacerData -- Racer Index is just populated as they are added in
	if racer == nil then
		print("Calculating Focus on racer index Error")
		return
	end
	if racer.racePosition == nil and not self.errorShown then
		print("CFocus has no RacePos",racer)
		self.errorShown = true
		return
	end
	self:focusAllCameras(racer)

end

function Control.getFutureGoal(self,camLocation) -- gets goal based on new location
    local racer = self.focusedRacerData
	-- If droneactive get droneFocusData
	if camLocation == nil then
        print("cam loc lnil")
        return 
    end
	if racer == nil then 
		if #ALL_DRIVERS > 0 then
			racer = ALL_DRIVERS[1]
			self.hasError = false
		else
			if not self.hasError then
				print("No Focused Racer")
				self.hasError = true
			end
			return nil
		end
	end
	if racer.id == nil  then
		if self.hasError == false then
			print("malformed racer") -- Add hasError?
			self.hasError = true
		end
		return nil
	else
		self.hasError = false
	end
	--print(carID)
	local location = racer.shape:getWorldPosition()
	local goalOffset =  location - camLocation
    local dir = sm.camera.getDirection()
    --print("GoalSend:",goalOffset,camLocation,dir)
	return goalOffset
end

function Control.getGoal( self) -- Finds focused car and takes location based on that
	local racer = self.focusedRacerData
	-- If droneactive get droneFocusData
	
	if racer == nil then 
		if #ALL_DRIVERS > 0 then
			racer = ALL_DRIVERS[1]
			self.hasError = false
		else
			if not self.hasError then
				print("No Focused Racer")
				self.hasError = true
			end
			return nil
		end
	end
	if racer.id == nil  then
		if self.hasError == false then
			print("malformed racer") -- Add hasError?
			self.hasError = true
		end
		return nil
	else
		self.hasError = false
	end
	--print(carID)
	local location = racer.location
	
	local camLoc = sm.camera.getPosition()
	local goalOffset =  location - camLoc
	--print(camLoc)
    --print("goal?",goalOffset,racer.id,self.hasError,self.focusedRacerData)
	return goalOffset
end

function Control.updateCameraPos(self,goal,dt)
	--print(self.droneActive,dt,self.currentCamera,self.cameraActive)
    if goal == nil then return end
    local camDir = sm.camera.getDirection()
    local camLoc = sm.camera.getPosition()
    local dirDT = dt
    local dirMovement = nil
	local locMovement = nil
	local frameBuffer = 3

   

    if self.raceMetaData['lapsLeft']  == 0 and self.autoCameraSwitch then
        --print("Final Lap")
        local firstCar = getDriverByPos(1)
        if firstCar then
            local totalNodes = #firstCar.nodeChain
            --print(totalNodes - firstCar.currentNode.id)
            if totalNodes - firstCar.currentNode.id < 20 and totalNodes - firstCar.currentNode.id >= 1 then
                self.finishCameraActive = true
            end
        end
    end
     -- Finish cam takes priority
     if self.finishCameraActive then
        chosenCamera = ALL_CAMERAS[1] -- First camera is first camera
        --if chosenCamera == nil then return end
        local firstCar = getDriverByPos(1) -- TODO: grab general node chain instead
        if firstCar == nil or firstCar.nodeChain == nil then self.finishCameraActive = false return end
        local focusSpot = firstCar.nodeChain[1].mid
        local camSpot = chosenCamera.location
        local goalOffset = focusSpot - camSpot
        --print("forcing cam spot",camSpot,focusSpot,goalOffset)
        self:cl_toggleCameraMode(0) -- force into race cam mode was going into free cam mode
        --{<Vec3>, x = -236.75, y = -28.625, z = 2.096}
        self:cl_switchCamera(chosenCamera.cameraID)
        self:cl_sendCameraCommand({command="forceDir",value=goalOffset})
        --self.autoCameraFocus = false
        --self.autoCameraSwitch = false
        if true then return end
    end

    if self.droneActive then
        --print("dact")
        local goalLocation = self.droneLocation
        if goalLocation == nil then
            print("drone has no loc onupdate")
            return
        end
        --print(self.droneLocation)
    
        local dirSmooth = dt * 0.8 
        local locSmooth = dt * 6 
    
        -- TODO convert to quats and then convert back before setting pos
        local racer = nil
        if self.focusedRacerData == nil then 
            print("No focus racer") --TODO: Figure out how to fix this
            return
        else
            racer = self.focusedRacerData
            if racer == nil then print("no racer data") return end
            goalLocation = self.droneLocation + self.droneOffset
            --goalLocation = location--camLoc + sm.vec3.new 
        end
        local location2 = racer.shape:getWorldPosition() -- target location
        local idealLoc = (self.droneLocation + self.droneOffset)

        local goalOffset =  location2 - idealLoc -- was camLoc 
       
        --print(idealLoc,camLoc)
       
        if self.frameCountTime - self.lastCamSwitch < frameBuffer then -- Sets to instant cam movement
            --print("preset",location2,camLoc,goalOffset)
            dirMovement = goalOffset
            locMovement = goalLocation
        else
            --print("postset",location2,camLoc,goalOffset)
            dirMovement = sm.vec3.lerp(camDir,goalOffset,dirSmooth)--self.camTransTimer
            locMovement = sm.vec3.lerp(camLoc,goalLocation,locSmooth)
        end
        --print("actset",dirMovement,camDir)
        self:cl_sendCameraCommand({command="setPos",value=locMovement}) -- locMovement
        self:cl_sendCameraCommand({command="setDir",value=dirMovement}) -- dirMovement
        
        --`print("DroneSendA",sm.camera.getPosition(),sm.camera.getDirection())
    
    elseif self.onBoardActive then
        if self.focusedRacerData == nil then 
            --print("No focus racer") TODO: Figure out how to fix this
            return 
        end
        local racer = self.focusedRacerData
        if racer == nil then return end
        local location = racer.shape:getWorldPosition()-- gets front location
        local frontLength = (racer.carDimensions or 1) -- ??
        local rearLength =0
        local carDir = racer.shape:getAt()

        --print(racer.carDimensions)
        if racer.carDimensions ~= nil then 
            local rotation  =  racer.carDimensions['center']['rotation']
            local newRot =  rotation * racer.shape:getAt()
            location = racer.shape:getWorldPosition() + (newRot * racer.carDimensions['center']['length']) -- centerlcoation
            rearLength = racer.carDimensions['rear']:length() *0.3 -- mor padding
        end
        local rearLoc = location + (carDir*-rearLength) -- whats freecam speed supposed to do?
        
        local rvel = racer.velocity
        local dvel = carDir - camDir --racer.angularVelocity
        --print("locZ",dvel:length())
        local newCamPos = rearLoc + sm.vec3.new(0,0,3) --+ TODO: dynamic height??
        local newCamDir = camDir + (dvel *2)
        local dirSmooth = dt * 0.9
        local locSmooth = dt * 2 -- 1.1
        if self.frameCountTime - self.lastCamSwitch < frameBuffer then -- Sets to instant cam movement
            --print("frame buf2")
            locMovement = newCamPos
            dirMovement = racer.shape:getAt()
        else
            --print("no frame buf2")
            locMovement = sm.vec3.lerp(camLoc,newCamPos,locSmooth)
            dirMovement = sm.vec3.lerp(camDir,racer.shape:getAt(),dirSmooth)
        end

       
        
        --print("setDir updateOnboard",dirMovement)
        self:cl_sendCameraCommand({command="setDir",value=dirMovement})
        self:cl_sendCameraCommand({command="setPos",value=locMovement})
    
    else -- race camera
        -- location is alreadyh set
        local locSmooth = dt * 1.5 -- 1.1
        if self.frameCountTime - self.lastCamSwitch < frameBuffer then -- Sets to instant cam movement
            --print("frame buf3")
            dirMovement = sm.vec3.lerp(camDir,goal,1) -- this needs to be set
        else
            dirMovement = sm.vec3.lerp(camDir,goal,self.camTransTimer * 0.1)
        end
       
        --dirMovement = sm.vec3.lerp(camDir,goal,dt*0.1)
        --print(self.frameCountTime) TODO: if gets annooying, we can figure out the things we did above (only set when > 2)
        self:cl_sendCameraCommand({command="setDir",value=dirMovement})
    end
        
    self.camTransTimer = dirDT -- works only with 1 frame yasss!

end
-- Race line Export
function Control.exportSimplifyChain(self,nodeChain)
    local simpChain = {}
    --sm.log.info("simping node chain") -- TODO: make sure all seg IDs are consistance
    for k=1, #nodeChain do local v=nodeChain[k]
        local newNode = {id = v.id, midX = v.mid.x, midY = v.mid.y, midZ = v.mid.z, width = v.width, }
        table.insert(simpChain,newNode)
    end
    return simpChain
end

-- Will e exporting live map data for current map Oncreate/Load
-- Will also need to find a way to save all other maps to their named locations
function Control.sv_export_current_mapChain(self)
    -- Exports current ma-pchain into JsonData/Maps/CurrentMap.json
    self:sv_loadData(TRACK_DATA)
    --print("exporting node chain",self.trackLoaded)
    --print("nc",self.nodeChain)
    if self.nodeChain then -- might need to simplify first...
        local exportableChain = self:exportSimplifyChain(self.nodeChain)
        local savePath = MAP_DATA .. "current_map.json"
        print("saving chain to",savePath)
        sm.json.save(exportableChain,savePath)
    else
        print('no nodechian found')
    end
end



function Control.sv_export_nodeChain(self)
    self:sv_loadData(TRACK_DATA)
    --print("exporting node chain",self.trackLoaded)
    --print("nc",self.nodeChain)
    if self.nodeChain then -- might need to simplify first...
        local exportableChain = self:exportSimplifyChain(self.nodeChain)
        local savePath = MAP_DATA .. self.trackID .. "_" ..self.trackName .. ".json"
        print("saving chain to",savePath)
        sm.json.save(exportableChain,savePath)
    else
        print('no nodechian found')
    end
end


function Control.client_canTinker( self, character )
    return true
end

function Control.client_onTinker( self, character, state ) -- For manual exporting (not necessary and can depreciate for now,)
	if state then
        local racerID = 20
        if character:isCrouching() then
            self.network:sendToServer("sv_delete_all_racers")
        else
            --print('Exporting track')
            --self.network:sendToServer("sv_export_nodeChain")
            --self.BehaviorMenu:open()
            --self.network:sendToServer("sv_import_racer",racerID) -- TODO; go back to behavior menu when ready
            local tester = {1}
            local a_league = {1,2,3,5,6,7,8,9,10,11,12,13,15,16,17,18}
            local b_league = {14,19,20,21,22,23,24,25,26,27,28,30,31,33}
            --self.network:sendToServer("sv_import_racers",a_league)
            self.network:sendToServer("sv_add_racer_to_import_queue",1)
        end
	end
end





-- UI

function Control.client_textChanged(self,buttonName,value)
    -- Validation here but not necessary since advanced stuff
    -- Values will pretty much all be numbers so don't accept non number input
    --print("edit box changed",value,tonumber(value))
    if tonumber(value) == nil then
        print("not a number")
    end
    
    
end

function Control.client_editAccepted(self,buttonName,value)
    print("Edit box accepted",buttonName,value)


    if buttonName == "WallDistV" then
       
        print("Editing wall distance avoidance to", avoidDist)
        if tonumber(value) == nil then
            print("not a number")
            self.BehaviorMenu:setText("WallDistV", tostring(avoidDist) )
        else
            local avoidDist = tonumber(value)
            self.trackLimPad = value -- TODO: Make a client->server function  that updates every carr too
        end
    end
end

function Control.client_buttonPress( self, buttonName )
    --print("clButton",buttonName)
    -- if not self.cl and cl2 then self.cl = cl2 end -- Verify if game data exits
	if buttonName == "DraftBtn" then
		self.DraftExpanded = not self.DraftExepanded
		self:client_DropDownButton( { btnName = buttonName, index = "DraftMode", state = self.DraftExpanded } )
	elseif buttonName == "DraftYes" or buttonName == "DraftNo" then
        self:cl_ChangeDraft(buttonName)
		self.DraftExpanded = false
		self:client_DropDownButton( { btnName = buttonName, index = "DraftMode" } )
    elseif buttonName == "LapBtnAdd" then
        self.network:sendToServer("sv_changeLapCount",1)
    elseif buttonName == "LapBtnSub" then
        self.network:sendToServer("sv_changeLapCount",-1)
    elseif buttonName == "HandiBtnAdd" then
        self.network:sendToServer("sv_changeHandiCap",0.1)
    elseif buttonName == "HandiBtnSub" then
        self.network:sendToServer("sv_changeHandiCap",-0.1)
    elseif buttonName == "DraftBtnAdd" then
        self.network:sendToServer("sv_changeDraft",0.1)
    elseif buttonName == "DraftBtnSub" then
        self.network:sendToServer("sv_changeDraft",-0.1)
    elseif buttonName == "ResetRace" then
        --print("Resetting Race")
        if (self.raceStatus == 1 or self.raceStatus == 2 or self.raceStatus == 3 )and not self.raceFinished then -- Mid race
            self.RaceMenu:setText("PopUpYNMessage", "Still Racing, Reset?")
            self.RaceMenu:setVisible("PopUpYNMainPanel", true)
		    self.RaceMenu:setVisible("CreateRacePanel", false)
            self.PopUpYNOpen = true
        else
            --self.RaceMenu:setText("PopUpYNMessage", "Start Game?")
            --self.RaceMenu:setVisible("CreateRacePanel", false)
            self.RaceMenu:close()
            self:cl_resetRace()
        end
		
    
    elseif buttonName == "PopUpYNYes" then
            --print("resetting race match")
            self.RaceMenu:setVisible("CreateRacePanel", true)
            self.RaceMenu:setVisible("PopUpYNMainPanel", false)
            self.RaceMenu:close()
            self:cl_resetRace()
            self.PopUpYNOpen = false
            --print("Resetting mid race")    
	elseif buttonName == "PopUpYNNo" then
		self.RaceMenu:setVisible("CreateRacePanel", true)
		self.RaceMenu:setVisible("PopUpYNMainPanel", false)
		self.PopUpYNOpen = false
    elseif buttonName == "BlueBtn" then
        --print("Joining blue team")
        self:changeTeam(2)
    elseif buttonName == "RedBtn" then
        --print("Joining Red Team")
        self:changeTeam(1)
    else
        print("buton not recognized")
    end
end

function Control.client_OnOffButton( self, buttonName, state )
	self.RaceMenu:setButtonState(buttonName.. "On", state)
	self.RaceMenu:setButtonState(buttonName.. "Off", not state)
end

function Control.client_DropDownButton( self, data ) -- Expands and collapses dropdown menu (client)
    for index, titles in pairs( self.DropDownList ) do
        local newstate = not data.state
        if index ~= data.index then newstate = true end --hide other dropdowns
        self.RaceMenu:setVisible(index.. "Collapsed", newstate)
        self.RaceMenu:setVisible(index.. "Expanded", not newstate)
        for _, Widget in pairs( titles ) do -- Shows specified items
            self.RaceMenu:setVisible(Widget, newstate)
        end
    end
end


function Control.cl_onSliderChange( self, sliderName, sliderPos )
    print("sliderCHange",sliderName,sliderPos)
    if sliderName == "TimeSlider" then
        print("changing time to",sliderPos)
        -- sendTo Server
    end
end

function Control.client_onRaceMenuClose( self )
    --print("MenuOnclose")
    if PopUpYNOpen then
		self.RaceMenu:open()
		self.RaceMenu:setVisible("CreateRacePanel", true)
		self.RaceMenu:setVisible("PopUpYNMainPanel", false)
		PopUpYNOpen = false
	elseif self.DraftExpanded then
		self.DraftExpanded = false
		self:client_DropDownButton( { btnName = "DraftBtn", index = "DraftMode", state = false } )
    end
    --self.RaceMenu:destroy()
    --self.RaceMenu = sm.gui.createGuiFromLayout( "$CONTENT_"..MOD_UUID.."/Gui/Layouts/RaceMenu.layout",false )

end



