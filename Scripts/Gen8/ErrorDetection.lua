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
    if self.stuckCooldown[1] == true then -- cooldown actvie
        if self.stuckCooldown[2] == nil then -- check if location  is set
            if self.location == nil then -- both are nil
                --print("stuck coolwon both nil")
                --print(self.tagText,"stuckcooldown")
                return
            else -- location exists
                self.stuckCooldown[1] = false
                --print(self.tagText,"stuck[12] false")
                return
            end
        else -- location node exista
            local dist = getDistance(self.stuckCooldown[2],self.location)
            if dist < 0.7 then -- if car is still within small dist
                --print(self.tagText,"stuck?",dist)
                return 
            else
                self.stuckCooldown[1] = false
                --print(self.tagText,"stuckfalse")
                return
            end
        end
    end



    local offset = posAngleDif3(self.location,self.shape.at,self.goalNode.location)
    --print(offset,self.goalDirectionOffset)
    --print("hah",self.engine.curRPM)
    --print(self.speed,toVelocity(self.engine.curRPM),self.curGear, offset) -- Get distance away from node? track Dif?
    if math.abs(offset) >= 30 or math.abs(self.goalDirectionOffset) > 8.5 then 
        --print("Stuck?",offset,self.goalDirectionOffset,self.speed)
        if self.speed <= 4 and not self.userControl then
            --print(self.tagText,"offset stuck",offset,self.speed,self.goalDirectionOffset)
            self.stuck = true
            return
        end
        
    end
    --print(self.stuck,self.speed,toVelocity(self.engine.curRPM))
    if  toVelocity(self.engine.curRPM) - self.speed > 2.5 then -- if attempted speed and current speed > 2
        --print(self.tagText,self.speed)
        if self.speed <= 4  and not self.userControl then
            --print(self.tagText,"slow stuck",self.speed,self.engine.curRPM,toVelocity(self.engine.curRPM))
            self.stuck = true
            return
        end
    end
    if self.rejoining == false and self.stuck and self.offTrack == 0 and self.speed > 2.5 then -- check this
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


function Driver.updateErrorLayer(self) -- Updates throttle/steering based on error fixing
    if self.engine == nil then return end
    if self.engine.engineStats == nil then return end
    if self.goalNode == nil or self.currentNode == nil then return end

-- Check tilted
    --print(self.currentNode.location.z,self.currentNode.mid.z)
    if self.tilted== true then 
        if self.debug  then
            print(self.tagText,"correcting tilt")
        end
        local offset = sm.vec3.new(0,0,0)
		--local angularVelocity = self.shape.body:getAngularVelocity()
		--local worldRotation = self.shape:getWorldRotation()
		local upDir = self.shape:getUp()
		--print(angularVelocity)
		--print(worldRotation)
		--print(upDir)
		-- Check if upside down,
		local stopDir = self.velocity * -1.1
        if sm.vec3.closestAxis(upDir).z == -1 then
            local weight =self.mass * DEFAULT_GRAVITY
		    stopDir.z = self.mass/2.5
            --print(self.mass/3)
            --print("flip")
        else
            
            stopDir.z = self.mass/11
        end
		
		offset = upDir * 4
		if self.shape:getWorldPosition().z >= self.currentNode.location.z + 3 then 
			stopDir.z = -450 -- maybe anti self.weight?
			--offset = 
		end
		sm.physics.applyImpulse( self.shape.body, stopDir,true,offset)
    end
