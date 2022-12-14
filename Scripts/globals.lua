-- List of globals to be listed and changed here, along with helper functions
CLOCK = os.clock


MAX_SPEED = 10000 -- Maximum engine output any car can have ( to prevent craziness that occurs when too fast)
MOD_FOLDER = "$CONTENT_DATA/" -- ID to open files in content
--CAMERA_FOLDER = "$CONTENT_d42a91c3-2f86-4923-add5-93d8258b2c08/"
-- SELF FOLDER =- "$CONTENT_5411dc77-fa28-4c61-af84-bcb1415e3476/"
sm.SMARGlobals = {
    LOAD_CAMERA = true, -- REMEMBER TO SET THIS TO FALSE
    SMAR_CAM = -1 -- Smar camera loaded from cinecam mod
}

MAX_STEER_VALUE = 40 -- maximum angle car can turn wheels
ALL_DRIVERS = {} -- contains all constantly updating information of each driver, can be read from anywhere that imports globals.lua (updated dynamically)
RACE_CONTROL = nil -- Contains race control Object
ALL_CAMERAS = {}
-- HARD LIMITS no engine can go past this on acident
ENGINE_SPEED_LIMIT = 200 -- Car should never get this high anyways but just in case

--

-- Physics Defaults
DEFAULT_GRAVITY = 10 -- Good even number
DEFAULT_FRICTION = 0.0006046115371 -- Friction coeficient -- could be wrong

-- Conversion Rates
VELOCITY_ROTATION_RATE = 0.37 -- 1 rotation speed ~= 0.37 velocity length -- How fast wheels should rotate (engine  speed) to achieve a certain velocity
DECELERATION_RATE = -9.112992895 -- Multiply this number by the braking speed to get the aproximate deceleration rate for brake distance calculaitons (decrease for longer breaking distances)
-- VMAX calculation defaults
MAX_VELOCITY = 150
DEFAULT_MAX_STEER_VEL = 14
DEFAULT_MINOR_STEER_VEL = 26
DEFAULT_MAX_STEER = (MAX_STEER_VALUE or 55)
DEFAULT_MINOR_STEER = 5
DEFAULT_VMAX_CONVERSION = 27.47018327 * math.exp(0.01100092674*1) -- * 1 <- steering angle goes here
-- K = 1/(MAxSteer-minSteer)* ln(MaxSteerVel/minSteerVel), A0 = MinSteerVEl* e^(-k*SteerInput)

-- Track generation options -- possibly move to track piece?
FORCE_SENSITIVIY = 4 -- How much angle differences affect total force on node chain
FORCE_THRESHOLD = 0.01 -- when nodes accept where they are
WALL_PADDING = 6.5
TRACK_DATA = 1 -- Location to save world storage for the racing line

TEMP_TRACK_STORAGE = { -- Temporary storage for tracks... [unused for now]

}

-- New manual Checkpoint globals
NODE_CHAIN = {}
CHECK_POINTS = {}

SEGMENT_TYPES = {
    {
        TYPE = "Straight",
        THRESHOLD = {-2.5,2.5},
        COLOR = "4DD306FF"
    },
    {
        TYPE = "Fast_Right",
        THRESHOLD = {2.5,5},
        COLOR = "07FFECFF"
    },
    {
        TYPE = "Fast_Left",
        THRESHOLD = {-5,-2.5},
        COLOR = "FF6755FF"
    },
    {
        TYPE = "Medium_Right",
        THRESHOLD = {5,15},
        COLOR = "047FCAFF"
    },
    {
        TYPE = "Medium_Left",
        THRESHOLD = {-15,-5}
        , COLOR = "B80606FF"
    },
    {
        TYPE = "Slow_Right",
        THRESHOLD = {15,90},
        COLOR = "0B0066FF"
    },
    {
        TYPE = "Slow_Left",
        THRESHOLD = {-90,-15},
        COLOR = "660000FF"
    }
}
-- Engine Definitions
ENGINE_TYPES = { -- Sorted by color but could also maybe gui Dynamic? mostly defaults but also custom at end
   {
        TYPE = "road", -- slowest
        COLOR = "222222ff", -- black
        MAX_SPEED = 73.5, -- 73.5 ?
        MAX_ACCEL = 0.4,
        MAX_BRAKE = 0.70,
        GEARING = {0.6,0.5,0.4,0.2,0.2}, -- Gear acceleration Defaults (soon to be paramaterized)
        REV_LIMIT = 73.8/5 -- LImit for VRPM TODO: adjust properly
    },
    {
        TYPE = "sports", -- medium -- dark gray
        COLOR = "4a4a4aff",
        MAX_SPEED = 80, -- 80
        MAX_ACCEL = 0.5,
        MAX_BRAKE = 0.9, -- 1?
        GEARING = {0.7,0.6,0.5,0.3,0.2}, -- Gear acceleration Defaults (soon to be paramaterized)
        REV_LIMIT = 80/5 -- LImit for VRPM TODO: adjust properly
    },
    {
        TYPE = "formula", -- Fast
        COLOR = "7f7f7fff", -- Light gray
        MAX_SPEED = 100,
        MAX_ACCEL = 1,
        MAX_BRAKE = 1,
        GEARING = {0.75,0.8,0.6,0.2,0.25}, -- Gear acceleration Defaults (soon to be paramaterized)
        REV_LIMIT = 100/5
    },
    {
        TYPE = "insane", -- Insane -- add custom later?
        COLOR = "eeeeeeff", -- white
        MAX_SPEED = 150,
        MAX_ACCEL = 2,
        MAX_BRAKE = 1.5,
        GEARING = {0.8,0.85,0.65,0.4,0.3}, -- Gear acceleration Defaults (soon to be paramaterized)
        REV_LIMIT = 150/5
    }
}
-- Data managment
function saveData(data,channel) -- gather more params
    TEMP_TRACK_STORAGE[channel] = data
