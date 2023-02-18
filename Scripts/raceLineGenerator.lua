-- This will Generate the racing line generator, hoepfuly it works
--- This is just a non function draft to get the mnath down
-- TODO: IDEA, Possibly load nodes based off of scanned terrain tile UUID from preset stored nodes (prevents bad scans on user side)
    -- Have preset track nodes saved in folder, and open them if track scanner senes the tile uuid
-- TODO: Make Scanner more sensitive to corners/straights
dofile "Timer.lua" 
local nodePrev = {loc= sm.vec3.new(0,1,1), id = 1, pevious = nil, next = node, totalForce = 0, energy = 0}
local nodeNext = {loc= sm.vec3.new(0,1,1), id = 1, pevious = node, next = nil, totalForce = 0, energy = 0}

local node = {loc= sm.vec3.new(0,1,1), id = 1, pevious = nodePrev, next = nodeNext, totalForce = 0, energy = 0,inVector = sm.vec3.new(0,0,0),outVector = sm.vec3.new(0,0,0)}
-- SMARL Track Generator V2.0
-- Copyright (c) 2020 SaltySeraph --
--trackTracecr.lua 
--[[
	- This is experimental tech that follows along a race track and attempts to map it out into three different parts: Left Wall, Right Wall, & Center Line
    - V1.5 removes physical car following and learning, purely virtual scanning to perform scans much quicker and more accurate
    - V2.0 Changes scanning function to follow any race track with walls
]]
dofile "globals.lua"

Generator = class( nil )
Generator.maxChildCount = -1
Generator.maxParentCount = -1
Generator.connectionInput = sm.interactable.connectionType.power + sm.interactable.connectionType.logic
Generator.connectionOutput = sm.interactable.connectionType.power + sm.interactable.connectionType.logic
Generator.colorNormal = sm.color.new( 0xffc0cbff )
Generator.colorHighlight = sm.color.new( 0xffb6c1ff )
local clock = os.clock --global clock to benchmark various functional speeds ( for fun)



-- Local helper functions utilities
function round( value )
	return math.floor( value + 0.5 )
end

function Generator.client_onCreate( self ) 
	self:client_init()
	print("Created Track Generator")
end

function Generator.client_onDestroy(self)
    print("Generator destroyed")
    if self.effect:isPlaying() then
        self.effect:stop()
    end
    self:stopVisualization()
end

function Generator.client_init( self )  -- Only do if server side???
	--dofile( "util.lua")
	self.id = self.shape.id
	-- Initial Data goes here (Started/stopped and what not)
    self.location = sm.shape.getWorldPosition(self.shape)
    self.dampening = 0.05 -- how little to move smoothing
    self.scanSpeed = 4 -- how small to move in vector direction during midline scan
	self.scanning = false
    self.smoothing = false
    self.scanLocation = self.location
    self.scanVector = self.shape.at
    self.trackStartDirection =self.shape.at
    self.nodeChain = {}
    self.effectChain = {}
    self.debugEffects = {}
    self.effect = sm.effect.createEffect("Loot - GlowItem")
    self.effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    self.effect:setPosition(self.location)
    self.visualizing = false
    self.showSpeeds = false
    self.showSegments = true
    self.started = 0
    self.globalTimer = 0
	self.gotTick = false
    self.scanClock = 0
    self.scanLength = 6000
    self.asyncTimeout = 0-- Scan speed [0 fast, 1 = 1per sec]
    self.asyncTimeout2 = 0 -- optimizawtion speed
    self.nodeIndex = 1 -- 1 is the first one
    self.totalDistance = 0
    self.totalForce = 0
    self.avgSpeed = 0
    self.maxSpeed = nil
    self.minSpeed = nil

    self.lastDif = 0
    self.smoothEqualCount = 0
    self.smoothAmmount = 5 -- how many smoothing iterations to do in preprocess
    self.saveTrack = true

    self.segSearch = 0
    self.segSearchTimeout = 100

    self.debug = true -- Debug flag
    self.instantScan = false
    self.instantOptimize = false -- Scans and optimizes in one loop
    -- error states
    self.scanError = false
    self.errorLocation = nil

    self.showWalls = false -- show wall effects (reduces total allowed effects)
	print("Track Generator V2.0 Initialized at ",self.location,self.shape.at)
end


function Generator.server_onCreate(self)
    self.spawnedBodies = {}

end


function Generator.client_onRefresh( self )
	self:client_onDestroy()
	self:client_init()
end

function sleep(n)  -- freezes game?
  local t0 = clock()
  while clock() - t0 <= n do end
end

function Generator.asyncSleep(self,func,timeout)
    --print("weait",self.globalTimer,self.gotTick,timeout)
    if timeout == 0 or (self.gotTick and self.globalTimer % timeout == 0 )then 
        --print("timeout",self.globalTimer,self.gotTick,timeout)
        local fin = func(self) -- run function
        return fin
    end
end

function getDirectionFromFront(self,precision) -- Precision fraction 0-1
	local front = self.shape.getAt(self.shape)
	--print(front)
	if front.y >precision then -- north?
		--print("north") 
		return 0
	end

	if front.x > precision then
		--print("east")
		return 1
	end
	
	if front.y < -precision then
		--print("south")
		return 2
	end

	if front.x < -precision then
		--print("west")
		return 3
	end
	return -1
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

--visualization helpers
function Generator.stopVisualization(self) -- Stops all effects in node chain (specify in future?)
    debugPrint(self.debug,'Stoppionng visualizaition')
    for k=1, #self.nodeChain do local v=self.nodeChain[k]
        if v.effect ~= nil then
            v.effect:stop()
        end
        if v.lEffect ~= nil then
            if not v.lEffect:isPlaying() then
                v.lEffect:stop()
            end
        end
        if v.rEffect ~= nil then
            if not v.rEffect:isPlaying() then
                v.rEffect:stop()
            end
        end
    

        if v.lEffect ~= nil then
            if not v.lEffect:isPlaying() then
                v.lEffect:stop()
            end
        end
        if v.rEffect ~= nil then
            if not v.rEffect:isPlaying() then
                v.rEffect:stop()
            end
        end
    end

    if self.debug then -- only show up on debug for now
        for k=1, #self.debugEffects do local effect=self.debugEffects[k]
            if not effect:isPlaying() then
                effect:stop()
            end
        end
    end
    self.visualizing = false
end

function Generator.showVisualization(self) --starts all effects
    debugPrint(self.debug,"Starting visualization")
    for k=1, #self.nodeChain do local v=self.nodeChain[k]
        if v.effect ~= nil then
            if not v.effect:isPlaying() then
                v.effect:start()
            end
        end
        if self.showWalls then
            if v.lEffect ~= nil then
                if not v.lEffect:isPlaying() then
                    v.lEffect:start()
                end
            end
            if v.rEffect ~= nil then
                if not v.rEffect:isPlaying() then
                    v.rEffect:start()
                end
            end
        end
    end

    if self.debug then -- only show up on debug for now
        for k=1, #self.debugEffects do local effect=self.debugEffects[k]
            if not effect:isPlaying() then
                effect:start()
            end
        end
    end
    self.visualizing = true
end

function Generator.updateVisualization(self) -- moves/updates effects according to nodeChain
    for k=1, #self.nodeChain do local v=self.nodeChain[k]
        if v.effect ~= nil then
            if v.pos ~= nil then -- possibly only trigger on change
                v.effect:setPosition(v.pos)
                if self.showSpeeds then
                    if v.vMax ~= nil then
                        local color = getSpeedColorScale(self.maxSpeed,self.minSpeed,v.vMax)
                        v.effect:setParameter( "Color", color )
                    end
                end
                if self.showSegments then
                    if v.segType ~= nil then
                        local color = sm.color.new(v.segType.COLOR)
                        v.effect:setParameter( "Color", color )
                    end
                end

                if self.visualizing then
                    if not v.effect:isPlaying() then
                        v.effect:start()
                    end
                else
                    v.effect:stop()
                end
                if self.showWalls then
                    if v.lEffect ~= nil then
                        if not v.lEffect:isPlaying() then
                            v.lEffect:start()
                        end
                    end
                    if v.rEffect ~= nil then
                        if not v.rEffect:isPlaying() then
                            v.rEffect:start()
                        end
                    end
                end
            end
        end
    end

    if self.debug then -- only show up on debug for now
        for k=1, #self.debugEffects do local effect=self.debugEffects[k]
            if not effect:isPlaying() then
                effect:start()
            end
        end
    end
