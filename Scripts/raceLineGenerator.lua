-- This block scans the walls of a track and creates a virtual track for cars to understand and follow
--- This is just a non function draft to get the mnath down
-- TODO: IDEA, Possibly load nodes based off of scanned terrain tile UUID from preset stored nodes (prevents bad scans on user side)
    -- Have preset track nodes saved in folder, and open them if track scanner senes the tile uuid
-- TODO: Make Scanner more sensitive to corners/straights
-- TODO: Change names to Track Scanner and Scanner class
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
    self.scanSpeed = 3 -- how small to move in vector direction during midline scan
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
   
    self.nodeIndex = 1 -- 1 is the first one
    self.totalDistance = 0
    self.totalForce = 0
    self.avgSpeed = 0
    self.maxSpeed = nil
    self.minSpeed = nil

    self.lastDif = 0
    self.smoothEqualCount = 0
    self.smoothAmmount = 10 -- how many smoothing iterations to do in preprocess
    self.saveTrack = true

    self.segSearch = 0
    self.segSearchTimeout = 100
    -- USER CONTROLABLE VARS:
    self.wallThreshold = 0.40
    self.wallPadding = WALL_PADDING -- = 5 US
    self.debug =false  -- Debug flag -- REMEMBER TO TURN THIS OFF
    self.instantScan = true
    self.instantOptimize = false -- Scans and optimizes in one loop
    self.optimizeStrength = 3
    self.racifyLineOpt = true -- Makes racing line more "racelike"
    self.asyncTimeout = 0 -- Scan speed [0 fast, 1 = 1per sec]
    
    
    self.asyncTimeout2 = 0 -- optimization speed
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
    --debugPrint(self.debug,'Stopionng visualizaition')
    for k=1, #self.nodeChain do local v=self.nodeChain[k]
        if v.effect ~= nil then
            v.effect:stop()
        end
        if v.lEffect ~= nil then
            if v.lEffect:isPlaying() then
                v.lEffect:stop()
            end
        end
        if v.rEffect ~= nil then
            if v.rEffect:isPlaying() then
                v.rEffect:stop()
            end
        end
    

        if v.lEffect ~= nil then
            if v.lEffect:isPlaying() then
                v.lEffect:stop()
            end
        end
        if v.rEffect ~= nil then
            if v.rEffect:isPlaying() then
                v.rEffect:stop()
            end
        end
    end

    
    for k=1, #self.debugEffects do local v=self.debugEffects[k]
        if v ~= nil then
            if v:isPlaying() then
                v:stop()
            end
        end
    end
    

    if self.errorNode then
        self.errorNode:stop()
    end
    self.visualizing = false
end

function Generator.showVisualization(self) --starts all effects
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
        for k=1, #self.debugEffects do local v=self.debugEffects[k]
            if not v:isPlaying() then
                v:start()
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

    if self.errorNode then
        if not self.errorNode:isPlaying() then
            self.errorNode:start()
        end 
    end

    if self.visualizing then -- only show up on debug for now
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
   -- TODO: upgrade to perpvector2
   -- TODO: remove righwallTop
    if inVector == nil then
        print("node gen no inVector")
    end
    return {id = index, pos = location, outVector = nil, last = previousNode, inVector = inVector, force = nil, distance = distance, 
            perpVector = generatePerpVector(inVector), midPos = location, pitPos = nil, width = width, next = nil, effect = nil, 
            segType = nil, segID = nil, pinned = false, weight = 1, incline = 0,
            leftWall = leftWall,rightWall = rightWall,leftWallTop = leftWallTop, rightWallTop = rightWallTop ,bank = bank} -- move effect?
end


function Generator.getSegmentBegin(self,segID) -- parameratize by passing in nodeChain instead
    if self.nodeChain == nil then
        print("no node chain")
        return
    end
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


function Generator.findTypeLimits(self,segType,startNode) -- similar to get segment begin/end but returns both directions and moves across segments
    --returns two nodes startNode, endNode
    --print("finding type limits",segType,startNode.id)
    if segType == nil or startNode == nil then return startNode, startNode end
    if startNode.segType.TYPE ~= segType then print("immediatelimitfind mismatch",segType,startNode.segType.TYPE) return startNode, startNode end

    local firstNode = nil
    local lastNode = nil

    -- Going backwards first
    --print('looking back')
    local foundChange = false
    local timeout = 0
    local node = startNode.last -- get next node
    while not foundChange do
        if timeout > 1000 then
            print("last timeout")
            break 
        end
        timeout = timeout + 1
        if node.id == startNode.id then
            print("change not found backWard",node.id,startNode.id)
            break
        end

        if node.segType.TYPE ~= segType then
            --print("found seg dif bac",node.id,node.segType.TYPE,node.next.id,node.next.segType.TYPE,segType)
            firstNode = node.next -- Grabs next node (keep on prev seg)
            foundChange = true
        end
        node = node.last -- get previous node
    end

    -- going forwardNext
    --print("looking next")
    foundChange = false
    timeout = 0
    local node = startNode.next -- get next node
    while not foundChange do
        if timeout > 1000 then
            print("next timeout")
            break 
        end
        timeout = timeout + 1
        if node.id == startNode.id then
            print("change not found forward",node.id,startNode.id)
            break
        end
        if node.segType.TYPE ~= segType then
            --print("found seg dif for",node.id,node.segType.TYPE,node.last.id,node.last.segType.TYPE,segType)
            lastNode = node.last -- Grabs last node (keep on prev seg)
            foundChange = true
        end
        node = node.next -- get next node
    end
    if firstNode == nil and lastNode == nil then
        print("Track all straight segments")
        firstNode = startNode 
        lastNode = startNode
    end
    return firstNode,lastNode
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

