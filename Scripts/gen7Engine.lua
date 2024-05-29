
-- SMARL CAR AI V3 (Gen 7) Engine
-- Copyright (c) 2020 SaltySeraph -- Should be much faster
--dofile "../Libs/GameImprovements/interactable.lua"

-- This just takes in acceleration input from smar driver. How engine responds can be simulated in driver or loaded from globals?
-- Engine Type will have defaults based on engine Color, map it some time
if sm.isHost then
	print("Loaded Engine Class") -- Do whatever here?
end
dofile "globals.lua" -- Or json.load?

Engine = class( nil )
Engine.maxChildCount = 20
Engine.maxParentCount = 2
Engine.connectionInput = sm.interactable.connectionType.power
Engine.connectionOutput = sm.interactable.connectionType.bearing + sm.interactable.connectionType.logic
Engine.colorNormal = sm.color.new( 0xe6a14dff )
Engine.colorHighlight = sm.color.new( 0xF6a268ff )


-- (Event) Called from Game
function Engine.server_loadWorldContent( self, data )
	sm.event.sendToGame( "server_onFinishedLoadContent" )
    self.loadingWorld = false
    --print("Engine loaded world content")
end

function Engine.server_onCreate( self ) 
    --print("Creating gen7 Engine")
	self:server_init()
	
end

function Engine.client_onCreate( self ) 
    print("Creating gen7 Engine")
	self:client_init()
end

function Engine.client_onDestroy(self)
    print("Client destroy")
    if self.effect then
        self.effect = nil
    end
end

function Engine.server_onDestroy(self)
    --print("server destroy")
    if self.driver and not self.noDriverError then
        self.driver:on_engineDestroyed(self)
    end
end

function Engine.client_onRefresh( self )
    print("engine client refresh")
	self:client_onDestroy()
    self:client_init()
end

function Engine.server_onRefresh( self )
	--self:client_onDestroy()
    self:server_onDestroy()
	--self.effect = sm.effect.createEffect("GasEngine - Level 3", self.interactable )
    --print("Engine server refresh")
    self:server_init()
    -- send to server refresh
end

function Engine.server_init( self ) 
    -- Note: put error states up front
    self.noDriverError = false
    self.noStatsError = false

	self.loaded = false
	self.id = self.shape.id
    self.carData = {} -- load car data from stored bp/storage
    self.accelInput = 0
    self.curRPM = 0 -- was engineSpeed
    self.curVRPM = 0
    self.curGear = 0
    self.engineColor = "673b00" -- or self.shape.color maybe use ID instead
    self.engineStats = {}
    self:updateType()
    self.driver = nil
   
    self.engineNoiseEnabled = true
    --print("Gen7 Engine Initialized")
end

function Engine.client_init(self)
    if self.engineNoiseEnabled then 
        -- print("loading effect")
        self.effect = sm.effect.createEffect("GasEngine - Level 3", self.interactable )
        self.effect:setParameter("gas", 1 )
        if self.effect then
            if self.effect:isPlaying() then 
                self.effect:stop()
            end
        end
    end
end

function Engine.cl_resetEngine(self) -- resets the engine (noise effect primarily)
    
    if self.engineNoiseEnabled then

        self.effect = sm.effect.createEffect("GasEngine - Level 3", self.interactable )
        if self.effect then
            if self.effect:isPlaying() then 
                self.effect:stop()
            end
            self.effect = nil
        end
        if self.effect then
            self.effect:setParameter("gas", 1 )
        end
    end
    -- self:server_init()?
    self.network:sendToServer("sv_resetEngine")
end

function Engine.sv_resetEngine(self)
    print("Engine reset")
    self:server_onRefresh()
end

function Engine.ping(self) -- checks status of engine
    print("Engine Pinged",self.noDriverError,self.engineStats,self.curRPM)
end