-- Check oversteer and understeer
    if self.oversteer and self.goalNode then
        local offset = self.goalDirectionOffset
        self.rotationCorrect = true
       --print(self.id,"oversteer correct",offset,self.speed, self.strategicThrottle)
        --self.pathGoal = "mid"
        if self.strategicThrottle >= 0 then  
            self.strategicThrottle = self.strategicThrottle - 0.05 -- begin coast
            -- reduce steering?
            if math.abs(offset) > 14 or self.speed > 23 then
                --print(self.speed)
                self.strategicThrottle = ratioConversion(10,35,0.9,1,self.speed) -- Convert x to a ratio from a,b to  c,d
                --print("ovrsteer overspeed thrott",self.speed,self.strategicThrottle)
            else
                self.strategicThrottle =self.strategicThrottle -0.01 -- coast
            end
        end
    end

    if self.understeer and self.goalNode and not self.oversteer then
        local offset = self.goalDirectionOffset
        --print(self.id,"understeer correct",offset,self.speed, self.strategicThrottle)
        self.rotationCorrect = true
        if self.strategicThrottle >= 0 then  -- Do this when not "braking"
            self.strategicThrottle = self.strategicThrottle - 0.05
            --print(self.id,"understeerCorrect",self.strategicThrottle)
            if math.abs(offset) > 13 or self.speed > 24 then
                self.strategicThrottle = ratioConversion(10,35,0.9,1,self.speed) -- Convert x to a ratio from a,b to  c,d
                --print("understeer overspeed thrott",self.speed,self.strategicThrottle)
                if self.speed <= 10 then
                    self.strategicThrottle = 0.4
                    self.strategicSteering = self.strategicSteering/2
                    --print("half steer")
                end
            else
                self.strategicThrottle = self.strategicThrottle - 0.01 -- coast
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
        --print(self.id,"fix rotate",self.angularVelocity:length(),self.goalDirectionOffset, self.speed,self.strategicThrottle)
        if self.speed < 15 and  math.abs(self.goalDirectionOffset) > 3 and self.angularVelocity:length() > 0.7 then -- counter steer
            self.strategicSteering = self.strategicSteering / -10
            --print(self.tagText,"counterSteer?")
        end
        
        if self.speed < 18 or self.angularVelocity:length() < 1 and math.abs(self.goalDirectionOffset) < 1 then
            self.rotationCorrect = false
            self.speedControl = 0
            --self.strategicThrottle = self.strategicThrottle - 0.01
            --print("rotation fixed?")
        end
        if self.speed >20 then
           --print("over speed rotatin correct")
            --print("brake",self.speed)
            self.strategicThrottle = self.strategicThrottle - 0.05
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

    local wallSteer = 0
    if hitR and rData.type == "terrainAsset" then
        local dist = getDistance(self.location,rData.pointWorld) 
        if dist <= 6 then
            wallSteer = ratioConversion(8,0,0.05,0,dist)  -- Convert x to a ratio from a,b to  c,d
            --print(self.tagText,"right",dist,wallSteer)
        end
        if dist < 1 then
            self.strategicThrottle = self.strategicThrottle - 0.01
        end
    end

    if hitL and lData.type == "terrainAsset" then
        local dist = getDistance(self.location,lData.pointWorld) 
        --print(dist)
        if dist <= 6  then
            --print("left",dist)
            wallSteer = ratioConversion(8,0,0.05,0,dist) * -1  -- Convert x to a ratio from a,b to  c,d
            --print(self.tagText,"left",wallSteer)
        end
        if dist < 1 then
            --print(self.tagText,"wallSlowfront")
            self.strategicThrottle = self.strategicThrottle - 0.01
        end
    end

    local frontPredictR = frontLoc + (self.shape.at *8 + self.shape.right *6)
    local frontPredictL = frontLoc + (self.shape.at *8 + self.shape.right *-6)

    local hitR,rData = sm.physics.raycast(frontLoc,frontPredictR,self.body) 
    local hitL,lData = sm.physics.raycast(frontLoc,frontPredictL,self.body)
    
    if hitR and rData.type == "terrainAsset" then
        local dist = getDistance(self.location,rData.pointWorld) 
        if dist <= 5 then
            wallSteer = wallSteer + ratioConversion(8,0,0.05,0,dist) *1  -- Convert x to a ratio from a,b to  c,d
            --print(self.tagText,"right",dist,wallSteer)

        end
        if dist < 1 then
            self.strategicThrottle = self.strategicThrottle - 0.01
        end
    end

    if hitL and lData.type == "terrainAsset" then
        local dist = getDistance(self.location,lData.pointWorld) 
        --print(dist)
        if dist <= 5 then
            --print("left",dist)
            wallSteer = wallSteer +  ratioConversion(8,0,0.05,0,dist) * -1  -- Convert x to a ratio from a,b to  c,d
            --print(self.tagText,"left",walStwallSteereer)
        end
        if dist < 1 then
            --print(self.tagText,"wallSlowside")
            self.strategicThrottle = self.strategicThrottle - 0.01
        end
    end

    -- try to stay within tracklimits (exeption on overtake?)
    local trackAdj = 0
    --if self.trackPosition == nil then return end
    local tDist = sideLimit - math.abs(self.trackPosition)
    if tDist <10 then
        if self.trackPosition > 0 then
            trackAdj = ratioConversion(10,0,0.1,0,tDist) *1  -- Convert x to a ratio from a,b to  c,d    
        else
            trackAdj = ratioConversion(10,0,0.1,0,tDist) *-1 -- Convert x to a ratio from a,b to  c,d 
        end
        --print(self.tagText, "track limit",trackAdj,tDist)
    
        if self.passing.isPassing or math.abs(wallSteer) > 0 then -- dampen/strenghen? limits
            --trackAdj = trackAdj *0.95
            --print("Track lim test",trackAdj)
        end
    end
    --print(self.trackPosition,sideLimit,tDist,trackAdj,wallSteer)
    self.strategicSteering = self.strategicSteering + wallSteer + trackAdj-- Maybe not desparate?


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
                        self.strategicThrottle = 0.95
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
                    self.strategicThrottle = 0.95
                end

            elseif self.curGear > 0 then -- If moving forward to rejoin
                local segID = self.currentSegment
                
                local segBegin = self:getSegmentBegin(segID)
                local segEnd = self:getSegmentEnd(segID)
                local segLen = self:getSegmentLength(segBegin.segID)
                local maxSpeed = calculateMaximumVelocity(segBegin,segEnd,segLen) 
                --print(self.tagText,"gear > 0",self.strategicThrottle,toVelocity(self.engine.curRPM))
                if toVelocity(self.engine.curRPM) > 5 and  self.speed <= math.abs(toVelocity(self.engine.curRPM)) -1 then -- Stuck going forward
                    if self.speed <= 2 then
                        --print("rejoin stuck",toVelocity(self.engine.curRPM),self.speed,self.trackPosBias)
                        local distanceThreshold = -50 -- make dynamic?
                        local clearFlag = self:checkForClearTrack(distanceThreshold)
                        if clearFlag then
                            --print("cleaaar")
                            self.stuckTimeout = self.stuckTimeout + 1
                            self.curGear = -1
                            self:shiftGear(-1)
                            self.strategicThrottle = 0.95
                            local curentSide = self:getCurrentSide()
                            --print("Rejoining backwards",self.trackPosition,curentSide)
                            self.trackPosBias = curentSide
                        else
                            self.strategicThrottle = -1
                        end
                    end
                end
                self.strategicThrottle = 0.5 -- until otherwise?
                --print(self.tagText,"rejoining",offset,dist,self.speed,maxSpeed,self.engine.curRPM,self.strategicThrottle)
                
                
                if (self.speed >= maxSpeed - 5 and toVelocity(self.engine.curRPM) >= maxSpeed - 5 and self.offTrack == 0) or (self.curGear >=5 and self.offTrack == 0) then
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
               self.strategicThrottle = 0.5
               self.rejoining = true
               self.stuck = false
               self.trackPosBias = 0 -- reset bias...
               self.stuckTimeout = self.stuckTimeout + 5
            end

        else -- start rejoin process (only if car has tried going forward)
            if self.engine.curRPM > 1 and self.curGear >=0 then
                --print("slowing to reverse?",self.engine.curRPM)
                self.strategicThrottle = -1
            else -- Check for clear entry point then reverse

                local distanceThreshold = -55 -- make dynamic?
                local clearFlag = self:checkForClearTrack(distanceThreshold)
                if clearFlag then
                    local curentSide =0 -- 0 self:getCurrentSide() TODO:get right and finsih
                    --print("Rejoining",self.trackPosition,curentSide)
                    self.trackPosBias = curentSide
                    self.rejoining = true
                    self.curGear = -1
                    self:shiftGear(self.curGear)
                    --print("reeversing begin",self.curGear,self.engine.curRPM)
                    self.strategicThrottle = 0.6
                    self.strategicSteering = self.strategicSteering * -1.4
                else -- stay stopped
                    self.strategicThrottle = -1
                end
            end
        end
    end
    