function Generator.getWallFlatUp(self,location,perp,cycle) -- Scans directly out to the sides to determine wall location (starts at node then goes up) good with tunnels, bad with uneven terrain
    local searchLimit = 60 -- how far to look for walls, dynamic: self.nodeChain[#self.nodeChain]].lastNode.width/2
    if self.nodeChain[self.nodeIndex -1] ~= nil and self.nodeChain[self.nodeIndex-1].width then
        searchLimit = (self.nodeChain[self.nodeIndex-1].width * 0.9 or 60)
    end

    local zOffsetLimit = 7 -- How far above/below to search [ may need to increase]
    local zOffset = 0 -- unecessary?
    local zStep = 0.5 -- granularitysearch sear
    local searchLocation = location + (perp*searchLimit)
    local hit,data = sm.physics.raycast(location, searchLocation)
    if data.valid == false then -- TODO: add or staement to check if wall or creation is there
        for k= 0, zOffsetLimit, zStep do -- Iterates z position up
            searchLocation = (location + (perp*searchLimit)) + sm.vec3.new(0,0,k) -- angle going from flat then start moving it down
            hit,data = sm.physics.raycast(location,searchLocation)
            --table.insert(self.debugEffects,self:generateEffect(location,sm.color.new('ff0000ff')))
            --table.insert(self.debugEffects,self:generateEffect(searchLocation,sm.color.new('00ff00ff')))
            if data.valid == false then
                --print("K",k,"Left wall failed",location,searchLocation)
            else
                if cycle == 1 then 
                   --self:createEfectLine(location,data.pointWorld,sm.color.new('ee127fff'))
                end
                return data.pointWorld
            end
        end
    else
        if cycle == 1 then 
            --self:createEfectLine(location,data.pointWorld,sm.color.new('ee127fff'))
        end
        return data.pointWorld
    end
end

function Generator.getWallAngleDown(self,location,perp,cycle) -- finds wall from scanning from ground to up and down (Bad with tunnels and uneven terrain)
    local searchLimit = 60 -- how far to look for walls, dynamic: self.nodeChain[#self.nodeChain]].lastNode.width/2
    if self.nodeChain[self.nodeIndex -1] ~= nil and self.nodeChain[self.nodeIndex-1].width then
        searchLimit = (self.nodeChain[self.nodeIndex-1].width * 0.9 or 60)
    end
    
    local hit, data
    local zOffsetLimit = 7 -- How far above/below to search [ may need to increase]
    local zOffsetStart = location.z -- default floor level
    local zStep = 0.5 -- granularitysearch sear
    local searchLocation = (location + (perp*searchLimit))
    searchLocation.z = zOffsetStart
    for k= zOffsetLimit, -zOffsetLimit,-zStep do -- scanning from top to bottom and below
        searchLocation = (location + (perp*searchLimit))
        searchLocation.z =  zOffsetStart + k -- gives old offset and adds(subs) k to scan from top down
        hit,data = sm.physics.raycast(location,searchLocation)
        if cycle == 1 then
            --table.insert(self.debugEffects,self:generateEffect(location,sm.color.new('ff0000ff'))) -- red dot at start locationi
            table.insert(self.debugEffects,self:generateEffect(searchLocation,sm.color.new('00ff00ff'))) -- green dot at scan location
        end
        if data.valid == false then --or (hitL and lData.type ~= 'terrainAsset') then -- could not find wall
        else -- we found a wall, create debug effect line
            if cycle == 1 then
                --self:createEfectLine(location,data.pointWorld,sm.color.new('ee127fff')) -- red ish line
            end
            return data.pointWorld
        end
    end
    
end

function Generator.cl_changeWallSense(self,amnt)
    -- increasees wall thin
    self.wallThreshold = self.wallThreshold + (0.05* amnt)
    if self.wallThreshold <= 0 then
        self.wallThreshold = 0 
    end
    local color = "#ffffff"
    if amnt < 0 then
        color = "#ffaaaa"
    elseif amnt > 0 then
        color = "#aaffaa"
    end

    sm.gui.chatMessage("Wall Detection sensitivity: "..color ..self.wallThreshold .. " #ffffffCrouch to decrease")
end

function Generator.cl_updateWallPadding(self,amnt) -- updates global wall padding var (should be cl)
    self.wallPadding = self.wallPadding + amnt
    WALL_PADDING = self.wallPadding
    sm.gui.chatMessage("Set Wall Padding to ".. self.wallPadding)
end

-- Wider scan to find the initial wall from the top down
function Generator.findWallTopDown(self,location,direction,cycle,threshold) -- scans walls from the top down and across the perp axis (BEST)
    -- Scans from location to another location from top down 
    -- original location is estimated position based off of last wall
    -- stores floor location and if floor height threshold is passed then will return wall location
   local scanHeight = threshold + 20 -- how high from location to start scan
   local perpOffset = 2 -- start 2 away from center block
   local perpLimit = 35  -- end scan dist
   local floorValue = nil
   local scanGrain = 0.25 -- Sweeet spot may need adjustment [0.25]
   local scanStart = location + (direction * perpOffset)
   scanStart.z = location.z + scanHeight
   local scanEnd = scanStart + sm.vec3.new(0,0,-scanHeight*1.5) -- scan down even further
   local foundWall = nil

   for k= perpOffset, perpLimit, scanGrain do -- scans from pre direction, to post direction
           hit,data = sm.physics.raycast(scanStart,scanEnd) -- shoot raycast down
           if cycle == 1 then
                --table.insert(self.debugEffects,self:generateEffect(scanStart,sm.color.new('1111ffff'))) -- blue dot at start location
                --table.insert(self.debugEffects,self:generateEffect(scanEnd,sm.color.new('11ff11ff'))) -- green dot at end location
           end

           if hit then -- found floor
               if cycle == 1 then
                    --table.insert(self.debugEffects,self:generateEffect(scanStart,sm.color.new('1111ffff'))) -- blue dot at start location
                   --table.insert(self.debugEffects,self:generateEffect(data.pointWorld,sm.color.new('11ff11ff'))) -- green dot at end location
               end

               floorLoc = data.pointWorld.z
               if floorValue then
                    --print( "floorDif",floorValue,floorLoc, math.abs((floorLoc - floorValue)),threshold)
               end
               if floorValue and math.abs((floorLoc - floorValue))  > threshold then -- if there is a large change in floorthreshold
                   --print("found potential wall",math.abs(floorLoc - floorValue),threshold)
                   --self:createEfectLine(scanStart,data.pointWorld,sm.color.new('aaaaff')) -- white ish line
                   foundWall = data.pointWorld
                   break -- stop looping here
               else
                   floorValue = floorLoc -- adjust floor location in case uneven terrain?
                   -- TODO to debug: Might miss smooth walls, changing it to floorlocation 
               end
           end
           
           -- Set new location 
           scanStart = location + (direction * k)
           scanStart.z = location.z + scanHeight
           scanEnd = scanStart + sm.vec3.new(0,0,-scanHeight*1.5) -- scan down
   end
   return foundWall,floorValue
end

function Generator.getWallTopDown(self,location,direction,cycle,threshold) -- scans walls from the top down and across the perp axis (BEST)
    -- Scans from location to another location from top down 
    -- original location is estimated position based off of last wall
    -- stores floor location and if floor height threshold is passed then will return wall location
   local scanHeight = threshold + 20 -- how high from location to start scan TODO: make 
   local perpOffset = -6 -- start BEFORE predicted wall location (bring inwards) 
   local perpLimit = 40  -- end scan dist (maybe offset*5?)
   local floorValue = nil
   local scanGrain = 0.2 -- Sweeet spot may need adjustment [0.25] TODO: also make adjustable? Wall Thickness
   local scanStart = location + (direction * perpOffset)
   scanStart.z = location.z + scanHeight -- caused issues because this shifts wall scan up and technically scan end should be lower
   local scanEnd = scanStart + sm.vec3.new(0,0,-(scanHeight + location.z)*1.5) -- scan down even further by combining location and height and adding padding
   local foundWall = nil
   --table.insert(self.debugEffects,self:generateEffect(scanStart,sm.color.new('ff00ff'))) -- purple dot at start location
   for k= perpOffset, perpLimit, scanGrain do -- scans from pre direction, to post direction
           hit,data = sm.physics.raycast(scanStart,scanEnd) -- shoot raycast down
           if cycle == 1 then
                --table.insert(self.debugEffects,self:generateEffect(scanStart,sm.color.new('1111ffff'))) -- blue dot at start location
                --table.insert(self.debugEffects,self:generateEffect(scanEnd,sm.color.new('11ff11ff'))) -- green dot at end location
           end

           if hit then -- found floor
               if cycle == 1 then
                    --table.insert(self.debugEffects,self:generateEffect(scanStart,sm.color.new('1111ffff'))) -- blue dot at start location
                    --table.insert(self.debugEffects,self:generateEffect(data.pointWorld,sm.color.new('11ff11ff'))) -- green dot at end location
               end

               local floorLoc = data.pointWorld.z
               --print(floorLoc,floorValue)
               if floorValue then
                    --print( "floorDif",floorValue,floorLoc, math.abs((floorLoc - floorValue)),threshold)
               end
               if floorValue and math.abs((floorLoc - floorValue))  > threshold then -- if there is a large change in floorthreshold
                   --print("found potential wall",math.abs(floorLoc - floorValue),threshold)
                   if cycle == 1 then
                    --table.insert(self.debugEffects,self:generateEffect(scanStart,sm.color.new('eeee11'))) -- yellow at each scan start
                    --self:createEfectLine(scanStart,data.pointWorld,sm.color.new('aaaaff')) -- white from start to stop
                   end
                   foundWall = data.pointWorld
                   break -- stop looping here
               else
                   floorValue = floorLoc -- adjust floor location in case uneven terrain?
                   -- TODO to debug: Might miss smooth walls, changing it to floorlocation 
               end
           end
           -- Set new location 
           scanStart = location + (direction * k)
           scanStart.z = location.z + scanHeight
           scanEnd = scanStart + sm.vec3.new(0,0,-scanHeight*1.5) -- scan down
   end
   return foundWall,floorValue -- also sending floor to base bank off of floor
end

function Generator.checkForSharpEdge(self,midPoint,newWall,cycle) -- TODO: Determine whether or not to slow down track scan here??
   if cycle == 1 then
       --self:createEfectLine(location,searchLocation,sm.color.new('ee127fff')) -- red ish line
       --print("FoundLeftWall",searchLocation.z,location.z) -- Validate difference/distance between walls
   end
   if lastWall then
       local wallChange = getDistance(lastWall,newWall)
       if wallChange > 6 then  -- TODO: figure out good averag and go 2+ (so var avg is 4-5)
           --print("Sharp Wall Edge",wallChange)
           if cycle == 1 then
               --self:createEfectLine(location,searchLocation,sm.color.new('ee127fff')) -- red ish line
               table.insert(self.debugEffects,self:generateEffect(midPoint,sm.color.new('ff0000ff'))) -- red dot at start locationi
               --table.insert(self.debugEffects,self:generateEffect(searchLocation,sm.color.new('00ff00ff'))) -- green dot at scan location
               --table.insert(self.debugEffects,self:generateEffect(newWall,sm.color.new('0000ffff'))) -- blue dot at wall location
               --self:createEfectLine(location,lData.pointWorld,sm.color.new('ee127fff')) -- left is more red
               return true
           end
       end
   end
   return false
end
--TODO: Consolidate these into one function
-- Only used at startTrack Sacn
function Generator.getWallMidpoint(self,location,direction,cycle) -- cycle is new, determines which time it is ran to prevent annoying overlay on debug draw
    --print("originalZ",location.z)
    --print("scaning perp",direction)
    --if self.nodeChain == nil then return end
    -- TODO: figure out loopdy loops, will need to look forward instead of straight down in order to find ramps/inclines. have upsidedown tag for node aswell
    -- TODO: FIgure out fixes for bugs like goin in tunnels,scanner will break
    local searchLimit = 60 -- how far to look for walls, dynamic: self.nodeChain[#self.nodeChain]].lastNode.width/2
    local inTunnel = false
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
    local floorHeight,floorData = sm.physics.raycast(location + self.shape.up *2.5, location + self.shape.up * -60) -- TODO: balance height to prevent confusion...
    local ceilingHeight,ceilingData = sm.physics.raycast(location + self.shape.up *1.1, location + self.shape.up * 50) -- Check for ceiling (initioal tunnel or starting line stuff)
    -- TODO: Check which object has been hit (for all raycasts) and alert player if player has been hit
    local floor = location.z
    if floorHeight then
        --print("local normie",floorData.normalLocal,floorData.normalWorld)
        floor = floorData.pointWorld.z+0.1
    else
        print("could not find floor",floor)
        self.scanError = true
        self.errorReason = "Floor not found or invalid coordinates"
        return nil
        -- Double check floor from higher distance?
    end
    local ceiling = nil -- or 0?
    if ceilingHeight then
        --print("local normie",floorData.normalLocal,floorData.normalWorld)
        ceiling = ceilingData.pointWorld.z-0.1
        inTunnel = true
    else
        inTunnel = false
    end

    -- Look Forward First to see if floor is rising in front
    -- First send node out to front and see if it hits a point at higher z than floor
    local front, frontData =  sm.physics.raycast(location,location + direction * self.scanSpeed) -- change multiplier?
    if front then -- TODO: UPGRADSE THIS TO determine last location from next location , subtract the z values and you get z slope dif
        local floorDif = frontData.pointWorld.z - floor
        if floorDif < -.3 then
            print("Road is sloping up")
            floor = frontData.pointWorld.z + 0.5 -- may need to adjust?
            location.z = floor 
        end
    else
        --print(location.z - floor) -- bug, it sees going gdown but doesnt determine flat
        if location.z - floor > 0.3 then
            print("Road going down")
            location.z = frontData.pointWorld.z
        end
    end

    -- left wall Initial Find
    if inTunnel then -- if in tunnel just look directly left and right for walls
        leftWall = self:getWallFlatUp(location,-perp2,1) -- find left wall
    else
        leftWall,leftFloor = self:findWallTopDown(location,-perp2,1,self.wallThreshold)
    end
    if leftWall == nil then
        print("Finding Left wall failed",leftWall,location,cycle)
        -- switch scan methods?
    else -- we found the wall, create debug effect line
        self:checkForSharpEdge(location,leftWall,cycle) -- returns truefalse for failsafes
    end

    -- Right Wall Initial Find
    if inTunnel then -- if in tunnel just look directly left and right for walls
        rightWall = self:getWallFlatUp(location,perp2,1) -- find left wall
    else
        rightWall,rightFloor = self:findWallTopDown(location,perp2,1,self.wallThreshold)
    end
    if rightWall == nil then
        print("Finding Right Wall failed",rightWall,location,cycle)
        -- switch scan methods
    else -- we found the wall, create debug effect line
        self:checkForSharpEdge(location,rightWall,cycle)
    end
    
    if not leftWall then
        print('Left wall invalid')
    end
    if not rightWall then
        print("right wall invalid")
    end

    if not leftWall or not rightWall then
        print("Something went wrong While scanning track")
        -- Just Return Best Guess Which is just location but new floor
        self.scanError = true
        self.errorLocation = location
        self.errorReason = "Wall invalid @ red dot (check for gaps or tunnels)"
        return location
    end
   
    local midPoint = getMidpoint(leftWall,rightWall)
    midPoint.z = floor -- sets the floor as a track ground, 
    local width = getDistance(leftWall,rightWall) -- -1 padding?
    local bank = 0
    local bankThresh = 3 -- threshold to determine banking
    if leftWall.z - rightWall.z > bankThresh then -- If left wall is 3? higher than right wall, it is banked right
        bank = 1
    elseif rightWall.z - leftWall.z > bankThresh then -- if right wall is 3? hgihter than left wall, it is banked left
        bank = -1
    end -- else bank is 0
    return midPoint, width,leftWall,rightWall,bank
end

function Generator.getWallMidpoint2(self,location,direction,cycle) -- new Method for scanning Utilizes top down approach.
    -- TODO: figure out loopdy loops, will need to look forward instead of straight down in order to find ramps/inclines. have upsidedown tag for node aswell
    -- TODO: FIgure out fixes for bugs like goin in tunnels,scanner will break
    --[[
        * Initial node has to be flat surface and clear access to walls
        * Reasonable track width consistency 
        * After initial floor and wall locations are found
        * Scanner establishes perp nodes
        * Scanner has established height (5?)
            * Or no higher than 3 units above wall
        * Sets initial scan heightpos to wall height +3?
        * Scanner scans top down with multiple casts along perpnode starting from slightly inside previous wall distance to outside wall distance 
        * Scan for floor location, store z<
        * Check difference from last known floor z location.
        * If difference > 3? Establish that location as wall
        * Begin vertical z scan outwards towards wall until Sccanheight reached (start from floor locatio
        * Store distance to wall (starting 1? Closer to center of track) 
        * If difference from previous scan is >1? Establish the previous location as top of the wall (for tunnels it will stop upon 
        * intersection with terrain top (very dramatic (possibly really close) distance) might need top wall decrease 
        * Set new wall height if needed but only if dif is > 2? Initial wall height (not previous)
    ]]
    -- ALSO: Potentially get VHDif of lastWall/curWall to determine direction of turn & etc

    local searchLimit = 60 -- how far to look for walls, dynamic: self.nodeChain[#self.nodeChain]].lastNode.width/2
    local scanFromHeight = 2 --* self.shape.up
    if self.nodeChain[self.nodeIndex -1] ~= nil and self.nodeChain[self.nodeIndex-1].width then
        searchLimit = (self.nodeChain[self.nodeIndex-1].width * 0.8 or 60)
    end

    -- find the floor
    local incline = false
    local inTunnel = false
    local floorHeight,floorData = sm.physics.raycast(location + (self.shape.up *scanFromHeight), location + (self.shape.up * -60)) -- TODO: balance height to prevent confusion...
    local ceilingHeight,ceilingData = sm.physics.raycast(location + self.shape.up *1.1, location + self.shape.up * 50) -- Check for ceiling (initioal tunnel or starting line stuff)

    local floor = location.z -- setting flor to be previous floor 
    if floorHeight then
        --print("local normie",floorData.normalLocal,floorData.normalWorld)
        floor = floorData.pointWorld.z + 0.6
    else
        print("could not find floor",floor)
        self.scanError = true
        self.errorReason = "Floor not found or invalid coordinates"
        return nil
        -- Double check floor from higher distance?
    end

    local ceiling = nil -- or 0?
    if ceilingHeight then
        --print("local normie",floorData.normalLocal,floorData.normalWorld)
        ceiling = ceilingData.pointWorld.z-0.1
        inTunnel = true
        --print("Curr In tunnel")
    else
        --print("no curTunnel")
        inTunnel = false
    end
    -- Generate perpindeicular vectors towards assumed wall
    local perp = generatePerpVector(direction)-- Generates perpendicular vector to given direction - right side 
    local perp2 = self:generatePerpVector2(direction,location,self.nodeChain[#self.nodeChain])
    if perp.z ~=0 then -- perp is zerod in prior function
        --print("perp z no need",perp.z)
        perp.z = 0
    end

    -- set up wall locations
    local lastLeftWall, lastRightWall,lastCenter,leftWallDist,rightWallDist -- find previous node wall locations
    if self.nodeChain[self.nodeIndex -1] ~= nil then 
        if self.nodeChain[self.nodeIndex-1].leftWall then
            lastLeftWall = self.nodeChain[self.nodeIndex-1].leftWall
        end
        if self.nodeChain[self.nodeIndex-1].rightWall then
            lastRightWall = self.nodeChain[self.nodeIndex-1].rightWall
        end
        if self.nodeChain[self.nodeIndex-1].location then
            lastCenter = self.nodeChain[self.nodeIndex-1].location
        else
            lastCenter = location -- just use curr loc
        end
        leftWallDist = getDistance(lastLeftWall,sm.vec3.new(lastCenter.x,lastCenter.y,lastLeftWall.z))
        rightWallDist = getDistance(lastRightWall,sm.vec3.new(lastCenter.x,lastCenter.y,lastRightWall.z)) -- The Z difference skewed the distance prediction, setting z to be the same. now only skew is with minimal x/y
    end
    
    --print("Lwall RWall:",leftWallDist,rightWallDist)
    -- check previous leftWall/rightWall locations/distances/existence
    if cycle == 1 then
        --table.insert(self.debugEffects,self:generateEffect(location + self.shape.up *3.5 ,sm.color.new('ffff00ff'))) -- oarnge dot at start location
    end
    
    local wallThreshold = self.wallThreshold--0.55 -- how much difference in floor height to determine a wall [[TODO: Make user controlable dynamic, sweet spot is 0.2]]
    -- Can possibly make ^ dynamic according to failed params?
    --local location = lastLeftWall
    --print("\nLeft Wall Scan:")
    -- new wall location = location
    -- Left wall scan
    local lWallPredict = location + (-perp2*leftWallDist)
    local leftWall,leftFloor = nil
    --print("left Wall Predict",lastLeftWall,lastCenter,perp2,leftWallDist,lWallPredict)
    lWallPredict.z = lastLeftWall.z -- adjust z value???
    if inTunnel then -- if in tunnel just look directly left and right for walls
        leftWall = self:getWallFlatUp(location,-perp,cycle)
    else
        leftWall,leftFloor = self:getWallTopDown(lWallPredict,-perp2,cycle,wallThreshold)
    end
    if  leftWall == nil then
        print("Left Top Down scan failed",wallThreshold,cycle)
        -- do failsafe scan? -- increase/decrease threshold/granularity?
        table.insert(self.debugEffects,self:generateEffect(location + self.shape.up *3.5 ,sm.color.new('bbbb00ff'))) -- oarnge dot at start location
        leftWall = self:getWallAngleDown(location,-perp,cycle) -- TODO: use perp or perp2??
        if leftWall == nil then -- only three methods
            print("Left Angle Down Scan failed")
            leftWall = self:getWallFlatUp(location,-perp,cycle)
            if leftWall == nil then 
                print("Left All scanning methods failed",location,-perp,cycle)
                self:createEfectLine(location,lWallPredict,sm.color.new('aa3300ff')) -- redish orange line shows where it thinks the wall should be
                -- TODO: Have wall scans send back scan pos debug when failed
                print("could not Scan left Wall",location)
                self.scanError = true
                self.errorReason = "could not Scan left Wall"
                return nil
            end
        end
    else -- we found the wall, create debug effect line
        self:checkForSharpEdge(location,leftWall,cycle) -- returns true/false for morefailsafes
    end

    --print("\nRight Wall Scan:")
    ------ RIGHT WALL SCAN
    local rWallPredict = location + (perp2*rightWallDist) 
    rWallPredict.z = lastRightWall.z -- adjust zval
    local rightWall,rightFloor = nil
    if inTunnel then -- if in tunnel just look directly left and right for walls
        rightWall = self:getWallFlatUp(location,perp,cycle) -- find left wall
    else
        rightWall,rightFloor = self:getWallTopDown(rWallPredict,perp2,cycle,wallThreshold)
    end
    if  rightWall == nil then
        print("Right Top Down scan failed",wallThreshold,cycle)
        table.insert(self.debugEffects,self:generateEffect(location + self.shape.up *3.5 ,sm.color.new('bbbb00ff'))) -- oarnge dot at start location
        rightWall = self:getWallAngleDown(location,perp,cycle)
        if rightWall == nil then -- only three methods
            print("Right angle down Scan failed")
            rightWall = self:getWallFlatUp(location,perp,cycle)
            if rightWall == nil then 
                print("Right All scanning methods failed",location,perp,cycle)
                self:createEfectLine(location,rWallPredict,sm.color.new('aa3300ff')) -- redish orange line shows where it thinks the wall should be
                -- TODO: Have wall scans send back scan pos debug when failed, Possibly have it force a wall at the rWall Predict place (fill in gaps)
                print("could not Scan right Wall",location)
                self.scanError = true
                self.errorReason = "could not scan right Wall"
                return nil
            end
        end
    else -- we found the wall, create debug effect line
        self:checkForSharpEdge(location,rightWall,cycle)
    end
    
    -- TODO: find top of wall by scanning from bottom up until drastic raycast diff is found
    -- Error checking

    if rightWall == nil or leftWall == nil then
        print("Something went wrong While scanning track")
        -- Just Return Best Guess Which is just location but new floor
        self.scanError = true
        self.errorLocation = location
        return location
    end
    local midPoint = getMidpoint(leftWall,rightWall)
    midPoint.z = floor -- sets the floor as a track ground, 
    local width = getDistance(leftWall,rightWall) -- -1 padding?
    
    local bankThresh = 1 -- threshold to determine banking -- Can use height over width to get angle: bankAngle = (floorLeft - floorRight)/width
    local floorBank = 0
    local bankAngle = 0
    -- Removed Wall-based bank detection
    if leftFloor and rightFloor then
        if leftFloor - rightFloor > bankThresh then -- If left wall is 3? higher than right wall, it is banked right
            floorBank = 1
        elseif rightFloor - leftFloor > bankThresh then -- if right wall is 3? hgihter than left wall, it is banked left
            floorBank = -1
        end -- else bank is 0
        bankAngle = (leftFloor-rightFloor)/width
    end
    return midPoint, width,leftWall,rightWall,bankAngle
end

function Generator.analyzeSegment(self,initNode,flag) -- Legacy; DEPRECIATING
    if initNode == nil then print("Error No init node") return end
    local index = initNode.id
    local turnThreshold = 0.1 -- how much track curves before considering it a turn [0.1]
    local straightThreshold = 0.04 -- how straight track needs to be before considered straight [0.02]4?
    for k = index, #self.nodeChain do local node = self.nodeChain[k]
        if node.next.id == self.nodeChain[1].id then
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
    if initNode.id == startNode.id then 
        print("same init and start, single node trace: returning stright",initNode.id,startNode.id)
        return initNode
    end
    local index = startNode.id - 1
    local lastAngle = nil
    local numStraight = 0
    local straightThreshold = 0.3 -- angle difference before not considered straight line
    local straightCutoff = 4 -- how many straight nodes found before cutting of segment
    --local turnDir = 0
    --local turnThreshold = 2 -- how steep curve must be before apex is triggered
    --print("backtracing:",index,initNode.id,startNode.id,self.nodeChain[1].id,self.nodeChain[1].segID)
    for k = index, initNode.id ,-1 do local node = self.nodeChain[k] -- used to back trace until 1, Changed to backtrace to startnode
        if node.id == self.nodeChain[1].id or node.id == initNode.id then
            --print("found beginning",node.id,self.nodeChain[1].id,self.nodeChain[1].segID)
            return node
        end
        
        -- determine if node is the last node of last segment then quit
        local angle = getNodeAngle(initNode,node)
        --print(node.id,"b:",angle, math.abs(angle - (lastAngle or 0)),self.nodeChain[1].id,self.nodeChain[1].segID)

        if lastAngle == nil or math.abs(angle - lastAngle) < straightThreshold then
            --print("found straight",node.id,self.nodeChain[1].id,self.nodeChain[1].segID)
            numStraight = numStraight + 1
        else
            --print("found curve",node.id,self.nodeChain[1].id,self.nodeChain[1].segID) -- maybe keep track of turn angle
            lastAngle = angle
            numStraight = 0
            -- will need to account for quick reversals, set threshold? and if it crosses then end that turn too
        end

        if numStraight >= straightCutoff then
            --print("end of curve",node.id,self.nodeChain[1].id,self.nodeChain[1].segID)
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
    --print("startigna init",index,self.nodeChain[1].id,self.nodeChain[1].segID)
    for k = index, #self.nodeChain do local node = self.nodeChain[k] -- maybe not do whole chain?
        if node.next.id == self.nodeChain[1].id then
            startNode = self:backTraceSegment(initNode,node) -- TODO: figure this out
            --print("first backtraced",startNode.id,self.nodeChain[1].id,self.nodeChain[1].segID)
            return startNode,node, true
        end
        
        local angle = getNodeAngle(initNode,node) -- double check this
        --print(node.id,"f:",angle,lastAngle,angle - lastAngle,self.nodeChain[1].id,self.nodeChain[1].segID)

        if apexNode ~= nil then -- continue down curve until straight path found or reversal of turn
            if math.abs(angle - lastAngle) < straightThreshold then
                --print("continue straight",math.abs(angle - lastAngle),self.nodeChain[1].id,self.nodeChain[1].segID)
                numStraight = numStraight + 1
            else
                --print("curve continue",math.abs(angle - lastAngle),self.nodeChain[1].id,self.nodeChain[1].segID)
                lastAngle = angle
                numStraight = 0
                -- will need to account for quick reversals, set threshold? and if it crosses then end that turn too
            end

            -- reversal angle = 
            if numStraight >= straightCutoff then
                --print("curve ends",node.id,"backtracing...",initNode.id,apexNode.id,self.nodeChain[1].id,self.nodeChain[1].segID)
                startNode = self:backTraceSegment(initNode,apexNode)
                numStraight = 0
                --print("returning:",startNode.id,node.id,self.nodeChain[1].id,self.nodeChain[1].segID)
                return startNode,node,false -- just stop it for now, return start and end nodes eventually
                -- Begin for loop that searches backwards?
            end
        else
            if angle > turnThreshold then
                --print("right Turn apex",angle,node.id,self.nodeChain[1].id,self.nodeChain[1].segID)
                apexNode = node
                lastAngle = angle
                apexAngle = angle
            end
            if angle < -turnThreshold then
                --print("left Turn apex",angle,node.id,self.nodeChain[1].id,self.nodeChain[1].segID)
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
    --print(firstNode.id)
    --print("First scan got", startNode.id,endNode.id,self.nodeChain[1].id,self.nodeChain[1].segID)
    local lastNode
    local firstSegment = getSegment(self.nodeChain,firstNode,startNode) -- create segment
    --print("betweenSeg?",#firstSegment,firstNode.id,startNode.id)
    if #firstSegment > 1 then -- if curve has straight seg before
        local type,angle = defineSegmentType(firstSegment)
        --print(segID,"Setting Between segment (start)",firstNode.id,startNode.id,type.TYPE,angle)
        local output = segID.." setting between seg at start, " .. firstNode.id .. " - " .. startNode.id .. " : " .. type.TYPE
        --sm.log.info(output)
        setSegmentType(firstSegment,type,angle,segID)
        segID = segID + 1
        --lastNode = startNode
        --startNode
    else
        --sm.log.info("no between seg at start")
    end
    local segment = getSegment(self.nodeChain,startNode,endNode)
    local type,angle = defineSegmentType(segment)
    --print(segID,"setting first segment",startNode.id,endNode.id,type.TYPE,angle,self.nodeChain[1].id,self.nodeChain[1].segID)
    local output = segID.." setting first segment " .. startNode.id .. " - " .. endNode.id .. " : " .. type.TYPE
    --sm.log.info(output)
    setSegmentType(segment,type,angle,segID)
    segID = segID + 1
    lastNode = endNode
     -- store whatever the last node was to find between segments
    
    local scanTimeout = #self.nodeChain + 1
    local timeoutCounter = 0
    while not done do
        --print("StartLoop",startNode.id,endNode.id,self.nodeChain[1].id,self.nodeChain[1].segID)
        startNode = endNode.next
        lastNode = startNode -- store last segment end
        startNode,endNode,finished = self:analyzeSegment5(startNode)
        --print("post anal:",startNode.id,endNode.id,self.nodeChain[1].id,self.nodeChain[1].segID)

        -- check for segment between
        --print("finding segments",lastNode.id,startNode.id,endNode.id)
        local betweenSeg = getSegment(self.nodeChain,lastNode,startNode) -- discover if there is segment before first "turn segment"
        --print("betweenseg?",lastNode.id,startNode.id, #betweenSeg, self.nodeChain[1].id,self.nodeChain[1].segID)
        if #betweenSeg > 1 then -- If there is no segment between last turn and next turn
            --print("set between seg")
            local type,angle = defineSegmentType(betweenSeg)
            --print(segID,"setting between segment",lastNode.id,startNode.id,type.TYPE,angle,self.nodeChain[1].id,self.nodeChain[1].segID)
            local output = segID.." setting between segment " .. lastNode.id .. " - " .. startNode.id .. " : " .. type.TYPE
            --sm.log.info(output)
            --print("setting segment type between",lastNode.id,startNode.id,self.nodeChain[1].id,self.nodeChain[1].segID)
            setSegmentType(betweenSeg,type,angle,segID)
            --print("post set segment between",self.nodeChain[1].id,self.nodeChain[1].segID)
            segID = segID + 1
        else -- set a segment between them first
            --print(segID,"no between seg",#betweenSeg,self.nodeChain[1].id,self.nodeChain[1].segID)
        end    
        -- Acutally set turn segment
        --print("getting segment",startNode.id,endNode.id,self.nodeChain[1].id,self.nodeChain[1].segID)
        local segment = getSegment(self.nodeChain,startNode,endNode)
        local type,angle = defineSegmentType(segment)
        --print(segID,"setting segment type",startNode.id,endNode.id,type.TYPE,angle,self.nodeChain[1].id,self.nodeChain[1].segID)
        local output = segID.." setting next segment " .. startNode.id .. " - " .. endNode.id .. " : " .. type.TYPE
        --sm.log.info(output)
        setSegmentType(segment,type,angle,segID)

        if finished then -- TODO: Figure if this will still work
            -- Check between then set final segment?
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
    self.totalSegments = segID - 1
    
    print("Finished scan, Segment Count:",self.totalSegments,"Node Count:",#self.nodeChain)
    --print(self.nodeChain[#self.nodeChain-1].id,self.nodeChain[#self.nodeChain-1].segType)
end

function Generator.generateSegments(self) -- starts loading track segments, better results after optimization is complete
    self:scanTrackSegments()
    self:hardUpdateVisual()
end

function Generator.simplifyNodeChain(self) 
    local simpChain = {}
    --sm.log.info("simping node chain") -- TODO: make sure all seg IDs are consistance
    for k=1, #self.nodeChain do local v=self.nodeChain[k]
        output = v.segID .. ": " .. v.id
        --sm.log.info(output) Possibly export into json for track transport
        local newNode = {id = v.id, distance = v.distance, location = v.pos, segID =v.segID, segType = v.segType.TYPE,
                         segCurve = v.segCurve, mid = v.midPos, pit = v.pitPos, width = v.width, perp = v.perpVector, 
                         outVector = v.outVector,incline = v.incline, bank = v.bank } -- add race instead of location?-- Radius? Would define vMax here but car should calculate it instead
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
    --debugPrint(self.debug,data)
    local channel = data.channel
    data = self.simpNodeChain -- was data.raceLine --{hello = 1,hey = 2,  happy = 3, hopa = "hdjk"}
    sm.storage.save(channel,data) -- track was channel
    --sm.terrainData.save(data) -- saves as terrain??
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
    local exists = sm.terrainData.exists()
    print("data exists?",exists)
    if exists then 
        local data2 = sm.terrainData.load()
        print("finished loading terrain2",data2)
    end
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


-- New ALgo?1

-- Working algorithm that is much better at pinning apex/turn efficient points
function Generator.racifyLine(self)
    local straightThreshold = 20 -- Minimum length of nodes a straight has to be
    local nodeOffset = 5 -- number of nodes forward/backwards to pin (cannot be > straightLen/2) TODO; change so it only affects turn exit/entry individually
    local shiftAmmount = 0.04  -- Maximum node pin shiftiging amound (>2)
    local lockWeight = 3
    local lastSegID = 0 -- start with segId
    local lastSegType = nil
    -- TODO: only racify when there curve is a medium or more
    -- Find straight
    for k=1, #self.nodeChain do local node=self.nodeChain[k]
        if lastSegID == 0 and lastSegType == nil then -- first segment
            firstFlag =true
            lastSegID = node.segID
            lastSegType = node.segType.TYPE
            --print("Set first seg2")
        end
        if node.segType.TYPE == "Straight" and lastSegID ~= node.segID then -- If new straight found
            --print(node.segType.TYPE,node.segID)
            local segLen = self:getSegmentLength(node.segID) -- Do findTypeLimits to get real length
            if segLen > straightThreshold then --- skip things too short
                -- offset first and last nodes
                --print("eligible for typelimits",node.id,node.segType.TYPE,segLen)
                local firstNode,lastNode = self:findTypeLimits(node.segType.TYPE,node) -- Gets first and last node that match selected type
                if (firstNode.id == lastNode.id) then -- track has no turns
                    break
                end
                local offsetFirstNode = getNextItem(self.nodeChain,firstNode.id,nodeOffset)
                --print("got first node offset",firstNode.id,offsetFirstNode.id,nodeOffset)
                local offsetLastNode = getNextItem(self.nodeChain,lastNode.id,-nodeOffset)
                --print("got last node offset",lastNode.id,offsetLastNode.id,-nodeOffset)
                -- gather shared vars
                if shiftAmmount > node.width/2 then print("shift ammount too much last",shiftAmmount,node.width) end
                -- actual setting node positions
                local lastTurnDirection = getSegTurn(firstNode.last.segType.TYPE) -- 1 is right, -1 is left ( IF last turn was right turn, exit point should be on left, inverse segTurn)
                if math.abs(lastTurnDirection) >= 1 then
                    local desiredTrackPos = offsetFirstNode.pos
                    desiredTrackPos = offsetFirstNode.pos + (offsetFirstNode.perpVector * (shiftAmmount * -getSign(lastTurnDirection)))
                    offsetFirstNode.pos = desiredTrackPos
                    offsetFirstNode.pinned = false -- pin/weight?
                    offsetFirstNode.weight = lockWeight
                end
                
                local nextTurnDirection = getSegTurn(lastNode.next.segType.TYPE) -- 1 is right, -1 is left ( IF next turn is right turn, entry point should be on left)
                if math.abs(nextTurnDirection) >=1 then
                    desiredTrackPos = offsetLastNode.pos
                    desiredTrackPos = offsetLastNode.pos + (offsetLastNode.perpVector * (shiftAmmount * -getSign(nextTurnDirection)))
                    offsetLastNode.pos = desiredTrackPos
                    offsetLastNode.pinned = false -- pin/weight?
                    offsetLastNode.weight = lockWeight
                end
            end 
            -- else print "too short"
        end
    end
    print("Finished racifying line")
end



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
        -- TODO: refactor this into consolidated code
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
            if maxV1 > maxV2 + 0.012 then 
                --if maxV1 > maxV then
                    if testLoc1 == nil or perpV == nil then
                        print("nil test?",testLoc1,perpV)
                    end
                    if validChange(v,testLoc1,perpV,1) then
                        v.pos = testLoc1
                        v.vMaxEst = maxV1
                        calculateNewForceAngles(v)
                    end
                --end
            end

            if maxV2 > maxV1 + 0.012 then
                --if maxV2 > maxV then
                    if validChange(v,testLoc2,perpV,-1) then
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
    if math.abs(dif - self.lastDif) < 0.016 then
        --print("smooth",self.dampening)
        self.dampening = self.dampening/ 1.05
        self.smoothEqualCount = self.smoothEqualCount + 0.1
        local progress = (self.smoothEqualCount/self.optimizeStrength) * 100 -- IF global setting dont forget to change here too
        sm.gui.displayAlertText("Optimizing: " .. string.format("%i",progress) .. "%")
    end
    self.lastDif = dif
    self.totalForce = totalForce
    if self.smoothEqualCount >= self.optimizeStrength then -- TODO: have this user defined?
        return true
    end
    --self.smoothEqualCount = self.smoothEqualCount + 0.1 -- Remove, stops cscan
end

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
    -- TODO: Ensure correctness of scanVector every time (check math of anglediff)
    local nextLocation = getPosOffset(self.scanLocation,self.scanVector,self.scanSpeed)
    --Potential problem. tight corners loses fidelity
    local wallmidPoint, width,leftWall,rightWall,bank  = self:getWallMidpoint2(nextLocation,self.scanVector,0) -- new midpoint based off of previous vector looking for perpendicular walls
    if self.scanError then return end
    local nextVector = getNormalVectorFromPoints(self.scanLocation,wallmidPoint)-- Measure from last node to current midPoint
    --REdo scan so next vector and scan vector are aligned with midpoint differences and not just scanvector
    local wallmidPoint2, width,leftWall,rightWall,bank  = self:getWallMidpoint2(nextLocation,nextVector,1) -- TODO: determine if we need to find top
    if self.scanError then return end
    local nextLocation2 = wallmidPoint2 -- Do another nextVector?
    local nextVector2 = getNormalVectorFromPoints(self.scanLocation,wallmidPoint2)-- Measure from last node to current midPoint can remove nextVector2 if necessary, doubles as inVector

    self.scanLocation = nextLocation2
    self.scanVector = nextVector -- not nextVector2?? TODO: investigate why
    if nextVector == nil then
        print("nil vector")
    end

    -- Gather meta data
    
    local lastNode = self.nodeChain[self.nodeIndex -1]
    if lastNode == nil then
        print("could not find node index")
        self.scanError = true
        self.errorReason = "Could not format node chain, (contact seraph)"
        return true  
    end
    --print(self.nodeIndex,"lastNode",lastNode.id)
    self.totalDistance = self.totalDistance + getDistance(lastNode.pos,nextLocation2)
    local newNode = self:generateMidNode(self.nodeIndex,lastNode,nextLocation2,nextVector,self.totalDistance,width,leftWall,rightWall,bank)
    --print("Incline vector",nextVector.z)

    if math.abs(nextVector.z) >0.05 then
        newNode.incline = nextVector.z
        newNode.pinned = false -- TODO: Check validity of pinning incline nodes
    end
    -- Finish calculations on previous node
    lastNode.next = newNode
    lastNode.outVector = getNormalVectorFromPoints(lastNode.pos,newNode.pos)
    lastNode.force = vectorAngleDiff(lastNode.inVector,lastNode.outVector)
    if math.abs(lastNode.force) < 0.05 then
        self.scanSpeed = 5 -- 5?
    elseif math.abs(lastNode.force) > 0.3 then
        self.scanSpeed = 3
    elseif math.abs(lastNode.force) > 0.5 then
        self.scanSpeed = 2
    else
        self.scanSpeed = 4
    end
    -- use rolling average force?
    --print("Last Node",lastNode.inVector,lastNode.outVector,lastNode.force)

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
    if distanceFromStart < self.scanSpeed + 3 and self.scanClock > 3 then -- 1is padding just in case?
        local firstNode = self.nodeChain[1]
        newNode.next = firstNode -- link back to begining
        newNode.outVector = getNormalVectorFromPoints(newNode.pos,firstNode.pos)
        newNode.force = vectorAngleDiff(newNode.inVector,newNode.outVector)

        firstNode.last = newNode
        firstNode.inVector = getNormalVectorFromPoints(newNode.pos,firstNode.pos) -- or lastNode.outVector if too much
        firstNode.force = vectorAngleDiff(firstNode.inVector,firstNode.outVector)
        self.scanning = false
        local totalForce = calculateTotalForce(self.nodeChain)
        if self.debug then
            --print("finished Scanning, Total Forces = ",totalForce)
        end
        self.totalForce = (totalForce or math.inf) -- Or math.inf
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
            sm.gui.displayAlertText("Scan Failed: " .. (self.errorReason or ""),10)
            self.errorDisplayed = true
            self.errorNode = self:generateEffect(self.errorLocation,sm.color.new("EE2222FF"))
            self.errorNode:start()
            return
        end
    end
    if self.scanning and not self.instantScan then -- Debug scan
        local finished = self:asyncSleep(self.iterateScan,self.asyncTimeout)
        if finished then
            self.scanning = false
            self.scanClock = 0
            print("finished Track Scan, Generating segments")
            self:quickSmooth(self.smoothAmmount)
            self:generateSegments() --original
            --print("Finished Segment Gen, Optimizing Race line")
            if self.racifyLineOpt then
                self:racifyLine()
            end
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
            print("Generating segmens after optimization")
            self:generateSegments()-- testing location
            --self:printNodeChain()
            self.smoothing = false
            self.scanClock = 0
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
    self.scanError = false -- reset error
    self.nodeChain = {} -- reset chain
    self.scanClock = 0 -- reset scanclock
    self.started = clock()
    self.nodeIndex = 1
    sm.gui.displayAlertText("Scanning")
    local startPoint, width,leftWall,rightWall,bank = self:getWallMidpoint(self.location,self.trackStartDirection,1)
    self.scanLocation = startPoint
    self.scanVector = sm.vec3.normalize(self.trackStartDirection)
    print("Starting SCAN",#self.nodeChain,self.nodeIndex,width)
   
    local startingNode = self:generateMidNode(self.nodeIndex,nil,startPoint,self.trackStartDirection,self.totalDistance,width,leftWall,rightWall,bank)
  
    table.insert(self.nodeChain, startingNode)
    if self.instantScan then -- instant game freezing scan
        while self.scanClock < self.scanLength do
            if self.scanError then
                print("Scan error",self.debug)
                if not self.debug then
                    sm.gui.displayAlertText("Scan Failed: " .. (self.errorReason or "") .. " \n(Crouch interact to toggle debug)",10)
                else
                    sm.gui.displayAlertText("Scan Failed: " .. (self.errorReason or ""),10)
                end
                break
            end
            local finished = self:iterateScan()
            if finished then
                self.scanning = false
                self.scanClock = 0
                print("finished Track Scan, Generating segments")
                -- quick smoothing
                
                self:quickSmooth(self.smoothAmmount)
                self:generateSegments()
                -- if self.optimize then
                print("Finished Segment Gen, Optimizing Race line")
                if self.racifyLineOpt then
                    self:racifyLine()
                end
                self:startOptimization()
                self:hardUpdateVisual()
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
 
function Generator.sv_toggleRacify(self,toggle) -- Turns off and on racify line
    self.racifyLineOpt = not self.racifyLineOpt
    print("Toggling racify",self.racifyLineOptw)

    if self.racifyLineOpt then 
        sm.gui.chatMessage("Race Line Enhancement Turned #22ee22ON #ffffff(Good for Road Courses)")
    else
        sm.gui.chatMessage("Race Line Enhancement Turned #ee2222OFF #ffffff(Good for Ovals)")
    end
end

function Generator.printNodeChain(self)
    for k, v in pairs(self.nodeChain) do
		print(v.id,v.segID)
    end
end

function Generator.client_onInteract(self,character,state)
     if state then
        if character:isAiming() then -- if char is aiming then downforce detect
            self.network:sendToServer('sv_toggleRacify',state)
        elseif character:isCrouching() then
            self.debug = not self.debug -- togle debug
            self:toggleVisual(self.nodeChain)
            self.instantScan = false
		elseif not self.scanning then
            self.nodeChain = {}
            self.effectChain = {}
            self:startTrackScan()
            sm.gui.chatMessage("If scan does not work properly (bad shape or error): Press 'U' (upgrade) on the track scanner block to decrease wall detection sensitivity. Crouch 'U' to increase. then try to scan again. (may need to replace scanner block)")
            sm.gui.chatMessage("NOTE: Lower sens value = higher sensitivity (better for very flat tracks with sharp/low walls) \n Higher sens value = lower sensitivity (useful for tracks with high walls and/or bumpy roads like offroad sections or banked turns)")
            
		else
			print("Scan already started")
		end
    end
end



function Generator.client_canTinker( self, character )
	local useText =  sm.gui.getKeyBinding( "Use", true )
    local tinkerText = sm.gui.getKeyBinding( "Tinker", true )
    --sm.gui.setInteractionText("Save",sm.gui.getKeyBinding("Use"), "Load", sm.gui.getKeyBinding('Tinker'))
    sm.gui.setInteractionText( useText,"Start Scan", tinkerText,"Set Sensitivity","")
    
    return true
end

function Generator.client_onTinker( self, character, state )
    --print('onTinker')

	if state then
        if character:isCrouching() then
            self.network:sendToServer('cl_changeWallSense',-1)
        else
            self.network:sendToServer('cl_changeWallSense',1)
        end
	end
end