function Engine.setRPM(self,value)
    --print("engine speed",value,toEngineSpeed(value))
    if value == nil then value = 0 end -- error value cuz no driver
    if self.noDriverError then value = 0 end

    --local carWeight = self.body.
    local rotationstrength = 250 -- Default
    if self.driver ~= nil then 
        if self.driver.mass then
            --bvprint("got mass",self.driver.mass)
            local mass = (self.driver.mass or 5000) -- in case mass is nill
            rotationstrength = ratioConversion(0,10000,1000,100,mass)--self.driver.body.mass)
            if rotationstrength < 240 then
                rotationstrength = 240
            end

            if rotationstrength > 7000 then
                rotationstrength = 7000
            end
            -- Standardize this shit
            --print(self.driver.body.mass,rotationstrength)
        else
            print(self.driver.id, "no body?")
        end
    end

    local rotationstrength = 500
    for k, v in pairs(sm.interactable.getBearings(self.interactable )) do
        sm.joint.setMotorVelocity(v, value, rotationstrength )
    end
end

function Engine.setGear(self,gear) -- set current Gear (called from driver)
    if self.engineStats == nil or self.driver == nil then  return end
    if gear == nil or gear < -1 or gear > #self.engineStats.GEARING then print("Gear shift failed:",gear) return end
    self.curGear = gear
    --print(self.driver.id,"Gear shifted",self.curGear)
end

function Engine.getGearAccel(self,gear ) -- Gets max acceleration of a gear depending on stats
    if gear == 0 then return 0 end
    if gear < 0 then return 0.1 end -- slower acceleration for reversal
    if gear > #self.engineStats.GEARING then -- Gear is too high. should avoid this
        gear = #self.engineStats.GEARING
    end

    local maxAccel = self.engineStats.GEARING[gear]
    if maxAccel == nil then print("Gear Accel failed",gear,self.engineStats.GEARING) return 0 end
    return maxAccel
end

function Engine.getGearRPMMax(self,gear) -- gets rpm limit according to gear
 if self.engineStats == nil then return end
 if gear <=0 then return self.engineStats.REV_LIMIT end
 local limit = self.engineStats.REV_LIMIT * gear
 --print("limit",gear,limit)
 return limit
end

function Engine.getGearRPMMin(self,gear) -- gets lowest rpm limit according to gear
    if gear <= 1 then return 0 end
    local min = self.engineStats.REV_LIMIT * (gear-1)
    --print("Min",gear,min)
    return min
end

function Engine.calculateVRPM(self,gear,rpm) -- calculates virtual rpm based on gear and rpm passed
    local vrpm = nil 
    local gear = (gear or self.curGear)
    local rpm = (rpm or self.curRPM)
    local gearLimit = self:getGearRPMMax(gear)
    local gearMin = self:getGearRPMMin(gear)
    if rpm == nil or gearLimit == nil or gearMin == nil or gear == nil then return 0 end -- wait for load?
    if rpm >= gearLimit then -- OverRevving
        vrpm = self.engineStats.REV_LIMIT -- MAX VRPM 
        --print("maxvrp",vrpm)
    elseif rpm <= gearMin then 
        vrpm = 0 -- 0 vrpm
        --print("minvrp",vrpm)

    else
        vrpm = rpm % self.engineStats.REV_LIMIT -- possibly have rpm be slightly higher for each gear higher?
        --print("ElseVRP",vrpm)
    end
    --print("return",vrpm)
    return vrpm
end