end

function loadData(channel)
    --print("loading",channel,TEMP_TRACK_STORAGE[channel])
    return TEMP_TRACK_STORAGE[channel]
end

function getRaceControl()
    --if RACE_CONTROL == nil then
    return RACE_CONTROL
end


function cameraCompare(a,b)
    --print(a.cameraID)
	return a['cameraID'] < b['cameraID']
end

function sortCameras()
    --print("Sorting Cameras")
    table.sort(ALL_CAMERAS, cameraCompare)
    --print(ALL_CAMERAS)
end

function setSmarCam(cam)
    sm.SMARGlobals.SMAR_CAM = cam
    --print("set smar cam",SMAR_CAM)
end

function getSmarCam()
    return  sm.SMARGlobals.SMAR_CAM
end
-- Helper functions

-- Car helpers





    -- Track related helper

function generateNodeMap(nodeChain) -- Creates a mapped 2d array of nodes based on [y],[x] location -- try for pathType??
    local map = {} -- Wwhole map
    local indexGroup = {} -- array of nodes within an index of the map

    if nodeChain == nil then
        print("Could not generate nodemap; no nodes")
    end

    for k=1, #nodeChain do local node=nodeChain[k]
        local row = round(node.location.y)
        local col = round(node.location.x)
        if map[row] == nil then
            map[row] = {}
        end
        if map[row][col] == nil then
            map[row][col] ={}
        end
        table.insert(map[row][col],node)
        --print("insertingnode",row,col,map[row])
    end
    return map
end