-- Check Offtrack
    if self.offTrack ~= 0 and not self.userControl then
        --print(self.id,"offtrack",self.offTrack)
        if self.speed < 15 then -- speed rejoin
            self.strategicSteering = self.strategicSteering --+ self.offTrack/90 --? when at high speeds adjust to future turn better?
            --print(self.id,"offtrack correction", print(self.id,"offtrack",self.goalDirectionOffset))
            self.strategicSteering = self.strategicSteering - (self.goalDirectionOffset/(math.abs(self.offTrack) +0.1))
            --print("start rejoining?")
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
                    --print(self.tagText,"Spinout??",self.goalDirectionOffset,self.strategicThrottle)
                    self.goalOffsetCorrecting = true
                else
                    if self.goalOffsetCorrecting then 
                        self.goalOffsetCorrecting = false
                    end
                end

            else -- car turning
                --print("turn",self.goalDirectionOffset)
                if math.abs(self.goalDirectionOffset) > 3.2 then -- if too much turn
                    --print(self.tagText,"Turn offDirection Adjust")
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
                    --print(self.tagText,"Turn Spinout??",self.goalDirectionOffset,self.strategicThrottle)
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
    -- cautijon check
    if self.caution then
        self:checkCautionPos()
    end

    if self.formation then
        self:checkFormationPos()
    end


end