function Engine.calculateRPM(self) -- TODO: Introduce power reduction as vrpm reaches Rev Limit
    -- self.curRPM self.curGear, self.engineStats.gearing
    if self.driver == nil and self.noDriverError == false then print ("NO Driver, Please connect engine to driver block") self:sv_setDriverError(true) return 0 end
    if self.curRPM == nil then print("No rpm") return 0 end
    if self.engineStats == nil or self.noStatsError then return 0 end
    if not self.driver.racing then -- slow down?
        if self.driver.userControl then
            -- noop
        else
            --print("stop car")
            self.curVRPM = 0
            return 0 -- stop car?
        end
    end
    local rpmIncrement = 0
    if self.accelInput > 0  or (self.driver.userControl and self.accelInput == -1 and self.curGear == -1) then -- throttle says accelerate
        if self.curGear >= 0 then -- increase rpm
            local maxAccel = self:getGearAccel(self.curGear) + ((self.driver.handicap or 1)/2000) -- small acceleration boos too
            --print(self.driver.id,self.driver.handiCap,self.driver.handicap/70)
            rpmIncrement = ratioConversion(0,1,maxAccel,0,self.accelInput) --+ (self.driver.handicap/200) -- TODO: replace 70 with max handicap
        
        elseif self.curGear == 0 then -- zero gear, stop engine
            return 0
        
        else -- If reversing
            if self.curRPM > -300 and not self.driver.userControl then -- if rpm is too high positive, may need to adjust/fix
                rpmIncrement = -ratioConversion(0,1,self.engineStats.MAX_ACCEL,0,self.accelInput) -- adjust rpmIncrement by throttleInput
            elseif self.driver.userControl then -- go backwards
                rpmIncrement = ratioConversion(0,1,self.engineStats.MAX_ACCEL,0,self.accelInput)
            else
                rpmIncrement = 0
            end
            --print("engineREverse",rpmIncrement)
        end
        --print("accel",self.accelInput,rpmIncrement)
    elseif self.accelInput < 0 then -- Braking
        --print(self.accelInput,self.curRPM)
        if self.curRPM > 10 then
            rpmIncrement = ratioConversion(0,-1,-self.engineStats.MAX_BRAKE,0,self.accelInput)
            if self.shape:getVelocity():length() < 1 then
                --print("Reverse speed boost")
                rpmIncrement = -10
            end
            --print("rpmInc",rpmIncrement)
        elseif self.curRPM <= 10 and self.curRPM > -10 then
            rpmIncrement = -self.curRPM -- try to stop car
            --print("normalIn",rpmIncrement)
        elseif self.curRPM < -10 then -- slowDown(speed up) car
            rpmIncrement = ratioConversion(0,-1,self.engineStats.MAX_BRAKE,0,self.accelInput)
           --print("revertse braking",rpmIncrement)
        end
        --print("brake",rpmIncrement)
    else -- EngineBrake
        if math.abs(self.curRPM) > 5 then 
            rpmIncrement = -self.curRPM/50 -- Or set engineBrake? idk
        else
            rpmIncrement = -self.curRPM/10
        end
    end
    --print(self.curGear,self.curRPM,rpmIncrement)

-- Drafting handling

    local draftTS = 0 -- * global.draftStrengthHow much to increase the top speed by ()
    if self.driver.drafting and self.accelInput >= 0.9 and getRaceControl().draftingEnabled == true then -- only work while accelerating, can get in the way of brakes
        draftTS = 5 -- * draftStrength --TODO: add draft strength UI var in RaceControl
        rpmIncrement = rpmIncrement + 0.00015 -- * global.draftStrength
    end
    -- handicap handing
    local handiTS = 0
    --print(self.driver.id,self.driver.handiCap)
    handiTS = (self.driver.handicap or 1)/24
    --print(self.driver.id,handiTS)

    --print(self.curRPM,rpmIncrement)
    local nextRPM = self.curRPM + rpmIncrement
    local nextVRPM = self:calculateVRPM(self.curGear,nextRPM)
    self.curVRPM = self:calculateVRPM(self.curGear,nextRPM)
    --print("setVrpm",self.curVRPM,nextVRPM)
    local nextVRPM = self.curVRPM
    if nextVRPM > self:getGearRPMMax(self.curGear) then -- Rev Limit Bounce
        nextRPM = self.curRPM - 5 -- TODO: Decide which bounce dist is best
        print("RevBounce")
    elseif nextVRPM < self:getGearRPMMin(self.curGear) then -- Continue to slow ? (automatic flag automatic downshift)
        -- Unsure what to do here ...sound effect?
    end
    --print(self.driver.tagText,"drafting",self.driver.drafting,draftTS,handiTS)

    --print(self.driver.id,self.driver.handicap,handiTS,draftTS,self.driver.drafting)

    -- hard limiter checcks in case of error
    if nextRPM >= (self.engineStats.MAX_SPEED or ENGINE_SPEED_LIMIT) + draftTS + handiTS and rpmIncrement > 0 then -- If car has reached what should be allowed
        if self.driver.drafting then -- and drafting enabled...
            --print(self.driver.tagText,"drafting lim reach",nextRPM)
            nextRPM =nextRPM - (rpmIncrement*1.05)
            if nextRPM > ((self.engineStats.MAX_SPEED or ENGINE_SPEED_LIMIT) + draftTS + handiTS ) +  5 then -- if over by 5 then increase reduction
                nextRPM =nextRPM - (rpmIncrement*1.1)
            end
        elseif self.driver.passing.isPassing then -- if driver is passing
            --print(self.driver.tagText,"Passing lim reach",nextRPM)
            nextRPM =nextRPM - (rpmIncrement*1.02)
        elseif nextRPM > ((self.engineStats.MAX_SPEED or ENGINE_SPEED_LIMIT) + draftTS +  handiTS) + 5 then -- if generally over speed by 5 then increase reduction
            nextRPM = nextRPM -  (rpmIncrement*1.1)
        else -- not drafting or passing ( just cooling down from it)
            --nextRPM = (self.engineStats.MAX_SPEED or ENGINE_SPEED_LIMIT) + draftTS + handiTS --old code, hard set
            nextRPM =nextRPM - (rpmIncrement*1.05) -- could be bad for engines with high acceleration...
            --print(self.driver.tagText,"General Limit reached",nextRPM,rpmIncrement)
        end
    elseif  nextRPM <= -40 then --(-self.engineStats.MAX_SPEED or -ENGINE_SPEED_LIMIT) then -- Shouldnt go anywhere near this while reversing
        nextRPM = -40 --(-self.engineStats.MAX_SPEED or -ENGINE_SPEED_LIMIT)
    end
    --print(self.driver.id,nextRPM,draftTS,handiTS)
    -- failsafe engine limiter
    if nextRPM > (self.engineStats.MAX_SPEED or ENGINE_SPEED_LIMIT) + draftTS + handiTS + 10 then -- General overspeed
        --print(self.driver.tagText,"Engine Limit Reached",nextRPM)
        --nextRPM = (self.engineStats.MAX_SPEED + draftTS + handiTS +7  or nextRPM - 0.5) -- old
        nextRPM =nextRPM -  (rpmIncrement*1.5)
    end
    --print(self.driver.tagText,"rp:",nextRPM,self.engineStats.MAX_SPEED,draftTS,handiTS,(self.engineStats.MAX_SPEED or ENGINE_SPEED_LIMIT) + draftTS + handiTS + 10)
    return nextRPM