end

function Generator.hardUpdateVisual(self) -- toggle visuals to gain color
    self:stopVisualization()
    self:showVisualization()
end

function Generator.generateEffect(self,location,color) -- Creates new effect at param location
    
    local effect = sm.effect.createEffect("Loot - GlowItem")
    effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    effect:setScale(sm.vec3.new(0,0,0))
    local color = (color or sm.color.new("AFAFAFFF"))
    
   -- local testUUID = sm.uuid.new("42c8e4fc-0c38-4aa8-80ea-1835dd982d7c")
    --effect:setParameter( "uuid", testUUID) -- Eventually trade out to calculate from force
    --effect:setParameter( "Color", color )
    if location == nil then
        effect:setPosition(sm.vec3.new(0,0,0)) -- remove too
        effect:setParameter( "Color", sm.color.new("ff3333FF") )
        return effect
    end
    effect:setPosition(location) -- remove too
    effect:setParameter( "Color", color )
    return effect
end
-----

function Generator.generateMidNode(self,index,previousNode,location,inVector,distance,width,leftWall,rightWall,bank)
   -- print("making node",dirVector)
   -- TODO: upgrade to perpvector2?
    if inVector == nil then
        print("node gen no inVector")
    end
    return {id = index, pos = location, outVector = nil, last = previousNode, inVector = inVector, force = nil, distance = distance, perpVector = generatePerpVector(inVector), 
            midPos = location, pitPos = nil, width = width, next = nil, effect = nil, segType = nil, segID = nil, pinned = false, weight = 1, incline = 0,leftWall = leftWall,rightWall = rightWall,bank = bank} -- move effect?
end


function calculateTotalForce(nodeChain)
    local totalForce = 0
    for k=1, #nodeChain do local v=nodeChain[k]
        totalForce = totalForce + math.abs(v.force)
    end
    return totalForce
end


function Generator.getSegmentBegin(self,segID) -- parameratize by passing in nodeChain instead
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

function Generator.getSegmentLength(self,segID) --Returns a list of nodes that are in a segment, (could be out of order) (altered binary search??)
    local node = self:getSegmentBegin(segID)
    local foundSegment = false
    local finding = false
    local count = 1
    local index = 1
    while foundSegment == false do
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

function calculateTotalHorz(nodeChain)
    local totalHorz = 0
    for k=1, #nodeChain do local v=nodeChain[k]
        totalHorz = totalHorz + math.abs(v.sumHoz)
    end
    return totalHorz
end

function calculateAvgvMax(nodeChain)
    local totalVmax = 0
    local lenChain = #nodeChain
    for k=1, #nodeChain do local v=nodeChain[k]
        totalVmax = totalVmax + ( v.vMaxEst or 0 )
    end
    return totalVmax/lenChain
end

function Generator.createEfectLine(self,from,to,color) --
    local distance = getDistance(from,to)
    local direction = (to - from):normalize()
    local step = 3
    for k = 0, distance,step do
        local pos = from +(direction * k)
        table.insert(self.debugEffects,self:generateEffect(pos,(color or sm.color.new('00ffffff'))))
    end

end

function Generator.generatePerpVector2(self,direction,location,node) -- generates perpendicular vector based on last angle to wall
    if node == nil or node.last == nil then
        return generatePerpVector(direction)
    end -- generates generalized 2d perp vector
    local angleToWall = node.last.rightWall - node.last.pos  -- should be the vector to the right wall
    local angleToWall2 = generatePerpVector(direction)
    angleToWall2.z = angleToWall.z
    --print(node.last.rightWall,node.last.pos,angleToWall)
    return generatePerpVector(direction)--angleToWall

end

