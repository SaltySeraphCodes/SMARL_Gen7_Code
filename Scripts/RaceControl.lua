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
CAMERA_INSTRUCTIONS = MOD_FOLDER .. "/JsonData/cameraInput.json"
QUALIFYING_DATA = MOD_FOLDER .. "/JsonData/qualifyingData.json" -- Data structure with id, place, and split, formed by python
QUALIFYING_FLIGHT_DATA = MOD_FOLDER .. "/JsonData/qualifying_flight_"
Control = class( nil )
Control.maxChildCount = -1
Control.maxParentCount = -11
Control.connectionInput = sm.interactable.connectionType.logic
Control.connectionOutput = sm.interactable.connectionType.logic
Control.colorNormal = sm.color.new( 0xffc0cbff )
Control.colorHighlight = sm.color.new( 0xffb6c1ff )
local clock = os.clock --global clock to benchmark various functional speeds ( for fun)



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
    if self.smarCamLoaded then
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
    self.handiCapMultiplier = 1.5
    self.handiCapEnabled = true
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
        self.RaceMenu:setButtonCallback( "DraftBtn", "client_buttonPress" )
        self.RaceMenu:setButtonCallback( "DraftYes", "client_buttonPress" )
        self.RaceMenu:setButtonCallback( "DraftNo", "client_buttonPress" )

        -- Time Limit callbac NOTE: SLIDERS DO NOT WORK
        --self.RaceMenu:setSliderCallback( "TimeSlider", "cl_onSliderChange" )
        --self.RaceMenu:setButtonCallback( "TimeSlider", "client_buttonPress" )
        --self.RaceMenu:setVisible("TimeSlider",false)

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

-- Camera things
    self.smarCamLoaded = false
    self.externalControlsEnabled = true
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
    self.droneOffset = sm.vec3.new(50,25,10) -- virtual offset/movement of drone
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
    self.frameCountTime = 0
	--print("Camera Control Init")

end

function Control.server_init(self)
    self.debug = true
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

    -------------------- QUALIFYING SETUP -----------------
    self.qualifying = true -- whether we are qualifying or not -- dynamic
    self.qualifyingFlight = 1 -- which flight to store data as
    self.totalFlights = 1 -- choose how many flights there are (can automate but eh)
    -----------------------------------------------------

    self.finishResults = {}
    self.qualifyingResults = {} -- list of results per flight

    self.leaderID = nil -- race leader id
    self.leaderTime = 0 -- takes splits from leader
    self.leaderNode = 0 -- ? keeps track of which node leader is on
    
    self.resetCarTimer = Timer()
    self.resetCarTimer:start(5)

    self.dataOutputTimer = Timer()
    self.dataOutputTimer:start(1)

    self.timeSplitArray = {} -- each node makes rough split

    self.handiCapThreshold = 5 -- how far away before handicap starts

    self.handiCapOn = false
    self.draftStrength = 100 -- TODO: implement
    self.handiCapStrength = 100
    self.handiCapMultiplier = 1.5 -- multiplies handicap by ammount
    print("Race Control V2.0 Initialized SV")
    RACE_CONTROL = self 
    -- TODO: Make lap count based off of totalNodes too, not just crossing line 
    self.sortedDrivers = {} -- Sorted list by race position of drivers, necessary? for printing?
    self.raceResultsShown = false
    self:updateRacers()

    -- just cam things
    self.smarCamLoaded = false
    self.externalControlsEnabled = true
    self.viewIngCamera = false -- whether camera is being viewed
    
    
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
    self.network:sendToClients("cl_setZoomInState",state) --TODO maybe have pcall here for aborting versus stopping
end


function Control.sv_setZoomOutState(self,val)
    local state = false
    if val == 1 then
        state = true
    end
    self.network:sendToClients("cl_setZoomOutState",state) --TODO maybe have pcall here for aborting versus stopping
end