end

function Engine.updateEffect(self) -- TODO: Un comment this when ready
	
    if self.effect == nil then
        print("reset create")
        self.effect = sm.effect.createEffect("GasEngine - Level 3", self.interactable )
    end
    if self.driver == nil or self.noDriverError == true then
       
        if self.effect then
            
            if self.effect:isPlaying() then
                print("no driver stop Effect",self.effect)
                self.effect:setParameter( "load", 0 )
                self.effect:setParameter( "rpm", 0 )
                self.effect:stop()
                return
            else
                return
            end
        else
            print("no return",self.effect)
            return
        end
    end
    
    
    if self.effect and not self.effect:isPlaying() and not self.driver.racing then
        --print("start effect",self.driver.racing,self.effect:isPlaying())
		self.effect:start()
	elseif self.effect and self.effect:isPlaying() and self.driver.racing == false then
        --print("idle")
		self.effect:setParameter( "load", 0 )
		self.effect:setParameter( "rpm", 0 )
		--self.effect:stop()
    elseif self.effect and not self.effect:isPlaying() and self.driver.racing then
        --print("not playing but racing so reset")
        --print("Reset effect")
       -- self:cl_resetEngine()
       --print("race on and not playing? start")
       self.effect:start()
    end
    local highestGear = #self.engineStats.GEARING
	local engineConversion = ratioConversion(0,self.engineStats.REV_LIMIT,1,0 + (self.curGear/9),self.curVRPM)
    local loadConvert = highestGear - self.curGear
    local loadConversion = ratioConversion(0,highestGear,0.8,0.6,loadConvert)
    --print(self.curVRPM,engineConversion,self.curGear,loadConversion)
    --print(engineConversion,self.curGear/10)

	--local brakingConversion = ratioConversion(0,1600,0,1,self.brakePower) --2000 means more breaking coolown sound
	
	--print(self.curVRPM,engineConversion,loadConversion,self.curGear)
	
	if self.effect and self.effect:isPlaying() then
		self.effect:setParameter( "rpm", engineConversion )
		self.effect:setParameter( "load", loadConversion ) --?
	end