function Generator.getWallMidpoint(self,location,direction,cycle) -- cycle is new, determines which time it is ran to prevent annoying overlay on debug draw
    --print("originalZ",location.z)
    --print("scaning perp",direction)
    --if self.nodeChain == nil then return end
    -- TODO: figure out loopdy loops, will need to look forward instead of straight down in order to find ramps/inclines. have upsidedown tag for node aswell
    -- TODO: FIgure out fixes for bugs like goin in tunnels,scanner will break
    local searchLimit = 60 -- how far to look for walls, dynamic: self.nodechain[#self.nodeChain]].lastNode.width/2
    if self.nodeChain[self.nodeIndex -1] ~= nil and self.nodeChain[self.nodeIndex-1].width then
        searchLimit = (self.nodeChain[self.nodeIndex-1].width * 0.8 or 60)
    end
    local incline = false
    local perp = generatePerpVector(direction)-- Generates perpendicular vector to given direction - right side 
    local perp2 = self:generatePerpVector2(direction,location,self.nodeChain[#self.nodeChain])
    if perp.z ~=0 then -- perp is zerod in prior function
        --print("perp z no need",perp.z)
        perp.z = 0
    end
    local floorHeight,floorData = sm.physics.raycast(location + self.shape.up *3.5, location + self.shape.up * -60) -- TODO: balance height to prevent confusion...
    if cycle == 1 then
        --table.insert(self.debugEffects,self:generateEffect(location + self.shape.up *3.5 ,sm.color.new('ffff00ff'))) -- oarnge dot at start locationi
    end
    local floor = location.z
    if floorHeight then
        --print("local normie",floorData.normalLocal,floorData.normalWorld)
        floor = floorData.pointWorld.z + 0.6
    else
        print("could not find floor",floor)
        return nil
        -- Double check floor from higher distance?
    end
    local testLoc = location
    testLoc.z = floor
    if cycle == 1 then
        --table.insert(self.debugEffects,self:generateEffect(testLoc,sm.color.new('ff00ffff'))) -- purple dot at end locationi
    end

    -- Look Forward First to see if floor is rising in front
    -- First send node out to front and see if it hits a point at higher z than floor
    local front, frontData =  sm.physics.raycast(location,location + direction * self.scanSpeed) -- change multiplier?
    if front then -- TODO: UPGRADSE THIS TO determine last location from next location , subtract the z values and you get z slope dif
        
        local floorDif = frontData.pointWorld.z - floor
        if floorDif < -.3 then
            --print("Road is sloping up")
            floor = frontData.pointWorld.z + 0.5 -- may need to adjust?
            location.z = floor 
            --print(floor)
        end
    else
        --print(location.z - floor) -- bug, it sees going gdown but doesnt determine flat
        if location.z - floor > 0.3 then
            --print("Road going down")
            location.z = frontData.pointWorld.z
        end
    end

   
       
    --[[-- THis was old stuff commenting out for now
        local zOffsetLimit = 7 -- How far above/below to search [ may need to increase]
        local zOffset = 0 -- unecessary?
        local zStep = 0.5 -- granularitysearch sear
        local searchLocation = location + perp2*-searchLimit
        local hitL,lData = sm.physics.raycast(location, searchLocation)
        --self:createEfectLine(location,searchLocation,sm.color.new('ee127fff')) -- left is more red
        if lData.valid == false then -- TODO: add or staement to check if wall or creation is there
            print("left fail 1")
            for k= zOffsetLimit/2, -zOffsetLimit,-zStep do 
                searchLocation = (location + perp2*-searchLimit) + sm.vec3.new(0,0,k) -- angle going from flat then start moving it down
                hitL,lData = sm.physics.raycast(location,searchLocation)
                table.insert(self.debugEffects,self:generateEffect(location,sm.color.new('ff0000ff')))
                table.insert(self.debugEffects,self:generateEffect(searchLocation,sm.color.new('00ff00ff')))
                if lData.valid == false then
                    
                    print("K",k,"L Wallfailed",location,searchLocation)
                else
                    self:createEfectLine(location,searchLocation)
                    print("FoundLeftWall\n\n",searchLocation.z,location.z) -- Possibly validate here
                    break --? possibly average rest of measurements?
                end
            end
        end
        self:createEfectLine(location,lData.pointWorld,sm.color.new('ee127fff')) -- left is more red
        -- Introduce x/y Offsets if necesary
        local searchLocation = location + perp2*searchLimit
        local hitR,rData = sm.physics.raycast(location, location + perp2*searchLimit)
        --self:createEfectLine(location,searchLocation,sm.color.new('2271eeff')) -- right is more blue

        if rData.valid == false then -- TODO: ad or staement to check if wall or creation is there
            print('right fail 1')
            for k=zOffsetLimit/2, -zOffsetLimit,-zStep do 
                searchLocation = (location + perp2*searchLimit) + sm.vec3.new(0,0,k)
                hitR,rData = sm.physics.raycast(location,searchLocation)
                table.insert(self.debugEffects,self:generateEffect(location,sm.color.new('ff0000ff')))
                table.insert(self.debugEffects,self:generateEffect(searchLocation,sm.color.new('00ff00ff')))
                if rData.valid == false then
                    print("K",k,"R wallfailed")
                else
                    self:createEfectLine(location,searchLocation)
                    table.insert(self.debugEffects,self:generateEffect(rData.pointWorld,sm.color.new('ffff00ff')))

                    print("FoundRightWal",location.z,searchLocation.z,rData.pointWorld.z) -- Possibly validate here
                    break --? possibly average rest of measurements?
                end
            end
        end
        self:createEfectLine(location,rData.pointWorld,sm.color.new('2271eeff')) -- right is more blue

        --sm.debugDraw.addArrow('perp', location, location + perp*-50,sm.color.new('11aa11ff')) -- color
        --sm.debugDraw.addArrow('perp2', location, location + perp2*-50,sm.color.new('11aaaaff')) -- color
        --table.insert(self.debugEffects,self:generateEffect(location+ perp2*-50,sm.color.new('22aaeeff')))
        --table.insert(self.debugEffects,self:generateEffect(location+ perp2*50,sm.color.new('22ff11ff')))
        ]]
    -- BANKED FLAG= 0 = flat, 1 = left wall higher than right, -1 = right wall higher than left
    -- TODO: Have IT SCAN FROM BOTTOM UP instead and use closest as wall, (must avoid scanning floor)
    --- LEFT WALL SCAN
    --print({"scan from",location.z})
    local hitL, lData
    local zOffsetLimit = 5 -- How far above/below to search [ may need to increase]
    local leftZOffsetStart = location.z -- default floor level
    local lastLeftWall = nil
    if self.nodeChain[self.nodeIndex -1] ~= nil and self.nodeChain[self.nodeIndex-1].leftWall then
        lastLeftWall = self.nodeChain[self.nodeIndex-1].leftWall
        leftZOffsetStart = lastLeftWall.z
    end
    local zStep = 0.5 -- granularitysearch sear
    local searchLocation = (location + perp2*-searchLimit)
    searchLocation.z = leftZOffsetStart
    for k= zOffsetLimit, -zOffsetLimit,-zStep do 
        searchLocation = (location + perp2*-searchLimit)
        searchLocation.z =  leftZOffsetStart + k -- gives old offset and adds(subs) k to scan from top down
        hitL,lData = sm.physics.raycast(location,searchLocation)
        if cycle == 1 then
            --table.insert(self.debugEffects,self:generateEffect(location,sm.color.new('ff0000ff'))) -- red dot at start locationi
            --table.insert(self.debugEffects,self:generateEffect(searchLocation,sm.color.new('00ff00ff'))) -- green dot at scan location
        end
        if lData.valid == false then --or (hitL and lData.type ~= 'terrainAsset') then -- could not find wall
            --print("L Wallfailed",k)
        else -- we found the wall, create debug effect line
            if cycle == 1 then
                --self:createEfectLine(location,searchLocation,sm.color.new('ee127fff')) -- red ish line
                --print("FoundLeftWall",searchLocation.z,location.z) -- Validate difference/distance between walls
            end

            --print("local normieLWall",lData.normalLocal,lData.normalWorld)

            if lastLeftWall then
                local wallChange = getDistance(lastLeftWall,lData.pointWorld)
                if wallChange > 5 then  -- TODO: figure out good averag and go 2+ (so var avg is 4-5)
                    print("drastic left wall change",wallChange)
                    if cycle == 1 then
                        --self:createEfectLine(location,searchLocation,sm.color.new('ee127fff')) -- red ish line
                        table.insert(self.debugEffects,self:generateEffect(location,sm.color.new('ff0000ff'))) -- red dot at start locationi
                        --table.insert(self.debugEffects,self:generateEffect(searchLocation,sm.color.new('00ff00ff'))) -- green dot at scan location
                        table.insert(self.debugEffects,self:generateEffect(lData.pointWorld,sm.color.new('0000ffff'))) -- blue dot at wall location

                    end
                end
            end
            -- do not break, grab closest distance Bug would be when it hits floor, so break when pointWolrd.z is <0.1? of location, wont work on bankins
            --do a triangle cross check, raycast diret perpendicular (if possible,) and break when scan z gets close to cross check z
            -- OVERHAL and use normals?
            -- triangulate normal and scan like triangle, (to get perp)
            
            break --? possibly average rest of measurements?
        end
    end
    --self:createEfectLine(location,lData.pointWorld,sm.color.new('ee127fff')) -- left is more red

    ------ RIGHT WALL SCAN
    local hitR, rData
    local zOffsetLimit = 5 -- How far above/below to search [ may need to increase]
    local rightZOffsetStart = location.z -- default floor level
    local lastRightWall = nil
    if self.nodeChain[self.nodeIndex -1] ~= nil and self.nodeChain[self.nodeIndex-1].rightWall then
        lastRightWall = self.nodeChain[self.nodeIndex-1].rightWall
        rightZOffsetStart = lastRightWall.z
    end
    local zStep = 0.5 -- granularitysearch Can probably reduce
    local searchLocation = (location + perp2*searchLimit)
    searchLocation.z = rightZOffsetStart
    for k= zOffsetLimit, -zOffsetLimit,-zStep do 
        searchLocation = (location + perp2*searchLimit)
        searchLocation.z =  rightZOffsetStart + k -- gives old offset and adds(subs) k to scan from top down
        hitR,rData = sm.physics.raycast(location,searchLocation)
        
        if cycle == 1 then
            --table.insert(self.debugEffects,self:generateEffect(location,sm.color.new('ff0000ff'))) -- red dot at start locationi
            --table.insert(self.debugEffects,self:generateEffect(searchLocation,sm.color.new('00ff00ff'))) -- green dot at scan location
        end

        if rData.valid == false then -- scan ended, keep going
            --print("R Wallfailed",k)
        else -- we found the wall, create debug effect line
            if cycle == 1 then 
                --self:createEfectLine(location,searchLocation,sm.color.new('2271eeff')) -- blue ish line
                --print("FoundRighttWall",location.z,lData.pointWorld.z) -- Validate difference/distance between walls
            end
            --print("local normieRWall",rData.normalLocal,rData.normalWorld)
            if lastRightWall then
                local wallChange = getDistance(lastRightWall,rData.pointWorld)
                if wallChange > 5 then 
                    print("drastic Right wall change",wallChange)
                    if cycle == 1 then
                        --self:createEfectLine(location,searchLocation,sm.color.new('2271eeff')) -- blue ish line
                        table.insert(self.debugEffects,self:generateEffect(location,sm.color.new('ff0000ff'))) -- red dot at start locationi
                        --table.insert(self.debugEffects,self:generateEffect(searchLocation,sm.color.new('00ff00ff'))) -- green dot at scan location
                        table.insert(self.debugEffects,self:generateEffect(rData.pointWorld,sm.color.new('0000ffff'))) -- blue dot at wall location

                    end
                end
            end
            break --? possibly average rest of measurements?
        end
    end
    --self:createEfectLine(location,lData.pointWorld,sm.color.new('2271eeff')) -- right is more blue
    -- END WALL SCAN, more validation and error handling
    if not lData or lData.valid == false then
        print('Left wall invalid')
    end
    if not rData or rData.valid == false then
        print("right wall invalid")
    end

    if not lData.valid or not rData.valid then
        print("Something went wrong While scanning track")
        -- Just Return Best Guess Which is just location but new floor
        self.scanError = true
        self.errorLocation = location
        
        return location
    end
    wallLeft = lData.pointWorld
    wallRight = rData.pointWorld
    --wallLeft.z = floor -- used to have this but idk why
    --wallRight.z = floor
    --print("leftWall",wallLeft,"rightWall",wallRight)
    local midPoint = getMidpoint(wallLeft,wallRight)
    midPoint.z = floor -- prevent wonky spacing during banks
    local width = getDistance(wallLeft,wallRight) -- -1 padding?
    local bank = 0
    if wallLeft.z - wallRight.z > 3 then -- If left wall is 3? higher than right wall, it is banked right
        bank = 1
    elseif wallRight.z - wallLeft.z > 3 then -- if right wall is 3? hgihter than left wall, it is banked left
        bank = -1
    end -- else bank is 0
    
    return midPoint, width,wallLeft,wallRight,bank
end


function Generator.analyzeSegment(self,initNode,flag) -- Attempt # 4
    if initNode == nil then print("Error No init node") return end
    local index = initNode.id
    local turnThreshold = 0.1 -- how much track curves before considering it a turn [0.1]
    local straightThreshold = 0.04 -- how straight track needs to be before considered straight [0.02]4?
    for k = index, #self.nodeChain do local node = self.nodeChain[k]
        if node.next.id == self.nodeChain[1].id then
            print("found end",node.id)
            return node,flag, true
        end
        if flag == 0 or flag == nil then -- on straight most likely
            local angle = getNodeAngle(initNode,node)
            print(node.id,"node angle",angle,turnThreshold)
            if angle > turnThreshold then -- Turning right
                print(node.id,"right")
                return node,1,false 
            elseif angle < -turnThreshold then -- Turning left
                print(node.id,"left ")
                return node,-1,false 
            else -- continueing straight
                print(node.id,"straight")
            end
        elseif flag == 1 then
            --print("1 turn node",node.id,node.force,straightThreshold)
            if node.force < straightThreshold then -- if node is straight or turning left?
                if node.next.force < straightThreshold then -- node is confirmed staight or turning left
                    return node,0,false -- possibly return -1 if the force is <0
                else
                    --print("Tricky node moved turning right")
                end
            end
        elseif flag == -1 then
            --print("-1 turn node",node.id,node.force,-straightThreshold,node.force < -straightThreshold)
            if node.force < -straightThreshold then -- if node is straight or turning right
                if node.next.force > -straightThreshold then -- confirmed straight or turning right
                    return node,0,false -- possibly return 1 if forces are both >0 or smaller turn thresh?\
                else
                    --print("Tricky node moved on turning left")
                end
            end
        end
    end

end

function Generator.backTraceSegment(self,initNode,startNode) -- goes backwards and finds beginning of turn + 3 nodes
    if initNode == nil then print("Error No init node") return end
    local index = startNode.id - 1
    local lastAngle = nil
    local numStraight = 0
    local straightThreshold = 0.3 -- angle difference before not considered straight line
    local straightCutoff = 4 -- how many straight nodes found before cutting of segment
    --local turnDir = 0
    --local turnThreshold = 2 -- how steep curve must be before apex is triggered
    for k = index, 1,-1 do local node = self.nodeChain[k]
        if node.id == self.nodeChain[1].id or node.id == initNode.id then
            --print("found beginning",node.id)
            return node
        end
        
        -- determine if node is the last node of last segment then quit
        local angle = getNodeAngle(initNode,node)
        --print(node.id,"b:",angle, math.abs(angle - (lastAngle or 0)) )

        if lastAngle == nil or math.abs(angle - lastAngle) < straightThreshold then
            --print("found straight")
            numStraight = numStraight + 1
        else
            --print("found curve") -- maybe keep track of turn angle
            lastAngle = angle
            numStraight = 0
            -- will need to account for quick reversals, set threshold? and if it crosses then end that turn too
        end

        if numStraight >= straightCutoff then
            --print("end of curve")
            numStraight = 0
            return node
            -- Begin for loop that searches backwards?
        end
    end

end

--segment analyzer attempt # 5 
function Generator.analyzeSegment5(self,initNode) -- Attempt # 5
    if initNode == nil then print("Error No init node") return end
    local index = initNode.id
    local apexNode = nil
    local apexAngle = 0
    local lastAngle = 0
    local numStraight = 0
    local straightThreshold = 0.3 -- angle difference before not considered straight line
    local straightCutoff = 3 -- how many straight nodes found before cutting of segment
    local turnDir = 0
    local turnThreshold = 2 -- how steep curve must be before apex is triggered
    
    for k = index, #self.nodeChain do local node = self.nodeChain[k]
        if node.next.id == self.nodeChain[1].id then
            print("found end",node.id)
            startNode = self:backTraceSegment(initNode,node) -- TODO: figure this out
            return startNode,node, true
        end
        
        local angle = getNodeAngle(initNode,node)
        --print(node.id,"f:",angle)

        if apexNode ~= nil then -- continue down curve until straight path found or reversal of turn
            if math.abs(angle - lastAngle) < straightThreshold then
                --print("continue straight")
                numStraight = numStraight + 1
            else
                --print("curve continue")
                lastAngle = angle
                numStraight = 0
                -- will need to account for quick reversals, set threshold? and if it crosses then end that turn too
            end

            -- reversal angle = 
            if numStraight >= straightCutoff then
                --print("curve ends")
                startNode = self:backTraceSegment(initNode,apexNode)
                numStraight = 0
                --print("returning:",startNode.id,node.id)
                return startNode,node,false -- just stop it for now, return start and end nodes eventually
                -- Begin for loop that searches backwards?
            end
        else
            if angle > turnThreshold then
                --print("right Turn apex")
                apexNode = node
                lastAngle = angle
                apexAngle = angle
            end
            if angle < -turnThreshold then
                --print("left Turn apex")
                apexNode = node
                lastAngle = angle
                apexAngle = angle
            end
        end
    end
end

function Generator.scanTrackSegments(self) -- Pairs with analyze Segments TODO: run a filterpass over segments and combine all like/adjacent segments into one segID
    local firstNode = self.nodeChain[1]
    local segID = 1
    local done = false
    local finished = false
    local flag = nil
    local startNode, endNode, finished = self:analyzeSegment5(firstNode) -- returns segment start and end
    --print("First scan got", startNode.id,endNode.id)
    local lastNode
    local firstSegment = getSegment(self.nodeChain,firstNode,startNode) -- discover if there is segment before first "turn segment"
    --print("betweenSeg?",#firstSegment,firstNode.id,startNode.id)
    if #firstSegment > 1 then
        local type,angle = defineSegmentType(firstSegment)
        print(segID,"Setting Between segment (start)",firstNode.id,startNode.id,type.TYPE,angle)
        local output = segID.." setting between seg at start, " .. firstNode.id .. " - " .. startNode.id .. " : " .. type.TYPE
        sm.log.info(output)
        setSegmentType(firstSegment,type,angle,segID)
        segID = segID + 1
        --lastNode = startNode
        --startNode
    else
        sm.log.info("no between seg at start")
    end
    local segment = getSegment(self.nodeChain,startNode,endNode)
    local type,angle = defineSegmentType(segment)
    print(segID,"setting first segment",startNode.id,endNode.id,type.TYPE,angle)
    local output = segID.." setting first segment " .. startNode.id .. " - " .. endNode.id .. " : " .. type.TYPE
    sm.log.info(output)
    setSegmentType(segment,type,angle,segID)
    segID = segID + 1
    lastNode = endNode
     -- store whatever the last node was to find between segments
    
    local scanTimeout = #self.nodeChain + 1
    local timeoutCounter = 0
    while not done do
        
        startNode = endNode.next
        lastNode = startNode -- store last segment end
        startNode,endNode,finished = self:analyzeSegment5(startNode)
       
        -- check for segment between
        local betweenSeg = getSegment(self.nodeChain,lastNode,startNode) -- discover if there is segment before first "turn segment"
        --print("betweenseg?",#betweenSeg,lastNode.id,startNode.id)
        if #betweenSeg > 1 then -- If there is no segment between last turn and next turn
            --print("set between seg")
            local type,angle = defineSegmentType(betweenSeg)
            print(segID,"setting between segment",lastNode.id,startNode.id,type.TYPE,angle)
            local output = segID.." setting between segment " .. lastNode.id .. " - " .. endNode.id .. " : " .. type.TYPE
            sm.log.info(output)
            setSegmentType(betweenSeg,type,angle,segID)
            segID = segID + 1
        else -- set a segment between them first
            --print(segID,"no between seg",#betweenSeg)
        end    
        -- Acutally set turn segment
        local segment = getSegment(self.nodeChain,startNode,endNode)
        local type,angle = defineSegmentType(segment)
        print(segID,"setting segment type",startNode.id,endNode.id,type.TYPE,angle)
        local output = segID.." setting next segment " .. startNode.id .. " - " .. endNode.id .. " : " .. type.TYPE
        sm.log.info(output)
        setSegmentType(segment,type,angle,segID)

        if finished then -- TODO: Figure if this will still work
            -- Check between then set final segment?
            print("Analysis complete",segID,endNode.id)
            done = true
            break
        end

        -- Iterate forward (timeout and segment?)
        segID = segID +1 
        timeoutCounter = timeoutCounter + 1
        if timeoutCounter >= scanTimeout then 
            print("track seg scan timeout",timeoutCounter,scanTimeout)
            break
        end
    end
    print("Finish scan",segID)
    self.totalSegments = segID - 1
    print(self.totalSegments)
   
    --print(self.nodeChain[#self.nodeChain-1].id,self.nodeChain[#self.nodeChain-1].segType)
end

function Generator.generateSegments(self) -- starts loading track segments
    -- Scan and set track segments ( better results if done after optimization)
    --self:defineTrackSegments() Depreciated
    self:scanTrackSegments()
    self:hardUpdateVisual()
end

function Generator.simplifyNodeChain(self) 
    local simpChain = {}
    sm.log.info("simping node chain") -- TODO: make sure all seg IDs are consistance
    for k=1, #self.nodeChain do local v=self.nodeChain[k]
        output = v.segID .. ": " .. v.id
        sm.log.info(output)
        local newNode = {id = v.id, distance = v.distance, location = v.pos, segID =v.segID, segType = v.segType.TYPE,
                         segCurve = v.segCurve, mid = v.midPos, pit = v.pitPos, width = v.width, perp = v.perpVector, 
                         outVector = v.outVector,bank = v.bank } -- add race instead of location?-- Radius? Would define vMax here but car should calculate it instead
        table.insert(simpChain,newNode)
    end
    --print("simpchain = ",simpChain)
    return simpChain
end

-- Saving and loading?
function Generator.saveRacingLine(self) -- Saves nodeChain, may freeze game --TODO: have ways for people to send me their nodes to make track SMAR certified, (send client json? send file?)
    self.simpNodeChain = self:simplifyNodeChain()
    local data = {channel = TRACK_DATA, raceLine = true} -- Eventually have metaData too?
    self.network:sendToServer("sv_saveData",data)
    sm.gui.displayAlertText("Scan Complete: Track Saved")
end

function Generator.sv_saveData(self,data)
    debugPrint(self.debug,"Saving data")
    debugPrint(self.debug,data)
    local channel = data.channel
    data = self.simpNodeChain -- was data.raceLine --{hello = 1,hey = 2,  happy = 3, hopa = "hdjk"}
    print("saving Track")
    sm.storage.save(channel,data) -- track was channel
    saveData(data,channel) -- worldID?
    print("Track Saved")
end

function Generator.loadData(self,channel) -- Loads any data?
    local data = self.network:sendToServer("sv_loadData",channel)
    if data == nil then
        print("Data not found?",channel)
        if data == nil then
            print("all data gone",data)
        end
    end
    return data
end

function Generator.sv_loadData(self,channel)
    print("Loading data")
    local data = sm.storage.load(channel)
    print("finished Loading",data)
    return data
end

function Generator.removeNode(self,nodeID) -- removes node
    for k, v in pairs(self.nodeChain) do
		if v.id == nodeID then
			table.remove(self.nodeChain, k)
		end
    end
    -- re index
    for k, v in pairs(self.nodeChain) do
		--print(k)
        v.id = k
    end
    -- re segID
end

function Generator.getNodeVH(self,node1,node2,searchVector) -- returns horizontal and vertical distances from node1 to node2 
    -- only works on one side of pi?
    --print("getNodeP",node1.id,node1.location,"pepV",node1.perpVector,"sear",searchVector)
    --node1.pos.z = node2.pos.z
    local node1Copy,node2Copy = node1, node2
    node1Copy.z = node2Copy.z -- create fake z levels
    local goalVec = (node2.pos - node1.pos) -- multiply at * velocity? use velocity instead?
    
    local vDist = searchVector:dot(goalVec)
    local hDist = sm.vec3.cross(goalVec,searchVector).z
    
    local vhDifs = {horizontal = vDist, vertical = hDist}
    --print("vhDif",vhDifs)
    return vhDifs
end
-- MainLoop and interaction Functions


-- New ALgo? 
-- Racifying -- Pins nodes at entry/exit points for a more raceline feeling TODO:Dothis...
function Generator.racifyLine(self) -- Add heuristics? Tries to shif entry and exit nodes 
    print("setting raceify line")
    local turnMargin = 2 -- how many nodes in/out to place pinned exit point
    local pinThreshold = 5 -- how long a segment has to be to be considered for pinning -- The shorter it is, the less distance to move?
    local shiftMaxDiv = 3  -- Maximum node pin shiftiging amound (>2)
    local lastSegID = 0
    local lastSegType = nil 
    local firstFlag = false
    local lastFlag = false
    for k=1, #self.nodeChain do local node=self.nodeChain[k]
        if lastSegID == 0 and lastSegType == nil then
            firstFlag =true
            lastSegID = node.segID
            lastSegType = node.segType.TYPE
            print("Set first seg")
        end
        
        if node.segType.TYPE == "Straight" then 
            if lastSegID ~= node.segID then --- check previous segment 
                --print(node.segType.TYPE,node.segID)
                if lastSegType ~= node.segType.TYPE then 
                    local segLen = self:getSegmentLength(node.segID)
                    --print("len",segLen)
                    if segLen >= pinThreshold then -- Figure out which direciton to move node
                        local turnDirection = getSegTurn(lastSegType) -- 1 is right, -1 is left ( IF last turn was right turn, exit point should be on left, inverse segTurn)
                        if math.abs(turnDirection) > 1 then
                            turnDirection = getSign(turnDirection)
                            local maxShiftAmmount = node.width/shiftMaxDiv
                            local segDamp = segLen/2
                            local shiftAmmount = maxShiftAmmount - (maxShiftAmmount/segDamp) -- could possibly Dampen/reduce segLen
                            if shiftAmmount > node.width/2 then print("what",shiftAmmount) end
                            --print("Moving",goalTrackLocation,node.width/2,turnDirection)
                            local desiredTrackPos = node.pos + (node.perpVector * (shiftAmmount * -turnDirection))
                            print("MOVED PRe:",node.pos,shiftAmmount,turnDirection,desiredTrackPos )
                            node.pos = desiredTrackPos
                            --node.pinned = true
                            node.weight = 2.5
                        end
                    end
                end
            end
        end

        if node.segType.TYPE == "Straight" then
            local nextSegmentID = getNextIndex(self.totalSegments,node.segID,1)
            --print(nextSegmentID,self.totalSegments)
            local segNode = self:getSegmentBegin(nextSegmentID)
            if segNode.segType.TYPE ~= node.segType.TYPE then 
                local segLen = self:getSegmentLength(node.segID)
                --print("len",segLen)
                if segLen >= pinThreshold then -- Figure out which direciton to move node
                    local turnDirection = getSegTurn(segNode.segType.TYPE) -- 1 is right, -1 is left ( IF last turn was right turn, exit point should be on left, inverse segTurn)
                    if math.abs(turnDirection) > 1 then
                        turnDirection = getSign(turnDirection)
                        local maxShiftAmmount = node.width/shiftMaxDiv
                        local segDamp = segLen/2
                        local shiftAmmount = maxShiftAmmount - (maxShiftAmmount/segDamp) -- could possibly Dampen/reduce segLen
                        if shiftAmmount > node.width/2 then print("what",shiftAmmount) end
                        --print("Moving",goalTrackLocation,node.width/2,turnDirection)
                        local desiredTrackPos = node.pos + (node.perpVector * (shiftAmmount * -turnDirection))
                        print("MOVED Post:",node.pos,shiftAmmount,turnDirection,desiredTrackPos )
                        node.pos = desiredTrackPos
                        --node.pinned = true
                        node.weight = 2.5
                    end
                end
            end
        end       
        -- Update
        lastSegID = node.segID
        lastSegType = node.segType.TYPE    
    end
    print("Finish racify line")
end

--[[
function Generator.iterateSmoothing3(self) -- Will try to find smallest angle dif ( TRUE shortest path)
    for k=1, #self.nodeChain do local v=self.nodeChain[k]
        local perpV = v.perpVector
        local lessenDirection = getSign(v.force)
        --local changeVector = perpV * lessenDirection
        --print(changeVector.z)

        --- NEW calculation of hinge force
        -- Gets distance along perpV direction last and next node are
        local vhDif1 = self:getNodeVH(v,v.last,perpV)
        local vhDif2 =  self:getNodeVH(v.next,v,perpV)

        local lastC = false
        local nextC = false

        if vhDif1.vertical < 1 then
            --print("closenodeLast")
            lastC = true
        end
        if vhDif2.vertical < 1 then
            --print("closenodeNext")
            nextC = true
        end

        if getDistance(v.last.pos,v.next.pos) < 1 then
            --print("really close nodes d")
            lastC = true
            nextC = true
        end

        if lastC or nextC then -- delete middle node
            --print("Deleting node",v.id,v.pos)
            v.last.next = v.next
            v.next.last = v.last -- blip out
            --print(v.last.id,v.next.id)
            self:removeNode(v.id)
            --print(v.last.id,v.next.id,v.next.next.id,v.next.next.next.id)
            break

        end

        local sumHoz = math.deg(vhDif1.horizontal - vhDif2.horizontal) -- decrease SumHoz?
        v.sumHoz = sumHoz
        local pointAngle = math.abs(posAngleDif3(v.pos,v.inVector,v.next.pos)) * 10
        local maxV = getVmax(pointAngle)
        local smoothness = 0 -- ??
        v.vMaxEst = maxV

        -- Calculate two directions to go and check maxVest
        
        local changeDirection1 = perpV * 1--sumHoz
        local testLoc1 = getPosOffset(v.pos,changeDirection1,self.dampening)
        local testLoc1inVector = getNormalVectorFromPoints(v.last.pos,testLoc1) -- use tempPos?
        local pointAngle1 = math.abs(posAngleDif3(testLoc1,testLoc1inVector,v.next.pos)) * 10
        local maxV1 = getVmax(pointAngle1) 

        local changeDirection2 = perpV * -1 --sumHoz
        local testLoc2 = getPosOffset(v.pos,changeDirection2,self.dampening)
        local testLoc2inVector = getNormalVectorFromPoints(v.last.pos,testLoc2) -- use tempPos?
        local pointAngle2 = math.abs(posAngleDif3(testLoc2,testLoc2inVector,v.next.pos)) * 10
        local maxV2 = getVmax(pointAngle2)

        -- which bigger? -- Do something about straight tyhrehshold??
        if pointAngle1 < pointAngle2 then 
            --if pointAngle1 < pointAngle then
                if validChange(v.pos,changeDirection1,v) then
                    --print(v.id,"Faster line 1",maxV1)
                    v.pos = testLoc1
                    v.vMaxEst = maxV1
                    calculateNewForceAngles(v)
                end
            --end
        end

        if pointAngle2 < pointAngle1 then 
            --if pointAngle2 < pointAngle then
                if validChange(v.pos,changeDirection2,v) then
                    --print(v.id,"Faster line 2",maxV2)
                    v.pos = testLoc2
                    v.vMaxEst = maxV2
                    calculateNewForceAngles(v)
                end
            --end
        end
    end
    -- actually propogate
    -- Check force
    local totalForce = calculateTotalForce(self.nodeChain)
    local avgVmax = calculateAvgvMax(self.nodeChain)
    --print("force = ",totalForce)
    --print("ForceAvg = ",totalForce)
    
    local dif = math.abs(totalForce - self.totalForce)
    local sdif = avgVmax - self.avgSpeed
    --print(string.format("dif = %.3f , %.3f",dif,totalForce))
    --self.smoothEqualCount = self.smoothEqualCount + 1

    
    if math.abs(dif - self.lastDif) < 0.0002 then
        self.smoothEqualCount = self.smoothEqualCount + 1
    end

    if self.smoothEqualCount > 5 then
        debugPrint(self.debug,"Three equalinro")
        return true
    end

    self.totalForce = totalForce
    self.avgSpeed = avgVmax
    self.lastDif = dif

    self.scanClock = self.scanClock + 1
end]]


function Generator.iterateSmoothing(self) -- {DEFAULT} Will try to find fastest average velocity (short path better...)
    for k=1, #self.nodeChain do local v=self.nodeChain[k]
        local perpV = v.perpVector
        local lessenDirection = getSign(v.force)
        --local changeVector = perpV * lessenDirection
        --print(changeVector.z)

        --- NEW calculation of hinge force
        -- Gets distance along perpV direction last and next node are
        local vhDif1 = self:getNodeVH(v,v.last,perpV)
        local vhDif2 =  self:getNodeVH(v.next,v,perpV)

        local lastC = false
        local nextC = false

        if vhDif1.vertical < 1.5 then
            --print("closenodeLast")
            lastC = true
        end
        if vhDif2.vertical < 1.5 then
            --print("closenodeNext")
            nextC = true
        end

        if getDistance(v.last.pos,v.next.pos) < 1.5 then
            --print("really close nodes d")
            lastC = true
            nextC = true
        end
        if not v.pinned then
            if v.weight == 1 then 
                if lastC or nextC then -- delete middle node
                    --print("Deleting node",v.id,v.pos)
                    if v.pinned or v.weight > 1 then 
                        --print("canceling pinned removal...")
                        break
                    end
                    v.last.next = v.next
                    v.next.last = v.last -- blip out
                    --print(v.last.id,v.next.id,v.pinned,v.weight)
                    self:removeNode(v.id)
                    --print(v.last.id,v.next.id,v.next.next.id,v.next.next.next.id)
                    break
                end
            end
        end

        local sumHoz = math.deg(vhDif1.horizontal - vhDif2.horizontal) -- decrease SumHoz?
        v.sumHoz = sumHoz
        local pointAngle = math.abs(posAngleDif3(v.pos,v.inVector,v.next.pos)) * 10
        local maxV = getVmax(pointAngle)
        v.vMaxEst = maxV

        -- Calculate two directions to go and check maxVest
        
        local changeDirection1 = perpV * 1--sumHoz
        if v.weight > 1 then
            --print("Moving",self.dampening/v.weight,v.pinned)
        end
        local testLoc1 = getPosOffset(v.pos,changeDirection1,self.dampening/v.weight) -- Dampen it based v.weight
        local testLoc1inVector = getNormalVectorFromPoints(v.last.pos,testLoc1) -- use tempPos?
        local testLoc1outVector = getNormalVectorFromPoints(testLoc1,v.next.pos) -- use tempPos?
        local pointAngle1 = math.abs(posAngleDif3(testLoc1,testLoc1inVector,v.next.pos)) * 10
        local maxV1 = getVmax(pointAngle1) 

        local changeDirection2 = perpV * -1 --sumHoz
        local testLoc2 = getPosOffset(v.pos,changeDirection2,self.dampening/v.weight)
        local testLoc2inVector = getNormalVectorFromPoints(v.last.pos,testLoc2) -- use tempPos?
        local testLoc2outVector = getNormalVectorFromPoints(testLoc2,v.next.pos) -- use tempPos?
        local pointAngle2 = math.abs(posAngleDif3(testLoc2,testLoc2inVector,v.next.pos)) * 10
        local maxV2 = getVmax(pointAngle2)

        -- which bigger? -- Do something about straight tyhrehshold??
        if not v.pinned then -- only if point isn't pinned down
            if maxV1 > maxV2 + 0.02 then 
                --if maxV1 > maxV then
                    if validChange(v.pos,changeDirection1,v) then
                        --print(v.id,"Faster line 1",maxV1)
                        v.pos = testLoc1
                        v.vMaxEst = maxV1
                        calculateNewForceAngles(v)
                    end
                --end
            end

            if maxV2 > maxV1 + 0.02 then
                --if maxV2 > maxV then
                    if validChange(v.pos,changeDirection2,v) then
                        --print(v.id,"Faster line 2",maxV2)
                        v.pos = testLoc2
                        v.vMaxEst = maxV2
                        calculateNewForceAngles(v)
                    end
                --end
            end
        end
    end
    -- actually propogate
    -- Check force
    local totalForce = calculateTotalForce(self.nodeChain)
    local avgVmax = calculateAvgvMax(self.nodeChain)
    --print("vmaxAvg = ",avgVmax,totalForce)
    --print("ForceAvg = ",totalForce)
    self.scanClock = self.scanClock + 1

    local dif = math.abs(totalForce - self.totalForce)
    local sdif = avgVmax - self.avgSpeed
    --print(string.format("dif = %.3f , %.5f",dif,math.abs(dif - self.lastDif)))
    --self.smoothEqualCount = self.smoothEqualCount + 1

    
    if math.abs(dif - self.lastDif) < 0.002 then
        print("smooth",self.dampening)
        self.dampening = self.dampening/ 1.2
        self.smoothEqualCount = self.smoothEqualCount + 0.5
    end

    if self.smoothEqualCount >= 5 then
        --debugPrint(self.debug,"Three equalinro")
        return true
    end
    self.lastDif = dif
    self.totalForce = totalForce
    if self.smoothEqualCount >= 3 then
        --debugPrint(self.debug,"Three equalinro")
        return true
    end

    --self.smoothEqualCount = self.smoothEqualCount + 0.1 -- Remove, stops cscan

end

--[[ original[[
function Generator.iterateSmoothing1(self) -- failed attempt at smoothing lines, somewhat finds shortest path...
    for k=1, #self.nodeChain do local v=self.nodeChain[k]
        local perpV = v.perpVector
        local lessenDirection = getSign(v.force)
        --local changeVector = perpV * lessenDirection
        --print(changeVector.z)

        --- NEW calculation of hinge force
        -- Gets distance along perpV direction last and next node are
        local vhDif1 = self:getNodeVH(v,v.last,perpV)
        local vhDif2 =  self:getNodeVH(v.next,v,perpV)

        local lastC = false
        local nextC = false

        if vhDif1.vertical < 1 then
            --print("closenodeLast")
            lastC = true
        end
        if vhDif2.vertical < 1 then
            --print("closenodeNext")
            nextC = true
        end

        if getDistance(v.last.pos,v.next.pos) < 1 then
            --print("really close nodes d")
            lastC = true
            nextC = true
        end

        if lastC or nextC then -- delete middle node
            print("Deleting node",v.id,v.pos)
            v.last.next = v.next
            v.next.last = v.last -- blip out
            --print(v.last.id,v.next.id)
            self:removeNode(v.id)
            --print(v.last.id,v.next.id,v.next.next.id,v.next.next.next.id)
            break

        end

        local sumHoz = vhDif1.horizontal - vhDif2.horizontal
        v.sumHoz = sumHoz
        local changeDirection = perpV * lessenDirection --perpV * sumHoz
        --print(changeDirection:length())
        local distance = getDistToWall(v.pos,changeDirection)
        if distance > WALL_PADDING then -- if not too close to wall
           if math.abs(sumHoz) > FORCE_THRESHOLD then -- If the force is too strong
                --print(sumHoz)
                v.propogateLoc = getPosOffset(v.pos,changeDirection,self.dampening) --  -- Validate eventually? (check if on track or pitlane or anything else)
            else
               v.propogateLoc = v.pos
            end
        else
            v.propogateLoc = v.pos
        end
        --print(v.id,"VH DIffs:",v.force,sumHoz)
        
    end
    -- actually propogate
    for k=1, #self.nodeChain do local v=self.nodeChain[k]
        local newLocation = (v.propogateLoc or v.pos)
        local perpV = v.perpVector
        --print(v.next.id,newLocation)
        local nOutVector = getNormalVectorFromPoints(newLocation,v.next.pos)
        local nInVector = getNormalVectorFromPoints(v.last.pos,newLocation)
        local newForce = angleDiff(nInVector,nOutVector)
        local vhDif1 = self:getNodeVH(v,v.last,perpV)
        local vhDif2 =  self:getNodeVH(v.next,v,perpV)
        local nsumHoz = vhDif1.horizontal + vhDif2.horizontal

        v.pos = newLocation --check VH sum? only move if sum lower?
        v.force = newForce    
        v.sumHoz = nsumHoz 
        
    end
    -- Check force
    local totalForce = calculateTotalForce(self.nodeChain)
    local totalHorz = calculateTotalHorz(self.nodeChain)
    if totalForce > self.totalForce then 
        --debugPrint(self.debug,string.format("Force: %.3F Horz: %.3f",totalForce,totalHorz))
    elseif totalForce < self.totalForce then
        --debugPrint(self.debug,string.format("Force: %.3F Horz: %.3f",totalForce,totalHorz))
    else
        --debugPrint(self.debug,string.format("Force: %.3F Horz: %.3f",totalForce,totalHorz))
        self.smoothEqualCount = self.smoothEqualCount + 1
    end

    local dif = math.abs(totalForce - self.totalForce)
    --print(string.format("dif = %.3f , %.3f",dif,totalForce))

    self.totalForce = totalForce
    if self.smoothEqualCount > 3 then
        return true
    end
    self.scanClock = self.scanClock + 1
end]]

function Generator.scanPit(self) -- Scans just like regular but looks for pit lane if user properly bloced off track
end

function Generator.quickSmooth(self,ammount)
    local scanLen = 0
    for i = 0, ammount do -- Have seperate optimize clock?
        local finished = self:iterateSmoothing()
        if finished then
            self.smoothing = false
            self.scanClock = 0
            print("QuickSMooth did finish")
            sm.gui.displayAlertText("Optimization Finished prematurely")
            break
        end 
        scanLen = scanLen + 1
    end
end 

function Generator.iterateScan(self)
    self.nodeIndex = self.nodeIndex + 1
    --print("node",self.nodeIndex)
    local nextLocation = getPosOffset(self.scanLocation,self.scanVector,self.scanSpeed)
    --print("next location",nextLocation)
    local wallmidPoint,leftWall,rightWall,bank = self:getWallMidpoint(nextLocation,self.scanVector,0) -- new midpoint based off of previous vector
    local nextVector = getNormalVectorFromPoints(self.scanLocation,wallmidPoint)-- Measure from last node to current midPoint
    --print(nextVector)
    -- maybe smooth it? YES IT DOES
    local wallmidPoint2, width,leftWall,rightWall,bank = self:getWallMidpoint(nextLocation,nextVector,1)
    local nextLocation2 = wallmidPoint2 -- Do another nextVector?
    local nextVector2 = getNormalVectorFromPoints(self.scanLocation,wallmidPoint2)-- Measure from last node to current midPoint can remove nextVector2 if necessary, doubles as inVector

    self.scanLocation = nextLocation2
    self.scanVector = nextVector

    if nextVector == nil then
        print("nil vector")
    end

    -- Gather meta data
    
    local lastNode = self.nodeChain[self.nodeIndex -1]
    if lastNode == nil then
        print("could not find node index")
        self.scanError = true
        return true  
    end
    --print(self.nodeIndex,"lastNode",lastNode.id)
    self.totalDistance = self.totalDistance + getDistance(lastNode.pos,nextLocation2)
    local newNode = self:generateMidNode(self.nodeIndex,lastNode,nextLocation2,nextVector,self.totalDistance,width,leftWall,rightWall,bank)
    --print(nextVector.z)
    if math.abs(nextVector.z) >0.05 then
        newNode.incline = nextVector.z
        newNode.pinned = true
    end
    -- Finish calculations on previous node
    lastNode.next = newNode
    lastNode.outVector = getNormalVectorFromPoints(lastNode.pos,newNode.pos)
    lastNode.force = angleDiff(lastNode.inVector,lastNode.outVector)
    --
    -- Add effects and put into node chaing
    if leftWall == nil or rightWall == nil or nextLocation2 == nil then
        print("Error finding wall and mid location")
        print(leftWall,rightWall,nextLocation2)
    else
        local newEffect = self:generateEffect(nextLocation2)
        --print("wallEffects:",leftWall.z,rightWall.z)
        local leftEffect = self:generateEffect(leftWall + sm.vec3.new(0,0,1),sm.color.new("2244ee")) -- left wall blue
        local rightEffect = self:generateEffect(rightWall + sm.vec3.new(0,0,1),sm.color.new("22ee44")) -- right wall green
        newNode.effect = newEffect -- 
        newNode.lEffect = leftEffect --
        newNode.rEffect = rightEffect --  
    end
    
    
    table.insert(self.effectChain,self:generateEffect(nextLocation2))

    table.insert(self.effectChain,self:generateEffect(leftWall))
    table.insert(self.effectChain,self:generateEffect(rightWall))

    table.insert(self.nodeChain, newNode)

    -- Just for timeout reasons
    self.scanClock = self.scanClock + 1
    --- Check if circut is completed
    local distanceFromStart = getDistance(self.nodeChain[1].pos,newNode.pos)
    --print(distanceFromStart)
    if distanceFromStart < self.scanSpeed + 1 and self.scanClock > 3 then -- 1is padding just in case?
        local firstNode = self.nodeChain[1]
        newNode.next = firstNode -- link back to begining
        newNode.outVector = getNormalVectorFromPoints(newNode.pos,firstNode.pos)
        newNode.force = angleDiff(newNode.inVector,newNode.outVector)

        firstNode.last = newNode
        firstNode.inVector = getNormalVectorFromPoints(newNode.pos,firstNode.pos) -- or lastNode.outVector if too much
        firstNode.force = angleDiff(firstNode.inVector,firstNode.outVector)
        self.scanning = false
        local totalForce = calculateTotalForce(self.nodeChain)
        if self.debug then
            print("finished Scanning, Total Forces = ",totalForce)
        end
        self.totalForce = totalForce
        return true
    end
end

function Generator.calculateApproxSpeeds(self) -- calculates approximate speeds/changes in node segments
    for k=1, #self.nodeChain do local v=self.nodeChain[k]
        --print(self.minSpeed,self.maxSpeed)
        if v.force == nil then
            return
        end
        local force = math.abs(v.force)
        local vMax = force*5 -- Generator.calculate approximate speeds
        
        if self.minSpeed == nil or vMax < self.minSpeed  then
            self.minSpeed = vMax
        end
        if self.maxSpeed == nil or vMax > self.maxSpeed then
            self.maxSpeed = vMax
        end
        v.vMax = vMax
    end
    
end

function Generator.toggleVisual(self,nodeChain)
    print("displaying",self.visualizing)
    if self.visualizing then
        self:stopVisualization()
        self.visualizing = false
    else
        self:showVisualization()
        self.visualizing = true
    end
end

function Generator.client_onFixedUpdate( self, timeStep ) 
    --print(self.scanError)
    if self.scanError then
        self.scanning = false
        self.smoothing = false
        if not self.errorDisplayed then
            sm.gui.displayAlertText("Scan Failed: Error")
            self.errorDisplayed = true
            local errorNode = self:generateEffect(self.errorLocation,sm.color.new("EE2222FF"))
            errorNode:start()
            return
        end
    end
    if self.scanning and not self.instantScan then -- Debug scan
        local finished = self:asyncSleep(self.iterateScan,self.asyncTimeout)
        if finished then
            self.scanning = false
            self.scanClock = 0
            --print("finished Track Scan, Generating segments")
            self:quickSmooth(self.smoothAmmount)
            --self:generateSegments() original
            --print("Finished Segment Gen, Optimizing Race line")
            --self:racifyLine() on hold until further noteice
            self:startOptimization()
            
            --self:hardUpdateVisual()
            return
        end
        if self.scanClock >= self.scanLength then
            self.scanning = false
            self.scanClock = 0
            sm.gui.displayAlertText("Scan Failed: Timeout")
        end
    end
    if self.smoothing and not self.instantOptimize then  
        local finished = self:asyncSleep(self.iterateSmoothing,self.asyncTimeout2)
        if finished then
            --print("Generating segmens after optimization")
            self:generateSegments()-- testing location
            --self:printNodeChain()
            self.smoothing = false
            self.scanClock = 0
            print("finished Optimizing Track, saving")
            sm.gui.displayAlertText("Optimization Finished")
            if self.saveTrack then
                self:saveRacingLine()
            end
            self:hardUpdateVisual()
            return
        end
        if self.scanClock >= self.scanLength  or self.smoothEqualCount > 3 then
            --print("Generating segmenst smoothcount")
            self:generateSegments()-- testing location
            --self:printNodeChain()
            self.smoothing = false
            self.scanClock = 0
            print("Optimization actually finished")
            sm.gui.displayAlertText("optimization Fin")
            if self.saveTrack then
                self:saveRacingLine()
            end
            self:hardUpdateVisual()
        end
    end
    self.location = sm.shape.getWorldPosition(self.shape)
    self:tickClock()
    self:calculateApproxSpeeds()
    self:updateVisualization()
end

function Generator.tickClock(self)
    local floorCheck = math.floor(clock() - self.started)
        --print(floorCheck,self.globalTimer)
    if self.globalTimer ~= floorCheck then
        self.gotTick = true
        self.globalTimer = floorCheck
        if self.scanning then
            --self:hardUpdateVisual() 
        end
    else
        self.gotTick = false
        self.globalTimer = floorCheck
    end
    if self.debug then
        if self.scanning == false and #self.nodeChain <=1 then
            if not self.visualizing then
                self:toggleVisual(self.nodeChain)
            end
            self:startTrackScan()
        end
    end
            
end

function Generator.startTrackScan(self)
    self.started = clock()
    self.nodeIndex = 1
    sm.gui.displayAlertText("Scanning")
    local startPoint, width,leftWall,rightWall,bank = self:getWallMidpoint(self.location,self.trackStartDirection,1)
    self.scanLocation = startPoint
    self.scanVector = sm.vec3.normalize(self.trackStartDirection)
    print("Starting SCAN at",self.scanLocation,self.scanVector,self.nodeIndex)
   
    local startingNode = self:generateMidNode(self.nodeIndex,nil,startPoint,self.trackStartDirection,self.totalDistance,width,leftWall,rightWall,bank)
    table.insert(self.nodeChain, startingNode)
    if self.instantScan then -- instant game freezing scan
        while self.scanClock < self.scanLength do
            if self.scanError then
                break
            end
            local finished = self:iterateScan()
            if finished then
                self.scanning = false
                self.scanClock = 0
                print("finished Track Scan, Generating segments")
                -- quick smoothing
                
                self:quickSmooth(self.smoothAmmount)
                
                self:hardUpdateVisual()
                -- if self.optimize then
                print("Finished Segment Gen, Optimizing Race line")
                --self:racifyLine() -- Will pin nodes at entry/exit points of chain
                self:startOptimization()
                break
            end
        end
        if self.scanClock >= self.scanLength then
            self.scanning = false
            self.scanClock = 0
            sm.gui.displayAlertText("Scan Failed: Scan timed out")
            return
        end
    else -- Slower visual scan
        self.scanning = true
    end
end

function Generator.startOptimization(self)
    sm.gui.displayAlertText("Optimizing")
    if self.instantOptimize then -- Game freezing optimization loop
        while self.scanClock < self.scanLength do -- Have seperate optimize clock?
            local finished = self:iterateSmoothing()
            if finished then
                self:generateSegments()
                self.smoothing = false
                self.scanClock = 0
                print("finished Optimizing Track, saving")
                sm.gui.displayAlertText("Optimization Finished")
                if self.saveTrack then
                    self:saveRacingLine()
                end
                break
            end 
        end 
        if self.scanClock >= self.scanLength then
            self:generateSegments() -- moved segment generation to after optimization, makes more sense
            self.smoothing = false
            self.scanClock = 0
            sm.gui.displayAlertText("Track too long to optimize")
            return
        end
    else -- Slower visual optimization
        self.smoothing = true
    end
end
 
function Generator.printNodeChain(self)
    for k, v in pairs(self.nodeChain) do
		print(v.id,v.segID)
    end
end

function Generator.client_onInteract(self,character,state)
     if state then
		if character:isCrouching() then
            self:toggleVisual(self.nodeChain)
		elseif not self.scanning then
            print("Starting Scan")
            self.nodeChain = {}
            self.effectChain = {}
            self:startTrackScan()
            
		else
			print("Scan already started")
		end
	end
end
