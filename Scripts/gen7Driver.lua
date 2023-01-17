
-- SMARL CAR AI V3 (Gen 7) Driver
-- Created by Seraph -- Should be much faster and smarter than Gen 6

-- This is Gen7 SM AR (Scrap Mechanic Auto Racers) AI Driver class, All logic is performed here for both steering and engine, connect to gen7Engine and steering bearings
-- All setups can be changed in the globals.lua file, not much here
-- driver will send steering values of -1..1 which should be comverted between max angle as degrees and vice versa


-- TODO: Unscanned car may not update into scanned car in global car system, double check this
-- TODO: Fix Car reversing when stopped and has car in front\ (not num inf)
-- TODO: get ratio between totallaps and current laps, step up aggression by lap until limit reached
-- TODO: Fix Track Passing: Don't just check to pass when directly behind one, check to pass if the car is also behind not beside, default to closest pass space`
-- TODO: Send raycast when stuck/offtrack to goal/currentnodes. if there is no obstruction, then keep on rejoin, else, continue to be "stuck"
-- TODO: Check for Clear track before resetting car pos
-- TODO: Reduce or eliminate stuck timeout during caution flags
-- TODO: Caution flags and formation laps (have race mode:  Q,F,R,C, Or weekend mode that cycles between all three without input)
-- TODO: Find max common color, possibly make tag text match
-- Car still senses things below

dofile "globals.lua" -- Or json.load?

Driver = class( nil )
Driver.maxChildCount = 15
Driver.maxParentCount = 1
Driver.connectionInput = sm.interactable.connectionType.seated + sm.interactable.connectionType.power + sm.interactable.connectionType.logic
Driver.connectionOutput = sm.interactable.connectionType.power + sm.interactable.connectionType.logic + sm.interactable.connectionType.bearing
Driver.colorNormal = sm.color.new( 0x76034dff )
Driver.colorHighlight = sm.color.new( 0x8f2268ff )


-- (Event) Called from Game
function Driver.server_loadWorldContent( self, data )
	sm.event.sendToGame( "server_onFinishedLoadContent" )
    self.loadingWorld = false
    print("Driver loaded world content")
end

function Driver.server_onCreate( self ) 
    --print("Creating gen7 Driver")
    self:server_init()
end

function Driver.client_onCreate( self ) 
    self:client_init()
end

function Driver.client_onDestroy(self)
    --print("Client destroy")
    for k, v in pairs(ALL_DRIVERS) do
		if v.id == self.id then
			table.remove(ALL_DRIVERS, k)
		end
    end
    -- possibly stop engine too
    self:hideVisuals()
end

function Driver.server_onDestroy(self)
    --print("server destroy")
    clearRunningBuffers(self)
    --self.nodeMap = nil
end

function Driver.client_onRefresh( self )
    --print("clientRefresh")
	self:client_onDestroy()
	--self.effect = sm.effect.createEffect("GasEngine - Level 3", self.interactable )
    --print("Client refresh")
    -- send to server refresh
    self:client_init()
end

function Driver.server_onRefresh( self )
    --print("server refresh")
	self:server_onDestroy()
	--self.effect = sm.effect.createEffect("GasEngine - Level 3", self.interactable )
    
    self:server_init()
    
    -- send to server refresh
end

function Driver.sv_add_metaData(self,metaData) -- Adds car specific metadata to self
    if self.carData['metaData'] == nil then
        print("no metaData")
    else
        print("metaData already loaded",self.carData['metaData'])
    end
    local carID = metaData['ID']
    local carName = metaData['Car_Name']
    local carType = metaData['Car_Type']
    local bodyStyle = metaData['Body_Style']
    -- Not sure what to do with all these, but they are there
    self.carData['metaData'] = metaData
    self.storage:save(self.carData)
    local text = (self.carData['metaData'].Car_Name or 'Unnamed')
    self.tagText = (text or self.id)
end

function Driver.server_init( self )
    self.loaded = false
    -- conditional & error states
    self.trackLoaded = false
    self.trackLoadError = false
    self.nodeFindError = false
    self.noEngineError = false
    self.lostError = false
    self.raceControlError = false
    self.validError = false
    self.scanningError = false


	self.id = self.shape.id
    self.carData = {}
    self.carData = self.storage:load()  -- load car data from stored bp/storagedata possibly replace with self.data
    --print("loaded Car data",self.carData)
    -- Car Attributes
    --print("set body",self.shape.body,self.shape:getBody())
    self.body = self.shape:getBody()
    self.mass = self.body.mass
    self.location  = self.shape.worldPosition -- location of center of body (may need to offset?)
    if self.carData == nil then -- no car data 
        self.carData = {} -- create empty table then save
        -- Load car data from json??
        -- Generate carDimensions
        print("Car Data not found")
        sm.log.info("Car data not found")
        self.carDimensions = self:generateCarDimensions()
        if self.carDimensions == nil then
            print("Error while scanning Car",self.carDimensions,"Car dimensions returned nil")
            if not self.scanningError then
                self:sv_sendAlert("Car scan failed")
            end
        else
            print("Scan Success")
            self:sv_sendAlert("Car scan successful")
        end
        self.carData['carDimensions'] = self.carDimensions
        --self.carData = nil
        self.storage:save(self.carData)

    else -- if car data
        -- check for car/racer data, if nil, load from JSON?
        self.carDimensions = self.carData.carDimensions-- Make variable?
        if self.carDimensions == nil then
            self.carDimensions = self:generateCarDimensions()
            if self.carDimensions == nil then
                print("Error while generating car dimensions, Nil Car dimension return")
                if not self.scanningError then
                    self:sv_sendAlert("Car scan failed")
                end
            else
                print("Successfully scanned car")
                self:sv_sendAlert("Car scan successful")
            end
            self.carData['carDimensions'] = self.carDimensions
            --self.carData = nil
            self.storage:save(self.carData)
        else
            --print("Loaded car dimensions",self.carDimensions)
            --self.carData = nil
            self.storage:save(self.carData)
        end
    end
    self.creationBodies = self.body:getCreationBodies()
    -- Collision avoidance Attributes (is rear padding necessary?)
    self.vPadding = 0.4
    self.hPadding = 0.15 -- or more

    self.frontColDist = 1
    self.rearColDist =  1
    self.leftColDist=  1
    self.rightColDist= 1 

    if self.carDimensions ~= nil then
        self.frontColDist = self.carDimensions['front']:length() + self.vPadding
        self.rearColDist = self.carDimensions['rear']:length() + self.vPadding 
        self.leftColDist= self.carDimensions['left']:length() + self.hPadding 
        self.rightColDist= self.carDimensions['right']:length() + self.hPadding 
    end

    self.carRadar = { front = 0, rear = 0, left = 0, right = 0 }
    self.carAlongSide = {left = 0, right = 0} -- triggers -1,1 if there is a car directly alongside somewhat closely
    self.opponentFlags = {} -- list of opponents and flags
    --self.engine = nil -- gets loaded from engine

    -- Car Control attributes
    self.steering = 0
    self.throttle = 0
    self.curGear = 0 

    self.strategicSteering = 0
    self.strategicThrottle = 0

    -- Driving and character layer states
    self.seatConnected = false -- whether seat is conrol
    self.userControl = false -- If a driver seat is connected, user has control over strategic steering+throttle
    self.userPower = 0
    self.userSteer = 0
    self.userSeated = false -- self explanitory hopefully

    self.racing = false -- TODO: Add More race statuses
    self.pitting = false
    self.caution = false
    self.formation = false
    self.safeMargin = false

    self.upShiftThreshold = 0.1 -- Save per car? load from json?
    self.downShiftThreshold = 0.1

    -- Movement attributes
    self.velocity = sm.shape.getVelocity(self.shape)
    self.angularVelocity = self.body.angularVelocity
    self.speed =sm.vec3.length(self.velocity)
    self.angularSpeed = sm.vec3.length(self.angularVelocity)
    self.brakingDistance = 0 -- How long it takes for car to slow down

    --Movement States
    self.oversteer = false
    self.understeer = false
    self.rotationCorrect = false -- overrotation correction
    self.offTrack = 0 -- distance offtrack car is
    self.stuck = false
    self.lost = false -- Only if super far offtrack to the point it cant find nearest node
    self.tilted = false
    self.rejoining = false
    self.goalOffsetCorrecting = false
    self.drafting = false
    self.passing = {isPassing=false, carID = nil} -- if car is passing other car
    self.passCommit = 0 -- which direction is pass committing to
    self.speedControl = 0 -- approx speed to try to stay at
    self.verticalMovement = 0 -- rate Car is moving up/down -- could just take form self.velocity
    self.offline = false -- if the car is too far off the racing line
    self.nudging = false -- whether the car is flying to correct itself

    -- Race Meta
    self.racePosition =0
    self.distTraveled = 0
    self.totalNodes = 0
    self.currentLap = 0
    self.newLap = false -- ensure there is no double trigger
    self.handicap = 0 -- set by raceControl, how many nodes away from leader fraction
    self.lapStarted = CLOCK() -- Time the current lap was started, for timeing
    self.leaderSplit = 0 -- Time between leader and checkpoints?
    self.raceSplit = 0
    self.lastLap = 0
    self.bestLap = 0
    self.raceFinished = false 
    
    -- Situational/goalstate
    self.pathGoal = "location"
    -- Track Data (copied?)
    self.nodeChain = nil
    self.totalSegments = nil
    self.ovalTrack = false

    self.goalNode = nil
    self.goalOffset = nil
    self.goalDirection = nil
    self.goalDirectionOffset = nil
    self.followStrength = 1 -- range between 1 and 10?
    self.trackPosBias = 0 -- Angled to try and get the car to get to a certain track position
    
    self.currentNode = nil
    self.currentSegment = nil

    self.futureLook =  {segID = 0, direction = 0, length = 0, distance = 0} 
    -- Tolerances and Thresholds
    self.overSteerTolerance = -2 -- The smaller (more negeative, the number, the bigger the tollerance) (custom? set by situation) (DEFAUL -1.5)
    self.underSteerTolerance = -0.4 -- Smaller (more negative [fractional]) the more tolerance to understeer-- USED TO BE:THe bigger (positive) more tolerance to understeer (will not slow down as early, DEFAULT -0.3)
    self.passAggression = -0.4 -- DEFAULT = -0.1 smaller (more negative[fractional]) the less aggresive car will try to fit in small spaces, Limit [-2, 0?]
    -- TODO: add these to a UI and self.storage for racer customization?
    -- testing states
    self.maxSpeed = nil
    self.maxFriction = nil
    self.maxLatAcc = nil
    self.maxAngVel = nil
    self.maxFrontDif = nil
    self.sliding = false
    self.testFinished = false
    self.testStarted = 0
    self.liftPlaced = false
    self.onLift = false -- not sure where to start this
    self.resetNode = nil
    self.carResetsEnabled = true -- whether to teleport car or not

    self.debug = false


    -- errorTimeouts
    self.RCE_timeout = 0
    self.nodeFindTimeout = 0
    self.stuckTimeout = 0
    self.resetPosTimeout = 0

    -- Race results state
    self.displayResults = true -- Whether to actually send the chat messge
    self.resultsDisplayed = false -- Check if message already displayed

    -- Effects 
    self.goalNodeEffect = nil
    self.currentNodeEffect = nil -- Populated on client
    self.effectsList = {self.goalNodeEffect,self.currentNodeEffect}
    --print(self.shape.at)
    self.creationId = self.body:getCreationId()
    self.player = nil -- host player
	print("SMAR Load",self.id,self.carData['metaData'])
     -- Insert into global allDrivers so everyone has access Possibly have a public/private section?
end