end



function Engine.updateType(self) -- Ran to constantly check if engine is updated -- can be changed to onPainted
    --print(self.noStatsError,self.noDriverError)
    if tostring(self.shape.color) ~= self.engineColor then
        self.engineColor = tostring(self.shape.color)
        --print("loading",self.engineColor)
        self.engineStats = getEngineType(self.engineColor)
        if self.engineStats == nil then
            sm.log.error("Engine Not proper color "..self.engineColor) -- gui alert?
            if self.engineColor == "673b00ff" and self.noStatsError == false then
                self.network:sendToClients( "client_showMessage", "SMAR: Default Engine Colors have changed: Black is the new Brown\n\n") -- TODO: Make individual client and not all?
                --print("Default Engine Colors have changed: Black is the new Brown")
            end
            self.noStatsError = true
        else
            self.noStatsError = false
            print("Loaded new engine",self.engineStats)
            if self.driver then
                self.driver:on_engineLoaded(self)
            end
        end
    end
end

function Engine.parseParents( self ) -- Gets and parses parents, setting them accordingly
    --print("Parsing Parents")
	local parents = self.interactable:getParents()
    if #parents == 0 and not self.noDriverError then
        print("No Driver Detected")
        self:sv_setDriverError(true)
    elseif  #parents == 1 and self.noDriverError then 
        --print("Improper parent",#parents)
    end
	for k=1, #parents do local v=parents[k]--for k, v in pairs(parents) do
		--print("parsparents")
        local typeparent = v:getType()
		local parentColor =  tostring(sm.shape.getColor(v:getShape()))
		if tostring(v:getShape():getShapeUuid()) == "fbc31377-6081-426d-b518-f676840c407c"  then -- Driver Controller - Set acceleration 
            if self.driver == nil then
                local id = v:getShape():getId()
                local driver = getDriverFromId(id)
                if driver == nil then
                    if not self.noDriverError then
                        print("Engine No Driver Found")
                        self:sv_setDriverError(true)
                    end
                else
                    --print("found Driver") -- Validate driver too?
                    self:sv_setDriverError(false)
                    self.driver = driver
                    self.loaded = true
                    self.driver:on_engineLoaded(self) -- Sends Engine Back to Driver for cross reference
                end
            end
            if v.power ~= self.accelInput then 
				self.accelInput = v.power
			end
		end
	end
	
end


function Engine.server_onFixedUpdate( self, timeStep )
    --print(self.noDriverError,self.noStatsError )
    self:parseParents()
    self:updateType()
    if not self.noDriverError and not self.noStatsError then
        
        self.curRPM = self:calculateRPM()
        self.VRPM = self:calculateVRPM() -- calculate virtual rpm depending on gearing (mostly for sounds?)
    end
    if self.curRPM >= ENGINE_SPEED_LIMIT then -- Engine explosion noise efect smoke
        print("WARNING: OVER SPEED ENGINE",self.curRPM)
        self.curRPM = 0 
    end
    self:setRPM(self.curRPM)
end

function Engine.client_onUpdate(self,timestep) -- This oculd be a problem
	--if not sm.isHost then -- Just avoid anythign that isnt the host for now
	--	return
	--end
    if self.engineNoiseEnabled then
	    self:updateEffect()
    end
end


function Engine.sv_setDriverError(self,param) -- sets network state for driver error
    self.noDriverError = param
    self.driver = nil
    self.network:sendToClients("cl_setNoDriver",param)
end

function Engine.cl_setNoDriver(self,param) -- sets no driver to clients -- Separate out between?>
    self.noDriverError = param
    print( "Engine: Driver " .. (param and "Not Detected" or "Detected"))
end


function Engine.client_showMessage( self, params )
	sm.gui.chatMessage( params )
end


function getLocal(shape, vec)
    return sm.vec3.new(sm.shape.getRight(shape):dot(vec), sm.shape.getAt(shape):dot(vec), sm.shape.getUp(shape):dot(vec))
end


function Engine.client_onInteract(self,character,state)
    if state then
       if character:isCrouching() then
           -- more visual?
       else
            print("Resetting engine?")
            self:cl_resetEngine()
       end
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