function Control.cl_setZoom(self)
    --print(self.zoomIn,self.zoomOut)
    local zoomSpeed = 0.6
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
        --print(driver.id,nodeDif,driver.handicap)
        if nodeDif < self.handiCapThreshold or self.raceStatus > 1 then -- caution or formation
            handicap = 0
        elseif nodeDif > self.handiCapStrength then
            handicap = self.handiCapStrength
        end
        --self:sv_sendCommand({car = driver.id, type="handicap", value=handiCap) honesty unecessary...
        if handicap == nil then handicap = 1 end
        driver.handicap = handicap * self.handiCapMultiplier
            
        
    end
end


function Control.sv_toggleRaceMode(self,mode) -- starts 
    print("toggling race mode")
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

end

function Control.sv_startRace(self)
    print("Race Start!") -- introduce delay?
    self:sv_sendAlert("Race Started")
    self.powered = true
    self.raceStatus = 1
    -- check if active or not first
    self:sv_sendCommand({car = {-1},type = "raceStatus", value = 1 })
    --self.controllerSwitch:setActive(true) TODO: find proper workaround otherwise just remove the switch
end


function Control.sv_stopRace(self)
    print("stoprace")
    self:sv_sendAlert("Race Stopped")
    self.raceStatus = 0
    self.powered = false
    self:sv_sendCommand({car = {-1},type = "raceStatus", value = 0 })
    -- check if active or not
    --self.controllerSwitch:setActive(false)
    if self.raceFinished then
        print("Stopping finished race: auto reset")
        self:sv_resetRace()
    end
end

function Control.sv_startFormation(self) -- race status 2
    print("Beggining formation lap")
    -- Grab qualifying information
    qualData = self:sv_ReadQualJson()
    for k=1, #qualData do local v=qualData[k] -- sets driver formation position based on data
        local id = v.racer_id
        local driver = getDriverFromMetaId(id)
        if driver ~= nil then
            driver.formationPos = v.position
        else
            print("missing",v.racer_name)
        end
    end 
    self:sv_sendAlert("Starting Formation Lap")
    self.raceStatus = 2
    self:sv_sendCommand({car = {-1},type = "raceStatus", value = 2 })
    
end


function Control.sv_cautionFormation(self) -- race status 3
    self:sv_sendAlert("#FFFF00Caution Flag")
    self.raceStatus = 3
    self:sv_sendCommand({car = {-1},type = "raceStatus", value = 3 })
    -- store position

end

function Control.setCautionPositions(self) -- sv sets all driver caution positions to their current positions
    for k=1, #ALL_DRIVERS do local v=ALL_DRIVERS[k]
        local curPos = self.cautionPos
        v.cautionPos = v.racePosition
        
    end
end


function Control.setFormationPositions(self) -- sv sets all driver caution positions to their current positions
    qualData = self:sv_ReadQualJson()
    if qualData == nil then
        for k=1, #ALL_DRIVERS do local v=ALL_DRIVERS[k] -- sets driver formation position based index placed
            v.formationPos = k
        end 
    else
        for k=1, #qualData do local v=qualData[k] -- sets driver formation position based on data
            local id = v.racer_id
            local driver = getDriverFromMetaId(id)
            if driver ~= nil then
                driver.formationPos = v.position
            end
        end 
    end
end
    --print("Set caution Positions")

function Control.cl_resetRace(self) -- sends commands to all cars and then resets self
    self.network:sendToServer("sv_resetRace")
    self:client_onRefresh()
end

function Control.sv_resetRace(self) -- sends commands to all cars and then resets self
    print("Resetting race")
    self:sv_sendCommand({car = {-1}, type = "resetRace", value = 0}) -- extra data in value just in ccase?
    self:sv_sendAlert("Race Reset")
    self:server_onRefresh()
    
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
    
    if self.handiCapMultiplier <= 1 and ammount <0 then
        print("disabled handicap")
        self.handiCapMultiplier = 0
    elseif self.handiCapMultiplier < 1 and ammount > 0 then
        self.handiCapMultiplier = 1
    else
        self.handiCapMultiplier = self.handiCapMultiplier + ammount
    end
    self.network:setClientData(self.handiCapMultiplier) -- send tagetLaps to clients
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
        if v.id == nodeNum then
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
        end
    end

    if self.currentLap <= self.targetLaps  then -- race on going -- or qualifying
        if self.currentLap >= 2 and self.handiCapEnabled == true then -- second lap, Enable drafting and handicap
            self.handiCapOn = true
            --self.draftingEnabled = true
        end

        if self.currentLap  == self.targetLaps - 1 then -- last laps
            driver.passAggression = -0.25 -- more agggressive passes?
        end
            --TODO: Investigate why car tied with 10th of second between them theoretically
        self.raceFinished = false
    else
        self.raceFinished = true
        if driver.carData['metaData'] == nil then return end
        local finishData = {
            ['position'] = driver.racePosition,
            ['racer_id'] = driver.carData['metaData']["ID"],
            ['racer_name'] = driver.carData['metaData']["Car_Name"],
            ['best_lap'] = driver.bestLap,
            ['split'] = driver.raceSplit
        }
        if self.qualifying then
            --print("Qualifyind data inserted",finishData)
            table.insert(self.qualifyingResults,finishData)
        end
        table.insert(self.finishResults,finishData) -- also store in finishResults
        --print("Finished:",#self.finishResults, #ALL_DRIVERS)
    end
    
    if driver.raceFinished ~= self.raceFinished then -- send message to driver to slow? variable slow speeds?
        driver.raceFinished = self.raceFinished
    

    --if #self.finishResults == #ALL_DRIVERS then -- TODO: deciding on whether to output all at once or one at a time, will need to adjust log parse if all at once
        if #self.qualifyingResults == #ALL_DRIVERS then
            if self.qualifying then --  qualifying round
                local flightNum = string.format("%s",self.qualifyingFlight) -- May need to string format
                sm.json.save(self.qualifyingResults, QUALIFYING_FLIGHT_DATA .. flightNum .. ".json")
                if self.totalFlights == 1 then -- If only one flight, just push results straight to final file
                    print("Saving single flight qual data",self.qualifyingResults)
                    sm.json.save(self.qualifyingResults, QUALIFYING_DATA)
                end
            end
        end

        --print("driver finished!",self.finishResults)
        local outputString = 'finish_data= [ ' -- 
        
        for k=1, #self.finishResults do local v=self.finishResults[k] -- Output finish data for live board
            --print("Finished race, outputting")
            if v ~= nil then
                local time_split = string.format("%.3f",v.split)
                local output = '{"id": "'.. v.racer_id ..'", "bestLap": "'..v.best_lap ..'", "place": "'.. v.position..'", "split": "'.. time_split..'"},'
                outputString = outputString .. output
            end
        end
        local noCommaEnding = string.sub(outputString,1,-2)
        local endString = ']'
        outputString = noCommaEnding .. endString
        --print("Outputting finish",outputString)
        self:sv_output_data(outputString)
    --end
    end

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
    self:tickClock()
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

    if self.smarCamLoaded and self.externalControlsEnabled then
        self:sv_ReadJson()
        self:sv_readZoomJson()
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
        if power == nil then -- assume off
            if self.powered or self.raceStatus ~= 0 then
                self:sv_stopRace()
            end
        elseif power then -- switch on
            if self.raceStatus == 0 or self.powered == false then
                self:sv_startRace()
            end
        elseif power == false then
            if self.powered or self.raceStatus ~= 0 then
                self:sv_stopRace()
            end
        else
            print("HUH?")
        end
    end
    if self.handiCapOn then
        self:sv_setHandicaps()
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
    
end

function Control.client_onFixedUpdate(self) -- key press readings and what not clientside
   -- MOve
   -- If freeCam on then
    --print("RC cl fixedBefore")
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
                if self.droneFollowPos then
                -- Set new droneLocation?
                end
            elseif self.cameraMode == 0 then -- and in free cam mode
                local movement = self:cl_moveCamera()
                if movement ~= 0 and movement ~= nil then
                    --print("Camera mode 0 Setting Pos")
                    self:cl_sendCameraCommand({command = "MoveCamera", value=movement})
                end
            elseif self.cameraMode == 1 then -- raceCamMode -- TODO: probably just remove all of thie
                --print("racecam mode",self.currentCamera,#ALL_CAMERAS)
                if #ALL_CAMERAS > 0 and self.currentCamera == nil then
                    --print("swittchingto camera 1")
                    self:switchToCamera(1) -- go to first camera
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
            camPos = self.droneLocation
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
    -- In Race status

    --[[ Match CountDown [[ Could be used for race countdowns?
    if self.matchCountDownFlag and not self.matchStartCountdown:done() then
        local timeLeft = self.matchStartCountdown:remaining()
        -- IF self has no team ID  set interaction Text To pick a team
        sm.gui.displayAlertText( "Match Staring In: "..tostring(timeLeft), 1 )
    end

    if self.TeamMenu then 
        local redText = self:generateTeamList(1)--"PlayerName\nPlayerName2\n"
        local blueText = self:generateTeamList(2)
        self.TeamMenu:setText("RedDisplay",redText)
        self.TeamMenu:setText("BlueDisplay",blueText)
    end


    if self.cl_gameStarted then -- Possibly have race stats here?
        self.RaceMenu:setText("StartGame","Cancel Game")
        self.RaceMenu:setText("SetupHeader","Game In Progress")
        self.RaceMenu:setVisible("ContainerHostPanel",false)
        -- TODO: Possibly have game stats here
    else
        self.RaceMenu:setText("StartGame","Start Game")
        self.RaceMenu:setText("SetupHeader","Creative PVP Game Setup")
        self.RaceMenu:setVisible("ContainerHostPanel",true)
    end]]

    
    if self.RaceMenu then
        self.RaceMenu:setText("LapValue", tostring(self.targetLaps) )
    end

    if self.RaceMenu then
        local handiValue = string.format("%.1f",self.handiCapMultiplier)
        if self.handiCapMultiplier == 0 then
            handiValue = "Off"
        end
        self.RaceMenu:setText("HandiValue", tostring(handiValue) )
    end
   --print("RC cl onUpdate after")
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
    self.network:sendToClients("cl_showAlert",msg) --TODO maybe have pcall here for aborting versus stopping
end

function Control.cl_showAlert(self,msg) -- client recieves alert
    --print("Displaying",msg)
    sm.gui.displayAlertText(msg,3)
end


function Control.tickClock(self) -- Just tin case
    local floorCheck = math.floor(clock() - self.started) 
        --print(floorCheck,self.globalTimer)
    if self.globalTimer ~= floorCheck then
        self.gotTick = true
        self.resetCarTimer:tick()
        self.globalTimer = floorCheck
        self.dataOutputTimer:tick()
        --print(self.dataOutputTimer:remaining())
        if self.dataOutputTimer:done() and not self.raceFinished then
            self:sv_performTimedFuncts()
            self.dataOutputTimer:start(3)
        end
        
    else
        self.gotTick = false
        self.globalTimer = floorCheck
    end
    if self.debug then
    end
            
end

function Control.sv_performTimedFuncts(self)
    --print("doing tick thing")
    self:sv_output_allRaceData()
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
            if convertedIndex < 4 then 
                shifter = 0
            elseif convertedIndex < 8 then
                shifter = 3
            elseif convertedIndex < 10 then
                shifter = 7
            end
            local racePos = convertedIndex + shifter
            self:focusCameraOnPos(racePos)
		else -- Direct switch to camera number (up to 10)
            self.camTransTimer = 1
            self:switchToCamera(convertedIndex)
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



function Control.sv_output_allRaceData(self) -- Outputs race data into a  big list
    local outputString = 'realtime_data= [ '
	for k=1, #ALL_DRIVERS do local v=ALL_DRIVERS[k]
		if v ~= nil then
            if v.carData == nil then return end
            if v.carData['metaData'] == nil then return end
            --print(v.carData['metaData']["ID"],v.carData['metaData']["Car_Name"])
            v:determineRacePosBySplit()
            local time_split = string.format("%.3f",v.raceSplit)
			local output = '{"id": "'.. v.carData['metaData']["ID"] ..'", "locX": "'..v.location.x..'", "locY": "'.. v.location.y..
            '", "lastLap": "'..v.lastLap..'", "bestLap": "'..v.bestLap ..'", "lapNum": "'.. v.currentLap..'", "place": "'.. v.racePosition..
            '", "timeSplit": "'.. time_split ..'", "isFocused": "'..v.isFocused ..'", "speed": "'..v.speed..'"},'
			outputString = outputString .. output
		end
        
	end
	local noCommaEnding = string.sub(outputString,1,-2)
	local endString = ']'
	outputString = noCommaEnding .. endString 
	self:sv_output_data(outputString)
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
        print("Got Qual data",data)
        -- send data to cars
        return data
    end
end


function Control.sv_ReadJson(self)
    --print("RC sv readjson before")
    local status, instructions =  pcall(sm.json.open,CAMERA_INSTRUCTIONS) -- Could pcall whole function
    if status == false then -- Error doing json open
        --print("Got error reading instructions JSON")
        return nil
    else
        --print("got instruct",instructions)
        sm.json.save("[]", CAMERA_INSTRUCTIONS) -- technically not just camera instructions
        if instructions ~= nil then --0 Possibly only trigger when not alredy there (will need to read client zoomState)
            local instruction = instructions['command']
            if instruction == "exit" then
                self:sv_exitCamera()
            elseif instruction == "focusCycle" then
                local direction = instructions['value']
                print("focus cycing",direction)
                self:sv_cycleFocus(direction)
            elseif instruction == "camCycle" then
                local direction = instructions['value']
                print("cam cycing",direction)
                
                self:sv_cycleCamera(direction)
            elseif instruction == "cMode" then
                local mode = tonumber(instructions['value'])
                --print("toggle camera mode")
                self:sv_toggleCameraMode(mode)
            elseif instruction == "raceMode" then -- 0 is stop, 1 is go, 2 is caution? 3 is formation
                local raceMode = tonumber(instructions['value'])
                --print("changing mraceMode",raceMode,sv_toggleRaceMode)
                self:sv_toggleRaceMode(raceMode)
            end
            return
        else
            print("camera Instructions are nil??")
            return nil
        end
    end
    --print("RC sv readjson after")
end

function Control.sv_SaveJson(self)

end


-- camera and car following stuff
function Control.sv_cycleFocus(self,direciton) -- calls iterate camera
    self.network:sendToClients("cl_cycleFocus",direciton)
    -- remove isFocused (should be SV)
    if self.focusedRacerData ~= nil then
        self.focusedRacerData['isFocused'] = false
    end
end 

function Control.sv_setFocused(self,racerID)
    racer = getDriverFromId(racerID)
    racer.isFocused = true
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

    self.network:sendToServer("sv_setFocused",self.focusedRacerID) -- sends to server driver focus stats

	self:focusAllCameras(nextRacer) -- TODO: get this
end

function Control.focusCameraOnPos(self,racePos) -- Grabs Racers from racerData by RacerID, pulls racer
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

function Control.focusCameraOnRacerIndex(self,id) -- Grabs Racers from racerData by RacerID, pulls racer
	local racer = getDriverFromId(id) -- Racer Index is just populated as they are added in
	if racer == nil then
		print("Camera Focus on racer index Error")
		return
	end
	if racer.racePosition == nil then
		print("Racer has no RacePos",racer.id)
		return
	end
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
    self.droneLocation = racer.location + self.droneOffset -- puts initial location a bit off and higher than racer`
	
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
    print("switching to drone")
    --TODO: FAULT, Switching directly from drone mode to Race mode (on sDeck) causes the focus/Goal to be offset. 
    if self.droneLocation == nil then
        print("Initializing Drone")
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
            --print("Settind drone to follow focused racer")
            self:setDroneFollowFocusedRacer()
        end 

    end
    
    if self.focusedRacerData == nil then
        print("Drone Error focus on racer")
        return
    end
    --*print("focusing",self.focusedRacerData.location,self.droneLocation)
    local racerlocation = self.focusedRacerData.location
    --local droneLocation = self.droneData.location
    local camPos = sm.camera.getPosition()
    local goalOffset = self:getFutureGoal(self.droneLocation)
    
    local camDir = sm.camera.getDirection()
    dirMovement1 = sm.vec3.lerp(camDir,goalOffset,1) -- COuld probably just hard code as 1
    self:cl_sendCameraCommand({command="setPos",value=self.droneLocation}) -- lerp drone location>?
	self:cl_sendCameraCommand({command="setDir",value=dirMovement1}) -- TODO: get this to get focus on car and send directions to cam
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
    local location = racer.shape:getWorldPosition()
    local rvel = racer.velocity
    local carDir = racer.shape:getAt()
    --print("locZ",newLoc)
    local newCamPos = location + (carDir / 10) + (rvel * 1) + sm.vec3.new(0,0,1.4)
    --locMovement = sm.vec3.lerp(camLoc,newCamPos,dt)
    --dirMovement = sm.vec3.lerp(camDir,carDir,1)
    --print(dirMovement)
    self:cl_sendCameraCommand({command="setPos",value=newCamPos})
    self:cl_sendCameraCommand({command="setDir",value=carDir})
   
end

function Control.switchToCamera(self, cameraIndex) -- switches to certain cameras based on  inddex (up to 10) 0-9
	--cameraIndex = cameraIndex + 1 -- Accounts for stupid non zero indexed arrays
	print("Doing camIndex",cameraIndex)
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
	print("switching to camera:",cameraIndex,self.currentCameraIndex)
	self:setNewCamera(cameraIndex - 1)
end

function Control.sv_cycleCamera(self,direciton) -- calls iterate camera
    self.network:sendToClients("cl_cycleCamera",direciton)
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
	self:setNewCamera(nextIndex)
	
end

function Control.setNewCamera(self, cameraIndex) -- Switches to roadside camera based off of its index
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

    local camDir = sm.camera.getDirection()
    dirMovement1 = sm.vec3.lerp(camDir,goalOffset,self.camTransTimer) -- COuld probably just hard code as 1
    self:cl_sendCameraCommand({command="setPos",value=camLoc})
	self:cl_sendCameraCommand({command="setDir",value=dirMovement1}) -- TODO: get this to get focus on car and send directions to cam
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
        self:switchToCamera((self.currentCameraIndex or 1))
    elseif mode == 1 then -- Drone cam
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
    elseif mode == 3 then -- Onboard cam
        print("Activate dash cam")
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
    local camDir = sm.camera.getDirection()
    local camLoc = sm.camera.getPosition()
    local dirDT = dt *0.3
    local dirMovement = nil
	local locMovement = nil
	
		
    if self.droneActive then
        --print("dact")
        local goalLocation = self.droneLocation
        if goalLocation == nil then
            print("drone has no loc onupdate")
            return
        end
        local smooth = 1
        local mSmooth = 1
        if self.frameCountTime > 5 then
            smooth =dt *0.2
            mSmooth = dt
        end

        

        dirMovement = sm.vec3.lerp(camDir,goal,smooth)--self.camTransTimer
        --camLoc.z = camLoc.z-0.15 -- not sure what this is for
        locMovement = sm.vec3.lerp(camLoc,goalLocation,mSmooth)
        --print(dirMovement,goal)
        --camLoc -- 
        --print("DroneSendB",sm.camera.getPosition(),sm.camera.getDirection()) -- grab locMovement`
        self:cl_sendCameraCommand({command="setPos",value=locMovement})
        self:cl_sendCameraCommand({command="setDir",value=dirMovement})
        --`print("DroneSendA",sm.camera.getPosition(),sm.camera.getDirection())
    
    elseif self.onBoardActive then
        if self.focusedRacerData == nil then 
            print("No focus racer")
            return 
        end
        local racer = self.focusedRacerData
        if racer == nil then return end
        local location = racer.shape:getWorldPosition()-- gets front location
        local frontLength = (racer.carDimensions or 1)
        if racer.carDimensions ~= nil then 
            local rotation  =  racer.carDimensions['center']['rotation']
            local newRot =  rotation * racer.shape:getAt()
            location = racer.shape:getWorldPosition() + (newRot * racer.carDimensions['center']['length'])
            frontLength = racer.carDimensions['front']:length()/3 -- Division reduces length
        end
        local frontLoc = location - (racer.shape:getAt()*self.freecamSpeed)

        local rvel = racer.velocity
        local carDir = racer.shape:getAt()
        local dvel = carDir - camDir --racer.angularVelocity
        --print("locZ",dvel:length())
        local newCamPos = frontLoc + (rvel * 1) + sm.vec3.new(0,0,1.3)
        local newCamDir = camDir + (dvel *9)
        local smooth = 1
        local mSmooth = 1
        if self.frameCountTime > 1 then
            smooth =dt * 1.5
            mSmooth = dt*1.1
        end

        locMovement = sm.vec3.lerp(camLoc,newCamPos,mSmooth)
        --locMovement.z = location.z + 1.4
        --print(location.z,locMovement.z)
        dirMovement = sm.vec3.lerp(camDir,newCamDir,smooth)
        --print(dirMovement)
        self:cl_sendCameraCommand({command="setPos",value=locMovement})
        self:cl_sendCameraCommand({command="setDir",value=dirMovement})
    else
        -- location is alreadyh set
        dirMovement = sm.vec3.lerp(camDir,goal,self.camTransTimer)
        --print("not drone active Setting Dir")
        self:cl_sendCameraCommand({command="setDir",value=dirMovement})
    end
        
    self.camTransTimer = dirDT -- works only with 1 frame yasss!

end
-- UI

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
    elseif buttonName == "ResetRace" then
        --print("Resetting Race")
        if self.raceStatus == 1 and not self.raceFinished then -- Mid race
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