function Driver.client_init(self)
    --print("Diver Client Init")
    -- Debug effects
    local colors = {
        front = sm.color.new("0721FFFF"), -- blue
        rear = sm.color.new("FF0707FF"), -- red
        right = sm.color.new("00FF1BFF"), -- Green
        left = sm.color.new("DCFF00FF"), -- yellow
        goal = sm.color.new("FF9106FF"), -- Orange 
        cur = sm.color.new("B706FFFF"), -- purple
        center = sm.color.new("06FFFBFF") -- #06FFFB cyan
    }

    -- item visualization
    --local effect = sm.effect.createEffect("ShapeRenderable")
    --effect:setParameter("uuid", uuid)
    --effect:setParameter("visualization", true)
    --effect:setScale(size)
    --effect:setPosition(pos)
    --effect:start()
    if sm.isHost then
        self.player = sm.localPlayer.getPlayer()
        --print("host player",self.player)
    end
    self.frontEffect = {pos = nil, effect =sm.effect.createEffect("Loot - GlowItem")}
    self.frontEffect.effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    self.frontEffect.effect:setScale(sm.vec3.new(0,0,0))
    self.frontEffect.effect:setParameter( "Color", colors.front )

    self.leftEffect = {pos = nil, effect =sm.effect.createEffect("Loot - GlowItem")}
    self.leftEffect.effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    self.leftEffect.effect:setScale(sm.vec3.new(0,0,0))
    self.leftEffect.effect:setParameter( "Color", colors.left )
    
    self.rightEffect = {pos = nil, effect =sm.effect.createEffect("Loot - GlowItem")}
    self.rightEffect.effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    self.rightEffect.effect:setScale(sm.vec3.new(0,0,0))
    self.rightEffect.effect:setParameter( "Color", colors.right )
    
    self.rearEffect = {pos = nil, effect =sm.effect.createEffect("Loot - GlowItem")}
    self.rearEffect.effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    self.rearEffect.effect:setScale(sm.vec3.new(0,0,0))
    self.rearEffect.effect:setParameter( "Color", colors.rear )
    
    self.goalNodeEffect = {pos = nil, effect =sm.effect.createEffect("Loot - GlowItem")}
    self.goalNodeEffect.effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    self.goalNodeEffect.effect:setScale(sm.vec3.new(0,0,0))
    self.goalNodeEffect.effect:setParameter( "Color", colors.goal )
    
    self.currentNodeEffect = {pos = nil, effect = sm.effect.createEffect("Loot - GlowItem")} 
    self.currentNodeEffect.effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    self.currentNodeEffect.effect:setScale(sm.vec3.new(0,0,0))
    self.currentNodeEffect.effect:setParameter( "Color", colors.cur )
    
    self.calcCenterEffect = {pos = nil, effect = sm.effect.createEffect("Loot - GlowItem")} 
    self.calcCenterEffect.effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    self.calcCenterEffect.effect:setScale(sm.vec3.new(0,0,0))
    self.calcCenterEffect.effect:setParameter( "Color", colors.center )

    
    self.fflEffect = {pos = self.location, effect =sm.effect.createEffect("Loot - GlowItem")}
    self.fflEffect.effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    self.fflEffect.effect:setScale(sm.vec3.new(0,0,0))
    self.fflEffect.effect:setParameter( "Color", colors.front )

    self.ffrEffect = {pos =  self.location, effect =sm.effect.createEffect("Loot - GlowItem")}
    self.ffrEffect.effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    self.ffrEffect.effect:setScale(sm.vec3.new(0,0,0))
    self.ffrEffect.effect:setParameter( "Color", colors.left )
    
    self.fblEffect = {pos =  self.location, effect =sm.effect.createEffect("Loot - GlowItem")}
    self.fblEffect.effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    self.fblEffect.effect:setScale(sm.vec3.new(0,0,0))
    self.fblEffect.effect:setParameter( "Color", colors.right )
    
    self.fbrEffect = {pos =  self.location, effect =sm.effect.createEffect("Loot - GlowItem")}
    self.fbrEffect.effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    self.fbrEffect.effect:setScale(sm.vec3.new(0,0,0))
    self.fbrEffect.effect:setParameter( "Color", colors.rear )

    
    self.effectsList = {self.goalNodeEffect,self.currentNodeEffect,self.frontEffect,self.leftEffect,
                        self.rightEffect,self.rearEffect,self.calcCenterEffect,
                        self.fflEffect, self.ffrEffect, self.fblEffect, self.fbrEffect
                    }
                    --print(self.effectsList)
    self.idTag = sm.gui.createNameTagGui()
    self.idTag:setHost(self.shape)
	self.idTag:setRequireLineOfSight( false )
	self.idTag:setMaxRenderDistance( 500 )
    if self.carData['metaData'] ~= nil then
        local text = (self.carData['metaData'].Car_Name or '')
        self.tagText = (text or self.id)
    else
        self.tagText = self.id
    end
	self.idTag:setText( "Text", "#ff0000"..self.tagText)


    if self.debug then
        self:showVisuals()
    end
    if not self.trackLoaded then
        --print("client load trackData")
        self:loadTrackData() -- Track data could contain racing lines and everything else (Should be server side, not client side)
    end
    self:addRacer()
    if self.player ~= nil then 
        self.network:sendToServer("sv_addPlayer",self.player)
    else
        print("not host or player not found")
    end
    --print(#ALL_DRIVERS) -- dont give whole engine
end


-- Soft reset, resets most values except those important for the middle of a race
function Driver.sv_softReset(self)
    self.nodeFindError = false
    self.noEngineError = false
    self.lostError = false
    self.raceControlError = false
    self.validError = false
    self.scanningError = false
    self.body = self.shape:getBody()
    self.mass = self.body.mass
    self.location  = self.shape.worldPosition -- location of center of body (may need to offset?)
    if self.carData == nil then -- no car data 
        print("Soft reset could not find car data")
    else -- if car data
    end
    self.creationBodies = self.body:getCreationBodies()
    -- Collision avoidance Attributes (is rear padding necessary?)
    
    -- Car Control attributes
    self.steering = 0
    self.throttle = 0
    self.curGear = 0 

    self.strategicSteering = 0
    self.strategicThrottle = 0

    -- Movement attributes
    self.velocity = sm.shape.getVelocity(self.shape)
    self.angularVelocity = self.body.angularVelocity
    self.speed =sm.vec3.length(self.velocity)
    self.angularSpeed = sm.vec3.length(self.angularVelocity)
    self.brakingDistance = 0 -- How long it takes for car to slow down

    --Movement States
    self.oversteer = false
    self.understeer = false
    self.rotationCorrect = false -- overrotation correction
    self.offTrack = 0 -- distance offtrack car is
    self.stuck = false
    self.lost = false -- Only if super far offtrack to the point it cant find nearest node
    self.tilted = false
    self.rejoining = false
    self.goalOffsetCorrecting = false
    self.drafting = false
    self.passing = {isPassing=false, carID = nil} -- if car is passing other car
    self.passCommit = 0 -- which direction is pass committing to
    self.speedControl = 0 -- approx speed to try to stay at
    self.verticalMovement = 0 -- rate Car is moving up/down -- could just take form self.velocity
    self.offline = false -- if the car is too far off the racing line
    self.nudging = false -- whether the car is flying to correct itself
    -- Situational/goalstate
    self.pathGoal = "location"
    -- Track Data (copied?)

    --self.goalNode = nil
    --self.goalOffset = nil
    --self.goalDirection = nil
    --self.goalDirectionOffset = nil
    self.followStrength = 1 -- range between 1 and 10?
    --self.trackPosBias = 0 -- Angled to try and get the car to get to a certain track position
    
    --self.currentNode = nil -- keep?
    --self.currentSegment = nil

    self.futureLook =  {segID = 0, direction = 0, length = 0, distance = 0} 
    -- Tolerances and Thresholds
   
    -- errorTimeouts
    self.RCE_timeout = 0
    self.nodeFindTimeout = 0
    self.stuckTimeout = 0
    self.resetPosTimeout = 0

    -- Effects 
   --print(self.tagText,"sv_soft reset")
end

function Driver.sv_hard_reset(self) -- resets everything including lap but not collision data
    self.loaded = false
    -- conditional & error states
    self.trackLoaded = false
    self.trackLoadError = false
    self.nodeFindError = false
    self.noEngineError = false
    self.lostError = false
    self.raceControlError = false
    self.validError = false
    self.scanningError = false

	--self.id = self.shape.id
    -- Car Attributes
    --print("set body",self.shape.body,self.shape:getBody())
    self.body = self.shape:getBody()
    self.creationBodies = self.body:getCreationBodies()
    self.mass = self.body.mass
    self.location  = self.shape.worldPosition -- location of center of body (may need to offset?)

    self.carData = self.storage:load()  -- load car data from stored bp/storagedata possibly replace with self.data
    --print("loaded Car data",self.carData)
    if self.carData == nil then
        print("ERROR: Car data not found (please re-scan/save the car)")
    else -- if car data
        -- check for car/racer data, if nil, load from JSON?
        self.carDimensions = self.carData.carDimensions-- Make variable?
        if self.carDimensions == nil then
            print("Hard Reset could not find car dimensions")
        else
            --print("Loaded car dimensions",self.carDimensions)
        end
    end
    
    -- Collision avoidance Attributes (is rear padding necessary?)
    self.vPadding = 0.4
    self.hPadding = 0.15 -- or more

    self.frontColDist = 1
    self.rearColDist =  1
    self.leftColDist=  1
    self.rightColDist= 1 

    if self.carDimensions ~= nil then
        self.frontColDist = self.carDimensions['front']:length() + self.vPadding
        self.rearColDist = self.carDimensions['rear']:length() + self.vPadding 
        self.leftColDist= self.carDimensions['left']:length() + self.hPadding 
        self.rightColDist= self.carDimensions['right']:length() + self.hPadding 
    end

    self.carRadar = { front = 0, rear = 0, left = 0, right = 0 }
    self.carAlongSide = {left = 0, right = 0} -- triggers -1,1 if there is a car directly alongside somewhat closely
    self.opponentFlags = {} -- list of opponents and flags
    --self.engine = nil -- gets loaded from engine

    -- Car Control attributes
    self.steering = 0
    self.throttle = 0
    self.curGear = 0 

    self.strategicSteering = 0
    self.strategicThrottle = 0

    -- Driving and character layer states
    self.seatConnected = false -- whether seat is conrol
    self.userControl = false -- If a driver seat is connected (and ai switch is off), user has control over strategic steering+throttle
    self.racing = false -- TODO: Add More race statuses
    self.pitting = false
    self.caution = false
    self.formation = false
    self.safeMargin = false

    -- Movement attributes
    self.velocity = sm.shape.getVelocity(self.shape)
    self.angularVelocity = self.body.angularVelocity
    self.speed =sm.vec3.length(self.velocity)
    self.angularSpeed = sm.vec3.length(self.angularVelocity)
    self.brakingDistance = 0 -- How long it takes for car to slow down

    --Movement States
    self.oversteer = false
    self.understeer = false
    self.rotationCorrect = false -- overrotation correction
    self.offTrack = 0 -- distance offtrack car is
    self.stuck = false
    self.lost = false -- Only if super far offtrack to the point it cant find nearest node
    self.tilted = false
    self.rejoining = false
    self.goalOffsetCorrecting = false
    self.drafting = false
    self.passing = {isPassing=false, carID = nil} -- if car is passing other car
    self.passCommit = 0 -- which direction is pass committing to
    self.speedControl = 0 -- approx speed to try to stay at
    self.verticalMovement = 0 -- rate Car is moving up/down -- could just take form self.velocity
    self.offline = false -- if the car is too far off the racing line

    -- Race Meta Will get reset on hard reset
    self.racePosition =0
    self.distTraveled = 0
    self.totalNodes = 0
    self.currentLap = 0
    self.newLap = false -- ensure there is no double trigger
    self.handicap = 0 -- set by raceControl, how many nodes away from leader fraction
    self.lapStarted = CLOCK() -- Time the current lap was started, for timeing
    self.leaderSplit = 0 -- Time between leader and checkpoints?
    self.raceSplit = 0
    self.lastLap = 0
    self.bestLap = 0
    self.raceFinished = false 
    
    -- Situational/goalstate
    self.pathGoal = "location"
    -- Track Data (copied?)
    self.nodeChain = nil
    self.totalSegments = nil
    self.ovalTrack = false

    self.goalNode = nil
    self.goalOffset = nil
    self.goalDirection = nil
    self.goalDirectionOffset = nil
    self.followStrength = 1 -- range between 1 and 10?
    self.trackPosBias = 0 -- Angled to try and get the car to get to a certain track position
    
    self.currentNode = nil
    self.currentSegment = nil

    self.futureLook =  {segID = 0, direction = 0, length = 0, distance = 0} 
    
  -- errorTimeouts
    self.RCE_timeout = 0
    self.nodeFindTimeout = 0
    self.stuckTimeout = 0

    -- Race results state
    self.displayResults = true -- Whether to actually send the chat messge
    self.resultsDisplayed = false -- Check if message already displayed
	print("SMAR Driver Hard Reset",self.id)

end

function Driver.cl_hard_reset(self) -- resets client side objects
    --print("Diver Client Init")
    -- Debug effects
    local colors = {
        front = sm.color.new("0721FFFF"), -- blue
        rear = sm.color.new("FF0707FF"), -- red
        right = sm.color.new("00FF1BFF"), -- Green
        left = sm.color.new("DCFF00FF"), -- yellow
        goal = sm.color.new("FF9106FF"), -- Orange 
        cur = sm.color.new("B706FFFF"), -- purple
        center = sm.color.new("06FFFBFF") -- #06FFFB cyan
    }

    -- item visualization
    --local effect = sm.effect.createEffect("ShapeRenderable")
    --effect:setParameter("uuid", uuid)
    --effect:setParameter("visualization", true)
    --effect:setScale(size)
    --effect:setPosition(pos)
    --effect:start()

    self.frontEffect = {pos = nil, effect =sm.effect.createEffect("Loot - GlowItem")}
    self.frontEffect.effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    self.frontEffect.effect:setScale(sm.vec3.new(0,0,0))
    self.frontEffect.effect:setParameter( "Color", colors.front )

    self.leftEffect = {pos = nil, effect =sm.effect.createEffect("Loot - GlowItem")}
    self.leftEffect.effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    self.leftEffect.effect:setScale(sm.vec3.new(0,0,0))
    self.leftEffect.effect:setParameter( "Color", colors.left )
    
    self.rightEffect = {pos = nil, effect =sm.effect.createEffect("Loot - GlowItem")}
    self.rightEffect.effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    self.rightEffect.effect:setScale(sm.vec3.new(0,0,0))
    self.rightEffect.effect:setParameter( "Color", colors.right )
    
    self.rearEffect = {pos = nil, effect =sm.effect.createEffect("Loot - GlowItem")}
    self.rearEffect.effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    self.rearEffect.effect:setScale(sm.vec3.new(0,0,0))
    self.rearEffect.effect:setParameter( "Color", colors.rear )
    
    self.goalNodeEffect = {pos = nil, effect =sm.effect.createEffect("Loot - GlowItem")}
    self.goalNodeEffect.effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    self.goalNodeEffect.effect:setScale(sm.vec3.new(0,0,0))
    self.goalNodeEffect.effect:setParameter( "Color", colors.goal )
    
    self.currentNodeEffect = {pos = nil, effect = sm.effect.createEffect("Loot - GlowItem")} 
    self.currentNodeEffect.effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    self.currentNodeEffect.effect:setScale(sm.vec3.new(0,0,0))
    self.currentNodeEffect.effect:setParameter( "Color", colors.cur )
    
    self.calcCenterEffect = {pos = nil, effect = sm.effect.createEffect("Loot - GlowItem")} 
    self.calcCenterEffect.effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    self.calcCenterEffect.effect:setScale(sm.vec3.new(0,0,0))
    self.calcCenterEffect.effect:setParameter( "Color", colors.center )
    

    self.fflEffect = {pos = nil, effect =sm.effect.createEffect("Loot - GlowItem")}
    self.fflEffect.effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    self.fflEffect.effect:setScale(sm.vec3.new(0,0,0))
    self.fflEffect.effect:setParameter( "Color", colors.front )

    self.ffrEffect = {pos = nil, effect =sm.effect.createEffect("Loot - GlowItem")}
    self.ffrEffect.effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    self.ffrEffect.effect:setScale(sm.vec3.new(0,0,0))
    self.ffrEffect.effect:setParameter( "Color", colors.left )
    
    self.fblEffect = {pos = nil, effect =sm.effect.createEffect("Loot - GlowItem")}
    self.fblEffect.effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    self.fblEffect.effect:setScale(sm.vec3.new(0,0,0))
    self.fblEffect.effect:setParameter( "Color", colors.right )
    
    self.fbrEffect = {pos = nil, effect =sm.effect.createEffect("Loot - GlowItem")}
    self.fbrEffect.effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    self.fbrEffect.effect:setScale(sm.vec3.new(0,0,0))
    self.fbrEffect.effect:setParameter( "Color", colors.rear )
    -- center?



    self.effectsList = {self.goalNodeEffect,self.currentNodeEffect,self.frontEffect,self.leftEffect,
                        self.rightEffect,self.rearEffect,self.calcCenterEffect,
                        self.fflEffect, self.ffrEffect, self.fblEffect, self.fbrEffect
                    }

    self.idTag = sm.gui.createNameTagGui()
    self.idTag:setHost(self.shape)
	self.idTag:setRequireLineOfSight( false )
	self.idTag:setMaxRenderDistance( 500 )
    if self.carData['metaData'] ~= nil then
        local text = (self.carData['metaData'].Car_Name or '')
        self.tagText = (text or self.id)
    else
        self.tagText = self.id
    end
	self.idTag:setText( "Text", "#ff0000"..self.tagText)


    if self.debug then
        self:showVisuals()
    end
    if not self.trackLoaded then
        print("client load trackData")
        self:loadTrackData() -- Track data could contain racing lines and everything else (Should be server side, not client side)
    end
    self:addRacer()
    --print(#ALL_DRIVERS) -- dont give whole engine
end

-- Initializing

function Driver.addRacer(self) -- declares itself to race control (grabs race status from RC)
    --print("add racer?",self.tagText)
    table.insert(ALL_DRIVERS,self)
    self:sv_sendCommand({car = {self.id}, type = "add_racer", value = 1})
end

function Driver.sv_addPlayer(self,player) -- sends player to server
    self.player = player
    --print("added player sv",self.player)
end

function Driver.loadTrackData(self) -- loads in any track data from the world
    --print('loadTrackData network send')
    local data = self.network:sendToServer("sv_loadData",TRACK_DATA) -- Will be good
end

function Driver.sv_loadData(self,channel)
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

function Driver.on_trackLoaded(self,data) -- Callback for when track data is actually loaded
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

function Driver.on_engineLoaded(self,data) -- callback when engine is connected to driver
    if data == nil then print("ENgine Loaded nil",data) return end
    self.engine = data
    self.noEngineError = false
end

function Driver.on_engineDestroyed(self,data)
    self.engine = nil
    self.noEngineError = true
    --print("engineDestroyed")
end

function Driver.generateCarDimensions(self) -- gets dimensions  of car (( only scan when placed on lift)) 
    if self.body:isDynamic() then -- Body is not on lift 
        self.scanningError = true
        print("Car must be on lift to be scanned propperly")
        self:sv_sendAlert("Car must be on lift to be scanned properly") -- send to
        self.scanningError = true
        return nil 
    end
    local frontOffset =  sm.vec3.new(0,0,0) -- Keeping vectors to have simplicity later on
    local rearOffset = sm.vec3.new(0,0,0)
    local leftOffset = sm.vec3.new(0,0,0)
    local rightOffset = sm.vec3.new(0,0,0) -- posibly change to {direction, length}
    local centerOffset = {rotation = sm.vec3.new(0,0,0), length = 1} -- multiply rot by at, add (len * rot) to worldPos

    local frontDir = self.shape.at
    local curLocation = self.shape.worldPosition
    local bodyShapes = self.body:getCreationShapes()

    -- GEt all directional offsets
    --print("front")
    frontOffset = getDirectionOffset(bodyShapes,frontDir,curLocation)
    --print("rear") 
    rearOffset = getDirectionOffset(bodyShapes,frontDir*-1,curLocation) 
    --print("right")
    rightOffset = getDirectionOffset(bodyShapes,self.shape.right*1,curLocation) 
    --print("left")
    leftOffset = getDirectionOffset(bodyShapes,self.shape.right*-1,curLocation)
    if not frontOffset or not rearOffset or not leftOffset or not rightOffset then
        print("Error Scanning Car",frontOffset,rearOffset,leftOffset,rightOffset)
        return nil 
    end
   
    local frontLeft = curLocation + frontOffset + leftOffset
    local rearRight = curLocation + rightOffset + rearOffset
    local center = getMidpoint(frontLeft,rearRight)
    local centerOffset = (center - curLocation)-- translate relative to self.shape.at and self.shape.right
    --print(centerOffset:length())
    local centerAt = centerOffset - self.shape.at
    local centerRight = centerOffset - self.shape.right
    --print(leftOffset.y,rightOffset.y,centerOffset)
    local v1 = self.shape:getAt()

    local v2,centerRotationVec,centerLen
    if centerOffset:length() == 0 then -- vector is 0
        v2 = sm.vec3.new(0,0,0)
        centerRotationVec = sm.vec3.new(0,0,0)
        centerLen = 0
    else
         v2 = centerOffset:normalize()
        centerRotationVec = sm.vec3.getRotation(v1, v2) -- Store this
        centerLen = centerOffset:length() -- Store this too
    end
    centerOffset = {rotation = centerRotationVec, length = centerLen}

    
    local newRot =  centerRotationVec * self.shape:getAt()
    local newCenter = self.shape.worldPosition + (newRot * centerLen)
    --print("worldCheck",centerOffset,newRot,centerRotationVec)
    print(leftOffset.y,rightOffset.y)
    local carDimensions =  {
            front = frontOffset,
            rear = rearOffset,
            left = leftOffset,
            right = rightOffset,
            center = centerOffset
            }
    --print("Dimension offsets",carDimensions, "shape location",curLocation)
            
    return carDimensions
end

function Driver.cl_hard_reset_Racer(self) -- resets racer from client
    self.network:sendToServer("sv_hard_reset_Racer")
    print("resetting racer")
end

function Driver.sv_hard_reset_Racer(self) -- resets racers (used after races mostly)
    self:hard_reset() 
    self.network:sendToClients("cl_hard_reset")
end

-- Control layer
function Driver.setSteering(self,value) --Just sets the bearings
    if self.speed > 0.2 then -- prevent twitching while in stand still
        for k, v in pairs(sm.interactable.getBearings(self.interactable )) do
            -- Possibly set the steer speed (0.25) to be adjusted by car speed
            sm.joint.setTargetAngle( v, value, 11, 10000)
        end
    end
end

function Driver.outputThrotttle(self,value)
    if type(value) ~= "number" or math.abs(value) == math.huge then
        print("not num",value)
        value = 0.5
    end
    self.interactable:setPower(value)
end

function  Driver.shiftGear(self,gear) --sets the gear for engine
    if self.engine == nil then return end
    if self.engine.engineStats == nil then return end
    self.curGear = gear
    self.engine:setGear(gear)
end

function Driver.updateControlLayer(self)
    if not self.userControl then 
        local angle = steeringToDegrees((self.strategicSteering or 0))-- In Degrees 
        local radians = angleToRadians(angle) -- Can save performance by reducing # of conversions if necessary
        self.steering = angle -- Has steering in degrees (necessary to calculate oversteer n stuff)
        local acceleration = (self.strategicThrottle or 0)
        self.throttle = acceleration
        self:setSteering(radians)
        self:outputThrotttle(acceleration)
    else -- user controls outputs
        local angle = -steeringToDegrees(self.userSteer)/2-- In Degrees 
        local radians = angleToRadians(angle) -- Can save performance by reducing # of conversions if necessary
        self.steering = angle -- Has steering in degrees (necessary to calculate oversteer n stuff)
        local acceleration = 0
        if self.userSeated then -- possibly stop car when user gets out of seat
            acceleration = (self.userPower or 0)
        end

        self.throttle = acceleration
        --print('ST=',acceleration,radians)
        self:setSteering(radians)
        self:outputThrotttle(acceleration)
    end
end

-- Car state /situational checking

function Driver.checkWide(self) -- checks if car is running too wide {Not necessary?}
    if not self:valididtyCheck() then return end
    -- Check direction wheels are turning
    -- check perpendicular to outside lateral speed
    -- if speed is > threshold, start tapering throttle
    local offline = self.currentNode.width/3
    local distFromLine = getDistance(self.currentNode.location,self.location)
    if distFromLine  >  offline then
        --print("wide?",distFromLine)
        self.offline = true
    else
        self.offline = false
    end
    --print("wideCheck:",distFromLine,offline)

end

function Driver.checkTilt(self) -- checks if car is tilted improperly
    local offset = 0 
	local upDir = self.shape:getUp()
	local frontDir = self.shape:getAt()
	if getSign(frontDir.x) == -1 then 
		offset = getSign(upDir.x)
	else
		offset = getSign(upDir.y)
	end
	if math.abs(upDir.y) > 0.6 or math.abs(upDir.x) > 0.6  or upDir.z > -0.8 then  
		self.tilted = true
	end

	local onNose = -0.5
	--print(racer.shape.worldRotation.z)
    local upaxis = sm.vec3.closestAxis(self.shape:getUp())
    --print(self.id,upaxis.z,self.shape.worldRotation.y,upaxis.z)
	if math.abs(self.shape.worldRotation.y) > 0.45  or upaxis.z ~= 1 then 
		--print(self.id,"Tilted",offset)
		self.tilted = true
    else
	    self.tilted = false
    end
end

function Driver.valididtyCheck(self) -- Checks if there are any nils that exist and returns false
    if self.validFail then 
        if self.currentNode == nil then return false end
        if self.goalDirectionOffset == nil then return false end
        if self.engine == nil then return false end
        if self.engine.engineStats == nil then return false end
        if self.goalNode == nil then return false end-- print?
        if self.carDimensions == nil then return false end
        if self.trackPosition == nil then return false end
    else
        if self.currentNode == nil then print("Current Node Validation Failed") self.validFail = true return false end
        if self.goalDirectionOffset == nil then print("Goal Direction Offset Failed") self.validFail = true return false end
        if self.engine == nil then  print("Engine Discovery Failed")  self.validFail = true return false end
        if self.engine.engineStats == nil then  print("Engine Stat Finding Failed")  self.validFail = true return false end
        if self.goalNode == nil then  print("Goal Node finding Failed") self.validFail = true return false end
        if self.carDimensions == nil then print("Car Dimensions are not loaded") self.validFail = true return false end
        if self.trackPosition == nil then print("Track position not set") self.validFail = true return false end
    end
    self.validFail = false
    return true
end

function Driver.checkOversteer(self) -- check if car is sliding based off of rotation speed alone,
    if self.steering == 0 or self.speed < 10 then -- not overSteering but could still be sliding
        self.oversteer = false
        return
    end
   
    local overSteerThreshold = (self.steering/self.speed)
    local overSteerMeasure = (self.steering * self.angularSpeed) /self.speed
    if overSteerMeasure - overSteerThreshold * getSign(self.steering) < self.overSteerTolerance  then
        self.oversteer = true
        --print("O",self.id, overSteerMeasure - overSteerThreshold * getSign(self.steering), self.overSteerTolerance,self.oversteer)
    else
        self.oversteer = false
    end
end

function Driver.checkUndersteer(self) -- check if car is sliding based off of rotation speed alone,
    if self.steering == 0 or self.speed <= 10 then
        self.understeer = false
        return
    end
    --print(self.steering,self.speed)
    local nominalMomentum = math.abs(self.steering)/(self.speed +.01) -- nonzero
    local understeerthresh = self.angularSpeed - nominalMomentum
    --print(string.format("understeerDif %.3f %.3f %.3f",nominalMomentum,self.angularSpeed,self.angularSpeed - nominalMomentum))
    if understeerthresh < self.underSteerTolerance then -- was just based on nominal momentum > 1
        self.understeer = true
        --print("U",self.id,understeerthresh,self.underSteerTolerance)

    else
        self.understeer = false
    end
end

function Driver.checkStuck(self) -- checks if car velocity is not matching car rpm
    if self.goalNode == nil then return end-- print?
    if self.engine == nil then return end
    local offset = posAngleDif3(self.location,self.shape.at,self.goalNode.location)
    --print(offset,self.goalDirectionOffset)
    --print("hah",self.engine.curRPM)
    --print(self.speed,toVelocity(self.engine.curRPM),self.curGear, offset) -- Get distance away from node? track Dif?
    if math.abs(offset) >= 30 or math.abs(self.goalDirectionOffset) > 8.5 then -- TODO:Have cooldown before checking after a car starts racing
        --print("Stuck?",offset,self.goalDirectionOffset,self.speed)
        if self.speed <= 3 then
            --print("offset stuck",offset,self.speed,self.goalDirectionOffset)
            self.stuck = true
            return
        end
        
    end
    --print(self.stuck,self.speed,toVelocity(self.engine.curRPM))
    if self.speed <= toVelocity(self.engine.curRPM) -1 then
        if self.speed <= 2  then
            --print("slow stuck",offset,self.engine.curRPM)
            self.stuck = true
            return
        end
    end
    if self.rejoining == false and self.stuck and self.offTrack == 0 and self.speed > 2 then -- check this
        --print("Toggle stuck",self.offTrack,self.stuckTimeout)
        self.stuck = false
        self.stuckTimeout = 0
    end
    --print(self.stuck,self.stuckTimeout)
end

function Driver.checkOffTrack(self) -- check if car is offtrack based on trackPosition
    if self.currentNode == nil or self.trackPosition == nil then self.offTrack = 0 return end
    if self.currentNode.width == nil then print("setting default width",self.currentNode) self.currentNode.width = 20 end -- Default width?
    local limit = self.currentNode.width/2
    local margin = 4 -- could be dynamic
    local status = math.abs(self.trackPosition) - limit
    if status > margin then
        self.offTrack = status * getSign(self.trackPosition)
        --print(self.id,"off track")
    else
        if self.offTrack ~= 0 then
            --print(self.tagText,"Back on track")
            self.offTrack = 0
        end
    end
    if self.offTrack < -5 then -- adjut limits
        self.offTrack = -5
    elseif self.offTrack > 5 then
        self.offTrack = 5
    end
end

function Driver.checkLocationOnTrack(self,currentNode,location) -- checks if location is on track or not based on width of currentNode(needs update eventually)
    if currentNode.width == nil then return true end -- or set currentNode.width = 20
    local vhDist = getLocationVHDist(currentNode,location)
    local nodePos = vhDist.horizontal
    local limit = currentNode.width/2
    local margin = 1 -- maybe smaller?
    local status = math.abs(nodePos) - limit
    if status > margin then
        --print("Node off track",status)
        --print(string.format("GoalNode Location %.2f %.2f %.2f",nodePos,limit,status))
        --print("------------------------\n")
        return false
    else
        return true
    end
end

function Driver.getCurrentSide(self) -- Gets the lane/trackPos of whichever side car is already on, based on node width
    if self.currentNode == nil then return 0 end -- failsafe
    if not self:valididtyCheck() then return 0 end
    local bias = 0
    if self.trackPosition < 0 then -- if car on left side of track
        bias = -self.currentNode.width/3
    else
        bias = self.currentNode.width/3
    end
    return bias
end

-- Strategic Layer
--Steering
function Driver.updateNearestNode(self) -- Finds nearest node to car and sets it as so
    --print(#self.nodeChain)

    if self.currentNode == nil then -- EItehr first load or node lost
        --print(self.id,"finding nearest")
        local nearestNode = nil
        if self.nodeFindTimeout < 10 and self.speed <= 2 and not self.onLift and not self.nudging then -- if at least mmoving
            nearestNode = getNearestNode(self.nodeMap,self.shape.worldPosition)
        elseif self.speed > 2 and self.stuckTimeout < 7  and not self.onLift and not self.nudging then -- dont search while nudging
            nearestNode = getNearestNode(self.nodeMap,self.shape.worldPosition)
        end

        --print("nilCurrent",self.nodeFindTimeout,nearestNode == nil)
        if nearestNode == nil then -- IS actually lost
            --print("Heh?")
            if not self.onLift then
                self.nodeFindTimeout = self.nodeFindTimeout + 1
                --print("NFT",self.nodeFindTimeout)
                if self.nodeFindTimeout > 10 then
                    self.strategicThrottle = -1
                    self.lost = true
                    return
                end
            end
            return
        else
            if self.lost and nearestNode ~= nil then
                print(self.tagText, "Is no longer lost")
                self.lost = false
                self.nodeFindTimeout = 0
                self:setCurrentNode(nearestNode)
                self.resetNode = nearestNode
            elseif nearestNode ~= nil then
                --print("Setting new loca")
                self.nodeFindTimeout = 0
                self:setCurrentNode(nearestNode)
                self.resetNode = nearestNode
                
            end
        end
        
    end
    --local loc = self.nodeChain[1].mid
    --loc.z = 10
    if self.stuck then
        --print('stuck',self.stuckTimeout)
        if self.stuckTimeout >= 10 and not self.onLift and self.speed < 4 then
            --print(self.tagText,"REset pos stuck",self.stuckTimeout)
            self.lost = true
            return
        end
        if self.stuckTimeout > 1 and self.stuckTimeout < 5 and not self.onLift and not self.nudging then
            --print("stuck timeout")
            nearestNode = getNearestNode(self.nodeMap,self.shape.worldPosition)
            if nearestNode == nil then
                print("nilnewrest nnew node")
                self.nodeFindTimeout = self.nodeFindTimeout + 1
            else
                self:setCurrentNode(nearestNode)
            end

        elseif self.stuckTimeout >= 5 and not self.shape:getBody():isStatic() and self.currentNode ~= nil then
            --print("nudge car",getDistance(self.location,self.currentNode.mid))
            self.strategicThrottle = 0
            local nudgeDir = sm.vec3.new(0,0,0)
            if math.abs(self.shape:getWorldPosition().z - self.currentNode.mid.z) <= 3  and not self.nudging then -- bring up then send over
                nudgeDir.z = self.mass/1.9
                --print("pickup",getDistance(self.location,self.currentNode.mid))
                self.nudging = true
            elseif getDistance(self.location,self.currentNode.mid) > 20  then
                --print("moving",getDistance(self.location,self.currentNode.mid))

                nudgeDir = sm.vec3.normalize((self.currentNode.mid-self.location)) * 1200 --(self.currentNode.mid-self.location) * 50
                if math.abs(self.shape:getWorldPosition().z - self.currentNode.mid.z) >= 5 then -- if too high
                    nudgeDir.z = -self.mass/2.4
                elseif math.abs(self.shape:getWorldPosition().z - self.currentNode.mid.z) <= 4 then -- too low
                    nudgeDir.z = self.mass/2.2
                end
            else
                --print("finishing up",self.stuck,self.stuckTimeout)
                if not self.stuck then
                    self.stuckTimeout = 0
                else
                    if not self.nudging then
                        self.stuckTimeout = self.stuckTimeout + 0.1
                    end
                end
                self.strategicThrottle = 0
            end
            --self.nudging = true ??
            sm.physics.applyImpulse( self.shape.body, nudgeDir,true)
        end
     --print("Getting next node in distance",distance,self.currentNode.location)
    else
        if self.nudging then
            print(self.tagText,"stoped nudge")
            self.nudging = false
        end
    end
    --print("before next items",self.location.z)
    local lastNode = getNextItem(self.nodeChain,self.currentNode.id,-1)
    local nextNode = getNextItem(self.nodeChain,self.currentNode.id,1)
    local curNodeDist = getDistance(self.currentNode.location,self.location)
    local lastNodeDist = getDistance(lastNode.location,self.location)
    local nextNodeDist = getDistance(nextNode.location,self.location)
    
    if lastNode ~= nil then 
        self.resetNode = lastNode
    end

    local distanceThreshold = 40 

    if curNodeDist > distanceThreshold and lastNodeDist > distanceThreshold and nextNodeDist > distanceThreshold then
        --print(self.id," car jumped nodes, searching",self.nodeFindTimeout)
        local closestNode = self.currentNode
        if self.nodeFindTimeout < 8 and self.speed <= 1 and not self.onLift and not self.nudging  then -- if at least mmoving
            closestNode = getNearestNode(self.nodeMap,self.shape.worldPosition)
            self.nodeFindTimeout = self.nodeFindTimeout + 1
            --print("nonilstopped" ,self.nodeFindTimeout,self.speed, closestNode == nil)
        elseif self.speed > 2 and not self.nudging then
            closestNode = getNearestNode(self.nodeMap,self.shape.worldPosition)
            self.nodeFindTimeout = self.nodeFindTimeout + 0.5
            --print("moving " ,self.nodeFindTimeout,self.speed, closestNode == nil)
        end

        if closestNode == nil and not self.onLift then 
            print("Node finding error",self.nodeFindTimeout) 
            self.nodeFindTimeout = self.nodeFindTimeout + 1
            if self.nodeFindTimeout > 10 then
                print(self.tagText,"am lost",closestNode == nil,lastNode == nil,nextNode == nil)
                if lastNode ~= nil then 
                    self.resetNode = lastNode
                end
                self.lost = true
                self.strategicThrottle = -1
            end
            return 
        else
            if self.lost then
               self.lost = false
               self.nodeFindTimeout = 0
               self.strategicThrottle = 1
            else
                --print("found node")
                self.nodeFindTimeout = 0
                self.strategicThrottle = 1
            end
        end

        if closestNode == nil then
            self.lost = true -- Do something with width of track too
            print(self.id,"Racer Stuck")
            return
        else
            if self.lost then
                self.lost = false
            end
        end
        local closestNodeDist = getDistance(closestNode.location,self.location)
        --print("nodedist",closestNodeDist)
        if closestNode.id ~= nextNode.id then -- something strange
            if math.abs(closestNode.id - nextNode.id) > 30 then -- way too far of a jump
                --print("car jump",curNodeDist,nextNodeDist,closestNodeDist)
                self:setCurrentNode(closestNode)
            else
                self:setCurrentNode(nextNode)
            end
        end
        
    elseif nextNodeDist < curNodeDist then
        --print("Moving on to nextNode")
        self:setCurrentNode(nextNode) 
        if self.racing and self.speedControl ~= 0 and self.raceFinished == false then
            --print("speed back")
            self.speedControl = 0
        end
    elseif lastNodeDist < curNodeDist then
        --print("Movingbackwards?",self.currentNode.id,lastNode.id)
        self.setCurrentNode(lastNode)
        if self.racing then
            self.speedControl = 10
        end
    end
end

function Driver.updateGoalNode(self) -- Updates self.goalNode based on speed heuristic (lookahead factor) -- MAy be checking enginesspeed and not current speed on restarts
    if self.lost then return end
    if self.currentNode == nil then return end
    local lookAheadConst = 5 -- play around until perfect -- SHould be dynamic depending on downforce?
    local lookAheadHeur = 0.5 -- same? Dynamic on downforce, more downforce == less const/heuristic?
    if self.rotationCorrect or self.offTrack ~= 0 then 
        lookAheadConst = 8
        lookAheadHeur = 1
    end
    
    local lookaheadDist = lookAheadConst + self.speed*lookAheadHeur
    local goalNode = self:getNodeInDistance(lookaheadDist)
    --print(self.tagText,goalNode.id,lookaheadDist,self.speed)
    self.goalNode = goalNode
end

function Driver.setCurrentNode(self,node)
    -- TODO: If stuck , run raycast between self and curnode, search until no wall in the way
    if node == nil then 
        --print("node missed")
        return
    end
    if self.currentNode == nil or self.currentNode.id ~= node.id then
        local nodeAdd = 0
        if self.currentNode == nil then
            nodeAdd = node.id - 0
        else
            nodeAdd = node.id - self.currentNode.id
        end
        if node.id == 1 then -- if start finish (grab node dif between curNode and lastnode, else 1)
            nodeAdd = 1
            --print("1 nodeAdd")
            if self.currentLap == 1 then -- if  on first lap of race, reset total nodes ? not needed  i dont think
                --self.totalNodes = 0
                --print("reseting current nodes")
            end
        end
        --print(nodeAdd)
        if nodeAdd < 0 then 
            --print (self.id,"Node Moving backwards?",nodeAdd)
        end
        self.totalNodes = self.totalNodes + nodeAdd
        self.currentNode = node
        
        if not self.raceControlError and self.racePosition == 1 then -- I  know this wont work well but whatever
            --print(self.tagText,"adding",self.totalNodes)
            getRaceControl():sv_insertSplitNode(self.totalNodes,self.currentNode)
            self.raceSplit = 0
        elseif not self.raceControlError then -- 
            local split = getRaceControl():sv_getNodeSplit(self.totalNodes)
            self.raceSplit = (split or self.raceSplit)
            if self.racePosition == #ALL_DRIVERS then
                --print(self.tagText,"las place removing node",self.totalNodes)
                getRaceControl():sv_removeSplitNode(self.totalNodes) -- offset by one to prevent backwards confusion
            end
        end
        -- crossCheck curSpeed and node Vmax
        self.currentSegment = node.segID
        --print("Set new node",node.id)
        --print(self.totalNodes,#self.nodeChain)
    end
end

function Driver.getNodeInDistance(self,distance) -- Searches for node in distance of car (following path) that is [distance] away from car (forward or backwards)
    if self.currentNode == nil then return end
    local checkIndex = 1 * getSign(distance)
    local nodeDist = getDistance(self.currentNode.location,getNextItem(self.nodeChain,self.currentNode.id,checkIndex).location)
    --print()
    local nodeDitsTimeout = 0
    local timeoutLimit = 300
    while nodeDist < math.abs(distance) do
        checkIndex = checkIndex + getSign(distance)
        nodeDist = getDistance(self.currentNode.location,getNextItem(self.nodeChain,self.currentNode.id,checkIndex).location)
        nodeDitsTimeout = nodeDitsTimeout + 1
        if nodeDitsTimeout > timeoutLimit then
            print("Get node in distance timeout")
            break
        end
    end
    local distNode = getNextItem(self.nodeChain,self.currentNode.id,checkIndex) -- Could possibly just update it in place (unnecessary GetNextItem)
    if self.stuck then 
        --print("found node right at",distNode,nodeDist,distance)
    end
    return distNode
end

function Driver.checkForClearTrack(self,distance) -- Checks for any cars with in {distance} on node chain
    if self.currentNode == nil then
        return false
    end
    local clearFlag = true
    local clearThreshold = distance -- make dynamic?
    local minNode = self:getNodeInDistance(clearThreshold)
    --print("MinNode",minNode.id)
    for k=1, #ALL_DRIVERS do local v=ALL_DRIVERS[k]
        if v.id ~= self.id then 
            --print("scanning",v.id,v.stuck,v.rejoining,v.currentNode.id)
            if not (v.stuck or v.rejoining) then -- If its not stuck
                if v.currentNode ~= nil and v.speed > 10 then 
                    local node = v.currentNode.id
                    ---print("checking clear ",minNode.id,node,self.currentNode.id)
                    if (node > minNode.id and node < self.currentNode.id)  then
                        clearFlag = false
                    end
                end
            end
        end
    end
    return clearFlag
end


function Driver.smoothTurns(self) -- if no cars dangerously close, make turns smooth (go wide, end wide)
    -- Allow faster Vmax when further on outside of corner

end

function Driver.updateStrategicSteering(self,pathType) -- updates broad steering goals based on path parameter [race,mid,pit]
    local SteerAngle
    if self.goalNode == nil then return end
    
    local goalNodePos = self.goalNode.location -- TODO: Replace with [racetype]
    local goalOffset = (self.goalOffset or sm.vec3.new(0,0,0))
    local goalPerp = self.goalNode.perp
    if self.caution then pathType = "mid" end
    --print(pathType)

    if pathType ~= "race" then -- TODO? should be 'mid'
        --print("pulled")
        goalNodePos = self.goalNode[pathType] --+ goalOffset
    end
    --print("goaloffset",self.goalOffset,goalOffset)
    goalNodePos = self.goalNode[pathType] + goalOffset-- place goalnode offset here...
    -- check if goalNode pos is offTrack
    local onTrack = self:checkLocationOnTrack(self.goalNode,goalNodePos)
    if not onTrack then
        if self.passing.isPassing then
            --print("offtrackStuff?")
            --self:cancelPass()
            self.strategicThrottle = self.strategicThrottle - 0.05
        end
        goalNodePos = self.goalNode[pathType] 
        if self.strategicThrottle > -1 then -- COrrect this foo by using offset too?
            self.strategicThrottle = self.strategicThrottle - 0.05
            --print("heading offtrack correction",self.strategicThrottle)
        end
    end
   
    local biasMult = 2
   --- FCY steering logic
    if self.caution == true then
        self.speedControl = 12
        self.trackPosBias = 10
        self.followStrength = 95 -- 1 is strong, 10 is weak
        biasMult = 1.1
        
        if #ALL_DRIVERS > 1 then
            if self.racePosition > 1 then -- all cars that arent in first
                local frontCar = getDriverByPos(self.racePosition - 1) -- finds car in front 
            end
        end




        -- does logic here
    end

    local biasDif = 0
    local followStren = self.followStrength
    local directionOffset = self.goalDirectionOffset

    if self.trackPosBias ~= nil and self.trackPosBias ~= 0 then
        biasDif = (self.trackPosBias -self.trackPosition)
        --print(self.trackPosBias,self.trackPosition,biasDif)
        biasDif = biasDif* biasMult  
    end
    if biasDif ~= 0 and math.abs(self.offTrack) == 0 then -- makes a slower recovery?
        --followStren = 5
        directionOffset = directionOffset * 1.5
    end
    if self.speed < 2 then 
        directionOffset = 0
    end
    if math.abs(self.offTrack) > 1 then
        followStren = followStren * 0.2
    end
    if self.curGear <=0  then
        directionOffset = 0
    end
    SteerAngle = (posAngleDif3(self.location,self.shape.at,goalNodePos)/followStren) + biasDif + directionOffset
    print("ag",self.trackPosBias,self.trackPosition,biasDif,SteerAngle)
    self.strategicSteering = degreesToSteering(SteerAngle) -- */ speed?
end

function Driver.getGoalDirAdjustment(self) -- Allows racer to stay relatively straight
	if self.speed < 0.5 or self.goalDirection == nil then return 0 end
    local velocity = self.velocity:normalize()
	local angleMultiplier = 10
	--velocity = sm.vec3.normalize(self.velocity) -- Normalized to prevent oversteer -- or use self.at?
	local goalVector = self.goalDirection -- This is a vector, (rename to goalVector?)
	local turnAngle = 0 
	local directionalOffset = sm.vec3.dot(goalVector,velocity)
	local directionalCross = sm.vec3.cross(goalVector,velocity)
	turnAngle = (directionalCross.z) * angleMultiplier -- NOTE: will return wrong when moving oposite of goalDir
	return turnAngle
end

function Driver.calculateGoalDirOffset(self) -- calculates the offset in which the driver is not facing the curNode's outDir
    if self.goalDirection == nil or self.velocity:length() <= 0.2 then return 0 end
    local velocity = self.velocity:normalize()
	local angleMultiplier = 8
	--velocity = sm.vec3.normalize(self.velocity) -- Normalized to prevent oversteer -- or use self.at?
	local goalVector = self.goalDirection -- This is a vector, (rename to goalVector?)
	local turnAngle = 0 
	local directionalOffset = sm.vec3.dot(goalVector,velocity)
	local directionalCross = sm.vec3.cross(goalVector,velocity)
    turnAngle = (directionalCross.z) * angleMultiplier -- NOTE: will return wrong when moving oposite of goalDir
    --print("Offset=",turnAngle)
    return turnAngle
end

-- Throttle
-- segment work
function Driver.getSegmentEnd(self,segID)
    for i=1, #self.nodeChain do local node = self.nodeChain[i]
        if node ~= nil then
            local nextNode =  getNextItem(self.nodeChain,i,1)
            if nextNode.segID == getNextIndex(self.totalSegments,segID,1) then
                --print("found end node")
                return nextNode
            end
        end
    end 
end

function Driver.getSegmentBegin(self,segID) -- parameratize by passing in nodeChain
    for i=1, #self.nodeChain do local node = self.nodeChain[i]
        if node ~= nil then
            if node.segID == segID then
                --print("found begin node")
                return node
            end
        end
    end 
    print("segBegin found no node...",segID,self.totalSegments)
end

function Driver.getSegmentLength(self,segID) --Returns a list of nodes that are in a segment, (could be out of order) (altered binary search??)
    local node = self:getSegmentBegin(segID)
    local foundSegment = false
    local finding = false
    local count = 1
    local index = 1
    local segTimeout = 0
    local timeoutLimit = 100
    while foundSegment == false do
        if segTimeout >= timeoutLimit then
            --print("getSeglength timoeut")
            break
        end
        segTimeout = segTimeout + 1
        if node == nil then
            print("error getting segLen",index,segID,node)
            return count 
        end
        if node.segID == segID then
            count = count + 1
            --print("counting",count,node.segID)
            if not finding then
                --print("beginCount",segID,node.segID)
                finding = true
            end
        else 
            if finding then
                --print("finished finding segment",count)
                finding = false
                foundSegment = true
            end
        end
        node = getNextItem(self.nodeChain,node.id,1)
    end
   
    return count
end


function Driver.updateBrakeDistance(self) -- Pull in braking info from ALL_DRIVERS table (posted by engine) then find the distance it you can do
    local brakePower = self.engine.engineStats.MAX_BRAKE
    --print("brakepower",brakePower)
    local distToZero = getBrakingDistance(self.speed,brakePower,0)
    --print(string.format("distToZero: %.3f ",distToZero))
    self.brakeDistance = distToZero
end
-- function getPotential speed at Distance(speed,acceleration,distance)

-- METHOD1: 
--      if self.vMax Searching: looking ahead at (BrakeDistance?) until we find a segment with a vMax < current Speed (and potential speed at that distance)
        -- Create attribute: self.vMaxGoal (which will be a node from nodeChain)
        --  Once segment is found, self.vmaxSearching = false, self.vmaxGoal = node 
        -- function self:maintainVmax() will also use characteristics for variablitity/skill
        --     Get distance away from vMaxNode and brakeDistance/potential acceleration
        --      once car is brakingdistance-distance (+-skill/situation) away from vmaxNode,
        --         set Throttle to (+- skill/sit) engineMax Brake
        -- Once Car has passed over vmaxNode (or near), self.searching = true
        -- I can forsee a lot of problems with this method

-- MEthod2: The following code:
function Driver.getAccel(self) -- GEts acceleration flag 
    if self.goalNode == nil then
        return 0
    end
    if self.engine== nil then return 0 end
    if self.engine.engineStats == nil then return 0 end

    local segID = self.goalNode.segID
    local segLen = self:getSegmentLength(segID)
    local segEnd = self:getSegmentEnd(segID)
    local vMax = calculateMaximumVelocity(self.goalNode,segEnd,segLen)
    vMax = self:refineBrakeSpeed(vMax,segEnd)
    --print("vmax:",vMax)
    if self.speedControl > 0 then
        vMax = self.speedControl
        --print("SC",self.speed,vMax)
        if self.speed > vMax then
            return -0.1
        else 
            return 1
        end
    end
    

    if vMax > self.speed + self.engine.engineStats.MAX_ACCEL then 
        return 1
    else
       return 1- math.abs(vMax/self.speed)
    end
end

function Driver.refineBrakeSpeed(self,vMax,segEndNode) -- refines vMax based on multiple factors
    --print("original",vMax)
    if not self:valididtyCheck() then return vMax end

    local tWidth = (segEndNode.width or 10)
    if segEndNode == nil then return vMax end
    vMax = vMax + tWidth/4.6
    vMax = vMax - (math.abs(self.trackPosition)/1.6)  -- Adjust max velocity based on closeness to center of track
    --print("twidthVmax",math.abs(self.trackPosition)/1.5,vMax)
    if self.passing.isPassing then vMax = vMax +0.4 end -- go a bit slower while passing
    if self.carAlongSide.left ~= 0 or self.carAlongSide.right ~= 0 then -- slow down when there is car alongside
        vMax = vMax - 2
    else
        
    end
    if tWidth <= 26 then -- if track is thinner, slow down more
        --print("thintrack",tWidth)
        vMax = vMax - vMax/5
    end

    if self.offline then
        vMax = vMax - 1
    end

    --print(tWidth)
    local goalAngle =  angleDiff(self.shape.at,segEndNode.outVector)
    --print(goalAngle)
    if math.abs(goalAngle) < 1 then --TODO: make threshold more variable depending on skill
        --print("turn boost",goalAngle)
        vMax = vMax + 5 -- ?variable depending on skill
    end

    --print("returning",vMax,math.abs(self.goalDirectionOffset))
    return vMax
end
   
function Driver.getBraking(self) -- TODO: Determine if there is a car ahead of self on turns, slow down
   
    if self.engine == nil then return 1 end -- dont move
    if self.engine.engineStats == nil then return 0 end

    if not self:valididtyCheck() then return 1 end

    local segID = self.currentSegment
    --print(segID,self.currentNode)
    if self.currentNode == nil or self.currentSegment == nil then
        return 0.2 -- slightly slow down
    end
    local lookAheadConst = 6 -- play around until perfect, possibly make dynamic for downforce/other factors?
    local lookAheadHeur = 2.1 -- same
    local maxLookaheadDist = lookAheadConst + self.speed*lookAheadHeur

    local segBegin = self:getSegmentBegin(segID)
    local segEnd = self:getSegmentEnd(segID)

    if segBegin == nil then
        return 0.2 -- untilSomethinghppens we can figure it out
    end
    if segEnd == nil then
        print("nil end")
        return 1
    end

    if segBegin.id == segEnd.id then
        print("same seg begin and end?") -- not sure here
    end

    local lookaheadDist = getDistance(self.location,segBegin.mid)
    --print("emmediateVmxCherck",segmentEnd.segID)
    local segLen = self:getSegmentLength(segBegin.segID)
    local vMax = calculateMaximumVelocity(segBegin,segEnd,segLen) -- REMOVED handicap speed boost due to issues.
    vMax = self:refineBrakeSpeed(vMax,segEnd)
   
    --print("\nBrakeChecka",vMax)
    local brakeDist = getBrakingDistance(self.speed,self.engine.engineStats.MAX_BRAKE,vMax)
    if self.speed > vMax then
        return 1 -- make easy braking function // based off of distance from node (ajustable by skill/state), not hard braking
    else
        segID = getNextIndex(self.totalSegments,segID,1)
        segBegin = self:getSegmentBegin(segID)
        if segBegin == nil then
            return 0.1 -- untilSomethinghppens we can figure it out
        end
        lookaheadDist = getDistance(self.location,segBegin.mid)
        local timeout = 50
        local timer = 0
        
        --print("look",lookaheadDist,maxLookaheadDist,segID)
        while (lookaheadDist < maxLookaheadDist) do
            if timer >= timeout then
                print("timed out")
                break
            end
            segBegin = self:getSegmentBegin(segID)
            segEnd = self:getSegmentEnd(segID)

            if segID == nil then
                print("segID nil")
            end
            if segBegin == nil then
                print('SEGbEGIN nil',segID)
            end
            if segEnd == nil then
                print("nil end")
            end

            --print("Looking at",segID,segBegin.id,segEnd.id)
            local segLen = self:getSegmentLength(segBegin.segID)
            local maxSpeed = calculateMaximumVelocity(segBegin,segEnd,segLen)
            maxSpeed = self:refineBrakeSpeed(maxSpeed,segEnd)
            

            --print("next",self.speed,maxSpeed,segID)
            if self.speed > maxSpeed then
                brakeDist =  getBrakingDistance(self.speed,self.engine.engineStats.MAX_BRAKE,maxSpeed)
                --local segBegin = self:getSegmentBegin(segID) -- if not nil
                if segBegin == nil then
                    return 0.1 -- untilSomethinghppens we can figure it out
                end
                local distToTurn = getDistance(self.location,segBegin.mid)
                --print(segBegin.id,"dist",brakeDist,distToTurn,self.speed,maxSpeed)
                if brakeDist > distToTurn then
                    --print("brake")
                    return 1 -- Skill based param too
                else
                    -- taper into brake?
                end
            end
            lookaheadDist = getDistance(self.location,segBegin.mid)
            segID = getNextIndex(self.totalSegments,segID,1)
            segBegin = self:getSegmentBegin(segID)
            timer = timer +1
        end
        return 0
    end
    return 0
end

function Driver.updateStrategicThrottle(self)
    if self.stuck then return end
    local braking = self:getBraking() -- self:getCollissionBraking
    local accel = 0
    if braking == 0 then
        accel = self:getAccel()
    else
        accel = 0
    end
    --print(accel,braking)
    self.strategicThrottle = accel - braking
    --print(accel,braking,self.strategicThrottle)
    --local segID = self.currentNode.segID
   -- local vMax = calculateMaximumVelocity(self.currentNode,self.mass)
   -- if self.speed > vMax then 
   --self.strategicThrottle = -1
    --else
    --    self.strategicThrottle = 1
    --end
    --print(vMax)
end
 
-- Gearing
function Driver.updateGearing(self) -- try to calculate the best gear to choose at the time and shift as well
    if self.engine == nil then return 1 end
    if self.engine.engineStats == nil then return 1 end
    local rpm = self.engine.curRPM
    local vrpm = self.engine.VRPM
    local revLimit = self.engine.engineStats.REV_LIMIT
    local nextGear = self.curGear

    if not self.userControl then
        if self.engine == nil or self.stuck then 
            if self.rejoining and self.speed > 9 then -- Update gears while rejoining but not when not stuck?
                --print("hello")
            else
                --print("return nil")
                return 
            end
        end -- cant shift gears with no engine

        if self.speed ~= nil then
            if self.speed < 5 then
                if self.curGear >= 2 then
                    nextGear = 1
                end
            end
        end

        if self.racing then -- If race status is clear then go full speed
            if self.strategicThrottle >= 0.5 then -- If supposed to accelerate full speed/half?
                if self.curGear <= 0 then 
                    nextGear = 1 -- If you are neutral then at least go to first gear
                    -- Possibly have rejoin/race start flag trigger?
                else
                    if revLimit - vrpm < self.upShiftThreshold then 
                        if self.curGear < 5 then -- Gearing limit, make variable?
                            nextGear = self.curGear + 1
                        end
                    end
                    if vrpm == 0 and self.curGear >1 then -- Downshift dude <= 0, negativeRPM?
                        nextGear = self.curGear -1
                    end
                end
            else -- If car is "coasting" or braking , check downshifting
                if vrpm < self.downShiftThreshold then -- How low vrpm should be before shifting down (fuel saving?)
                    if self.curGear > 1 then
                        nextGear = self.curGear - 1 
                    end
                end
            end
        end

        if nextGear ~= self.curGear then 
            self:shiftGear(nextGear)
        end

    else -- user is controling, TODO: Make manual option
        if self.speed ~= nil then
            if self.speed < 6 then
                if self.curGear >= 2 then
                    nextGear = 1
                end
            end
        end

        if self.userPower > 0 then -- If user on gas or coasting
            if self.curGear <= 0 then 
                nextGear = 1 -- If you are neutral then at least go to first gear
            else
                if revLimit - vrpm < self.upShiftThreshold then 
                    if self.curGear < 5 then -- Gearing limit, make variable?
                        nextGear = self.curGear + 1
                    end
                end
                if vrpm == 0 and self.curGear >1 then -- Downshift dude <= 0, negativeRPM?
                    nextGear = self.curGear -1
                end
            end
        else -- If car is braking , check downshifting
            if vrpm < self.downShiftThreshold then -- How low vrpm should be before shifting down (fuel saving?)
                if self.curGear > 1 then
                    nextGear = self.curGear - 1 
                end
            end
            if self.speed < 2 and self.userPower == -1 then -- flip into reverse
                --print("reverse",nextGear,self.curGear)
                nextGear = -1
            end
        end

        if nextGear ~= self.curGear then 
            self:shiftGear(nextGear)
        end
    end

end 

function getCollisionAvoidanceSteer(vhDif)
    local newSteer = 0
    if vhDif['vertical'] < 0 and vhDif['vertical'] > -10 then -- if intersection is behind midpoint of car
        if vhDif['horizontal'] > 0 then -- car is on right
            newSteer = ratioConversion(-6,2,-0.22,0,vhDif['horizontal'])--/(self.followStrength/1.5)   --TODO: figure out if getting passed/attack/defend?
        else -- brake
            --newSteer = ratioConversion(6,-2,0.22,0,vhDif['horizontal'])
        end
    else -- if intersection is in front possibly make it turn less hard?
        if vhDif['horizontal'] > 0 then -- car is on right
            newSteer = ratioConversion(-6,2,-0.12,0,vhDif['horizontal'])--/(self.followStrength/1.5)   --TODO: figure out if getting passed/attack/defend?
        else -- slowdown
            --newSteer = ratioConversion(6,-2,0.12,0,vhDif['horizontal'])
        end
    end
    return newSteer
end


function calculateCollisionMove(pointName,vhDif,opponent) -- move to global?
    local accel = 0
    local steer = 0
    -- if corner is frontleft 
    if pointName == "fl" then
        --print("fl",vhDif)
        if vhDif['vertical'] < 0 and vhDif['vertical'] > -10 then -- if point behind midpoint of car
            if vhDif['horizontal'] > 0 then -- car is on right side of midpoint
                newSteer = ratioConversion(0,5,0.2,0,vhDif['horizontal']) -- should turn sharper the closer to 0
                print("Steer avoidance right",vhDif['horizontal'],newSteer)
                --steer  = getCollisionAvoidanceSteer(vhDif)
            end
        end
        --print("Got steer FL",vhDif,steer)
    elseif pointName == "fr" then
        --print("fr",vhDif)
        if vhDif['vertical'] < 0 and vhDif['vertical'] > -10 then -- if point behind midpoint of car
            if vhDif['horizontal'] < 0 then -- car is on right side of midpoint
                newSteer = ratioConversion(-5,0,0,0.2,vhDif['horizontal']) -- should turn sharper the closer to 0
                print("Steer avoidance left",vhDif['horizontal'],newSteer)
                --steer  = getCollisionAvoidanceSteer(vhDif)
            end
        end

    elseif pointName == "bl" then -- dont need to do much
    elseif pointName == "br" then -- also not important
    end


    return accel,steer
end


function Driver.newUpdateCollisionLayer(self)-- -- New updated collision layer
    if self.carData == nil then return end -- not scanned
    --print(self.carData.carDimensions)
    if self.carData.carDimensions == nil then return end -- not scanned
    if self.engine == nil then return end
    if self.engine.engineStats == nil then return end -- Do validattion instead?

    local colThrottle = self.strategicThrottle
    local colSteer = self.strategicSteering
    local passSteer = 0 -- add on to colSteer
    local oppInRange = {}--self.opponentFlags -- possibly attatch to self so no regeneration necessary?
    local selfWidth = self.leftColDist + self.rightColDist
    local hasDraft = false
    local carsInRange = getDriversInDistance(self,60) -- also accounts for draft may be too 
    
    local timeScaleMultiplier = 0.5 -- ~1 second lookahead (adjustable) (40 iterations per second)
    local collisionPadding = 2 -- additional space  multiplier given to radar/collision > 1 for grow, < 1 for shrink
    local futurePosition = self.location + (self.velocity * timeScaleMultiplier) -- get future location
    self.futureLocation = futurePosition
    --print("future",self.location,self.velocity,futurePosition)
    local selfCollisionBox = generateBounds(futurePosition,self.carDimensions,self.shape:getAt(),self.shape:getRight(),collisionPadding)
    -- make effect for debug
    --print(self.fflEffect)
    self.fflEffect.pos = selfCollisionBox[1].position
    self.ffrEffect.pos = selfCollisionBox[2].position
    self.fblEffect.pos = selfCollisionBox[3].position
    self.fbrEffect.pos = selfCollisionBox[4].position

    local centerLocation = getCarCenter(self) -- returns center of car

    if carsInRange == nil then -- No cars go home
        if self.passing.isPassing then
            self:cancelPass()
        end
        if self.drafting then
            self.drafting = false
        end
        return 
    end
    
    for k=1, #carsInRange do local opponent=carsInRange[k] -- May need to have deep copy of carsInrange or create new class
        if opponent.carDimensions == nil then
            --self:sv_sendAlert("Car ".. self.id .. " Not Scanned; Place on Lift")
            break
        end
        local opDir = opponent.shape:getAt()
        local opFuturePos = opponent.location + (opponent.velocity * timeScaleMultiplier)
        local opCollisionBox = generateBounds(opFuturePos,opponent.carDimensions,opDir,opponent.shape:getRight(),collisionPadding)
        local centerLocation = getCarCenter(self) -- returns center of car
        local collisionPotential = getCollisionPotential(selfCollisionBox,opCollisionBox)
        if collisionPotential == false then 
            break -- no collision potential
        else
            local intersectPoint = selfCollisionBox[collisionPotential]
            local intersectVH = getPointRelativeLoc(centerLocation,intersectPoint['position'],opDir)
            --print(self.id,collisionPotential,intersectPoint['name'],intersectVH)
            local accel,steer = calculateCollisionMove(intersectPoint['name'],intersectVH,opponent) -- dont need opponent
            --print("Got",accel,steer, "to avoid car")
        end

    end
    --self.strategicThrottle = colThrottle
    --self.strategicSteering = self.strategicSteering + colSteer + passSteer
end

-- Updating methods (layers and awhat not)
function Driver.updateCollisionLayer(self)
    if self.carData == nil then return end -- not scanned
    --print(self.carData.carDimensions)
    if self.carData.carDimensions == nil then return end -- not scanned
    if self.engine == nil then return end
    if self.engine.engineStats == nil then return end -- Do validattion instead?

    --if self.speed < 5 then return end -- too slow
    local carsInRange = getDriversInDistance(self,70) -- gets list of all cars within certain distanvce
    if carsInRange == nil then -- No cars go home
        if self.passing.isPassing then
            self:cancelPass()
        end
        if self.drafting then
            self.drafting = false
        end
        return 
    end
    --print(self.opponentFlags)
    -- GEnerate Flag structure
    local colThrottle = self.strategicThrottle
    local colSteer = self.strategicSteering
    local passSteer = 0 -- add on to colSteer
    local oppInRange = {}--self.opponentFlags -- possibly attatch to self so no regeneration necessary?
    local selfWidth = self.leftColDist + self.rightColDist
    -- set up local car radar (big values )
    self.carRadar = {
        front = 100,
        rear = -100,
        right = 100,
        left = -100
    }
    
    local alongSideLeft = -100
    local alongSideRight = 100 

    local hasDraft = false

    for k=1, #carsInRange do local opponent=carsInRange[k] -- May need to have deep copy of carsInrange or create new class
        if opponent.carDimensions == nil then
            --self:sv_sendAlert("Car ".. self.id .. " Not Scanned; Place on Lift")
            break
        end
        if opponent.rearColDist == nil or opponent.frontColDist == nil then
            break
        end
        --local distance = getDriverDistance(self,opponent,#self.nodeChain) -- TODO: Remove cuz obsolete?
        local vhDist = getDriverHVDistances(self,opponent)
        local oppWidth
        if opponent.leftColDist == nil or opponent.rightColDist == nil then
            oppWidth = selfWidth
        else 
            oppWidth = (opponent.leftColDist + opponent.rightColDist) or selfWidth -- in case oppwidth is broken
        end
        if vhDist['vertical'] < 100 or vhDist['vertical'] > -25 then -- ??
            if oppInRange[opponent.id] == nil then
                oppInRange[opponent.id] ={data = opponent, inRange = true,  vhDist = {}, flags = {frontWatch = false,frontWarning = false, frontEmergency = false,
                                            alongSide = false, leftWarning = false,rightWarning = false,leftEmergency = false,rightEmergency = false,
                                            pass = false, letPass = false, drafting = false                 
            }}
            else
                oppInRange[opponent.id].flags.inRange = true
            end
        else
            if oppInRange[opponent.id] == nil then
                oppInRange[opponent.id] ={data = opponent, inRange = false, vhDist = {}, flags = {frontWatch = false,frontWarning = false, frontEmergency = false,
                alongSide = false, leftWarning = false,rightWarning = false,leftEmergency = false,rightEmergency = false,
                pass = false, letPass = false, drafting = false,  }}
            else
                oppInRange[opponent.id].inRange = false -- Sets everything to false to reset
                oppInRange[opponent.id].flags = {frontWatch = false,frontWarning = false, frontEmergency = false,
                alongSide = false, leftWarning = false,rightWarning = false,leftEmergency = false,rightEmergency = false,
                pass = false, letPass = false, drafting = false   }
            end
        end
        --obsoleteVHDistances(self,opponent)
        if vhDist == nil then break end -- send error?
        oppInRange[opponent.id].vhDist = vhDist -- send to opp

        local frontCol = nil
        local rearCol = nil
        local leftCol = nil
        local rightCol = nil

        if vhDist['horizontal'] > 0 then -- opponent on right
            rightCol = vhDist['horizontal'] - (self.rightColDist + (opponent.leftColDist or self.leftColDist))
        elseif  vhDist['horizontal'] <= 0 then -- opponent on left
            leftCol = vhDist['horizontal'] + (self.leftColDist + (opponent.rightColDist or self.rightColDist)) -- Failsaif to its own width
            -- if leftCol >= 0 then print("danger on left?")
        end



        if vhDist['vertical'] > 0 then -- if opponent in front 
            frontCol = vhDist['vertical'] - (self.frontColDist + (opponent.rearColDist or self.rearColDist))
        elseif vhDist['vertical'] <=0 then -- if opp behind 
            rearCol = vhDist['vertical'] + (self.rearColDist + (opponent.frontColDist or self.frontColDist))
            --if rearCol >= 0 then print("danger from behind") end
        end


        -- update localRadar
       if frontCol then
            if frontCol < self.carRadar.front then
                self.carRadar.front = frontCol
            end
       else
            self.carRadar.front = 100
       end
       
       if rearCol then
        if rearCol > self.carRadar.rear then
            self.carRadar.rear = rearCol
        end
        else
            self.carRadar.rear = -100
        end

       if leftCol then
        if leftCol > self.carRadar.left then
            self.carRadar.left = leftCol
        end
        else
            self.carRadar.left = -100
            --oppFlags.leftWarning = false
        end

       if rightCol then
        if rightCol < self.carRadar.right then
            self.carRadar.right = rightCol
        end
        else
            self.carRadar.right = 100
            --oppFlags.rightWarning = false
        end
       
        local oppFlags = oppInRange[opponent.id].flags
        if frontCol and frontCol < 70 then -- In draft range? (globals.draftRange)
            if (rightCol and rightCol <0.2) or (leftCol and leftCol > -0.2) then -- If overlapping (a little margin)
                oppFlags.drafting = true
                hasDraft = true
                --print(self.id,opponent.id,"hasDraft",hasDraft,oppFlags.drafting)
            else
                oppFlags.drafting = false
            end
        end
        
        if frontCol and frontCol < 50 and frontCol > 10 then -- somewhat close
            if self.speed - opponent.speed  > 1 then -- moving 1 faster ?
                if (rightCol and rightCol <0) or (leftCol and leftCol > -0) then -- If overlapping
                    oppFlags.frontWatch = true
                else
                    oppFlags.frontWatch = false
                end
            else
                oppFlags.frontWatch = false -- good idea??
            end
        else
            oppFlags.frontWatch = false
        end

        if frontCol and frontCol <= 20 then -- even closer, check for passing
            if self.speed - opponent.speed > 0.4 then -- if approaching 
                if (rightCol and rightCol <0) or (leftCol and leftCol > -0) then -- If overlapping, Makke separate flag?
                    local catchDist = self.speed * vhDist['vertical']/(self.speed-opponent.speed) -- vertical dist *should* be positive and
                    local brakeDist = getBrakingDistance(self.speed*2,self.engine.engineStats.MAX_BRAKE/2,opponent.speed) * 2.5 -- dampening? make variable
                    --print("catchDist",catchDist-brakeDist)
                    if catchDist - brakeDist < 15 and catchDist - brakeDist >0 then -- and greater than 0?
                        oppFlags.frontWarning = true -- check for passing
                    else
                        oppFlags.frontWarning = false
                    end
                else
                    oppFlags.frontWarning = false
                end
            else
                oppFlags.frontWarning = false
            end
        else
            oppFlags.frontWarning = false
        end
        
        if frontCol and frontCol < 2.7 then -- if real close use 0?
            if (rightCol and rightCol <0) or (leftCol and leftCol > 0) then -- If overlapping
                oppFlags.frontEmergency = true
            else
                oppFlags.frontEmergency = false -- good idea??
            end
        else
            oppFlags.frontEmergency = false

        end

        if rearCol and rearCol < -2 then
            --print("car behind",rearCol)
            if oppFlags.pass then
                --print("Pass complete")
                if self.passing.isPassing then
                    --print("stoppass")
                    oppFlags.pass = false
                    self:cancelPass()
                else
                    --print("unmatched pass???")
                end
                oppFlags.pass = false
            end
        end
        --print(frontCol,rearCol,oppFlags.frontEmergency,oppFlags.frontWarning)
-- Set & process flags & pass ( side)
        if (frontCol and frontCol <= 1.8) or (rearCol and rearCol >=0.4) then -- if car really close
            if (leftCol and leftCol <= 0.05) or (rightCol and rightCol >= -0.05) then
                oppFlags.alongSide = true
                if leftCol and leftCol > -selfWidth then
                    --print("car blcokingLeft",leftCol)
                    if leftCol > alongSideLeft then
                        alongSideLeft =  leftCol
                    end 
                end

                if rightCol and rightCol < selfWidth then
                    --print("car blcokingRight",rightCol)
                    if rightCol < alongSideRight then
                        alongSideRight = rightCol
                    end
                end

            else
                oppFlags.alongSide = false
            end

            if (leftCol and leftCol >= -7) then
                oppFlags.leftWarning = true
            else
                oppFlags.leftWarning = false
            end

            if (rightCol and rightCol <= 7) then
                oppFlags.rightWarning = true
            else
                oppFlags.rightWarning = false
            end
    
            if (leftCol and leftCol >=-0.7) then
                oppFlags.leftEmergency = true
             else
                oppFlags.leftEmergency = false
            end

            if (rightCol and rightCol <= 0.7) then
                oppFlags.rightEmergency = true
             else
                oppFlags.rightEmergency = false
             end
       
        else -- no warnings here
            oppFlags.rightWarning = false
            oppFlags.leftWarning = false
            oppFlags.rightEmergency = false
            oppFlags.leftEmergency = false
            oppFlags.alongSide = false -- ?
        end
        --print(self.tagText,"",frontCol,rearCol,leftCol,rightCol)
        if (frontCol or 0) <= -0.6 or (rearCol or 0) >= 0.6  then -- if car abnormally close/overlapping?
            --print(self.tagText,"close vertical",leftCol,rightCol,frontCol,rearCol)
            if (leftCol or 0) >= 0.7 or  (rightCol or 0) <= -0.7 then
                --print(self.tagText,"Collision with Opp",frontCol,rearCol,leftCol,rightCol)
                -- check if speed < 4
                if self.speed < 5 then -- double check disparity between speed and desired speed
                    --print(self.tagText,"Bad collision likely",self.shape.worldPosition.z,self.currentNode.mid.z,self.stuck,self.stuckTimeout)
                    -- check if z index is high
                    if self.shape.worldPosition.z > self.currentNode.mid.z + 2 or (self.stuck and self.stuckTimeout >= 5) then
                        --print(self.tagText,"Horrendus collision detected")
                        if self.carResetsEnabled then
                            print(self.tagText,"resetting colided car")
                            -- add check clearTrack
                            --self.lost = true
                            self:resetPosition(true)
                        end
                    end
                end
            end
        end
   --[[Pass calculations print("could pass?")
                self.passCommit = self:calculateClosestPassPoint(opponent,vhDist)
                local passDirection = self.passCommit
                if passDirection == 0 then
                    self.passCommit = 0
                    local testThrot = 0.9- math.abs(vMax/self.speed) 
                    if testThrot < colThrottle then
                        print("warning eadjust",testThrot)
                        colThrottle = testThrot
                    end
                    --print("EMERGENCY PASS FAILURE")
                else
                    self.goalOffset = self:calculateGoalOffset(oppInRange[opponent.id],passDirection)
                    self.passing.isPassing = true
                    elf.passing.carID = opponent.id
                    print("Start warning p[ass",passDirection) -- potentially set flag for ePass?
                    oppFlags.pass = true]]

                    --[[Emergency pass calculationsself.passCommit = self:calculateClosestPassPoint(opponent,vhDist)
                    local passDirection = self.passCommit
                    if passDirection ~= 0 then -- This is an emergency pass, execute if possible
                        self.goalOffset = self:calculateGoalOffset(oppInRange[opponent.id],passDirection)
                        print("ePass start",passDirection)
                        eThrot = 0.99 - math.abs(vMax/self.speed)
                        self.passing.isPassing = true
                        oppFlags.pass = true
                    else
                        if self.passing.isPassing and self.speed - vMax < 0 then
                            print("epassFail")
                            self:cancelPass()
                            oppFlags.pass = false
                        end
                        print("ebrake1")
                        eThrot = 0.80- math.abs(vMax/self.speed)
                    end]]
        
        -- TODO: ADD YELLOW FLAGS Stopped cars will add global yellow flags with segID and trackPos

        -- Process and execute flags
    

        if oppFlags.frontWatch then
            local vMax =opponent.speed
            local eThrot = colThrottle
            if self.speed - opponent.speed > 9 or opponent.speed < 8 then
                --print("Approaching front fast")
                eThrot = eThrot - 0.95
                --print("emergency brake")
                if self.passing.isPassing or oppFlags.pass then --and vhDist['vertical'] < 7 then -- TODO: determine if this is correct decision, dont cancel pass if opp is far away
                    --print("canceled pass emergency pass")
                    self:cancelPass()
                    oppFlags.pass = false
                end
            end
        end
         

        if oppFlags.frontWarning and not self.passing.isPassing then
            if self.speed - opponent.speed > 0.2 and frontCol < 20 then
                local vMax =opponent.speed - 0.3
                --print("could pass?")
            end
        end
        if oppFlags.frontEmergency then
            --print("ftooo close",frontCol,oppFlags.alongSide,self.passing.isPassing,oppFlags.pass)
        end
        if oppFlags.frontEmergency and not oppFlags.alongSide then--and not passing? oppFlags.pass
            local vMax =opponent.speed-4
            local eThrot = colThrottle
            if frontCol > 0 and frontCol <= 8 then
                if self.speed - vMax > 0.2 and not oppFlags.pass then -- make smooth ratio instead? -- maybe have closer range? and not self.passing.isPassing?
                    --print("AlertClose ") -- TODO: FIX emergency comes up while already passing, make sure car isnt being passed (oppFlags.pass?)
                    eThrot = 0.90- math.abs(vMax/self.speed) 
                else
                    if oppFlags.pass then -- maybe add pass ID(s) to self.passing.isPassing flag to cancel from outside of function too
                        if self.passing.isPassing and self.speed - vMax < 0 then
                            self:cancelPass()
                            print("epassFail2")
                            oppFlags.pass = false
                        end
                    else
                        if self.passing.isPassing then
                            --print("oppPass but not self.pass")
                            oppFlags.pass = false
                        end
                        eThrot = 0.80- math.abs(vMax/self.speed) 
                        --print("ebrake2",oppFlags.pass,self.passing.isPassing)
                    end
                end
            else -- way too close
                eThrot = 0.65- math.abs(vMax/self.speed)
                --print("ebrake3")
                if oppFlags.pass then
                    oppFlags.pass = false
                end
                if self.passing.isPassing then
                    self:cancelPass()
                    oppFlags.pass = false
                end
                --print(self.id,"ebrake",self.curGear,self.engine.VRPM,eThrot)
                --colSteer = colSteer + 0.01 -- or whichever inside is
            end

            if eThrot < colThrottle then
                colThrottle = eThrot
            end
            
        end

        if oppFlags.leftWarning and leftCol ~= nil then -- multiply by opposite if car is behind
            --colSteer = colSteer + 1/(leftCol*10) negative-- Divide by speed?
            colSteer = colSteer + ratioConversion(-6,2,-0.13,0,leftCol)--/(self.followStrength/1.5)   --TODO: figure out if getting passed/attack/defend?
            if self.carAlongSide.right ~= 0 then
                colSteer = colSteer/3
            end
            --print(self.tagText,"leftColSteer",colSteer,leftCol)
        end
        if oppFlags.rightWarning and rightCol ~= nil then
            --colSteer = colSteer +  1/(rightCol*10) positive
            colSteer = colSteer + ratioConversion(6,-2,0.13,0,rightCol)--/(self.followStrength/1.5)  -- Convert x to a ratio from a,b to  c,d
            if self.carAlongSide.left ~= 0 then
                colSteer = colSteer/3
            end
            --print(self.tagText,"righColSteer",colSteer,rightCol)
        end

        if oppFlags.leftEmergency then
            --colSteer = colSteer + 1/(leftCol*20)-- adjust to 
        end
        if oppFlags.rightEmergency then
            --colSteer = colSteer +  1/(rightCol*20) -- figure out adjust
        end
        if self.strategicSteering ~= colSteer then

        end
        if self.passing.isPassing then
            colSteer = colSteer/1.5 
        else
            colSteer = colSteer/1.2
        end

        
        -- Real Passing ALGo
        local catchDist = self.speed * vhDist['vertical']/(self.speed-opponent.speed) -- vertical dist *should* be positive and
        local brakeDist = getBrakingDistance(self.speed*2,self.engine.engineStats.MAX_BRAKE/2,opponent.speed) -- dampening? make variable
        
        local vMax =opponent.speed
        if vhDist['vertical'] > -1 then
            --print(catchDist,brakeDist,catchDist-brakeDist)
        end
        if vhDist['vertical'] - (self.frontColDist + opponent.rearColDist) >=0  and vhDist['vertical'] < 30 then -- if opponent is somewhat close
            --print(self.tagText,"check pass?",self.speed-opponent.speed)
            if (self.speed-opponent.speed) > 0.5 then --and vhDist['vertical'] - (self.frontColDist + opponent.rearColDist) < 14 then -- if catching ish
                --print(self.id,"approaching",self.speed-opponent.speed,oppFlags.pass,self.passing.isPassing)
                if not oppFlags.pass and not self.passing.isPassing then 
                    --print(self.id,vhDist['vertical'] - (self.frontColDist + opponent.rearColDist),self.carRadar.front)
                    if vhDist['vertical'] - (self.frontColDist + opponent.rearColDist) <= self.carRadar.front then -- if this is the closest, maybe not
                        --print(self.tagText,"Can potentially pass",catchDist,brakeDist)
                        local passDirection = self:checkPassingSpace(opponent)
                        if passDirection ~= 0 then 
                            self.passCommit = passDirection
                            --print(self.tagText,"commiting pass",passDirection,vhDist['vertical'])
                            self.goalOffset = self:calculateGoalOffset(oppInRange[opponent.id],passDirection)
                            self.passing.isPassing = true
                            self.passing.carID = opponent.id
                            oppFlags.pass = true -- Maybe make passing function?
                        else 
                            --print(self.id,"subprime pass point",vhDist['vertical'],passDirection)
                            self.passCommit = 0
                            oppFlags.pass = false
                            if oppFlags.frontWarning then
                                local testThrot = 0.9- math.abs(vMax/self.speed) 
                                if testThrot < colThrottle then
                                    --print("warning eadjust",testThrot)
                                    colThrottle = testThrot
                                end
                            end
                            --print("EMERGENCY PASS FAILURE")
                        end
                    end -- else: the car is not the closest
                else -- If already passing (midpass)
                    local space = self:confirmPassingSpace(opponent,self.passCommit)
                    --print(self.id,"midPass",space,vhDist.vertical)
                    if vhDist.vertical > 15 or vhDist.vertical < -1 then
                        if oppFlags.pass then
                            --print("dont pass this?")
                            oppFlags.pass = false
                            self:cancelPass()
                        else
                            if self.passing.isPassing then
                                --print("mismatch pass cancel")
                                self:cancelPass()
                            end
                        end
                    end
                    if space ~= self.passCommit then
                        if vhDist.vertical > 7 then
                            --print("cancelpass spaceChange",self.carRadar.front,space)
                            oppFlags.pass = false
                            self:cancelPass()
                        else
                            --print("too late now lol",vhDist.horizontal) -- either keep going or slow down depending on next turn?
                            if vhDist.horizontal > -1 or vhDist.horizontal < 1 then
                                if (self.carAlongSide.left == 0 and self.carAlongSide.right == 0) then
                                    colThrottle = colThrottle - 0.05
                                    --print("nowheretogo slow")
                                    oppFlags.pass = false
                                    self:cancelPass()
                                else
                                    --print("cahrgeAhead")
                                end
                            end
                        end
                    else
                        --passSteer =0 --self:calculatePassOffset(opponent,self.passCommit,vhDist)
                        self.goalOffset = self:calculateGoalOffset(oppInRange[opponent.id],self.passCommit)
                    end
                end
            else
                --print(self.id,"Not Catching")
                if oppFlags.pass then
                    oppFlags.pass = false
                    self:cancelPass()
                else
                    self:cancelPass()
                end

            end
        else-- Keep eye on car, check speed dif
            if (self.speed-opponent.speed) > 4 and vhDist['vertical'] > 0 then -- look for closest space
                --print("approaching car fast")
                local passDirection = self:calculateClosestPassPoint(opponent)
                local passDirection = self.passCommit
                if passDirection ~= 0 then -- This is an emergency pass, execute if possible
                    self.passCommit = passDirection
                    self.goalOffset = self:calculateGoalOffset(oppInRange[opponent.id],passDirection)
                    --print("ePass start",passDirection)
                    eThrot = 0.99 - math.abs(vMax/self.speed)
                    self.passing.isPassing = true
                    self.passing.carID = opponent.id
                    oppFlags.pass = true
                else
                    if self.passing.isPassing and self.speed - vMax < 0 then
                        print("epassFail")
                        self:cancelPass()
                        oppFlags.pass = false
                    end
                    --print("ebrake1")
                    eThrot = 0.75 - math.abs(vMax/self.speed)
                end
            end
        end

    end
    if self.passing.isPassing then
        --print(self.id,"midPass",self.passing.carID)
        if self.opponentFlags[self.passing.carID] ~= nil then
            local passCarData = self.opponentFlags[self.passing.carID]
            --print(self.id,passCarData.vhDist)
            if passCarData.vhDist.vertical > 15 or passCarData.vhDist.vertical < -1 then
                
                if passCarData.pass then
                    passCarData.pass = false
                    self:cancelPass()
                else
                    --print(self.id,"pass Complete?",passCarData.pass)
                    self:cancelPass()
                end
            end
        else
            --print("oppGone???")
            self:cancelPass()
        end
    end

    --print(self.id,getRaceControl().draftingEnabled)
    if not self.raceControlError then
        if getRaceControl().draftingEnabled then
            if hasDraft then
               -- print(self.id,"HS",self.id,hasDraft)
                self.drafting = true
            else
                self.drafting = false
            end
        else
            self.drafting = false
        end
    end

    if self.carRadar.front > 70 then -- also post pass check? 
        if self.drafting then
            --print("false draft",self.id)
            --self.drafting = false
        end
    end
    --print(self.id,self.goalOffset)
    if self.passing.isPassing then
        --print(self.id,"passing")
    end

    -- Alongside stuff
    if alongSideLeft >-100 then
        self.carAlongSide.left = alongSideLeft
    else
        self.carAlongSide.left = 0
    end

    if alongSideRight < 100 then
        --print("reset alongside")
        self.carAlongSide.right = alongSideRight
    else
        self.carAlongSide.right = 0
    end


    self.strategicThrottle = colThrottle
    self.strategicSteering = self.strategicSteering + colSteer + passSteer
    --print("passSteer and stratSteer",self.strategicSteering,colSteer,passSteer)
    self.opponentFlags = oppInRange
    --print(oppInRange)

end

-- Passing functionality
function Driver.cancelPass(self) -- cancels passing
    --print("cancelPass",self)
    self.passing.isPassing = false
    self.passing.carID = nil
    self.goalOffset = nil
    self.passCommit = 0 
end

function Driver.checkPassingSpace(self,opponent) -- calculates the best direction to pass -1 = left, 1 = right, 0 = nope.. bigger numbers will represent confidence level
    if not self.currentNode then return 0 end
    if not opponent then return 0 end
    if not opponent.currentNode then return 0 end -- Consolidate to validation function?
    if not self.futureLook or self.futureLook.direction == nil then return 0 end
    local passEligible = true
    local passDir = 0
    local oppDist = getDriverHVDistances(self,opponent)
    local oppDist = oppDist.vertical
    if oppDist <=4 then -- Maximum  margin will be at 1
        oppDist = 4
    end

    if self.safeMargin then -- prevent crazy passes?
        passeligible = false
    end

    -- CHeckk if on straight/ going to turn depending on aggressive state
    if self.currentNode.segType == "Straight" then
        --print("onstraight",self.futureLook.distance)
        if self.futureLook.distance > 45 then
            --print('Eigible pass?',self.futureLook.distance)
            passEligible = true
        end
    end


    local marginRatio = ratioConversion(15,4,-0.6,-3,oppDist) -- Convert x to a ratio from a,b to  c,d
    local turnDir = getSign(self.futureLook.direction)
    local oppTPos = opponent.trackPosition -- OOOR Just take the opponents distance from left/right wall
    local width = (opponent.currentNode.width or 20)
    local oppWidth = (opponent.leftColDist + opponent.rightColDist)
    local selfWidth = self.leftColDist + self.rightColDist
    local margin = self.passAggression + marginRatio --if distance is greater, aggression is smaller
    --print("margin",margin,((width/2) - oppTPos - oppWidth) + margin)
    if turnDir == 1 then -- turning right
        local spaceLeft = ((width/2) - oppTPos - oppWidth) + margin
        if spaceLeft < selfWidth then
            --print("No room on inside")
        else
            if not (opponent.carRadar.right < selfWidth and (opponent.carRadar.front < 1)) then -- room on opponents inside
                if self.carAlongSide.right == 0 or self.carAlongSide.right > selfWidth then -- if no car to your righty
                    --print("Passing on inside")
                    passDir = 1
                else 
                    --print("car on your inside")
                end
            else
                --print("Car blocking inside") -- Could check for room past the car on inside?
                local laneWidth = width/3 
                if math.abs(opponent.trackPosition) > laneWidth then -- check if possibility for three wide
                    --print('checking for three wide')
                    passDir = 1 -- should then switch over to next opponent eventually
                end
            end
        end
        -- check other side
        if passDir ~= 1 then -- if a decision wasnt made check the other side for room
            spaceLeft = math.abs(-(width/2) - oppTPos + oppWidth)  + margin
            if spaceLeft < selfWidth then
                --print("No room on outside")
            else
                if not (opponent.carRadar.left > -selfWidth and (opponent.carRadar.front < 0)) then --if there is no car in front/on left of opponent (may need to figure out how to split difference)
                    if self.carAlongSide.left == 0 or self.carAlongSide.left < -selfWidth then -- if no car to your left (may need to mess with negatives?)
                        --print("Passing on outise")
                        passDir = -1
                    else
                        --print("car on your outside")
                    end
                else
                    local laneWidth = width/3 
                    if math.abs(opponent.trackPosition) > laneWidth then -- check if possibility for three wide
                        --print('checking for three wide')
                        passDir = -1 -- should then switch over to next opponent eventually
                    end
                end
            end
        end
    elseif turnDir == -1 then -- turning left
        local spaceLeft = math.abs(-(width/2) - oppTPos + oppWidth)  + margin
        if spaceLeft < selfWidth then
            --print("No room on inside (left)")
        else
            if not (opponent.carRadar.left > -selfWidth and (opponent.carRadar.front < 0)) then --if there is no car in front/on left of opponent
                if self.carAlongSide.left == 0 or self.carAlongSide.left < -selfWidth then -- if no car to your left (may need to mess with negatives?)
                    --print("Passing on inside")
                    passDir = -1
                else
                    --print("car on your inside")
                end
            else
                local laneWidth = width/3 
                if math.abs(opponent.trackPosition) > laneWidth then -- check if possibility for three wide
                    --print('checking for three wide')
                    passDir = -1 -- should then switch over to next opponent eventually
                end
            end
        end
        -- check other side
        if passDir ~= -1 then -- if a decision wasnt made check the other side for room
            spaceLeft = ((width/2) - oppTPos - oppWidth)  + margin
            if spaceLeft < selfWidth then
                --print("No room on outside (right)")
            else
                if not (opponent.carRadar.left > -selfWidth and (opponent.carRadar.front < 0)) then --if there is no car in front/on right of opponent (may need to figure out how to split difference)
                    --print("Passing on outside")
                    if self.carAlongSide.right == 0 or self.carAlongSide.right > selfWidth then -- if no car to your righty
                        --print("Passing on inside")
                        passDir = 1
                    else
                        --print("car on your inside")
                    end
                else
                    local laneWidth = width/3 
                    if math.abs(opponent.trackPosition) > laneWidth then -- check if possibility for three wide
                        --print('checking for three wide')
                        passDir = 1 -- should then switch over to next opponent eventually
                    end
                end
            end
        end
    else
        
        passDir = self:calculateClosestPassPoint(opponent) -- default to left turn? maybe test oval
        --print("No Upcoming turns",passDir)
    end
    
    if passDir == 0 or passEligible == false then -- no decisions made
       passDir = 0

    end
    --print(self.tagText,"Passing space",passDir)  
    return passDir
end

function Driver.calculateClosestPassPoint(self,opponent) -- oppLoc = diver vh dist
    if not self.currentNode then return 0 end
    if not opponent then return 0 end
    if not opponent.currentNode then return 0 end    local oppTPos = opponent.trackPosition -- OOOR Just take the opponents distance from left/right wall
    local oppLoc
    if self.opponentFlags[opponent.id] ~= nil then
        oppLoc =  self.opponentFlags[opponent.id].vhDist
    else
        --print("could not find opp in flags")
        return 0 
    end
    local width = (opponent.currentNode.width or 20)
    local oppWidth = (opponent.leftColDist + opponent.rightColDist)
    local selfWidth = self.leftColDist + self.rightColDist
    local optimalDir = getSign(oppLoc.horizontal) -- easiest direction to move
    local mostSpace = -getSign(self.trackPosition) -- more space to move
    local margin = -0.5

    if optimalDir == mostSpace and optimalDir == 1 then -- the world aligns to the right
        local spaceLeft = ((width/2) - oppTPos - oppWidth) + margin
        if spaceLeft > selfWidth then
            if not (opponent.carRadar.right < selfWidth and (opponent.carRadar.front < 1)) then -- room on opponents inside
                if self.carAlongSide.right == 0 or self.carAlongSide.right > selfWidth then -- if no car to your righty
                    passDir = 1
                end
            end
        end
        if passDir ~= 1 then -- check other side
            spaceLeft = math.abs(-(width/2) - oppTPos + oppWidth)  - 2 -- bigger margin
            if spaceLeft > selfWidth then
                if not (opponent.carRadar.left > -selfWidth and (opponent.carRadar.front < 0)) then --if there is no car in front/on left of opponent (may need to figure out how to split difference)
                    if self.carAlongSide.left == 0 or self.carAlongSide.left < -selfWidth then -- if no car to your left (may need to mess with negatives?)
                        passDir = -1
                    end
                end
            end
        end
    elseif optimalDir == mostSpace and optimalDir == -1 then -- best to move left
        local spaceLeft = math.abs(-(width/2) - oppTPos + oppWidth)  + margin
        if spaceLeft > selfWidth then
            if not (opponent.carRadar.left > -selfWidth and (opponent.carRadar.front < 0)) then --if there is no car in front/on left of opponent
                if self.carAlongSide.left == 0 or self.carAlongSide.left < -selfWidth then -- if no car to your left (may need to mess with negatives?)
                    passDir = -1
                end
            end
        end
        -- check other side
        if passDir ~= -1 then -- if a decision wasnt made check the other side for room
            spaceLeft = ((width/2) - oppTPos - oppWidth)  + margin
            if spaceLeft > selfWidth then
                if not (opponent.carRadar.left > -selfWidth and (opponent.carRadar.front < 0)) then --if there is no car in front/on right of opponent (may need to figure out how to split difference)
                    if self.carAlongSide.right == 0 or self.carAlongSide.right > selfWidth then -- if no car to your righty
                        passDir = 1
                    end
                end
            end
        end
    else
        -- DO next best execution
        if optimalDir == 1 then -- easiest to go to right
            local spaceLeft = ((width/2) - oppTPos - oppWidth) + margin
            if spaceLeft > selfWidth then
                if not (opponent.carRadar.right < selfWidth and (opponent.carRadar.front < 1)) then -- room on opponents inside
                    if self.carAlongSide.right == 0 or self.carAlongSide.right > selfWidth then -- if no car to your righty
                        passDir = 1
                        --print("Yeet Right")
                    end
                end
            end
            if passDir ~= 1 then -- check other side
                spaceLeft = math.abs(-(width/2) - oppTPos + oppWidth)  - 2 -- bigger margin
                if spaceLeft > selfWidth then
                    if not (opponent.carRadar.left > -selfWidth and (opponent.carRadar.front < 0)) then --if there is no car in front/on left of opponent (may need to figure out how to split difference)
                        if self.carAlongSide.left == 0 or self.carAlongSide.left < -selfWidth then -- if no car to your left (may need to mess with negatives?)
                            passDir = -1
                            --print(" Yolo left")
                        end
                    end
                end
            end
        elseif optimalDir == -1 then -- best to move left
            local spaceLeft = math.abs(-(width/2) - oppTPos + oppWidth)  + margin
            if spaceLeft > selfWidth then
                if not (opponent.carRadar.left > -selfWidth and (opponent.carRadar.front < 0)) then --if there is no car in front/on left of opponent
                    if self.carAlongSide.left == 0 or self.carAlongSide.left < -selfWidth then -- if no car to your left (may need to mess with negatives?)
                        passDir = -1
                        --print("yeet left")
                    end
                end
            end
            if passDir ~= -1 then -- check other side
                spaceLeft = ((width/2) - oppTPos - oppWidth)  + margin
                if spaceLeft > selfWidth then
                    if not (opponent.carRadar.left > -selfWidth and (opponent.carRadar.front < 0)) then --if there is no car in front/on right of opponent (may need to figure out how to split difference)
                        if self.carAlongSide.right == 0 or self.carAlongSide.right > selfWidth then -- if no car to your righty
                            passDir = 1
                            --print(" yolo right")
                        end
                    end
                end
            end
        end
    end
    if passDir == 0 then -- no room??
        print("No yolo")
        if self.trackPosition > 0 then
            --print("Yolo Left")
            --passDir = -1
        else
            --print("yolo right")
           -- passDir = 1
        end
        --passDir = 0
    end

    if passDir == 0 then -- no decisions made
       --print("Stuck in middle Yolo",passDir)
    end  
    --print(self.tagText,"Closest patt",passDir) 
    return passDir
end

function Driver.confirmPassingSpace(self,opponent,dir) -- checks if the previus committed space is still availible
    if not self.currentNode then return 0 end
    if not opponent then return 0 end
    if not opponent.currentNode then return 0 end -- Consolidate to validation function?
    local passDir = 0
    local oppDist = getDriverHVDistances(self,opponent)
    local oppDist = oppDist.vertical
    if oppDist <=4 then -- Maximum  margin will be at 1
        oppDist = 4
    end
    local marginRatio = ratioConversion(15,4,-0.6,-3,oppDist) -- Convert x to a ratio from a,b to  c,d
    
    local oppTPos = opponent.trackPosition -- OOOR Just take the opponents distance from left/right wall
    local width = (opponent.currentNode.width or 20)
    local oppWidth = (opponent.leftColDist + opponent.rightColDist)
    local selfWidth = self.leftColDist + self.rightColDist
    local margin = self.passAggression + marginRatio --if distance is greater, aggression is smaller
    local laneWidth = width/3 

    --print("margin",margin,((width/2) - oppTPos - oppWidth) + margin)
    if dir == 1 then -- turning right
        local spaceLeft = ((width/2) - oppTPos - oppWidth) + margin
        if spaceLeft < selfWidth then
            --print("No room on inside")
        else
            if not (opponent.carRadar.right < selfWidth and (opponent.carRadar.front < 1)) then -- room on opponents inside
                if self.carAlongSide.right == 0 or self.carAlongSide.right > selfWidth then -- if no car to your righty
                    --print("Passing on inside")
                    passDir = 1
                else
                    --print("car on your inside")
                end
            else
                --print("Car blocking inside") -- Could check for room past the car on inside?
                if math.abs(opponent.trackPosition) > laneWidth then -- check if possibility for three wide
                    --print('confirming for three wide')
                    passDir = 1 -- should then switch over to next opponent eventually
                end
            end
        end
        -- check other side
        if passDir ~= 1 then -- if a decision wasnt made check the other side for room
            spaceLeft = math.abs(-(width/2) - oppTPos + oppWidth)  + margin
            if spaceLeft < selfWidth then
                --print("No room on outside")
            else
                if not (opponent.carRadar.left > -selfWidth and (opponent.carRadar.front < 0)) then --if there is no car in front/on left of opponent (may need to figure out how to split difference)
                    if self.carAlongSide.left == 0 or self.carAlongSide.left < -selfWidth then -- if no car to your left (may need to mess with negatives?)
                        --print("Passing on outise")
                        passDir = -1
                    else
                        --print("car on your outside")
                    end
                else
                    if math.abs(opponent.trackPosition) > laneWidth then -- check if possibility for three wide
                        --print('confirming for three wide')
                        passDir = -1 -- should then switch over to next opponent eventually
                    end
                end
            end
        end
    elseif dir == -1 then -- turning left
        local spaceLeft = math.abs(-(width/2) - oppTPos + oppWidth)  + margin
        if spaceLeft < selfWidth then
            --print("No room on inside (left)")
        else
            if not (opponent.carRadar.left > -selfWidth and (opponent.carRadar.front < 0)) then --if there is no car in front/on left of opponent
                if self.carAlongSide.left == 0 or self.carAlongSide.left < -selfWidth then -- if no car to your left (may need to mess with negatives?)
                    --print("Passing on inside")
                    passDir = -1
                else
                    --print("car on your inside")
                end
            else
                if math.abs(opponent.trackPosition) > laneWidth then -- check if possibility for three wide
                    --print('confirming for three wide')
                    passDir = -1 -- should then switch over to next opponent eventually
                end
            end
        end
        -- check other side
        if passDir ~= -1 then -- if a decision wasnt made check the other side for room
            spaceLeft = ((width/2) - oppTPos - oppWidth)  + margin
            if spaceLeft < selfWidth then
                --print("No room on outside (right)")
            else
                if not (opponent.carRadar.left > -selfWidth and (opponent.carRadar.front < 0)) then --if there is no car in front/on right of opponent (may need to figure out how to split difference)
                    --print("Passing on outside")
                    if self.carAlongSide.right == 0 or self.carAlongSide.right > selfWidth then -- if no car to your righty
                        --print("Passing on inside")
                        passDir = 1
                    else
                        --print("car on your inside")
                    end
                else
                    if math.abs(opponent.trackPosition) > laneWidth then -- check if possibility for three wide
                        --print('confirming for three wide')
                        passDir = 1 -- should then switch over to next opponent eventually
                    end
                end
            end
        end
    else
        --print("Pass dir confirming 0???") -- maybe add some othe optyion??
    end

    if passDir == 0 then -- no decisions made, cancel the pass
        --print("Stuck in middle",passDir)
    end  
    --print(self.tagText,"pass",passDir)  
    return passDir
end

function Driver.calculateGoalOffset(self,opponentD,dir) -- calculates goal node offset needed to get around opp
    if self.goalNode == nil then return end
    if self.goalNode.width == nil then return end
    local opponent = opponentD.data
    local oppWidth = (opponent.leftColDist + opponent.rightColDist)
    local selfWidth = self.leftColDist + self.rightColDist
    local speedDif = self.speed - opponent.speed
    if speedDif < 3 then 
        speedDif = 3
    elseif speedDif > 13 then
        speedDif = 14
    end
    local goalTrackPos = getNodeVHDist(self.goalNode,self.goalNode).horizontal
    local desiredTrackPos = opponent.trackPosition + dir * (oppWidth + selfWidth/2)

    local strength = 0 
    --print("o[pp",opponentD.vhDist)
    local distFromOpp = opponentD.vhDist.vertical
    if distFromOpp < 9 then -- this is generally too close
        distFromOpp = distFromOpp/2
    end
    if distFromOpp <= 2 then
        distFromOpp = 1
    end

    if math.abs(desiredTrackPos) < self.goalNode.width/2.1 then
        --print("Pos on track")
        strength = (speedDif) + math.abs(goalTrackPos-desiredTrackPos)/(distFromOpp)  -- convert by distance away from opp
    else
        --print("Out of bounds look",desiredTrackPos,self.goalNode.width/2.1,self.trackPosition)
        strength = 2 -- possibly cancel pass
        --self:cancelPass() -- remove flag?
    end
    --print(self.tagText,"strength",strength,distFromOpp )
    local shiftDir = self.goalNode.perp * (dir * strength)
    
    return shiftDir
end

function Driver.calculatePassOffset(self,opponent,direction,oppLoc) -- calculate which angle wheel needs to be at to pass car
    local turnAngle = 0
    local frontDist = oppLoc.vertical
    local sideDist = oppLoc.horizontal
    if direction == 1 then
        turnAngle = ratioConversion(27,5,0.1,0,frontDist) * 1  -- Convert x to a ratio from a,b to  c,d
        if sideDist <= -2 and frontDist < 5 then -- or 0?
            print("preFilter",turnAngle)
            turnAngle = turnAngle/math.abs(sideDist-1)
        end
    elseif direction == -1 then
        turnAngle = ratioConversion(27,5,0.1,0,frontDist)  * -1 -- Convert x to a ratio from a,b to  c,d
        if sideDist >= 1 and frontDist < 5 then -- or 0?
            print("preFilter",turnAngle)
            turnAngle = turnAngle/math.abs(-sideDist-1)
        end
    end
    
    --print("passOffset",direction,frontDist,sideDist,turnAngle)
    return turnAngle
end

function Driver.calculateFutureTurn(self) -- calculate future turns
    if self.currentNode == nil then return nil end
    local foundTurn = false 
    local curSeg = self.currentNode.segID
    local curSegType = self.currentNode.segType
    local nextTurnSeg = curSeg -- will get updated with next turn found
    local segNode = nil
    local timeout = 0
    local timeoutLimit = #self.nodeChain
    --print("Grabbing futureTurn totalsegments",self.totalSegments)
    while not foundTurn do
        curSeg = getNextIndex(self.totalSegments,curSeg,1)
        segNode = self:getSegmentBegin(curSeg)
        if segNode == nil then return nil end
        
        if timeout >= timeoutLimit or self.ovalTrack == true then -- or self.ovalTrack
            self.ovalTrack = true
            --print("FutureTurn timout")
            nextTurnSeg = segNode -- just have last segment for now
            break
        end


        if segNode.segType ~= curSegType then
            if segNode.segType ~= "Straight" then
                foundTurn = true
                nextTurnSeg = segNode
            end
        end
        timeout = timeout + 1
        
    end
    local turnDir = getSegTurn(nextTurnSeg.segType)
    local distanceFromTurn = getDistance(segNode.location,self.location)
    local segID = segNode.segID
    
    local segLen = self:getSegmentLength(segID)
    if turnDir == 0 then 
        --print(segID,turnDir,segLen,distance)
    end
    if segLen == nil then
        print("nil Len",segID,segLen,distance)
    else
        --print("Len",segLen)
    end
    
    return {segID = segID, direction = turnDir, length = segLen, distance = distanceFromTurn} 
end


function Driver.updateErrorLayer(self) -- Updates throttle/steering based on error fixing
    if self.engine == nil then return end
    if self.engine.engineStats == nil then return end
    if self.goalNode == nil or self.currentNode == nil then return end

-- Check tilted
    if self.tilted== true then 
        if self.debug  then
            --print(self.id,"correcting tilt")
        end
        local offset = sm.vec3.new(0,0,0)
		--local angularVelocity = self.shape.body:getAngularVelocity()
		--local worldRotation = self.shape:getWorldRotation()
		local upDir = self.shape:getUp()
		--print(angularVelocity)
		--print(worldRotation)
		--print(upDir)
		-- Check if upside down,
		local stopDir = self.velocity * -1.5
        if sm.vec3.closestAxis(upDir).z == -1 then
            local weight =self.mass * DEFAULT_GRAVITY
		    stopDir.z = self.mass/2.3
            --print(self.mass/3)
            --print("flip")
        else
            
            stopDir.z = self.mass/10
        end
		
		offset = upDir * 4
		if self.shape:getWorldPosition().z >= self.currentNode.location.z + 3 then 
			stopDir.z = -500 -- maybe anti self.weight?
			--offset = 
		end
		--print("correcting tilt")
		sm.physics.applyImpulse( self.shape.body, stopDir,true,offset)
    end
-- Check oversteer and understeer
    if self.oversteer and self.goalNode then
        local offset = self.goalDirectionOffset
        self.rotationCorrect = true
        --print(self.id,"oversteer correct",offset,self.speed,self.curGear)
        --self.pathGoal = "mid"
        if self.strategicThrottle >= 0 then  
            self.strategicThrottle = 0.1 -- begin coast
            -- reduce steering?
            if math.abs(offset) > 14 or self.speed > 23 then
                --print(self.speed)
                self.strategicThrottle = ratioConversion(10,35,-0.7,0,self.speed) -- Convert x to a ratio from a,b to  c,d
                --print("ovrsteer thrott",self.speed,self.strategicThrottle)
            else
                self.strategicThrottle = 0.1 -- coast
            end
        end
    end

    if self.understeer and self.goalNode and not self.oversteer then
        local offset = self.goalDirectionOffset
        --print(self.id,"understeer correct",offset,self.speed,self.curGear)
        self.rotationCorrect = true
        if self.strategicThrottle >= 0 then  -- Do this when not "braking"
            self.strategicThrottle = 0.1
            if math.abs(offset) > 13 or self.speed > 24 then
                --print(self.id,"understeerCorrect",self.curGear,self.engine.VRPM,self.speed)
                self.strategicThrottle = ratioConversion(10,35,-0.8,0,self.speed) -- Convert x to a ratio from a,b to  c,d
                if self.speed <= 10 then
                    self.strategicThrottle = 0.1
                    self.strategicSteering = self.strategicSteering/2
                    --print("half steer")
                end
            else
                self.strategicThrottle = 0.1 -- coast
                self.strategicSteering = self.strategicSteering *0.95
            end
        else
            --print(self.id,"understeer braking",self.speed,offset,self.strategicThrottle)
            if self.speed > 17 then
                if offset > 14 then
                    self.strategicThrottle = self.strategicThrottle - 0.05
                end
            end
        end
    end

    if not self.understeer or not self.oversteer then -- Do same for oversteer? 
        if self.pathGoal ~= "location" then
            self.pathGoal = "location"
        end
    end
-- Check over rotation
    if self.rotationCorrect then
        --self.speedControl = 15
        --print(self.id,"fix rotate",self.angularVelocity:length(),self.goalDirectionOffset, self.speed)
        if self.speed < 15 and  math.abs(self.goalDirectionOffset) > 3 and self.angularVelocity:length() > 0.7 then -- counter steer
            self.strategicSteering = self.strategicSteering / -5
            --print("counterSteer?")
        end
        
        if self.speed < 18 or self.angularVelocity:length() < 1 and math.abs(self.goalDirectionOffset) < 1 then
            self.rotationCorrect = false
            self.speedControl = 0
            --print("corrected",self.speed)
        end
        if self.speed >25 then
            --print("brake",self.speed)
            self.strategicThrottle = -0.4
        end
    end    
-- Check walls
    local frontLength = (self.carDimensions or 1)
    if self.carDimensions ~= nil then 
        frontLength = self.carDimensions['front']:length()
    end
    local frontLoc = self.location + (self.shape.at*frontLength)
    local hitR,rData = sm.physics.raycast(frontLoc,frontLoc + self.shape.right *6,self.body) 
    local hitL,lData = sm.physics.raycast(frontLoc,frontLoc + self.shape.right *-6,self.body)
    local wallLimit = self.currentNode.width or 50 -- in case width is messed up
    local sideLimit = wallLimit/2.05 -- get approximate left/right limits on the wall

    local walSteer = 0
    if hitR and rData.type == "terrainAsset" then
        local dist = getDistance(self.location,rData.pointWorld) 
        if dist <= 4 then
            walSteer = ratioConversion(4,0,0.22,0,dist)  -- Convert x to a ratio from a,b to  c,d
            --print(self.tagText,"right",dist,walSteer)

        end
        if dist < 1 then
            self.strategicThrottle = 0.1
        end
    end

    if hitL and lData.type == "terrainAsset" then
        local dist = getDistance(self.location,lData.pointWorld) 
        --print(dist)
        if dist <= 4 then
            --print("left",dist)
            walSteer = ratioConversion(4,0,0.22,0,dist) * -1  -- Convert x to a ratio from a,b to  c,d
            --print(self.tagText,"left",walSteer)
        end
        if dist < 1 then
            self.strategicThrottle = 0.1
        end
    end

    -- try to stay within tracklimits (exeption on overtake?)
    local trackAdj = 0
    --if self.trackPosition == nil then return end
    local tDist = sideLimit - math.abs(self.trackPosition)
    if tDist <7 then
        if self.trackPosition > 0 then
            trackAdj = ratioConversion(7,0,0.06,0,tDist) *1  -- Convert x to a ratio from a,b to  c,d    
        else
            trackAdj = ratioConversion(7,0,0.06,0,tDist) *-1 -- Convert x to a ratio from a,b to  c,d 
        end
        --print(self.tagText, "track limit",trackAdj,tDist)
    
        if self.passing.isPassing or math.abs(walSteer) > 0 then -- dampen/strenghen? limits
            --trackAdj = trackAdj *0.95
            --print("Track lim test",trackAdj)
        end
    end
    --print(self.trackPosition,sideLimit,tDist,trackAdj,walSteer)
    self.strategicSteering = self.strategicSteering + walSteer + trackAdj-- Maybe not desparate?


-- check stuck
    if self.stuck and self.raceStatus ~= 0 then
        local offset = posAngleDif3(self.location,self.shape.at,self.goalNode.location) -- TODO: replace with goaldiroffset
        local frontDir = self.shape.at
        --frontDir.z = self.shape:getWorldPosition().z -- keep z level the same for inclines
        local hit,data = sm.physics.raycast(self.shape:getWorldPosition(),self.location + frontDir *20,self.body)
        local dist = 50

        if hit then
            dist = getDistance(self.location,data.pointWorld) 
        end
        --print(self.tagText,"RAYCAST",dist,data,self.curGear)
            
        if self.rejoining then -- Car is approved and rejoining, check different things
            if self.curGear == -1 then -- If reversing
                --print("attemptReverse")
                if  toVelocity(self.engine.curRPM) < -9 and self.speed <= math.abs(toVelocity(self.engine.curRPM)) -1 then --math.abs(toVelocity(self.engine.curRPM)) -1
                    if self.speed <= 1 then
                        --print("reverse stuck",toVelocity(self.engine.curRPM),self.speed)
                        local distanceThreshold = -50 -- make dynamic?
                        local clearFlag = self:checkForClearTrack(distanceThreshold)
                        if clearFlag then
                            --print("Clear shift 1")
                            self.curGear = 1
                            self:shiftGear(1)
                            self.strategicThrottle = 1
                            self.stuckTimeout = self.stuckTimeout + 1
                        else
                            --print("brak -1")
                            self.strategicThrottle = -1 -- brake
                            self.stuckTimeout = self.stuckTimeout + 1
                        end
                    end
                end
                self.strategicSteering = self.strategicSteering * -1.5 -- Inverse steering
                --print("Reverse rejoin",self.speed,self.engine.curRPM, math.abs(toVelocity(self.engine.curRPM)),math.abs(offset),dist)
                if (math.abs(offset) < 13  and  dist >= 25) or dist >=35 then -- If facing right way and not in wall
                    if self.speed > 1 then -- TEMPORARY FIX for leaning against wall, check tilt and rotation as well 
                        self.curGear = 1
                        self:shiftGear(1)
                        self.strategicThrottle = 1
                        -- stay mid until up to speed?
                        -- check for wall in front?
                        --print("aligned/Finish reverse",offset,dist)
                    end
                end

                if self.strategicThrottle ~= 1 then
                   -- print("RandomFlip",self.curGear,self.strategicThrottle)
                   if not self.nudging then
                        self.stuckTimeout = self.stuckTimeout + 1
                   end
                    self.strategicThrottle = 1
                end

            elseif self.curGear > 0 then -- If moving forward to rejoin
                local segID = self.currentSegment
                local segBegin = self:getSegmentBegin(segID)
                local segEnd = self:getSegmentEnd(segID)
                local segLen = self:getSegmentLength(segBegin.segID)
                local maxSpeed = calculateMaximumVelocity(segBegin,segEnd,segLen) 
                --print(self.tagText,"gear > 0",self.strategicThrottle,toVelocity(self.engine.curRPM))
                if toVelocity(self.engine.curRPM) > 6 and  self.speed <= math.abs(toVelocity(self.engine.curRPM)) -2 then -- Stuck going forward
                    if self.speed <= 1 then
                        --print("rejoin stuck",toVelocity(self.engine.curRPM),self.speed,self.trackPosBias)
                        local distanceThreshold = -50 -- make dynamic?
                        local clearFlag = self:checkForClearTrack(distanceThreshold)
                        if clearFlag then
                            --print("cleaaar")
                            self.stuckTimeout = self.stuckTimeout + 1
                            self.curGear = -1
                            self:shiftGear(-1)
                            self.strategicThrottle = 1
                            local curentSide = self:getCurrentSide()
                            --print("Rejoining backwards",self.trackPosition,curentSide)
                            self.trackPosBias = curentSide
                        else
                            self.strategicThrottle = -1
                        end
                    end
                end
                self.strategicThrottle = 1 -- until otherwise?
                --print(self.tagText,"rejoining",offset,dist,self.speed,maxSpeed,self.engine.curRPM,self.strategicThrottle)
                
                
                if (self.speed >= maxSpeed - 4 and toVelocity(self.engine.curRPM) >= maxSpeed - 5 and self.offTrack == 0) or (self.curGear >=4 and self.offTrack == 0) then
                    self.rejoining = false
                    self.stuck = false
                    self.pathGoal = "location"
                    self.trackPosBias = 0
                    self.stuckTimeout = 0
                    print(self.tagText,"rejoin done",self.offTrack,self.stuckTimeout)
                end
            else -- something wong
               print(self.tagText,"SOmething wrong",self.curGear)
               self:shiftGear(1)
               self.curGear = 1
               self.strategicThrottle = 1
               self.rejoining = true
               self.stuck = false
               self.trackPosBias = 0 -- reset bias...
               self.stuckTimeout = self.stuckTimeout + 5
            end

        else -- start rejoin process
            if self.engine.curRPM > 1 and self.curGear >=0 then
                --print("slowing",self.engine.curRPM)
                self.strategicThrottle = -1
            else -- Check for clear entry point then reverse

                local distanceThreshold = -50 -- make dynamic?
                local clearFlag = self:checkForClearTrack(distanceThreshold)
                if clearFlag then
                    local curentSide = self:getCurrentSide()
                    --print("Rejoining",self.trackPosition,curentSide)
                    self.trackPosBias = curentSide
                    self.rejoining = true
                    self.curGear = -1
                    self:shiftGear(self.curGear)
                    --print("reeversing begin",self.curGear,self.engine.curRPM)
                    self.strategicThrottle = 0.6
                    self.strategicSteering = self.strategicSteering * -1.4
                else
                    self.strategicThrottle = -1
                end
            end
        end
    end
    
-- Check Offtrack
    if self.offTrack ~= 0 then
        --print(self.id,"offtrack",self.offTrack)
        if self.speed < 15 then -- speed rejoin
            self.strategicSteering = self.strategicSteering --+ self.offTrack/90 --? when at high speeds adjust to future turn better?
            --print(self.id,"offtrack correction", print(self.id,"offtrack",self.goalDirectionOffset))
            self.strategicSteering = self.strategicSteering - (self.goalDirectionOffset/(math.abs(self.offTrack) +0.1))
            --print("start rejoining?")
            --self.stuck = true
        else -- just use nodefollow?
            self.strategicThrottle = -0.2
            if self.speed < 1 then
                --print(self.id,"stuck offtrack")
                self.stuck = true
            end
        end
        --print(self.id,"offtrack",self.offTrack,self.strategicSteering)
    end
-- Check wildly offCenter I think these conflict with other things
    local adjustmenDampener = 80 -- 
    if not self.rejoining and not self.stuck then
        if self.goalDirectionOffset ~= nil and math.abs(self.goalDirectionOffset) >0  then 
            if self.currentNode.segType == "Straight" then -- If supposed to be on straight
                if math.abs(self.goalDirectionOffset) > 3 then -- if too much turn
                    if self.speed > 20 then
                        --print(self.tagText,"WildOfftrackAdjustST",self.strategicSteering,self.goalDirectionOffset)
                        self.strategicThrottle = 0.1
                        if math.abs(self.trackPosition) < self.currentNode.width/3.5 then -- if somewhat in the middle, slow the adjustment
                            --print("pre adjust",self.strategicSteering)
                            self.strategicSteering = self.strategicSteering + -(self.goalDirectionOffset / adjustmenDampener)
                            --print(self.tagText,"adjusted",self.strategicSteering,(self.goalDirectionOffset / adjustmenDampener))
                            self.strategicThrottle = 0.1                 
                        else
                            --print(self.tagText,"outside",-self.goalDirectionOffset)
                            self.strategicThrottle = -0.1
                            self.strategicSteering = self.strategicSteering - self.goalDirectionOffset
                        end
                        self.goalOffsetCorrecting = true
                    end -- Else if speed < 7 then keep throttle at 0 or low power
                    --print("Spinout??",self.goalDirectionOffset,self.strategicThrottle)
                    self.goalOffsetCorrecting = true
                else
                    if self.goalOffsetCorrecting then 
                        self.goalOffsetCorrecting = false
                    end
                end

            else -- car turning
                --print("turn",self.goalDirectionOffset)
                if math.abs(self.goalDirectionOffset) > 3.2 then -- if too much turn
                    --print(self.id,"Turn offDirection Adjust")
                    --self.strategicSteering = self.strategicSteering/1.5 -- + (self.goalDirectionOffset / 5) Mauybe remove
                    if self.speed > 20 then
                        --print(self.tagText, "WildOfftrackAdjustTurn",self.trackPosition,self.goalDirectionOffset)
                        if math.abs(self.trackPosition) < self.currentNode.width/3.5 then -- if somewhat in the middle, slow the adjustment
                            self.strategicThrottle = 0
                            --print("pre adjustTurn",self.strategicSteering)
                            self.strategicSteering = self.strategicSteering + -(self.goalDirectionOffset / adjustmenDampener)
                           --print("adjustedTrurn",self.strategicSteering,-(self.goalDirectionOffset / adjustmenDampener))
                        else
                            --print(self.tagText,"onoutsideTurn",self.goalDirectionOffset,self.strategicSteering)
                            self.strategicThrottle = 0
                            self.strategicSteering = self.strategicSteering - (self.goalDirectionOffset/adjustmenDampener)
                        end
                        self.goalOffsetCorrecting = true
                    end
                    --print("Turn Spinout??",self.goalDirectionOffset,self.strategicThrottle)
                else
                    if self.goalOffsetCorrecting then 
                        self.goalOffsetCorrecting = false
                    end
                end
            end
        end
    end
    if self.rejoining then -- what going on?
        --print(self.curGear)
        if  self.curGear >= 4 then
            --print("rejoin complete")
            self.rejoining = false
            self.stuck = false
            self.pathGoal = "location"
            self.trackPosBias = 0
        end
    end
    

end

function Driver.resetPosition(self,force) -- attempts to place the driver on a lift
    --print(force,self.onLift,self.resetPosTimeout)
    if self.resetPosTimeout < 10 and not self.onLift and not force then
        self.resetPosTimeout = self.resetPosTimeout + 0.1
        --print("reset",self.resetPosTimeout)
        return 
    end
    if force then
        --print("Force reset")
    end
    if not self.raceControlError then
        if not getRaceControl():sv_checkReset() then
            --print("Wait for reset")
            return
        else
            --print("Can reset")
            getRaceControl():sv_resetCar()
        end
    else
        print("no race control")
    end

    if true then -- formerly if self.lost
        --print("fix lost?",self.onLift )
        if self.onLift then
            print("car on lift")
            return
        end
        if not self.liftPlaced and not self.onLift then
            local bodies = self.body:getCreationBodies()
            self.creationBodies = bodies
            local locationNode = (self.resetNode or self.nodeChain[4])
            local location = locationNode.mid * 4
            local rotation = getRotationIndexFromVector(locationNode.outVector,0.75)
            if rotation == -1 then
                print("Got bad rotation")
                rotation = getRotationIndexFromVector(locationNode.outVector, 0.45) -- less precice, more likely to go wrong or do a getNearest Axis and then rotate
            end
            local realPos = sm.vec3.new(math.floor( location.x + 0.5 ), math.floor( location.y + 0.5 ), math.floor(  self.nodeChain[2].mid.z + 5.5 ))
            -- check if this will intersect with anything else
            local okPosition, liftLevel = sm.tool.checkLiftCollision( self.creationBodies, realPos, rotation )
            --print("QuieckCHeck",okPosition,liftLevel)
            if okPosition then
                print('Resetting Position:',realPos,rotation)
                sm.player.placeLift( self.player, self.creationBodies , realPos, liftLevel, rotation ) --Lift Level, rotation index
                if not self.liftPlaced then
                    self.liftPlaced = true
                    --print("placed Lift",self.shape:getWorldPosition())
                    self:sv_softReset()
                    self.resetPosTimeout = 0
                end
            else
                print("collision, not resetting")
            end
            return
        end
        if self.liftPlaced and not self.lost then
            print("Lift placed and not lost")
            sm.player.removeLift( self.player)
            self.liftPlaced = false
        else 
            if self.onLift then
                print("MadOn lift but still lost")
            else
                print("Not on lift, try again?")
                sm.player.removeLift(self.player)
                self.liftPlaced = false
            end
        end
    else
        print("non lost reset")
    end
end


function Driver.calculateTrackPos(self)
    if not self.currentNode then return 0 end
    local trackPos = 0 -- 0 is center
    --print("trackPos",self.currentNode)
    local vhDist = getNodeVHDist(self,self.currentNode)
    return vhDist.horizontal
end

function Driver.calculateGoalDirection(self) -- calculates general direciton car should try to go
    if self.currentNode == nil then return self.shape.at end -- maybe instead of at, use goalNode?
    --print(self.goalNode)
    local goalDirection = self.currentNode.outVector -- Can make this dynamic according to different race states
    --print("goalDirection",goalDirection,self.goalDirection)
    return goalDirection
end

function Driver.calculateNodeFollowStrength(self) -- Calculates strength of node to follow (loose on straights, tight on turns?) INVERSEa
    --print(self.followStrength)
    if self.goalNode == nil then return 1 end
    if self.currentNode == nil then return 1 end 
    if self.caution then return 10 end -- TODO: figure out why
    --local segBegin = self:getSegmentBegin(self.goalNode.segID) -- Could be Either goal or current...
    local segLen = self:getSegmentLength(self.goalNode.segID)
    if math.abs(self.velocity.z) > 0.25 then -- short cut jumping
        --print("looseJumpe n")
        return 7
    end
    

    if self.rotationCorrect then -- todo, what do?
        --print("rotCorrect",self.followStrength)
        if self.followStrength < 15 then
            return self.followStrength - 0.01 -- or less?
        else
            return 15 -- or less?
        end
    end

    if self.offline then -- car offline
        if self.followStrength > 3 then
            --print("wideReduc",self.followStrength)
            return self.followStrength - 0.03 -- or less?
        else
            return 3
        end
    end

    if self.offTrack ~= 0 then
        --print("offtrack?",self.goalDirectionOffset)
        return 15
    end
    
    if self.goalNode.segType == "Straight" then
        if self.passing.isPassing then -- stay looseish while passing
            if self.followStrength > 4 then
                --print("reducing followstrenght for pass",self.followStrength)
                return self.followStrength - 0.01
            else
                return 4
            end
        else
            if self.carAlongSide.left ~= 0 or self.carAlongSide.right ~=0 then -- TODO: investigate effects of this
                if self.followStrength > 4 then
                    --print("reducing followstrenght for pass",self.followStrength)
                    return self.followStrength - 0.02 
                else
                    --print('rando 3')
                    return 4
                end
            end                 
        end

        
        if self.understeer or self.rejoining or self.stuck or self.speed < 5 or self.goalOffsetCorrecting then
            --print("errorRewsolutionFollowChange",self.followStrength)
            --print("offfsetCorrectionTight?",self.goalOffsetCorrecting,self.followStrength)
            if math.abs(self.offTrack) >= 1 then
                if self.followStrength > 2.5 then
                    return self.followStrength - 0.05 
                else
                    --print("offtrack node tighb 2.5")
                    return 2.5
                end
            end

            if self.followStrength > 5 then
                --print("reducing",self.followStrength)
                return self.followStrength - 0.5 
            else
                --print("reducde",self.followStrength)
                return 5
            end
          
        else
            if segLen < 20 then -- If on short straight, dont loosen too much
                --print("short Straight",self.followStrength)
                if self.goalOffsetCorrecting then 
                    if self.followStrength > 2 then
                        --print("reducing",self.followStrength)
                        return self.followStrength - 0.07 
                    else
                        --print("reducde",self.followStrength)
                        return 2
                    end
                end
                if self.followStrength < 7 then
                    if self.carAlongSide.left ~= 0 or self.carAlongSide.right ~= 0 then
                        return self.followStrength + 0.01
                    end
                    return self.followStrength + 0.1-- Slower?
                else
                    return 7
                end
            else -- if on long striahgt, can loosen more
                --print("long strencght",self.followStrength)
                if self.goalOffsetCorrecting then
                    if self.followStrength > 3.5 then
                        --print("reducing",self.followStrength)
                        return self.followStrength - 0.05 
                    else
                        --print("reducde",self.followStrength)
                        return 3.5
                    end
                end
                if self.followStrength < 14 then
                    if self.carAlongSide.left ~= 0 or self.carAlongSide.right ~= 0 then
                        return self.followStrength + 0.07
                    end
                    return self.followStrength + 0.2 --
                else
                    if self.followStrength < 14 then -- default straight
                        --print("Stright increase",self.followStrength)
                        return self.followStrength + 0.07
                    else
                        return 14
                    end
                end
            end
            --print("Huh?",self.followStrength)
        end
        
    else -- If turning! Try to follow nodes better
        if math.abs(self.velocity.z) > 0.15 then -- if vertical movement
            --print("looseJumpe n")
            return 3
        end

        if self.followStrength > 2 then -- TODO: Add segLen exceptions?
            --print(self.tagText,"turning",self.followStrength)
            return self.followStrength - 0.2
        else
            return 2
        end
    end
    return 
end

function Driver.calculateTrackPosBiasTurn(self) --[Unused] tries to make more efficient apex for attacking/defending Uses steering
    if self.currentNode == nil or self.goalNode == nil then return end
    if self.currentNode.width == nil then self.currentNode.width = 20 end
    --print(self.futureLook)
    local nextTurnDir = getSign(self.futureLook.direction)
    local distFromTurn = self.futureLook.distance
    local segLen = self:getSegmentLength(self.currentNode.segID)-- TODO: reduce ammount of seglen calculation (future)
    local selfWidth = self.leftColDist + self.rightColDist
    local sideLane = (self.currentNode.width/2 - selfWidth) -- + margin?
    local offsetBias = 0 
    --print(distFromTurn,self.futureLook)   
    if not self.passing.isPassing or self.understeer or self.oversteer then -- have one specific for rejoins?
        if self.currentNode.segType == "Straight" and segLen > 30 then-- if on long straight
            if distFromTurn > 20 then -- and segLength > 50
                if nextTurnDir == 1 then-- if supposed to turn right
                    local leftOffset = sideLane + self.trackPosition
                    offsetBias = ratioConversion(0,self.currentNode.width,3,0,leftOffset)
                    --print("LeftOffset",self.trackPosition,sideLane,leftOffset,offsetBias)
                elseif nextTurnDir == -1 then-- if supposed to turn right
                    local rightOffset = sideLane - self.trackPosition
                    offsetBias = ratioConversion(0,self.currentNode.width,3,0,rightOffset)
                    --print("rightOffset",rightOffset,offsetBias)
                else -- if no future turns just stay in the middle -- SHOULD USE FOR FORMATION LAPS AND STUFF
                    local offset = 0 + self.trackPosition
                    offsetBias = ratioConversion(0,self.currentNode.width,0,0.15,offset)
                end
            end
        end
    end

    if offsetBias > 4 then
        if self.goalNode.segType == "Straight" and self.followStrength > 2 then
            offsetBias = offsetBias * 1.5
        else   
            offsetBias = 4
        end
        print("compensate",offsetBias)
    end
    -- TODO: CHeck for car behind, Go "defensive if radar is less than 20"
    return offsetBias * -nextTurnDir -- TODO: FIgure out solution for turnDir being 0
end

function Driver.calculateTrackPosBiasNode(self) -- tries to make more efficient apex for attacking/defending, Uses Node shifting TODO: Needs a lot of work
    if self.currentNode == nil or self.goalNode == nil then return end
    if self.currentNode.width == nil then self.currentNode.width = 20 end
    --print(self.futureLook)
    local nextTurnDir = getSign(self.futureLook.direction)
    local distFromTurn = self.futureLook.distance
    local selfWidth = self.leftColDist + self.rightColDist
    local sideLane = (self.currentNode.width/2 - selfWidth) -- + margin?
    local offsetBias = 0
    local shiftDir = nil -- will be a vector
    --print(distFromTurn)   
    if not self.passing.isPassing or self.understeer or self.oversteer then -- have one specific for rejoins?
        if self.currentNode.segType == "Straight" then-- if on straight
            if distFromTurn > 10 then -- and segLength > 50
                if nextTurnDir == 1 then-- if supposed to turn right
                    local leftOffset = sideLane + self.trackPosition
                    offsetBias = ratioConversion(0,self.currentNode.width,4,0,leftOffset)
                    shiftDir = self.goalNode.perp * (-nextTurnDir * offsetBias)
                    print("LeftOffset",self.trackPosition,sideLane,leftOffset,offsetBias)
                elseif nextTurnDir == -1 then-- if supposed to turn right
                    local rightOffset = sideLane - self.trackPosition
                    offsetBias = ratioConversion(0,self.currentNode.width,4,0,rightOffset)
                    shiftDir = self.goalNode.perp * (nextTurnDir * offsetBias)
                    --print("rightOffset",rightOffset,offsetBias)
                else -- if no future turns just stay in the middle -- SHOULD USE FOR FORMATION LAPS AND STUFF
                    local offset = 0 + self.trackPosition
                    offsetBias = ratioConversion(0,self.currentNode.width,0,0.15,offset)
                    shiftDir = self.goalNode.perp * (nextTurnDir * offsetBias)
                end
            end
        end
    end
    self.goalNode.location = self.goalNode.location +  (shiftDir or sm.vec3.new(0,0,0))
    return 
   
end

-- Networking

function Driver.sv_recieveCommand(self,command) -- recieves various commands from race control
    if command == nil then return end
    --print(self.id,"revieved command",command)
    if command.type == "raceStatus" then 
        if command.value == 1 then -- Race is go
            self.safeMargin = true -- just starting out race
            self.racing = true
            self.caution = false
            self.formation = false
        elseif command.value == 0 then -- no race
            self.racing = false
            self.caution = false
            self.formation = false
        elseif command.value == 2 then -- formation lap
            self.racing = true -- ??
            self.formation = true 
            self.caution = false --??
        elseif command.value == 3 then -- no race
            self.racing = true -- ??
            self.formation = false 
            self.caution = true --??
        end
    elseif command.type == "handicap" then -- set car handicap (idk why i'm not setting directly...)
        self.handicap = command.value
    elseif command.type == "resetRace" then -- Reset Car
        self.handicap = self:sv_hard_reset()
    end
end

function Driver.sv_sendCommand(self,command) --sends command to race control
    local raceControl = getRaceControl()
    if raceControl == nil then
        if not self.raceControlError then
            print("No race Control")
            self.raceControlError = true
        end
        return
    end
    raceControl:sv_recieveCommand(command)
end


function Driver.sv_sendAlert(self,msg) -- sends alert message to all clients (individual clients not recognized yet)
    self.network:sendToClients("cl_showAlert",msg)
end

function Driver.cl_showAlert(self,msg) -- client recieves alert
    print("Displaying",msg)
    sm.gui.displayAlertText(msg,3)
end

function Driver.sv_sendChatMessage(self,msg) -- shows chat messgae on clients
    self.network:sendToClients("cl_showChatMessage",msg)
end

function Driver.cl_showChatMessage(self,msg)
    sm.gui.chatMessage(msg)
end

-- Car position checking and updating
function Driver.checkLapCross(self) -- also sets racePOS
    if self.nodeChain == nil then return end
    if self.location == nil then return end
    if self.currentNode == nil then return end
    if self.carDimensions == nil then return end
    if getRaceControl() == nil then return end
    local startLine = self.nodeChain[1]
    local sideWidth = startLine.width/2
    if startLine == nil then
        print("cant find start line")
    end
    local axis = sm.vec3.closestAxis(startLine.perp) -- Doesnt necessarily   need to be axis, could just be perp
    local buffer = sm.vec3.closestAxis(startLine.outVector)*2 -- Multiply for faster cars or laggier races
    local wall1 = startLine.location + (axis * sideWidth)
    local wall2 = startLine.location + (axis * -sideWidth) -- TODO: store in nodeMap or self instead of calculating every time...
    local bound = {left = wall1, right = wall2, buffer = buffer}
    --local 
    local frontLocation = self.location + (self.shape:getAt() *  self.carDimensions['front']:length()) -- check for linecross of this loc
    local crossing = withinBound(frontLocation,bound)
    --print(self.newLap,crossing)
    local now
    
    if crossing and self.newLap == false then
        self.newLap = true
        self.currentLap = self.currentLap + 1 -- and then do other lap stuff here too TODO: Ensure it only crosses once
        local lineOffset = offsetAlongVector(frontLocation,startLine,buffer) -- use outvector instead
        local dif = frontLocation.y - startLine.location.y -- TODO: store this difference and use it to dispute photo finishes
        
        now = CLOCK()
        local lapTime = now - (self.lapStarted or 0)
        self.lapStarted = now
        local split = 0
        -- check if first car to cross
        

        if not self.raceControlError then -- TODO: crosscheck with race control by lap and crossover time
            --print(self.currentLap,getRaceControl().currentLap,self.racePosition)
            if self.currentLap > getRaceControl().currentLap and self.racePosition > 1 then
                if getRaceControl().leaderID == nil then
                    print(self.id,"Confirmed leader nil lead",now)
                    self.racePosition = 1
                else
                    --print(self.id, "possibly first instead",self.racePosition)
                    if getDriverFromId(getRaceControl().leaderID).currentLap < self.currentLap then
                        print(self.id,"Confirmed leader over",getRaceControl().leaderID,now)
                        self.racePosition = 1
                    end
                end
            end

            if getRaceControl().leaderTime ~= nil then

                split = now - getRaceControl().leaderTime 
                -- Determine race positions based off of split
                
                if self.racePosition == 1 then 
                    split = 0
                end
            end
            if self.bestLap == 0 then
                --print("Initial best lap")
                if self.currentLap > 1 then -- Lap 1 doesnt count, warmup lap
                    self.bestLap = lapTime
                end
            elseif lapTime < self.bestLap  then
                --print("New best lap!",split)
                self.bestLap = lapTime
            end

            
            if self.currentLap < getRaceControl().currentLap then
                self:determineRacePosBySplit()
            else
                self.raceSplit = split
                self:determineRacePosBySplit()
            end
            
            self.lastLap = lapTime

            self:sv_sendCommand({car = self.id, type = "lap_cross", value = now}) -- maybe calculate dif between laps? keep running avg?
            if self.racePosition == 1 then print() end -- separator
            local output = self.tagText .. ": " .. "Position: " .. self.racePosition .. " Current Lap: " .. self.currentLap .. " Split: " .. string.format("%.3f",split) ..
                          " Last: " .. string.format("%.3f",lapTime) .. " Best: " .. string.format("%.3f",self.bestLap)
            --print(self.id,self.racePosition,self.currentLap,self.handicap,split,lapTime,self.bestLap)
            sm.log.info(output)
        end

    end
    if self.raceFinished and self.displayResults and not self.resultsDisplayed then
        local displayString = "#aa7777"..self.tagText .. "#FFFFFF: Position: #00aa00" ..self.racePosition .. " #ffffffSplit: #aaaa00".. string.format("%.3f",self.raceSplit) .. " #ffffffBest: #aaaa00" .. string.format("%.3f",self.bestLap)
        --print(displayString)
        self:sv_sendChatMessage(displayString)
        self.resultsDisplayed = true
        -- Show Data on NameTag too?
    end
    
    
    
    if self.currentNode.id < (#self.nodeChain/2) +1 and self.currentNode.id > (#self.nodeChain/2) -1 and self.newLap == true then -- TODO: find more dynamic sweet spot
        self.newLap = false
    end
    --print(self.id,self.racePosition)
end

function Driver.determineRacePos(self) -- constantly? checks car nodes, laps and positions to determine who is in the lead
    if self.raceFinished then return end-- dont update racePosition
    local leader = nil
    local leaderNodes = nil
    local racePos = 1  -- default to first
    drivers = getAllDrivers()
    if drivers == nil or #drivers == 0 then
        print("No drivers found")
    end
    for k=1, #ALL_DRIVERS do local racer=ALL_DRIVERS[k]
        
        if racer.id ~= self.id then -- if not self 
            --print(racer.id,racer.totalNodes,self.totalNodes,self.currentLap,racer.currentLap)
            
            if racer.totalNodes > self.totalNodes or racer.currentLap > self.currentLap then -- if competitor has hit more nodes than self
                racePos = racePos + 1
                
            elseif racer.totalNodes == self.totalNodes then
                if self.opponentFlags[racer.id] ~= nil then
                    local vhDif = self.opponentFlags[racer.id].vhDist -- Should probably do relative to track and not car direction
                    if vhDif.vertical > 0 then -- if opp is in front, stay down pos
                        racePos = racePos + 1
                        --print(self.id,"behind",vhDif.vertical,racePos)
                    end
                else
                    --print("opp not found")
                end
            end
        end
    end
    --print(self.id,self.racePosition)
    if self.racePosition ~= racePos then
        --print(self.id,racePos)
        self.racePosition = racePos
    end

    if self.racePosition == 1 then -- New leader
        if not self.raceControlError then 
            getRaceControl().leaderID = self.id
        end
    end
    

end

function Driver.determineRacePosBySplit(self) -- When Called, checks split from leader
    local leader = nil
    local leaderNodes = nil
    local racePos = 1  -- default to first
    for k=1, #ALL_DRIVERS do local racer=ALL_DRIVERS[k]
        if racer.id ~= self.id then -- if not self 
            if racer.currentLap > self.currentLap then -- opp ahead
                racePos = racePos + 1
            elseif racer.currentLap == self.currentLap then -- opp on same lap
                if self.raceSplit > racer.raceSplit then -- if race split broken then just skip?
                    --print(self.id,"race split inccrease")
                    racePos = racePos + 1
                elseif self.raceSplit == racer.raceSplit then
                   -- print(self.id,"CARS TIED?")
                    if self.velocity < racer.velocity then
                        racePos = racePos + 1
                        --print("I'm slower so bleh")
                    elseif self.velocity == racer.velocity then
                        --print("Wea re the same speed??")
                        -- check miniscule distance?
                        --racePos = racePos + 1 -- TODO: Actually do somethin gabout this
                    end 
                else -- car behind
                end
            end
        end
    end
    --print(self.id,self.racePosition)
    if self.racePosition ~= racePos then
        --print(self.id,racePos)
        self.racePosition = racePos
    end

    if self.racePosition == 1 then -- New leader
        if not self.raceControlError then 
            getRaceControl().leaderID = self.id
        end
    end
end

--[[ Caution flag strategy
validate self (return end)
local lane = self.currentNode.width/4? or 3
local formationPos = false -- whether car is in proper race pos
local cautionPosition = getCautionPos (from race control?)
local followDistance = 15 -- Distance to follow other cars +- 2?

if self.racePosition > self.cautionPos then -- behind
    self.trackPosBias = -lane -- stay on left to speed up
    self.speedControl = 40? -- something faster
elseif self.racePosition < self.cautionPos then -- in front
    self.trackPosBias = lane -- stay on right to slow down
    self.speedControl = 20? -- something slower
else -- Exactly at caution pos
    self.trackPosBias = 0 -- stay in middle
    self.speedControl = 30
    formationPos = true -- trigger next step
end

if formationPos then
    print(self.carRadar)
    if self.carRadar == nil then return end
    if self.carRadar.front == 0 then -- nobody tyhere? speed up?


*/]]

function Driver.updateCarData(self) -- Updates all metadata car may need (server)
    if self.shape:getBody():isStatic() then -- car on lift
        self.onLift = true
        self.nodeFindTimeout =0 -- --TODO: I think this may cause issues if car has failed scan while on lift during race reset??
        self.stuckTimeout = 0
        self.lost = false
        self.strategicThrottle = 0
        if self.scanningError == true then
            self.carDimensions = self:generateCarDimensions()
            self.frontColDist = self.carDimensions['front']:length() + self.vPadding
            self.rearColDist = self.carDimensions['rear']:length() + self.vPadding 
            self.leftColDist= self.carDimensions['left']:length() + self.hPadding 
            self.rightColDist= self.carDimensions['right']:length() + self.hPadding 
            if self.carDimensions == nil then
                self:sv_sendAlert("Car scan failed,Er")
                self.scanningError = true
            else
                self:sv_sendAlert("Car scan Successful")
                self.scanningError = false
            end
        end
    else
        self.onLift = false
    end
    if self.engine == nil or self.engine.engineStats == nil then self.noEngineError = true end
    if getDriverFromId(self.id) == nil then
        print("driver Re adding to race")
        self:addRacer()
    end
    local raceControl = getRaceControl()
    if raceControl == nil then
        if not self.raceControlError then
            print("No race Control")
            self.raceControlError = true
        end
    end
    
    if self.speed > 2 and not self.noEngineError then
        local force = sm.vec3.new(0,0,1)*-(self.speed^1.6)  -- TODO: Check for wedges/aero parts, tire warmth factor too
        --print(self.speed*10)
        -- if downforce enabled
        if self.velocity.z < -0.1 and not self.tilted then -- falling down
            --print(self.id,"vertical",self.velocity.z)
            sm.physics.applyImpulse(self.shape.body,sm.vec3.new(0,0,120),true,self.shape.at*1.4) -- should not be negative, and 100
            
        elseif self.velocity.z > 0.4 then -- going up
            --print(self.id,"Boost")
            --sm.physics.applyImpulse(self.shape.body,self.shape.at*900,true) -- really shouldnt be a thing
        else -- in between
            sm.physics.applyImpulse(self.shape.body,force,false)--,--self.shape.at)
        end 
    end
   -- HAve flag for when car is airborne, have it stop or slow down wheels
    --print(self.pathGoal)
    
    self.body = self.shape:getBody()
    if self.carDimensions == nil then
        --print("location")
        --print("updating location",self.location,self.shape.worldPosition)
        self.location = self.shape:getWorldPosition() --self.body.worldPosition
    else
        if self.carDimensions['center'] then
            if self.carDimensions['center']['rotation'] and self.carDimensions['center']['length'] then
                local rotation  =  self.carDimensions['center']['rotation']
                local newRot =  rotation * self.shape:getAt()
                local newCenter = self.shape:getWorldPosition() + (newRot * self.carDimensions['center']['length'])
                self.location = newCenter
                --print("locatin",newCenter.z,self.shape.worldPosition.z)
            end
        end
    end
    self.velocity = sm.shape.getVelocity(self.shape)
    self.angularVelocity = self.body.angularVelocity
    if math.abs(self.speed - self.velocity:length()) > 2 then
        --print(self.tagText,"crash detected",self.speed,self.velocity:length())
    end
    self.speed = self.velocity:length()
    self.futureLook = self:calculateFutureTurn()
    --print(self.speed,self.curGear,self.engine.VRPM)
    self.trackPosition = self:calculateTrackPos()
    self.goalDirection = self:calculateGoalDirection()
    self.goalDirectionOffset = self:calculateGoalDirOffset()
    self.followStrength = self:calculateNodeFollowStrength()
    --self.trackPosBias = self:calculateTrackPosBiasTurn()
    self.angularSpeed = self.angularVelocity:length() -- Moving here so we only need to calculate once
    self.mass = self.body.mass -- possibly not need
    
    if self.speed <= 13 then
        --print(self.id,"slow",self.curGear,self.engine.VRPM,self.speed,self.strategicThrottle)
    end
    if self.racing then
        self:determineRacePos()
        self:checkLapCross()
    end
    --print(self.mass)
    -- update Current states
   
end

function Driver.updateStrategicLayer(self) -- Runs the strategic layer  overhead (server)
    -- GEt cahraccteristic logic and race state and do stuff here
    if not self.trackLoaded then -- introduce timeout to prevent spamming
        print("strategic loading map")
        self.nodeChain = self:sv_loadData(TRACK_DATA) -- Track data could contain racing lines and everything else
        -- Etheir send to server/clients that track is loade or just generate map directly
        if self.nodeChain ~= nil then
            self.totalSegments = getNextItem(self.nodeChain,1,-1).segID
            if self.nodeMap == nil then -- possibly only do if necessary
                print("Generating node map")
                self.nodeMap = generateNodeMap(self.nodeChain)
            end
        end
    end
    if self.raceFinished then -- or caution flag?
        self.speedControl = 10 -- Make it vary
    elseif self.racing and self.caution or self.formation then
        --self.speedControl = 0
        -- Passing off speedcontrol to strategic steering FCY and formation module
    else
        self.speedControl = 0
    end

    if not self.lost then
        self:updateNearestNode()
        if self.lost then return end --TODO: Add searching algo to figure out bet way to get on track, possibly fly?
        self:updateGoalNode()
        if self.lost then return end
        self:updateStrategicSteering(self.pathGoal) -- Get goal from character layer (pit,mid,race)
        if not self.noEngineError and self.currentNode ~= nil then
            self:updateStrategicThrottle()
        end
        
    else
        self:updateNearestNode() -- TODO: Fix this...
        self.speedControl = 0
    end

end


function Driver.parseParents( self ) -- Gets and parses parents (check for car
    --print("Parsing Parents")
	local parents = self.interactable:getParents()
    if #parents == 0 then
        if self.seatConnected then
            print("driver seat disconnected")
            self.seatConnected = false
            self.userPower = 0
            self.userSteer = 0
            self.userSeated = false
            self.userControl = false
        else
            if userControl then
                userControl = false
            end
           -- noop
        end
    elseif  #parents == 1 then 
        -- only seat connected?
    end
	for k=1, #parents do local v=parents[k]--for k, v in pairs(parents) do
		--print("parsparents",v:hasOutputType(sm.interactable.connectionType.seated))
		local parentColor =  tostring(sm.shape.getColor(v:getShape()))
        if v:hasOutputType(sm.interactable.connectionType.seated) then
            if not self.seatConnected then
                print("driver seat connected")
                self.seatConnected = true
            else
                local active = v:isActive() -- if someone in seat
                local power = v:getPower() -- accel/deceleration (-1,0,1)
                local steer = v:getSteeringAngle() -- steering (-1,0,1)
                self.userPower = power
                self.userSteer = steer
                self.userSeated = active
                if not active then
                    if self.userControl then
                        self.strategicThrottle = -1
                    end
                end
                -- reset userControl to false??
                --print("inputs",active,power,steer)
            end
        else
            --
        end
    end

	
end


function Driver.server_onFixedUpdate( self, timeStep )
    --print(self.id,self.location.z)
    -- First check if driver has seat connectd
    self:parseParents()
    if self.body ~= self.shape:getBody() then
        --print(self.id,"updating body?",self.body)
        self.body = self.shape:getBody()
    end
    if self.shape:getBody() == self.body then -- double check this
        self:updateCarData()
        if self.raceControlError and self.RCE_timeout < 20 then
            self:try_raceControl()
            self.RCE_timeout = self.RCE_timeout + 1
        else
            if self.RCE_timeout == 20 then
                print("Error: can not find race control",self.RCEtiem)
                self.RCE_timeout = self.RCE_timeout + 1
            end
        end
        -- update Car logic if car is loaded
        --print(self.tagText,self.liftPlaced,self.onLift)
        if self.lost and self.trackLoaded then
            if self.liftPlaced and self.onLift  then -- if progam placed lift and creation on it
                print(self.id,"lost and on reset lift")
                sm.player.removeLift(self.player)
                self.liftPlaced = false
            elseif self.onLift then
                print(self.id,"on playerlift?")
            end
        end
        
        if self.liftPlaced and self.onLift then
            print(self.tagText,"on reset lift",self.lost,self.liftPlaced)
            sm.player.removeLift(self.player)
            self.liftPlaced = false
        end

        if self.trackLoaded and not self.lost then -- Maybe have a full load check not just track
            if self.lostError then
                print(self.tagText,"Not lost anymore",self.onLift,self.liftPlaced)
                if self.onLift and self.liftPlaced then
                    sm.player.removeLift(self.player)
                    self.liftPlaced = false
                end
                self.lostError = false
            end
            self:updateStrategicLayer() -- intermitent?
            -- only run if everything valid?
            self:updateErrorLayer()

            -- Read character layer here?
            --print(self.racing,self.curGear,self.strategicThrottle,self.curVRPM)
            if self.racing == false and not self.userControl then
                self.strategicThrottle = -1
                self:shiftGear(1)
                --print("heh")
                self:updateControlLayer()
            else
                --- Check racemode?
                self:updateCollisionLayer()
                --self:newUpdateCollisionLayer() TODO: plan out and finish this, needs better location prediction 
                if not self.noEngineError and (self.racing or self.userControl) and not self.shape:getBody():isStatic() then
                    self:checkOversteer()
                    self:checkUndersteer() -- TODO: Combine??
                    self:checkStuck()
                    self:checkOffTrack()
                    self:updateGearing()
                    self:checkTilt()
                    self:checkWide()
                end
                --print("2 update race control")
                self:updateControlLayer()
            end

                -- Update error detection layer
           
        elseif self.lost and self.lostError == false then -- Do what you can to make way back?
            print(self.tagText,"is lost")
            self.strategicThrottle = -1
            self.lostError = true
        elseif self.lost and self.carResetsEnabled then
            self:resetPosition(false)
        end

    else
        print(self.id,"body id mismatch")
    end
end

function Driver.client_onFixedUpdate(self,timeStep)
    if self.showingVisuals then
        self:updateVisuals()
    end
    if not self.trackLoaded and sm.isHost then -- introduce timeout to prevent spamming
        self:loadTrackData(TRACK_DATA) -- continuously load track data?
    end
    --local filter = sm.interactable.connectionType.seated + sm.interactable.connectionType.bearing + sm.interactable.connectionType.power
	--local currentConnectionCount = #self.interactable:getChildren( filter ) -- can connecto to lights and engine! without crazy loading thing
end

function Driver.try_raceControl(self)
    local raceControl = getRaceControl()
    if raceControl == nil then
        --print("attempt rc try",self.RCE_timeout)
    else
        print("found RC",self.RCE_timeout)
        self.raceControlError = false
        self.RCE_timeout = 0
        self:sv_sendCommand({car = {self.id}, type = "get_raceStatus", value = 1})
    end
end

function Driver.sv_toggleUserControl(self,toggle)
    if toggle then
        --self.carResetsEnabled = false
    else
        --self.carResetsEnabled = true
    end
    self.userControl = toggle
end

function Driver.cl_toggleUserControl(self) -- toggles user control
    if not self.userControl then
        self:cl_showChatMessage("#ffff55SMAR: #ffffffUser Control #55ff55Enabled")
        self:sv_toggleUserControl(true) -- I know there is a more efficient way to do this but readability is important too
    else
        self:cl_showChatMessage("#ffff55SMAR: #ffffffUser Control #ff5555Disabled")
        self:sv_toggleUserControl(false)
    end
end

-- Debug information and visuals

function Driver.client_onInteract(self,character,state)
    -- if driver active, then toggle userControl
    if state then
        if self.userSeated then
            --print("toggle ai",self.userSeated)
            self:cl_toggleUserControl()
            return
        end

        if character:isCrouching() then
            self:cl_hard_reset()
            if self.carData == {} or self.carData == nil then
                print("No car data found, rescan?")
                if self.shape:getBody():isStatic() then
                    print("start scan")
                end
            end
            local metaData = {   
            ['ID'] = 13, -- actual car id
            ['Car_Name'] = "Dirty Drafter",
            ['Car_Type'] = "Stock",
            ['Body_Style'] = "Bently",
            }
            self.network:sendToServer("sv_add_metaData",metaData) --TODO: MAKE SURE THIS IS On/off appropriately
       else
        self.debug = not self.debug
        print("setting debug",self.debug)
        if self.debug then
            self:hardUpdateVisual()
        else
            self:hideVisuals()
        end
       end
   end
end

function Driver.testAcceleration(self,timeStep)
    if self.testFinished then
        if self.speed > 2 then
            self.strategicThrottle = 1
        elseif self.speed < 2 then
            self.strategicThrottle = -0.1
        end
        return
    end
    local testSpeed = 30
   local start = false
   local bDist = getBrakingDistance(self.speed,self.engine.MAX_BRAKE,0)
   --self.strategicThrottle = 1
   --print(bDist)
    if self.testStarted == 0 and start then
        print("starting test")
        self.initSpeed = self.speed
        self.initTime = CLOCK()
        self.testStarted = 1
    elseif self.testStarted == 1 then -- acceleration
        --print(self.speed)
        if self.speed >= testSpeed then
            local timeTaken = CLOCK() - self.initTime 
            local acceleration = (self.speed-self.initSpeed)/ timeTaken
            print("AccelFinished",self.speed,timeTaken,acceleration)
            self.initSpeed = self.speed
            self.initTime = CLOCK()
            self.testStarted = -1
        else
            self.strategicThrottle = 1
        end
    elseif self.testStarted == -1 then
        if self.speed <= 0.5 then
            local timeTaken = CLOCK() - self.initTime 
            local acceleration = (self.speed-self.initSpeed)/ timeTaken
            print("DecelFinished",self.speed,timeTaken,acceleration)
            self.testFinished = true
        else
            self.strategicThrottle = -1
        end
    end



end

function Driver.updateVisuals(self) -- TODO: Un comment this when ready
    if self.goalNode == nil then return end
    if self.effectsList == nil then return end
    if self.carDimensions == nil then return end
    if not self:valididtyCheck() then return end
    --print(self.carDimensions)
    local center = self.shape.worldPosition
    
    if self.goalNodeEffect ~= nil then 
        self.goalNodeEffect.pos = self.goalNode.location -- self.body:getCenterOfMassPosition() -- Separate out to race or not race
    end
    if self.currentNodeEffect ~= nil then
        self.currentNodeEffect.pos = self.goalNode.location + (self.goalOffset or sm.vec3.new(0,0,0))--+ self.body:getLocalAabb()\
    end
    if self.calcCenterEffect ~= nil then
        self.calcCenterEffect.pos = self.location
    end
    
    if self.frontEffect ~= nil and self.leftEffect~= nil and self.rightEffect ~= nil and self.rearEffect ~= nil then
        self.frontEffect.pos = center +  self.shape.at*self.carDimensions['front']:length()
        self.leftEffect.pos = center -  self.shape.right*self.carDimensions['left']:length()
        self.rightEffect.pos = center + self.shape.right*self.carDimensions['right']:length()
        self.rearEffect.pos = center -  self.shape.at*self.carDimensions['rear']:length()
    end

    local splitFormat = string.format("%.3f",self.raceSplit)
    local rpmFormat = string.format("%.2f",self.engine.curRPM)
    local speedFormat = string.format("%.2f",self.speed)
    self.idTag:setText( "Text", "#ff0000"..self.tagText .. " #00ff00"..speedFormat .. " #ffff00"..splitFormat) -- TODO: Have overlays that show race position and time splits and speeds
    --print(self.shape.worldPosition.z-self.location.z)
    --print(self.shape.right,)
    for j=0, #self.effectsList do local effectD = self.effectsList[j] -- separate out to movable/unmovable fx
        if effectD ~= nil then
            if effectD.effect:isPlaying() then
                --print(effectD)
                effectD.effect:setPosition(effectD.pos)
            end
        end
    end
end

function Driver.showVisuals(self)
    --print("debug information",self.effectsList)
    self.idTag:open()
    for j=0, #self.effectsList do local effectD = self.effectsList[j]
        if effectD ~= nil then
            if not effectD.effect:isPlaying() then
                --print("starting")
                effectD.effect:start()
            end
        end
    end
    self.showingVisuals = true
end

function Driver.hideVisuals(self)
    --print("hiding debug visuals")
    self.idTag:close()
    for j=0, #self.effectsList do local effectD = self.effectsList[j]
        if effectD ~= nil then
            if effectD.effect:isPlaying() then
                effectD.effect:stop()
            end
        end
    end
    self.showingVisuals = false
end
    
function Driver.hardUpdateVisual(self)
    self:hideVisuals()
    self:showVisuals()
end

function getLocal(shape, vec)
    return sm.vec3.new(sm.shape.getRight(shape):dot(vec), sm.shape.getAt(shape):dot(vec), sm.shape.getUp(shape):dot(vec))
end


function Driver.determineFrictionCoefficient(self)
    --local force = self.shape.right* 1000
    --print("pushing",force:length())
    sm.physics.applyImpulse(self.shape.body,force,true)
    if self.location ~= sm.shape.getWorldPosition(self.shape) then
        if not self.sliding then
            print("Car Start slide")
            self.slideStarted = CLOCK()
            self.slideStartLocation = self.location
            self.sliding = true
        else
            local distanceSlid = getDistance(self.slideStartLocation,self.location)
            --print("slid",distanceSlid)
            if distanceSlid >= 1 then
                local slideStopped = CLOCK()
                local timeTook = slideStopped - self.slideStarted
                local Fnet = (2 * self.mass * distanceSlid) / timeTook^2 
                local Fapplied = force:length()
                local normal = self.mass * DEFAULT_GRAVITY
                local frictionForce =  Fapplied - Fnet

                print("Finished measurment",distanceSlid, timeTook,Fnet,Fapplied,normal,frictionForce)
                self.sliding = false
            end
        end
    end
    --print(self.mass)
    local weight = self.mass * DEFAULT_GRAVITY
    local normal = weight
    local fricCo = 10
    local blockMass = 35.15
    local wheelMass = 138.05
end

function Driver.testFriction(self,timeStep) -- Runs test to see how friction works
    local turnRadius = 0
    local lockSteer = degreesToSteering(turnRadius)
    local speedLimit = 4
    local accel = 0.005
    local throttle = 0
    local steeringVector = degreesToVector(turnRadius)
    local speed = self.speed
    --local steerDif = angleDiff(self.velocity + steeringVector,self.velocity)
    local frontDif = 0
    local realDif = 0
    local lateralAccel = 0
    local angSpeed = self.angularSpeed
    local latDif = 0
    --print(sm.vec3.length(steeringVector),steeringVector)
    if sm.vec3.length2(self.velocity) ~= 0 then
        lateralAccel = speed/turnRadius --( or do vector divided by vector?)
        --testLateral = self.velocity/steeringVector
        realDif = sm.vec3.length(sm.vec3.normalize(self.shape.at)-sm.vec3.normalize(self.velocity))
        --print(realDif)
        frontDif = angleDiff(self.shape.at,sm.vec3.normalize(self.velocity))
        latDif = lateralAccel*14 * getSign(turnRadius) - angSpeed
    end
    local angLenAvg = angularAverage(self,angSpeed)
    local fricAvg = runningAverage(self,realDif)
    local speedAvg = runningAverage2(self,speed)
    local fDiffAvg= runningAverage3(self,realDif)

    self.maxSpeed = checkMax(self.maxSpeed,speedAvg)
    self.maxFriction = checkMax(self.maxFriction,fricAvg)
    self.maxLatAcc = checkMax(self.maxLatAcc,lateralAccel)
    self.maxAngVel = checkMax(self.maxAngVel,angLenAvg)
    self.maxFrontDif = checkMax(self.maxFrontDif,fDiffAvg)


    --print(string.format("AVG: Speed: %.3f, Friction: %.3f, latAccel: %.3f, Angular Vel: %.3f, FrontDif: %.3f",speedAvg,fricAvg,lateralAccel,angLenAvg,fDiffAvg))
    --print(string.format("MAX: Speed: %.3f, Friction: %.3f, latAccel: %.3f, Angular Vel: %.3f, FrontDif: %.3f",self.maxSpeed,self.maxFriction,self.maxLatAcc,self.maxAngVel,self.maxFrontDif))
    if speed < speedLimit then
        throttle = accel
    end
    if speed > speedLimit then
        throttle = -accel
    end
    self:outputThrotttle(throttle)

end

function angularAverage(self,num)
    local runningAverageCount = 1000
    if self.angularAverageBuffer == nil then self.angularAverageBuffer = {} end
    if self.nextAngularAverage == nil then self.nextAngularAverage = 0 end
    
    self.angularAverageBuffer[self.nextAngularAverage] = num 
    self.nextAngularAverage = self.nextAngularAverage + 1 
    if self.nextAngularAverage >= runningAverageCount then self.nextAngularAverage = 0 end
    
    local runningAverage = 0
    for k, v in pairs(self.angularAverageBuffer) do
      runningAverage = runningAverage + v
    end
    --if num < 1 then return 0 end
    return runningAverage / runningAverageCount;
end

function runningAverage(self, num)
    local runningAverageCount = 1000
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

function runningAverage2(self, num)
    local runningAverageCount = 1000
    if self.runningAverageBuffer2 == nil then self.runningAverageBuffer2 = {} end
    if self.nextRunningAverage2 == nil then self.nextRunningAverage2 = 0 end
    
    self.runningAverageBuffer2[self.nextRunningAverage] = num 
    self.nextRunningAverage2 = self.nextRunningAverage2 + 1 
    if self.nextRunningAverage2 >= runningAverageCount then self.nextRunningAverage2 = 0 end
    
    local runningAverage = 0
    for k, v in pairs(self.runningAverageBuffer2) do
      runningAverage = runningAverage + v
    end
    --if num < 1 then return 0 end
    return runningAverage / runningAverageCount;
end

function runningAverage3(self, num)
    local runningAverageCount = 100
    if self.runningAverageBuffer3 == nil then self.runningAverageBuffer3 = {} end
    if self.nextRunningAverage3 == nil then self.nextRunningAverage3 = 0 end
    
    self.runningAverageBuffer3[self.nextRunningAverage] = num 
    self.nextRunningAverage3 = self.nextRunningAverage3 + 1 
    if self.nextRunningAverage3 >= runningAverageCount then self.nextRunningAverage3 = 0 end
    
    local runningAverage = 0
    for k, v in pairs(self.runningAverageBuffer3) do
      runningAverage = runningAverage + v
    end
    --if num < 1 then return 0 end
    return runningAverage / runningAverageCount;
end

function clearRunningBuffers(self)
    -- angAvg
    self.angularAverageBuffer = nil
    self.nextAngularAverage = nil

    self.runningAverageBuffer = nil
    self.nextRunningAverage = nil

    self.runningAverageBuffer2 = nil
    self.nextRunningAverage2 = nil

    self.runningAverageBuffer3 = nil
    self.nextRunningAverage3 = nil
end