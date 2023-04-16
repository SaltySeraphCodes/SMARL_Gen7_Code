-- CHeckpoint.lua, 
--[[
    Functionality:
        - logic block with arrow on it
        - gets placed down (beta in race order, can destroy/reset location but only on latest node)
        - Has two nodes show up (or possibly visual square) nodes will indicate width of track
        - Press E on it to increase width (possible ui) of nodes
        - data contains width and direction
        - Crouch and press E to decrease width of nodes (possible seat/camera interaction for more controls
        - node saves previous width of last node so not a lot of manual adjustment is needed
        - In future, possible optional/Split node, car can roll for chance to choose different path
        - Finish Loop/path by shooting First node with spud gun, nodes will form between each CP
        - Each Node will scan for walls and adjust accordingly (stay 5 ft away from wall), if no walls, it will attempt direct path to next node
        - Nodes will be straight paths, curves will be handled by cars, will not try to optimize apexes yet
        - once satisfie with nodes (after node generation), shoot first node with spud gun again to lock/save the path in place
        - nodelist gets saved in world under incrementing ID, race control can select ID (eventually, default 1 & overwritten)
]]
dofile "globals.lua"
dofile "Timer.lua" 

CheckPoint = class( nil )
CheckPoint.maxChildCount = -1
CheckPoint.maxParentCount = -11
CheckPoint.connectionInput = sm.interactable.connectionType.logic
CheckPoint.connectionOutput = sm.interactable.connectionType.logic
CheckPoint.colorNormal = sm.color.new( 0xffc0cbff )
CheckPoint.colorHighlight = sm.color.new( 0xffb6c1ff )
local clock = os.clock --global clock to benchmark various functional speeds ( for fun)



-- Local helper functions utilities
function round( value )
	return math.floor( value + 0.5 )
end

function CheckPoint.client_onCreate( self ) 
	self:client_init()
end

function CheckPoint.server_onCreate( self ) 
	self:server_init()
end

function CheckPoint.client_onDestroy(self)
    --print("Destroying",self.id)
end

function CheckPoint.server_onDestroy(self) -- remove node
    self:sv_sendAlert("Removed Checkpoint "..self.id)
    for k, v in pairs(CHECK_POINTS) do
		if v.id == self.id then
			table.remove(CHECK_POINTS, k)
		end
    end
    -- TODO: Validate CP Ids and array index
end

function CheckPoint.client_init( self ) 
    self.location =  sm.shape.getWorldPosition(self.shape)
    local frontDir = self.shape.at
    local perpVector = generatePerpVector(frontDir)
    
    self.leftLimit = sm.effect.createEffect("Loot - GlowItem")
    self.leftLimit:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    leftLocation = self.location - (perpVector * self.width/2)
    self.leftLimit:setPosition(leftLocation)
    self.leftLimit:setScale(sm.vec3.new(0,0,0))
    self.leftLimit:setParameter( "Color", sm.color.new("AA11AA"))

    self.rightLimit = sm.effect.createEffect("Loot - GlowItem")
    self.rightLimit:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    rightLocation = self.location + (perpVector * self.width/2)
    self.rightLimit:setPosition(rightLocation)
    self.rightLimit:setScale(sm.vec3.new(0,0,0))
    self.rightLimit:setParameter( "Color", sm.color.new("AA11AA"))

    if not self.leftLimit:isPlaying() then
        self.leftLimit:start()
    end

    if not self.rightLimit:isPlaying() then
        self.rightLimit:start()
    end
end

function CheckPoint.client_updateEffects(self)

end

function CheckPoint.server_init(self)
    self.debug = true
    -- might get jumbled if a lot of cps and server refresh
    self.location =  sm.shape.getWorldPosition(self.shape)
    self.direction = self.shape.at
    self.nodeFind = 0 -- 0 = nothing, 1 = finding, 2 = done
    self.nodeChain = {} -- contains all nodes
    self.effectChain = {}
    local frontDir = self.shape.at
    if self.id == nil then
        self.id = 0
    end
    if self.id == 0 then
        table.insert(CHECK_POINTS,self)
        self.id = #CHECK_POINTS
    else
        table.insert(CHECK_POINTS,self)
    end
    print("Adding checkpoint",#CHECK_POINTS,self.id)

    self:sv_sendAlert("Created Checkpoint    "..self.id)
    if CHECK_POINTS[self.id -1] == nil then
        self.width = 20 -- or whatever default width is
    else
        self.width = CHECK_POINTS[self.id-1].width -- Import last CP width for consistency
    end
end

function CheckPoint.client_onRefresh( self )
	self:client_onDestroy()
	self:client_init()
end

function CheckPoint.server_onRefresh( self )
	self:server_onDestroy()
	self:server_init()
end

function sleep(n)  -- n: seconds freezes game?
  local t0 = clock()
  while clock() - t0 <= n do end
end

function CheckPoint.asyncSleep(self,func,timeout)
    --print("weait",self.globalTimer,self.gotTick,timeout)
    if timeout == 0 or (self.gotTick and self.globalTimer % timeout == 0 )then 
        --print("timeout",self.globalTimer,self.gotTick,timeout)
        local fin = func(self) -- run function
        return fin
    end
end



function CheckPoint.removeNode(self,nodeID) -- removes node
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

function CheckPoint.getWallMidpoint(self,location,direction, widthLimit)
    --print("width",widthLimit)
    local widthLimit = widthLimit /2 -- cuts total width in half
    local incline = false
    local perp = generatePerpVector(direction)-- Generates perpendicular vector to given direction - right side 
    if perp.z ~=0 then 
        --print("perp z no need",perp.z)
        perp.z = 0
    end
    local floorHeight,floorData = sm.physics.raycast(location + sm.vec3.new(0,0,1) *3, location + sm.vec3.new(0,0,1) * -6) -- TODO: balance height to prevent confusion...
    local floor = location.z
    
    if floorHeight then
        floor = floorData.pointWorld.z + 0.5
    else
        print("could not find floor",floor)
        -- Double check floor from higher distance?
    end
    
    -- Look Forward First to see if floor is rising in front
    -- First send node out to front and see if it hits a point at higher z than floor
    local front, frontData =  sm.physics.raycast(location,location + direction * 2) -- change multiplier?
    --print(frontData)
    --{<Vec3>, x = -75.625, y = 113.625, z = 0.625} -- Approx location of last node before wall
    --{<Vec3>, x = -74.625, y = 109.875, z = 1.125} -- Aprox location of wall
    if front then
        --print("Hit something in front")
        local floorDif = frontData.pointWorld.z - floor
        if floorDif < -.3 then
            --print("Road is sloping up")
            floor = frontData.pointWorld.z + 0.5 -- may need to adjust?
            location.z = floor 
            --print(floor)
        end
    else
        --print(location.z - floor)
        if location.z - floor > 0.3 then
            --print("Road might be going down")
            location.z = floor
        end

    end

    -- Upgrading to location searching FOR Loops
    local zOffsetLimit = 0.7 -- How far above/below to search
    local zOffset = 0 -- unecessary?
    local zStep = 0.05 -- how many things to check

    local hitL,lData = sm.physics.raycast(location, location + perp*-widthLimit) -- Need to make sure that width actually scales
    if lData.valid == false then -- TODO: add or staement to check if wall or creation is there
        for k=-zOffsetLimit, zOffsetLimit,zStep do 
            local newLocation = location + sm.vec3.new(0,0,k)
            hitL,lData = sm.physics.raycast(newLocation,newLocation + perp*-widthLimit)
            if lData.valid == false then
                --print("K",k,"L Wallfailed")
            else
                --print("FoundLeftWall") -- Possibly validate here
                break --? possibly average rest of measurements?
            end
        end
    end
    -- Introduce x/y Offsets if necesary
    local hitR,rData = sm.physics.raycast(location, location + perp*widthLimit)
    if rData.valid == false then -- TODO: ad or staement to check if wall or creation is there
        for k=-zOffsetLimit, zOffsetLimit,zStep do 
            local newLocation = location + sm.vec3.new(0,0,k)
            hitR,rData = sm.physics.raycast(newLocation,newLocation + perp*widthLimit)
            if rData.valid == false then
                --print("K",k,"R wallfailed")
            else
                --print("FoundRightWall") -- Possibly validate here
                break --? possibly average rest of measurements?
            end
        end
    end

    local wallLeft,wallRight = nil
    if lData.valid == false then
        --print('No left wall, use default width')
        wallLeft = location - perp*widthLimit
    else
        wallLeft = lData.pointWorld
    end

    if rData.valid == false then
        --print("no right wall using default width")
        wallRight = location + perp*widthLimit
    else
        wallRight = rData.pointWorld
    end
    wallLeft.z = floor
    wallRight.z = floor
    --print("leftWall",wallLeft,"rightWall",wallRight)
    local midPoint = getMidpoint(wallLeft,wallRight)
    local width = getDistance(wallLeft,wallRight) -- -1 padding?
    --print("newWidth:",width)
    return midPoint, width
end

function CheckPoint.sv_changeWidth(self,newWidth)
    self.width = newWidth
    self.location =  sm.shape.getWorldPosition(self.shape)
    self.direction = self.shape.at
end


function CheckPoint.sv_sendAlert(self,msg) -- sends alert message to all clients (individual clients not recognized yet)
    self.network:sendToClients("cl_showAlert",msg) --TODO maybe have pcall here for aborting versus stopping
end

function CheckPoint.cl_showAlert(self,msg) -- client recieves alert
    print("Displaying",msg)
    sm.gui.displayAlertText(msg,3)
end

function CheckPoint.cl_generateVisuals(self)
    print("generating visuals")
    for k=1, #self.nodeChain do local v=self.nodeChain[k]
        if v.effect == nil then
            v.effect = self:generateEffect(v.pos)
        elseif v.effect ~= nil then
            if not v.effect:isPlaying() then
                v.effect:start()
            end
        end
    end
end




function CheckPoint.server_onProjectile(self,hitLoc,time,shotFrom) -- Functionality when hit by spud gun
	print("spud hit")
    if self.nodeFind == 0 then
        print("beginning node pathing")
        if #CHECK_POINTS >=3 then
            print("Valid nodes")
            result = self:generateNodeFindings()
            print("Done,",result,#self.nodeChain)
            self.network:sendToClients("cl_generateVisuals")
            self.network:sendToClients("cl_showVisualization")
            self:smoothNodes()
            self.network:sendToClients("cl_refreshVisuals")
        else
            print("not enough Checkpoints to complete a circuit",#CHECK_POINTS,CHECK_POINTS)
            sv_sendAlert("not enough Checkpoints to complete a circuit: ".. #CHECK_POINTS .. ". Need at Least 3")
        end  
    end
    
end

-- Node Chain generation
function CheckPoint.generateNodeFindings(self)
    self.scanning = true
    print("Finding nodes")
    local timeout = 0
    -- setup beginning node
    local totalDistance = 0
    local curCP = CHECK_POINTS[1]
    local nextCP = CHECK_POINTS[2]
    local curLocation = curCP.location
    local nodeID = 1
    local nextLocation = nextCP.location
    local scanVector = getNormalVectorFromPoints(curLocation,nextLocation)-- Measure from last node to current midPoint can remove nextVector2 if necessary, doubles as inVector
    local inVector = nil -- no invector yet
    local lastNode = self:generateMidNode(nodeID,nil,curLocation,scanVector,curCP.width)
    local scanSpeed = 2 -- how far to go
    table.insert(self.nodeChain,lastNode) -- possibly replace self.nodechain with global NODE_CHAIN
    
    while timeout < 2000 do -- 3000?
        nodeID = nodeID + 1
        print("node",nodeID)
        nextLocation = getPosOffset(curLocation,scanVector,scanSpeed)
        local wallmidPoint = self:getWallMidpoint(nextLocation,scanVector,nextCP.width) -- new midpoint based off of previous vector
        print("midpoint ",wallmidPoint,self.scanLocation)
        local nextVector = getNormalVectorFromPoints(curLocation,wallmidPoint)-- Measure from last node to current midPoint
        local wallmidPoint2, width = self:getWallMidpoint(nextLocation,nextVector,nextCP.width)
        local nextLocation2 = wallmidPoint2 -- Do another nextVector?
        local nextVector2 = getNormalVectorFromPoints(curLocation,wallmidPoint2)-- Measure from last node to current midPoint can remove nextVector2 if necessary, doubles as inVector

        curLocation = nextLocation2
        scanVector = nextVector

        if nextVector == nil then
            print("nil nextvector")
        end

        -- Gather meta data
        
        local lastNode = self.nodeChain[nodeID -1]
        if lastNode == nil then
            print("could not find node index")
            self.scanError = true
            break  
        end
        --print(nodeID,"lastNode",lastNode.id,lastNode,nextLocation2)
        totalDistance = totalDistance + getDistance(lastNode.pos,nextLocation2)
        local newNode = self:generateMidNode(nodeID,lastNode,nextLocation2,nextVector,totalDistance,nextCP.width)
        --print(nextVector.z)
        if math.abs(nextVector.z) >0.05 then
            newNode.incline = nextVector.z
            newNode.pinned = true
        end
        -- Finish calculations on previous node
        lastNode.next = newNode
        lastNode.outVector = getNormalVectorFromPoints(lastNode.pos,newNode.pos)
        lastNode.force = angleDiff(lastNode.inVector,lastNode.outVector)
    
        table.insert(self.nodeChain, newNode)
        -- Just for timeout reasons
        timeout = timeout + 1

        -- Check if checkpoint reached
        local distanceFromnextCP = getDistance(nextCP.location,newNode.pos)-- or curLocation
        --print(distanceFromnextCP)
        if distanceFromnextCP < scanSpeed + 1 then
            curCP = nextCP
            if curCP.id == #CHECK_POINTS then
                nextCP = CHECK_POINTS[1]
            else
                nextCP = CHECK_POINTS[nextCP.id + 1]
            end
            print("NewCP",curCP.id)
            nextLocation = nextCP.location
            scanVector = getNormalVectorFromPoints(curLocation,nextLocation)-- Measure from last node to current midPoint can remove nextVector2 if necessary, doubles as inVector
        end

        --- Check if circut is completed
        local distanceFromStart = getDistance(self.nodeChain[1].pos,newNode.pos)
        --print(distanceFromStart)
        if distanceFromStart < scanSpeed + 1 and timeout > 3 then -- 3& 1 is padding just in case?
            local firstNode = self.nodeChain[1]
            newNode.next = firstNode -- link back to begining
            newNode.outVector = getNormalVectorFromPoints(newNode.pos,firstNode.pos)
            newNode.force = angleDiff(newNode.inVector,newNode.outVector)

            firstNode.last = newNode
            firstNode.inVector = getNormalVectorFromPoints(newNode.pos,firstNode.pos) -- or lastNode.outVector if too much
            firstNode.force = angleDiff(firstNode.inVector,firstNode.outVector)
            self.scanning = false
            --print("finishing up")
            local totalForce = calculateTotalForce(self.nodeChain)
            if self.debug then
                print("finished Scanning, Total Forces = ",totalForce)
            end
            self.totalForce = totalForce
            return true
        end
    end
    return true
end

function CheckPoint.generateMidNode(self,index,previousNode,location,inVector,distance,width)
    -- print("making node",dirVector)
    if inVector == nil then
        print("node gen no inVector")
    end
    return {id = index, pos = location, outVector = nil, last = previousNode, inVector = inVector, force = nil, distance = distance, perpVector = generatePerpVector(inVector), 
            midPos = location, pitPos = nil, width = width, next = nil, effect = nil, segType = nil, segID = nil, pinned = false, weight = 1, incline = 0} -- move effect?
end

function CheckPoint.generateEffect(self,location,color) -- Creates new effect at param location
    local effect = sm.effect.createEffect("Loot - GlowItem")
    effect:setParameter("uuid", sm.uuid.new("4a1b886b-913e-4aad-b5b6-6e41b0db23a6"))
    effect:setScale(sm.vec3.new(0,0,0))
    local color = (color or sm.color.new("AFAFAFFF"))
    
    --local testUUID = sm.uuid.new("42c8e4fc-0c38-4aa8-80ea-1835dd982d7c")
    --effect:setParameter( "uuid", testUUID) -- Eventually trade out to calculate from force
    --effect:setParameter( "Color", color )
    effect:setPosition(location) -- remove too
    effect:setParameter( "Color", color )
    return effect
end

function CheckPoint.simplifyNodeChain(self) 
    local simpChain = {}
    sm.log.info("simping node chain") -- TODO: make sure all seg IDs are consistance
    for k=1, #self.nodeChain do local v=self.nodeChain[k]
        output = v.segID .. ": " .. v.id
        sm.log.info(output)
        local newNode = {id = v.id, distance = v.distance, location = v.pos, segID =v.segID, segType = v.segType.TYPE, segCurve = v.segCurve, mid = v.midPos, pit = v.pitPos, width = v.width, perp = v.perpVector, outVector = v.outVector } -- add race instead of location?-- Radius? Would define vMax here but car should calculate it instead
        table.insert(simpChain,newNode)
    end
    --print("simpchain = ",simpChain)
    return simpChain
end

function CheckPoint.saveRacingLine(self) -- Saves nodeChain, may freeze game --TODO: have ways for people to send me their nodes to make track SMAR certified, (send client json? send file?)
    self.simpNodeChain = self:simplifyNodeChain()
    local data = {channel = TRACK_DATA, raceLine = true} -- Eventually have metaData too?
    self.network:sendToServer("sv_saveData",data)
    sm.gui.displayAlertText("Scan Complete: Track Saved")
end
-- Smoothing helpers


-- Smoothing
function CheckPoint.smoothNodes(self) -- {DEFAULT} Will try to find fastest average velocity
    print("Smoothing nodes")
    local timeout = 0
    local totalForce = 0
    local avgSpeed = 0
    local lastDif = 0
    local dampening = 0.05
    local smoothEqualCount = 0
    while timeout < 200 do
        timeout = timeout + 1
        for k=1, #self.nodeChain do local v=self.nodeChain[k]
            local perpV = v.perpVector
            local lessenDirection = getSign(v.force)
            --local changeVector = perpV * lessenDirection
            --print(changeVector.z)

            --- NEW calculation of hinge force
            -- Gets distance along perpV direction last and next node are
            --print(v.id,v.last.id,v.next.id)
            local vhDif1 = self:getNodeVH(v,v.last,perpV)
            local vhDif2 =  self:getNodeVH(v.next,v,perpV)

            local lastC = false
            local nextC = false

            if vhDif1.vertical < 0.7 then
                lastC = true
            end
            if vhDif2.vertical < 0.7 then
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
                        self:removeNode(v.id) --Actually works better removed or with low values
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
            local testLoc1 = getPosOffset(v.pos,changeDirection1,dampening/v.weight) -- Dampen it based v.weight
            local testLoc1inVector = getNormalVectorFromPoints(v.last.pos,testLoc1) -- use tempPos?
            local testLoc1outVector = getNormalVectorFromPoints(testLoc1,v.next.pos) -- use tempPos?
            local pointAngle1 = math.abs(posAngleDif3(testLoc1,testLoc1inVector,v.next.pos)) * 10
            local maxV1 = getVmax(pointAngle1) 

            local changeDirection2 = perpV * -1 --sumHoz
            local testLoc2 = getPosOffset(v.pos,changeDirection2,dampening/v.weight)
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
        local totalForce2 = calculateTotalForce(self.nodeChain)
        local avgVmax2 = calculateAvgvMax(self.nodeChain)
        --print("vmaxAvg = ",avgVmax,totalForce)
        --print("ForceAvg = ",totalForce)
        --self.scanClock = self.scanClock + 1

        local dif = math.abs(totalForce2 - totalForce)

        --print(string.format("dif = %.3f , %.5f",dif,totalForce2))
        --self.smoothEqualCount = self.smoothEqualCount + 1

        
        if math.abs(dif - lastDif) < 0.002 then
            print("smooth",dampening)
            dampening = dampening/ 1.2
            smoothEqualCount = smoothEqualCount + 0.5
        end

        if smoothEqualCount >= 5 then
            debugPrint(self.debug,"Three equalinro")
            return true
        end
        lastDif = dif
        totalForce = totalForce2
        if smoothEqualCount >= 3 then
            debugPrint(self.debug,"Three equalinro")
            return true
        end
    end
        --self.smoothEqualCount = self.smoothEqualCount + 0.1 -- Remove, stops cscan

end

function CheckPoint.getNodeVH(self,node1,node2,searchVector) -- returns horizontal and vertical distances from node1 to node2 
    --TODO: just put thios in global. doesnt need to be class specific
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

function CheckPoint.server_onMelee(self,data) -- Functionality when hit by hammer
	print("melehit",data) -- Means save node?
end


function CheckPoint.client_onInteract(self,character,state)
    -- if driver active, then toggle userControl
    if state then
        if character:isCrouching() then
            self.width = self.width - 1
            self.network:sendToServer("sv_changeWidth",self.width)
            self:cl_showAlert("Decreasing width")
        else
            self.width = self.width + 1
            self.network:sendToServer("sv_changeWidth",self.width)
            self:cl_showAlert("Increasing width")
        end
         -- update effects/visualization
        local frontDir = self.shape.at
        local perpVector = generatePerpVector(frontDir)
        local leftLocation = self.location - (perpVector * (self.width/2))
        self.leftLimit:setPosition(leftLocation)

        local rightLocation = self.location + (perpVector * (self.width/2))
        self.rightLimit:setPosition(rightLocation)
        if not self.leftLimit:isPlaying() then
            self.leftLimit:start()
        end
    
        if not self.rightLimit:isPlaying() then
            self.rightLimit:start()
        end
    end
end


function CheckPoint.toggleVisual(self,nodeChain)
    print("displaying",self.visualizing)
    if self.visualizing then
        self:stopVisualization()
        self.visualizing = false
    else
        self:cl_showVisualization()
        self.visualizing = true
    end
end


function CheckPoint.cl_showVisualization(self) --starts all effects
    debugPrint(self.debug,"Starting visualization")
    for k=1, #self.nodeChain do local v=self.nodeChain[k]
        if v.effect ~= nil then
            if not v.effect:isPlaying() then
                v.effect:start()
            end
        end
    end
    self.visualizing = true
end


function CheckPoint.cl_stopVisualization(self) -- Stops all effects in node chain (specify in future?)
    debugPrint(self.debug,'stopping visualizaition')
    for k=1, #self.nodeChain do local v=self.nodeChain[k]
        if v.effect ~= nil then
            v.effect:stop()
        end
    end
    self.visualizing = false
end


function CheckPoint.cl_refreshVisuals(self) -- toggle visuals to gain color
    self:cl_stopVisualization()
    self:cl_showVisualization()
end



function CheckPoint.server_onFixedUpdate( self, timeStep )
    -- First check if driver has seat connectd
    --self:parseParents()
    self.location =  sm.shape.getWorldPosition(self.shape)
end


function CheckPoint.client_onUpdate(self,timeStep)

end