-- possibly use areaTrigger?
-- Get closest nodes to the nearest location?
function getNearestNode(nodeMap,location) -- TODO: Get outer bounds of nodeMAp, detect if outside, instead of searching all, just search for nearest node in general direction
    --print(nodeMap)
    local availibleNodes = {}
    local approxRow = round(location.y)
    local approxCol = round(location.x)
    local distance = nil
    local searchDistance = 0 -- how far away to search
    
    --print("getting nearest node",approxRow,approxCol)
    local searchLimit = 50
    local possibleRow = nodeMap[approxRow]
    if possibleRow ~= nil then
        local possibleCol = nodeMap[approxRow][approxCol]
        if possibleCol ~= nil then
            availibleNodes = nodeMap[approxRow][approxCol] -- posssibly index even more?
            --print("imediate nodes",availibleNodes)
        end
    end -- else

    while availibleNodes == nil or #availibleNodes == 0 do
        --print("while",searchDistance)
        searchDistance = searchDistance + 1
        if searchDistance > searchLimit then
            print("Searchlimit reached")
            break
        end
        local extendedNodes = {}
        for row = -searchDistance, searchDistance do
            for col = -searchDistance, searchDistance do -- SOmehow skip over nodes already seen
                if nodeMap[approxRow + row] ~= nil then -- valid node with row
                    if  nodeMap[approxRow + row][approxCol + col] ~= nil then -- Valid column node
                        --print()
                        --print("Found",approxRow + row,approxCol + col, nodeMap[approxRow + row][approxCol + col])
                        local extendedSearchNodes = nodeMap[approxRow +row][approxCol + col]
                        --print("Extended",extendedSearchNodes,extendedSearchNodes[1])
                        if extendedSearchNodes ~= nil and #extendedSearchNodes > 0 then
                            for j = 1, #extendedSearchNodes do local eNode = extendedSearchNodes[j]
                                if math.abs(eNode.location.z - location.z) < 2 then -- make smaller/bigger dif?
                                    --print(location.z,eNode.location.z)
                                    table.insert(extendedNodes, eNode) -- puts nodes into extendedNode
                                else
                                    --print("node not on same level")
                                end
                            end
                        end
                    else
                        --print('badCol')
                    end
                else
                    --print("badRow",nodeMap[approxRow])
                end
            end
        end
        if extendedNodes ~= nil and #extendedNodes > 0 then
            --print("whats goin ong",extendedNodes)
            --if availibleNodes == nil then availibleNodes = {} end -- make empty
            availibleNodes = tableConcat(availibleNodes,extendedNodes)
        else
            --print("expand",searchDistance,"search failed",location)
        end
    end
    -- print("pre filter",#availibleNodes)

    -- filter node zs
    for i=1, #availibleNodes do local node = availibleNodes[i]
        --print("nodefilter?",math.abs(node.location.z - location.z))
        if node == nil then print("Bad node") return end
        if math.abs(node.location.z - location.z) > 2 then -- TODO: just make lower priority instead of removing...
            print(node.id,"not in range")
            table.remove( availibleNodes,i )
        end
    end
    --print("post filter",#availibleNodes)

    if availibleNodes == nil or #availibleNodes == 0 then -- Nothing directly
        --print("Could not find any nodes close")
        return nil
    else
        --print("Node canidates",availibleNodes)
    end
    --print("near nodes",availibleNodes,location)
    return getNodeClosest(availibleNodes,location) -- else return the closest nodes

end

function getNodeClosest(nodeList,location) -- Gets node closest to to {location}
    local minDist = nil 
    local closestNode = nil
    local closestZ = nil
    local closeZNode = nil
    for i=1, #nodeList do local node = nodeList[i]        
        if closestZ == nil then
            closestZ = math.abs(location.z - node.location.z)
            closeZNode = node
        else
            if math.abs(location.z - node.location.z) < closestZ then
                --print("Found closer z node",closestZ,location.z,node.location.z)
                closestZ = math.abs(location.z - node.location.z)
                closeZNode = node
            end
        end
        local nDist = getDistance(node.location,location)
        if (minDist == nil or nDist < minDist) then
            closestNode =  node
            minDist = nDist
        end
        
    end
    if closestNode.id == closeZNode.id then 
        -- nodes are same
    else
        -- nodes are different
        --print("Found different levels of z node close",location,closestNode.location,closeZNode.location)
        if math.abs(closestNode.location.z - closeZNode.location.z) < 2 then
            --print("nodes are close enoug", math.abs(closestNode.location.z - closeZNode.location.z))
        else
            --Sprint("possible split in node verticals")
            if math.abs(location.z - closeZNode.location.z) < 2 then -- Make bigger or smaller?? 
                closestNode = closeZNode
                print("moving to closer z node")
            else
                print("staying with closest")
            end
        end

    end
    --print("Closest Node:",node,minDist)
    if closestNode == nil then
        --print("Could not determine closest node, z difference?")
    end
    return closestNode
end

-- Engine/Driver Connector helpers
function calculateMaximumVelocity(segBegin,segEnd,segLen) -- gets maximumSpeed based on segment node and length of turn
    local segType = segBegin.segType
    local segCurve = segBegin.segCurve
    local segLen = (segLen or 10)
    local angleMultiplier = 5 -- default
    local angle = math.abs(segCurve)
    local angle2 = angleDiff(segBegin.outVector,segEnd.outVector) -- depreciated
    if  segType == "Straight" then -- sometimes things go wrong
        
        return getVmax(angle) * 2
    elseif segType == "Fast_Right" or segType == "Fast_Left" then -- reduce ang
        --print("fastSeg",segLen)
        if segLen >= 20 then -- Long turn
            --print("maxWideTurn",segLen)
            return getVmax(angle)+ segLen - 20 -- Adjustable to engineVel?
        end
        angleMultiplier = 1.5
    elseif segType == "Medium_Right" or segType == "Medium_Left" then -- increase ang?
        if segLen >= 20 then -- Long turn
            --print("Medium long Turn",segLen)
            return getVmax(angle*1.5)+ segLen - 20 -- Adjustable to engineVel?
        end
        angleMultiplier = 2
    elseif segType == "Slow_Right" or segType == "Slow_Left" then -- increase ang?
        if segLen >= 20 then -- Long turn
            --print("Slow long Turn",segLen)
            return getVmax(angle*2)  -- Adjustable to engineVel?
        end
        angleMultiplier = 3
    end
       
    --print("angle",angle)
    --print("Velocity angle",segBegin.segID,segType,angle,angle2,getVmax(angle),getVmax(angle2))
    --angle = math.abs(angle2)*angleMultiplier
    return getVmax(angle)
end


function getBrakingDistance(speed,brakePower,targetSpeed) -- Get distance needed to go from speed {target}
    if speed <= targetSpeed then -- already there
        return 0
    end
    --local ticksToTarget = (speed-targetSpeed)/(brakePower)
    -- Ignoring the effects of negative acceleration, calculate distance
    --print("ticks",ticksToTarget)
    --return speed * ticksToTarget-- D = S*T -- Old dist formula

    local top = targetSpeed^2 - speed^2
    local bottom = 2*(brakePower*DECELERATION_RATE)
    local distance = top/bottom
    return distance

end


function getRotationIndexFromVector(vector,precision) -- Precision fraction 0-1
	if vector.y >precision then -- north?
		return 3
	end
	if vector.x > precision then
		return 2
	end
	if vector.y < -precision then
		return 1
	end
	if vector.x < -precision then
		return 0
	end
	return -1
end

-- Driver things


function getDriverFromId(id)
    for k=1, #ALL_DRIVERS do local v=ALL_DRIVERS[k]
		if v.id == id then 
			return v
		end
	end
end

function getAllDrivers()
    return ALL_DRIVERS
end

function getDriversFromIdList(idList)
    local driverList = {}
    for k=1, #idList do local v=idList[k]
		local driver = getDriverFromId(v)
        if driver ~= nil then
            table.insert(driverList,driver)
        else
            print("driver not found",v)
        end
	end
    return driverList
end

function getDriversInDistance(driver,distance) -- returns table of all drivers within a certain distance
    local drivers = {}
    for k=1, #ALL_DRIVERS do local v=ALL_DRIVERS[k]
        if v.id ~= driver.id then -- Dont look at yourself
            if v.goalNode ~= nil and driver.goalNode ~= nil then
                if v.carDimensions ~= nil then
                    if getDistance(driver.location,v.location) <= distance then -- Possibly just use trackDist/ID dist instead because we may get unececsary noise
                        if math.abs(v.goalNode.segID - driver.goalNode.segID) < 4 then -- within 4 segments could adjust if necessary
                            table.insert(drivers,v)
                        else
                            --print("too far")
                        end
                    end
                end
            end
		end
	end
    return drivers
end

function getDriverDistance(driver,target,totalNodes) -- GEts the distance between two drivers ONLY use for general dist tracking, not precise
    if driver.currentNode == nil then return 0 end -- bad
    if target.currentNode == nil then return 0 end -- error
    local sign = 1
    if driver.currentNode.id < 20 and totalNodes - target.currentNode.id < 20 then -- Check if there is an overlap/lap passed(if close, then driver ahead)
        sign = -1
    elseif totalNodes - driver.currentNode.id < 20 and target.currentNode.id < 20 then -- Driver is ahead of target
        sign = 1
    elseif driver.currentNode.id > target.currentNode.id then -- driver is in front of target
        sign = -1
    elseif driver.currentNode.id < target.currentNode.id then -- driver is behind target
        sign = 1
    else -- Drivers on same node, extreeme close, will need better way to check distances
        sign = 1
    end
    --local slope = (target.location.y - driver.location.y)/ (target.location.x - driver.location.x)
   
    
    local distance =getDistance(driver.location, target.location) * sign -- just take node differences to save computation
    --print(driver.id)
  
    --print("distance",distance)
    return distance

end

function getDriverPosition(id) -- Gets race Posistion of racer accoring to racerID
	local driver= getDriverFromId(id)
	
	if driver == nil then 
		print("GetPosition: Invalid Race ID",id,driver)
		return 0
	end
	local position = driver.racePosition
	if position == nil then
		print("getPos: driver Position is nil")
		return 0
	end
	return position
end

function getDriverByPos(racePos) -- Return whole racer based off of race posistion
	for k=1, #ALL_DRIVERS do local v=ALL_DRIVERS[k]
		--print(v.racePosition)
        if v.racePosition == racePos or v.racePosition == 0 then 
			--print("v")
			return v
		end
	end
end

function getLapsLeft()
	for k=1, #ALL_DRIVERS do local v=ALL_DRIVERS[k]
		if v.racePosition <= 1 then
            if getRaceControl() ~= nil then
			    return ( getRaceControl().targetLaps - v.currentLap)
            end
		end
	end
    return 10
end

function getRelativeSpeed(driverA,driverB)
	local relSpeed = driverA.speed - driverB.speed
	--print(string.format("REl = %.2f",relSpeed))
	--if relSpeed < 10 then return 10 end
	return relSpeed
end

function getCarCenter(racer)
    local rotation  =  racer.carDimensions['center']['rotation']
    local newRot =  rotation * racer.shape:getAt()
    return racer.shape:getWorldPosition() + (newRot * racer.carDimensions['center']['length'])
end 

function getPointRelativeLoc(center,checkPos,checkDir) -- similar to driver vh distances but the old school way
    center.z = checkPos.z --- THis setting of z mutates driver and may loead to unwanted consequences
    local goalVec = (center - checkPos) -- multiply at * velocity? use velocity instead?
    
    local vDist = checkDir:dot(goalVec)
    local hDist = sm.vec3.cross(goalVec,checkDir).z
    --print("v",vDist)
    local vhDifs = {horizontal = hDist, vertical = vDist}
    return vhDifs
end

function offsetAlongVector(location,target,dir) -- grabs offset from a vector
    local goalVec = (target.location - location) -- maybe use mid
    local vecAngle = math.acos(dir:dot(goalVec)/(goalVec:length())) -- convert pos/neg length somehow? ALL OF THIS IS UNECESSARY< JUST TAKE DOT PROCUT for vert dist :(
    local vecDeg = math.deg(vecAngle)
    local remainingDeg = 180 - vecDeg -- angle
    local realAngle = vecDeg -- < 90 and vecDeg or remainingDeg ----makes distance always positive, useful? 
    local realAngleR = math.rad(realAngle) -- convert to radians for sin functions or rewrite sin?
    local dist = goalVec:length() -- Hypotenuse

    local verticalDist = dist * math.cos(realAngleR) -- SocahToah heh
    --local verticalDist2 = math.sqrt( dist^2 - horizontalDist^2)-- pythag, a + b = c, solve for a
    local horizontalDist = dist * math.sin(realAngleR) -- opposite = hyp * sin (can go negative) THREE DIFFERENT WAYS TO DO THIS, only need cross product in the end...?
    --local horizontalDist2 = math.sqrt( dist^2 - verticalDist2^2 ) -- pythag crosscheck (always positive) (takes more calculations)
    --print(horizontalDist)
    local vhDifs = {horizontal = horizontalDist, vertical = verticalDist}
    return vhDifs
end


function getDriverHVDistances(driver,target) -- returns horizontal and vertical distances from driver to target driver
    -- vector angle dif -- Problems: something wierd going on when facing -+x axis with horizontal dist, mismatch distances
    driver.location.z = target.location.z --- THis setting of z mutates driver and may loead to unwanted consequences
    local goalVec = (target.shape.worldPosition - driver.shape.worldPosition) -- multiply at * velocity? use velocity instead?
    
    local vDist = driver.shape.at:dot(goalVec)
    local hDist = sm.vec3.cross(goalVec,driver.shape.at).z
    
    local vhDifs = {horizontal = hDist, vertical = vDist}
    if driver.id == 35715 then
        --print(hDist)
    end
    return vhDifs
end

function getNodeVHDist(driver,node) -- returns offset to a node
    -- vector angle dif -- Problems: something wierd going on when facing -+x axis with horizontal dist, mismatch distances
    driver.location.z = node.location.z
    local goalVec = (node.mid - driver.location) -- multiply at * velocity? use velocity instead?
    
    local hDist = node.perp:dot(goalVec) * -1 -- Left is neg right is pos
    local vDist = sm.vec3.cross(goalVec,node.perp).z
    
    local vhDifs = {horizontal = hDist, vertical = vDist}
    return vhDifs
end

function getLocationVHDist(node,location) -- returns vhDist offset based on a node/location (based off of nodes mid)
    node.location.z = location.z
    local goalVec = (node.mid - location) -- multiply at * velocity? use velocity instead?
    
    local hDist = node.perp:dot(goalVec) * -1 -- Left is neg right is pos
    local vDist = sm.vec3.cross(goalVec,node.perp).z
    
    local vhDifs = {horizontal = hDist, vertical = vDist}
    return vhDifs
end

function getRaceNodeVHDist(node,location) -- returns vhDist offset based on a node/location (based off of nodes mid)
    node.location.z = location.z
    local goalVec = (node.location - location) -- multiply at * velocity? use velocity instead?
    
    local hDist = node.perp:dot(goalVec) * -1 -- Left is neg right is pos
    local vDist = sm.vec3.cross(goalVec,node.perp).z
    
    local vhDifs = {horizontal = hDist, vertical = vDist}
    return vhDifs
end




function getLocationTracPos(loc1,loc2) -- ?
end

function withinBound(location,bound) -- determines if location is within boundaries of bound
	local box1 = {bound.left, bound.left + bound.buffer}
    local box2 = {bound.right, bound.right + bound.buffer}
    local minX = math.min(box1[1].x,box1[2].x,box2[1].x,box2[2].x) -- todo: also store this instead of calculating every time too
	local minY = math.min(box1[1].y,box1[2].y,box2[1].y,box2[2].y)
	local maxX = math.max(box1[1].x,box1[2].x,box2[1].x,box2[2].x) 
	local maxY = math.max(box1[1].y,box1[2].y,box2[1].y,box2[2].y)
	if location.x > minX and location.x < maxX then
		if location.y > minY and location.y < maxY then
			return true
		end
	end
	return false
end

function squareIntersect(location,square) -- determines if location is within boundaries of carBound square
    local minX = math.min(square[1].position.x,square[2].position.x,square[3].position.x,square[4].position.x) -- todo: also store this instead of calculating every time too
	local minY = math.min(square[1].position.y,square[2].position.y,square[3].position.y,square[4].position.y)
	local maxX = math.max(square[1].position.x,square[2].position.x,square[3].position.x,square[4].position.x) 
	local maxY = math.max(square[1].position.y,square[2].position.y,square[3].position.y,square[4].position.y)
	if location.x > minX and location.x < maxX then
		if location.y > minY and location.y < maxY then
			return true
		end
	end
	return false
end



-- format{ front, left, right, back,location,directionF,direction}
function generateBounds(location,dimensions,frontDir,rightDir,padding) -- Generates a 4 node box for front left right and back corners of position
    --print("gen bounds",location,dimensions,frontDir,rightDir,padding,dimensions['front']:length(),dimensions['left']:length())
    local bounds = {
    {['name'] = 'fl', ['position'] = location + (frontDir *  (dimensions['front']:length()*padding) ) + (-rightDir *  dimensions['left']:length()*padding)},
    {['name'] = 'fr', ['position'] = location + (frontDir *  (dimensions['front']:length()*padding) ) + (rightDir *  dimensions['left']:length()*padding)},
    {['name'] = 'bl', ['position'] = location + (-frontDir *  (dimensions['front']:length()*padding) ) + (-rightDir *  dimensions['left']:length()*padding)},
    {['name'] = 'br', ['position'] = location + (-frontDir *  (dimensions['front']:length()*padding) ) + (rightDir *  dimensions['left']:length()*padding)}
    }
    return bounds
end

function getCollisionPotential(selfBox,opBox) -- Determines if bounding box1 colides with box 2
    --print("gettinc colPot",selfBox)
    for k=1, #selfBox do local corner=selfBox[k]
        --print(corner['name'])
        local pos = corner['position']
        if squareIntersect(pos,opBox) then
            return k -- index in selfBox (corner)
        end
    end
    return false
end

-- More node stuff
function getSegment(nodeChain,first,last) -- Shoves first node and last node into a list Possibly Rename to CollectSegment
    local segList = {}
    local node = first
    while node.id ~= last.id do
        table.insert(segList,node)
        node = node.next
    end
    -- put final node in list?
    if node.id == last.id then
        table.insert(segList,node)
    end
    
    return segList
end


function findSegment(nodeChain,segID) --Returns a list of nodes that are in a segment, (could be out of order) (altered binary search??)
    local segList = {}
    local index = 1
    local node = nodeChain[index] -- first node
    local foundSegment = false
    local finding = false
    while (node ~= nil or foundSegment == false) do
        if node.segID == segID then
            table.insert(segList,node)
            if not finding then
                finding = true
            end
        else 
            if finding then
                print("finished finding segment")
                finding = false
                foundSegment = true
            end
        end
        node = getNextItem(nodeChain,index,1)
        index = index + 1
    end    
    return segList
end

function getSegTurn(segType) -- quickly returns -1 - 1 of segment's turn based on the type
    if segType == "Fast_Right" then return 1 
    elseif segType == "Medium_Right" then return 2
    elseif segType == "Slow_Right" then return 3 
    end

    if segType == "Fast_Left" then return -1 
    elseif segType == "Medium_Left" then return -2 
    elseif segType == "Slow_Left" then return -3 
    end
    
    return 0
end

function getNodeAngle(node1,node2) -- gets the angle difference between node 1 in vector and node2 outvector
    local firstVec = node1.inVector
    local lastVec = node2.outVector
    local angle = angleDiff(firstVec,lastVec) *2 -- maybe not as necessary? adjust to fit thresholds
    return angle
end

function defineSegmentType(segment) -- defines a segment based off of invector and outVector
    if segment == nil then
        print("NIl segment")
    end
    if  #segment == 1 then
        --print("single node segment")
    end
    
    local firstVec = segment[1].inVector
    local lastVec = segment[#segment].outVector
    local angle = angleDiff(firstVec,lastVec) *2
    local stype = getSegType(angle)
    if stype == nil then
        print("Something went werong with defining segments")
    else
        --print("got type",stype)
        return stype,angle
    end
end

function setSegmentType(segment,stype,curve,segID) -- Sets all nodes in segment to specified {type}
    for k=1, #segment do local node=segment[k]
        node.segType = stype
        node.segCurve = curve
        node.segID = segID
    end
    if #segment == 1 then
        --print("single set seg",segID,segment[1].id,segment[1].segType.TYPE,segment[1].segID)
    end
end


function getSegType(force)
    for k=1, #SEGMENT_TYPES do local v=SEGMENT_TYPES[k]
        --print("searching",color,v.COLOR)
        if force >= v.THRESHOLD[1] and force < v.THRESHOLD[2] then
            --print("foundSegment",v)
            return v
        end
    end
    print("COULD NOT FIND SEG TIYPE")
end



-- Helpers
function getPosOffset(location,vector,step)
    --print("old location",location,vector,vector*step)
    local newLocation = location  + (vector*step) -- -location?
    return newLocation
end

function getNormalVectorFromPoints(p1,p2)
   -- print("normalizing subtraction?",p2,p1)
    return sm.vec3.normalize(p2-p1)
end


function ratioConversion(a,b,c,d,x) -- Convert x to a ratio from a,b to  c,d
	return c+ (d - c) * (x - b) / (a - b)  -- Scale equation
end

function steeringToDegrees(value) -- Converts a value between -1 and 1 to steering input
    local converted = ratioConversion(-1,1,-MAX_STEER_VALUE,MAX_STEER_VALUE,value)
    if converted > MAX_STEER_VALUE then -- steering limits (could be dynamic?)
        converted = MAX_STEER_VALUE 
    elseif converted < -MAX_STEER_VALUE then 
        converted = -MAX_STEER_VALUE
    end
    return converted
end

function degreesToSteering(value)
    local converted = ratioConversion(-MAX_STEER_VALUE,MAX_STEER_VALUE,-1,1,value)
    --print("got converted",converted)
    if converted > 1 then
        return 1
    elseif converted < -1 then
        return -1
    end
    return converted
end

function degreesToVector(angle)
    local x = math.cos(angle)
    local y = math.sin(angle)
    return sm.vec3.new(x,y,0)
end

function vectorToDegrees(vector)
    return math.deg(math.atan2(vector.y,vector.x))--*180/math.pi
end

function angleToRadians(angle) -- Gets angle in degrees and converts to radians
    return angle*math.pi/180 -- Or just use math.rad
end

function steeringToRadians(steering) -- NOt really necessary because it will just be a combination of before

end

function getEngineType(color)
    for k=1, #ENGINE_TYPES do local v=ENGINE_TYPES[k]
        --print("searching",color,v.COLOR)
        if color == v.COLOR then
            --print("found",v,color)
            return v
        end
    end
end

function getDistance(vector1,vector2) -- GEts the distance of vector by power
    local diff = vector2 - vector1
    local dist = sm.vec3.length(diff)
    return dist
end

function getMidpoint(locA,locB) -- Returns vec3 contianing the midpoint of two vectors
	local midpoint = sm.vec3.new((locA.x +locB.x)/2 ,(locA.y+locB.y)/2,locA.z)
	return midpoint
end

function findFurthestShape(shapeList,direction) -- Finds the furthest shape in the direction out of a list of shapes from a body (make sure body is on lift)
    if #shapeList <= 1 then return shapeList[1] end -- may break but shouldnt be able to be called if no shapes exist in a body
    local furthest = nil
    local dir = {"x",1} -- chooses between x and y and direction (-1,1)
    if direction.x == 0 then
        dir = {"y",direction.y}
    elseif direction.y == 0 then
        dir = {'x',direction.x}
    else
        print("ERROR finding furthest shape",direction)
    end
    --print("scanning dir",dir,direction)
    for k=1, #shapeList do local shape=shapeList[k]
        --print("scanning",shape)
        local curLocation = shape.worldPosition
        if furthest == nil or (curLocation[dir[1]] - furthest.worldPosition[dir[1]]) * dir[2] > 0 then -- subtracts then multiplies by the pos/neg factor
          --print("New furht?",curLocation,dir,furthest)
          furthest = shape
        end
    end
    --print("Found FUrthest",furthest)
    return furthest

end

function getDirectionOffset(shapeList,direction,origin) -- Returns vector offset in relevant direction of the furthest shape from origin
    if shapeList == nil then print("Direction offset Nil shapelist",shapeList) return end
    if direction == nil then print("Direction offset Nil direction",direction) return end
    if origin == nil then print("Direction offset nil origin",origin) return end 

    local furthestShape = findFurthestShape(shapeList,direction)

    local offset = furthestShape.worldPosition-origin

    offset.z = 0 -- Just keep same z value for now
    if direction.x == 0 then
        offset.x = 0
    elseif direction.y == 0 then
        offset.y = 0
    else
        print("ERROR getting direction offset",direction)
        return nil
    end

    return offset

end


function calculateNewForceAngles(v) -- updates forces on a node
    v.outVector = getNormalVectorFromPoints(v.pos,v.next.pos)
    v.inVector = getNormalVectorFromPoints(v.last.pos,v.pos)
    v.force = angleDiff(v.inVector,v.outVector)
    v.perpVector = generatePerpVector(v.outVector)
    return v
end

function validChange(pos,dir,node) -- checks if a movement is valid (in track)
    local valid = false
    local distance = getDistToWall(pos,dir,node.width)
    if distance > WALL_PADDING then -- if not too close to wall
          valid = true
    end
    return valid
end

function getDistToWall(location,direction,width) -- sends out 3? raycasts to determine the distance to the wall, returns distance between vectors
    local zOffsetLimit = 0.6 -- How far above/below to search
    local zOffset = 0 -- unecessary?
    local zStep = 0.05 -- how many things to check
    local vWallDist = width/2
    local vWall = location + (direction*vWallDist) -- location of wall
    local hit,data = sm.physics.raycast(location, location + direction*300)
    if data.valid == false then -- If first try failed, just go all out
        for k=-zOffsetLimit, zOffsetLimit,zStep do 
            local newLocation = location + sm.vec3.new(0,0,k)
            hit,data = sm.physics.raycast(newLocation, newLocation + direction*300)
            if data.valid == false then
                --print("K",k,"DistTo Wallfailed")
            else
                --print("foundWall") -- Possibly validate here
                break --? possibly average rest of measurements?
            end
        end
    end
    if not data.valid then
        return getDistance(location,vWall)
    end
    return getDistance(location,data.pointWorld)
end


function posAngDif(location,vec,pos) -- gets the angle from the given location facing {vector} to a point {pos}
    local goalVec = (pos - location):normalize()
    goalVec.z = vec.z
    local cos = sm.vec3.dot(vec,goalVec) -- (divide by magnitude?)
    --print(cos)
    local bigAngle = math.acos( cos )
    if not bigAngle or tostring(bigAngle) == "nan" or bigAngle ~= bigAngle then
        print("som wong",vec,location,pos,cos,goalVec)
    end
    return bigAngle
end

function getPointAngleDiff(location,target) -- Same as above but probably more precise?
    return math.atan2(target.y-location.y,target.x - location.x)
end


function posAngleDif3(location,vec,target) -- Same as above but probably more precise?
    local goalVec = (target - location):normalize()
    local VangleDif = angleDiff(vec,goalVec)
    --targetAngle = targetAngle - math.atan2(vec.y,vec.x)
    return VangleDif * 9-- Dampen from force sensitivity?
end

function angleDiff(vector1,vector2) -- gets the angle difference between vectors
    local directionalOffset = sm.vec3.dot(vector2,vector1)
	local directionalCross = sm.vec3.cross(vector2,vector1)
    dif = (directionalCross.z) * FORCE_SENSITIVIY
    return dif
end

function generatePerpVector(direction) -- SiteEffect! Z will always be 0, Nomatter what
    if direction == nil then
        print("perp,no direction")
    end
    return sm.vec3.new(direction.y,-direction.x,0) -- banked turns?
end

function calculateTotalForce(nodeChain)
    local totalForce = 0
    for k=1, #nodeChain do local v=nodeChain[k]
        totalForce = totalForce + math.abs(v.force)
    end
    return totalForce
end

function calculateAvgvMax(nodeChain)
    local totalVmax = 0
    local lenChain = #nodeChain
    for k=1, #nodeChain do local v=nodeChain[k]
        totalVmax = totalVmax + ( v.vMaxEst or 0 )
    end
    return totalVmax/lenChain
end

function getSpeedColorScale(minColor,maxColor,value) -- Returns A scaled color Green is 0, red is max
    --print("getting scaled color",minColor,maxColor,value)
    local scaledColor = ratioConversion(minColor,maxColor,0,1,value) -- scale it to be between 0 and 1
    return sm.color.new(2.0 * scaledColor, 2.0 * (1 - scaledColor), 0)
end
    -- Math
function getSign(x) -- helper function until they get addes separtgely
    if x<0 then
      return -1
    elseif x>0 then
      return 1
    else
      return 0
    end
 end

 function round( value )
	return math.floor( value + 0.5 )
end


    -- Data
function tableConcat(t1,t2)
    for i=1,#t2 do
        t1[#t1+1] = t2[i]  --corrected bug. if t1[#t1+i] is used, indices will be skipped
    end
    return t1
end
function debugPrint(debug,info)
    if debug then
        print(info)
    end
end


function toEngineSpeed(velocity) -- Converts car velocity length to engine rotation speed (rate 0.37)*
    return velocity/VELOCITY_ROTATION_RATE 
end
function toVelocity(rotationSpeed) -- Converts car rotation speed approximate velocity
    if rotationSpeed == nil then return 0 end
    return rotationSpeed*VELOCITY_ROTATION_RATE 
end


function getVmax(angle,maxSteer,minSteer,maxVel,minVel)
    --print(maxSteer,DEFAULT_MAX_STEER)
    local k = 1/((maxSteer or DEFAULT_MAX_STEER) -(minSteer or DEFAULT_MINOR_STEER))* math.log((maxVel or DEFAULT_MAX_STEER_VEL)/(minVel or DEFAULT_MINOR_STEER_VEL) )
    local A0 = (minVel or DEFAULT_MINOR_STEER_VEL)* math.exp(-k*(minSteer or DEFAULT_MINOR_STEER))
    return A0 * math.exp(k*angle)
end


function checkMax(previous,current)
    if previous == nil and current == nil then
        print("CheckMax of two nils error")
        return 0
    end

    if previous == nil or current == nil then
        return (current or previous)
    end

    if current > previous then
        return current
    else
        return previous
    end
end

function getNextItem(linkedList,itemIndex,direction) -- Gets {direction} items ahead/behind in a linked list (handles wrapping)
    local nextIndex = 1
    if direction >= 0 then
        nextIndex = (itemIndex + direction -1 ) % #linkedList +1 -- because lua rrays -_-
    else
        nextIndex = (itemIndex + direction + #linkedList -1) %#linkedList + 1
    end
    return linkedList[nextIndex]
end

function getNextIndex(totalIndexes,currentIndex,direction) -- Gets {direction} items ahead/behind in a linked list (handles wrapping)
    local nextIndex = 1
    if direction >= 0 then
        nextIndex = (currentIndex + direction -1 ) % totalIndexes +1 -- because lua rrays -_-
    else
        nextIndex = (currentIndex + direction + totalIndexes -1) %totalIndexes + 1
    end
    return nextIndex    
end


---- Racer meta data helps
function sortRacersByRacePos(inTable)
	print("Sorting Racers")
	return table.sort(inTable, racePosCompare)
end

function racerIDCompare(a,b)
	return a['id'] < b['id']
end 

function racePosCompare(a,b)
	return a['racePosition'] < b['racePosition']
end 

-- Need a check min or some way to figure out which is which
-- *See SMARL FRICTION RESEARCH for data chart
print("loaded globals and helpers")