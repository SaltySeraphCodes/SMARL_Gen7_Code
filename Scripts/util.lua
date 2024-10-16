
print("Utilities Loaded")
function printf( s, ... )
	return print( s:format( ... ) )
end

function clamp( value, min, max )
	if value < min then return min elseif value > max then return max else return value end
end

function round( value )
	return math.floor( value + 0.5 )
end

function max( a, b )
	return a > b and a or b
end

function min( a, b )
	return a < b and a or b
end

function sign( value )
	return value >= DBL_EPSILON and 1 or ( value <= -DBL_EPSILON and -1 or 0 )
end

function lerp( a, b, p )
	return clamp( a + (b - a) * p, min(a, b), max(a, b) )
end

function easeIn( a, b, dt, speed )
	local p = 1 - math.pow( clamp( speed, 0.0, 1.0 ), dt * 60 )
	return lerp( a, b, p )
end

function unclampedLerp( a, b, p )
	return a + (b - a) * p
end

function isAnyOf(is, off)
	for _, v in pairs(off) do
		if is == v then
			return true
		end
	end
	return false
end

function valueExists( array, value )
	for _, v in ipairs( array ) do
		if v == value then
			return true
		end
	end
	return false
end

 function concat(a, b)
	for _, v in pairs(b) do
		a[#a+1] = v;
	end
end

--http://lua-users.org/wiki/SwitchStatement
function switch( table )
	table.case = function ( self, caseVariable )
		local caseFunction = self[caseVariable] or self.default
		if caseFunction then
			if type( caseFunction ) == "function" then
				caseFunction( caseVariable, self )
			else
				error( "case " .. tostring( caseVariable ).." not a function" )
			end
		end
	end
	return table
end


function addToArrayIfNotExists( array, value )
	local n = #array
	local exists = false
	for i = 1, n do
		if array[i] == value then
			return
		end
	end
	array[n + 1] = value
end


function removeFromArray( array, fnShouldRemove )
	local n = #array;
	local j = 1
	for i = 1, n do
		if fnShouldRemove( array[i] ) then
			array[i] = nil;
		else
			if i ~= j then
				array[j] = array[i];
				array[i] = nil;
			end
			j = j + 1;
		end
	end
	return array;
end

function CellKey( x, y )
	return ( y + 1024 ) * 2048 + x + 1024
end

function isHarvest( shapeUuid )

	local harvests = sm.json.open("$SURVIVAL_DATA/Objects/Database/ShapeSets/harvests.json")
	for i, harvest in ipairs(harvests.partList) do
		local harvestUuid = sm.uuid.new( harvest.uuid )
		if harvestUuid == shapeUuid then
			return true
		end
	end

	return false
end


function isPipe( shapeUuid )

	local pipeList = {}
	pipeList[#pipeList+1] = sm.uuid.new( "9dd5ee9c-aa5c-4bec-8fc2-a67999697085") --PipeStraight
	pipeList[#pipeList+1] = sm.uuid.new( "7f658dcd-e31d-4890-b4a7-4cd5e1378eaf") --PipeBend
	pipeList[#pipeList+1] = sm.uuid.new( "339dc807-099c-449f-bc4b-ecad92e9908d") --PneumaticPump
	pipeList[#pipeList+1] = sm.uuid.new( "28f536f2-f812-4bd4-821f-483a76f55de3") --PipeMerger

	for i, pipeUuid in ipairs(pipeList) do
		if shapeUuid == pipeUuid then
			return true
		end
	end

	return false

end

function getCell( x, y )
	return math.floor( x / 64 ), math.floor( y / 64 )
end

-- Allows to iterate a table of form [key, value, key, value, key, value]
function kvpairs(t)
	local i = 1
	local n = #t
	return function ()
		if i < n then
			local a = t[i]
			local b = t[i + 1]
			i = i + 2
			return a, b
		end
	end
end

function reverse_ipairs( a )
	function iter( a, i )
		i = i - 1
		local v = a[i]
		if v then
			return i, v
		end
	end
	return iter, a, #a + 1
end

function shuffle( array, first, last )
	first = first or 1
	last = last or #array
	for i = last, 1 + first, -1 do
		local j = math.random( first, i )
		array[i], array[j] = array[j], array[i]
	end
	return array
end

function reverse( array )
	local i, j = 1, #array
	while i < j do
		array[i], array[j] = array[j], array[i]
		i = i + 1
		j = j - 1
	end
end

function shallowcopy( orig )
	local orig_type = type( orig )
	local copy
	if orig_type == 'table' then
		copy = {}
		for orig_key, orig_value in pairs( orig ) do
			copy[orig_key] = orig_value
		end
	else -- number, string, boolean, etc
		copy = orig
	end
	return copy
end

function closestPointOnLineSegment( line0, line1, point )
	local vec = line1 - line0
	local len = vec:length()
	local dist = ( vec / len ):dot( point - line0 )
	local t = sm.util.clamp( dist / len, 0, 1 )
	return line0 + vec * t, t, len
end

function closestPointInLines( linePoints, point )
	local closest
	if #linePoints > 1 then
		local closestDistance2 = math.huge
		for i = 1, #linePoints - 1 do
			local pt, t, len = closestPointOnLineSegment( linePoints[i], linePoints[i + 1], point )
			local distance2 = ( pt - point ):length2()
			if distance2 < closestDistance2 then
				closest = { i = i, pt = pt, t = t, len = len }
				closestDistance2 = distance2
			end
		end
	elseif #linePoints == 1 then
		closest = { i = 1, pt = linePoints[1], t = 0, len = 1 }
	end
	return closest
end

function closestPointInLinesSkipFirst( linePoints, point )
	local closest
	if #linePoints > 1 then
		local closestDistance2 = math.huge
		for i = 2, #linePoints - 1 do
			local pt, t, len = closestPointOnLineSegment( linePoints[i], linePoints[i + 1], point )
			local distance2 = ( pt - point ):length2()
			if distance2 < closestDistance2 then
				closest = { i = i, pt = pt, t = t, len = len }
				closestDistance2 = distance2
			end
		end
	elseif #linePoints == 1 then
		closest = { i = 1, pt = linePoints[1], t = 0, len = 1 }
	end
	return closest
end


function lengthOfLines( linePoints )
	local lines = {}
	local totalLength = 0
	if #linePoints > 1 then
		for i = 1, #linePoints - 1 do
			lines[i] = {}
			lines[i].p0 = linePoints[i]
			lines[i].p1 = linePoints[i+1]
			lines[i].length = ( lines[i].p1 - lines[i].p0 ):length()
			totalLength = totalLength + lines[i].length
		end
	end
	return totalLength, lines
end

function closestFractionInLines( linePoints, point )
	if #linePoints > 1 then
		local closest = closestPointInLines( linePoints, point )
		return ( ( closest.i - 1 ) + closest.t ) / #linePoints
	elseif #linePoints == 1 then
		return 1.0
	end
end

function pointInLines( linePoints, fraction )
	local totalLength, lines = lengthOfLines( linePoints )

	if totalLength == 0 then
		return linePoints[1]
	end

	local point
	for i = 1, #lines do
		lines[i].minFraction = 0.0
		lines[i].maxFraction = lines[i].length / totalLength
		if lines[i-1] then
			lines[i].minFraction = lines[i].minFraction + lines[i-1].maxFraction
			lines[i].maxFraction = lines[i].maxFraction + lines[i-1].maxFraction
		end
		if i == #lines then
			lines[i].maxFraction = 1.0
		end

		if fraction >= lines[i].minFraction and fraction <= lines[i].maxFraction then
			local f = ( fraction - lines[i].minFraction ) / ( lines[i].maxFraction - lines[i].minFraction )
			point = sm.vec3.lerp( lines[i].p0, lines[i].p1, f )
			break
		end
	end

	return point
end

-- p = progress from first point (1) to last point (#points)
function spline( points, p, distances )
	assert( #points > 1, "Must have at least 2 points" )
	local i0 = math.floor( p )
	if i0 < 1 then
		i0 = 1
		p = 1
	elseif i0 >= #points then
		i0 = #points - 1
		p = #points
	end

	local u
	local ui
	if distances then
		local invDistance = 1 / distances[#distances]
		u = ( ( p - i0 ) * ( distances[i0 + 1] - distances[i0] ) + distances[i0] ) * invDistance
		ui = function( o )
			local i = i0 + o
			if i < 1 then i = 1 end
			if i > #distances then i = #distances end
			return distances[i] * invDistance
		end
	else
		u = p
		ui = function( o ) return i0 + o end
	end

	local pt1_0 = points[math.max( i0 - 1, 1 )]
	local pt2_0 = points[i0]
	local pt3_0 = points[i0 + 1]
	local pt4_0 = points[math.min( i0 + 2, #points )]

	local pt1_1 = sm.vec3.lerp( pt1_0, pt2_0, ( u - ui(-2 ) ) / ( ui( 1 ) - ui(-2 ) ) )
	local pt2_1 = sm.vec3.lerp( pt2_0, pt3_0, ( u - ui(-1 ) ) / ( ui( 2 ) - ui(-1 ) ) )
	local pt3_1 = sm.vec3.lerp( pt3_0, pt4_0, ( u - ui( 0 ) ) / ( ui( 3 ) - ui( 0 ) ) )

	local pt1_2 = sm.vec3.lerp( pt1_1, pt2_1, ( u - ui(-1 ) ) / ( ui( 1 ) - ui(-1 ) ) )
	local pt2_2 = sm.vec3.lerp( pt2_1, pt3_1, ( u - ui( 0 ) ) / ( ui( 2 ) - ui( 0 ) ) )

	local pt1_3 = sm.vec3.lerp( pt1_2, pt2_2, ( u - ui( 0 ) ) / ( ui( 1 ) - ui( 0 ) ) )

	return pt1_3, pt1_2, pt2_2, pt1_1, pt2_1, pt3_1
end

function getClosestShape( body, position )
	local closestShape = nil
	local closestDistance = math.huge
	local shapes = body:getShapes()
	for _, shape in ipairs( shapes ) do
		local distance = ( shape.worldPosition - position ):length()
		if closestShape then
			if distance < closestDistance then
				closestShape = shape
				closestDistance = distance
			end
		else
			closestShape = shape
			closestDistance = distance
		end
	end

	return closestShape
end

function lerpDirection( fromDirection, toDirection, p )
	local cameraHeading = math.atan2( -fromDirection.x, fromDirection.y )
	local cameraPitch = math.asin( fromDirection.z )

	local cameraDesiredHeading = math.atan2( -toDirection.x, toDirection.y )
	local cameraDesiredPitch = math.asin( toDirection.z )

	local shortestAngle = ( ( ( cameraDesiredHeading - cameraHeading ) % ( 2 * math.pi ) + 3 * math.pi ) % ( 2 * math.pi ) ) - math.pi
	cameraDesiredHeading = cameraHeading + shortestAngle

	cameraHeading = sm.util.lerp( cameraHeading, cameraDesiredHeading, p )
	cameraPitch = sm.util.lerp( cameraPitch, cameraDesiredPitch, p )

	local newCameraDirection = sm.vec3.new( 0, 1, 0 )
	newCameraDirection = newCameraDirection:rotateX( cameraPitch )
	newCameraDirection = newCameraDirection:rotateZ( cameraHeading )

	return newCameraDirection
end

function magicDirectionInterpolation( currentDirection, desiredDirection, dt, speed )
	-- Smooth heading and pitch movement
	local speed = speed or ( 1.0 / 6.0 )
	local blend = 1 - math.pow( 1 - speed, dt * 60 )
	return lerpDirection( currentDirection, desiredDirection, blend )
end

function magicPositionInterpolation( currentPosition, desiredPosition, dt, speed )
	local speed = speed or ( 1.0 / 6.0 )
	local blend = 1 - math.pow( 1 - speed, dt * 60 )
	return sm.vec3.lerp( currentPosition, desiredPosition, blend )
end

function magicInterpolation( currentValue, desiredValue, dt, speed )
	local speed = speed or ( 1.0 / 6.0 )
	local blend = 1 - math.pow( 1 - speed, dt * 60 )
	return sm.util.lerp( currentValue, desiredValue, blend )
end

function isDangerousCollisionShape( shapeUuid )
	return isAnyOf( shapeUuid, { obj_powertools_drill, obj_powertools_sawblade } )
end

function isSafeCollisionShape( shapeUuid )
	return isAnyOf( shapeUuid, { obj_scrap_smallwheel, obj_vehicle_smallwheel, obj_vehicle_bigwheel, obj_spaceship_cranewheel } )
end

function isTrapProjectile( projectileName )
	local TrapProjectiles = { "tape", "explosivetape" }
	return isAnyOf( projectileName, TrapProjectiles )
end

function isIgnoreCollisionShape( shapeUuid )
	return isAnyOf( shapeUuid, {
		obj_harvest_metal,

		obj_robotparts_tapebothead01,
		obj_robotparts_tapebottorso01,
		obj_robotparts_tapebotleftarm01,
		obj_robotparts_tapebotshooter,

		obj_robotparts_haybothead,
		obj_robotparts_haybotbody,
		obj_robotparts_haybotfork,

		obj_robotpart_totebotbody,
		obj_robotpart_totebotleg,

		obj_robotparts_farmbotpart_head,
		obj_robotparts_farmbotpart_cannonarm,
		obj_robotparts_farmbotpart_drill,
		obj_robotparts_farmbotpart_scytharm
	} )
end

function getTimeOfDayString()
	local timeOfDay = sm.game.getTimeOfDay()
	local hour = ( timeOfDay * 24 ) % 24
	local minute = ( hour % 1 ) * 60
	local hour1 = math.floor( hour / 10 )
	local hour2 = math.floor( hour - hour1 * 10 )
	local minute1 = math.floor( minute / 10 )
	local minute2 = math.floor( minute - minute1 * 10 )

	return hour1..hour2..":"..minute1..minute2
end

function formatCountdown( seconds )
	local time = seconds / DAYCYCLE_TIME
	local days = math.floor(( time * 24 ) / 24)
	local hour = ( time * 24 ) % 24
	local minute = ( hour % 1 ) * 60
	local hour1 = math.floor( hour / 10 )
	local hour2 = math.floor( hour - hour1 * 10 )
	local minute1 = math.floor( minute / 10 )
	local minute2 = math.floor( minute - minute1 * 10 )

	return days.."d "..hour1..hour2.."h "..minute1..minute2.."m"
end

function getDayCycleFraction()

	local time = sm.game.getTimeOfDay()

	local index = 1
	while index < #DAYCYCLE_SOUND_TIMES and time >= DAYCYCLE_SOUND_TIMES[index + 1] do
		index = index + 1
	end
	assert( index <= #DAYCYCLE_SOUND_TIMES )

	local night = 0.0
	if index < #DAYCYCLE_SOUND_TIMES then
		local p = ( time - DAYCYCLE_SOUND_TIMES[index] ) / ( DAYCYCLE_SOUND_TIMES[index + 1] - DAYCYCLE_SOUND_TIMES[index] )
		night = sm.util.lerp( DAYCYCLE_SOUND_VALUES[index], DAYCYCLE_SOUND_VALUES[index + 1], p )
	else
		night = DAYCYCLE_SOUND_VALUES[index]
	end

	return 1.0 - night
end

function getTicksUntilDayCycleFraction( dayCycleFraction )
	local time = sm.game.getTimeOfDay()
	local timeDiff = ( time > dayCycleFraction ) and ( dayCycleFraction - time ) + 1.0 or ( dayCycleFraction - time )
	return math.floor( timeDiff * DAYCYCLE_TIME * 40 + 0.5 )
end

-- Brute force testing of a function for randomizing integer ranges
function testRandomFunction( fn )
	local a = {}
	local sum = 0
	for i = 1,1000000 do
		local n = fn()
		a[n] = a[n] and a[n] + 1 or 1
		sum = sum + n
	end

	for n,v in pairs( a ) do
		print( n, "=", (v / 10000).."%" )
	end
	print( "avg =", sum / 1000000 )
end

function randomStackAmount( min, mean, max )
	return clamp( round( sm.noise.randomNormalDistribution( mean, ( max - min + 1 ) * 0.25 ) ), min, max )
end

function randomStackAmount2()
	return randomStackAmount( 1, 1, 2 )
end

function randomStackAmountAvg2()
	return randomStackAmount( 1, 2, 3 )
end

function randomStackAmountAvg3()
	return randomStackAmount( 2, 3, 4 )
end

function randomStackAmount5()
	return randomStackAmount( 2, 3.5, 5 )
end

function randomStackAmountAvg5()
	return randomStackAmount( 3, 5, 7 )
end

function randomStackAmount10()
	return randomStackAmount( 5, 7.5, 10 )
end

function randomStackAmountAvg10()
	return randomStackAmount( 5, 10, 15 )
end

function randomStackAmount20()
	return randomStackAmount( 10, 15, 20 )
end

function GetOwnerPosition( tool )
	local playerPosition = sm.vec3.new( 0, 0, 0 )
	local player = tool:getOwner()
	if player and player.character and sm.exists( player.character ) then
		playerPosition = player.character.worldPosition
	end
	return playerPosition
end

function CharacterCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal )

	if type( other ) == "Shape" and not sm.exists( other ) then
		return 0, 0
	end

	if type( other ) == "Shape" and sm.exists( other ) then
		if isIgnoreCollisionShape( other:getShapeUuid() ) then
			return 0, 0
		end
	end

	local fallDamageFraction = 0
	local collisionDamageFraction = 0
	local specialCollisionDamageFraction = 0
	local fallTumbleTicks = 0
	local collisionTumbleTicks = 0
	local specialCollision = false

	-- Fall damage
	local dotThreshold = 0.85
	local fallMinVelocity = 19.5
	local fallMaxVelocity = 34.5
	local fallRangeScale = math.min( math.max( ( ( -selfPointVelocity.z - fallMinVelocity ) ) / ( fallMaxVelocity - fallMinVelocity ), 0.0 ), 1.0 )
	local fallDotFraction = math.abs( collisionNormal:dot( sm.vec3.new( 0, 0, 1 ):normalize() ) )
	fallDotFraction = ( ( fallDotFraction > dotThreshold ) and fallDotFraction or 0 ) -- Filter friction fall damage
	fallDamageFraction = fallRangeScale * fallDotFraction
	if fallRangeScale * fallDotFraction > 0.5 then
		fallTumbleTicks = MEDIUM_TUMBLE_TICK_TIME
	end

	if type( other ) == "Shape" then

		-- Special damage
		if isDangerousCollisionShape( other:getShapeUuid() ) then
			local angularVelocity = other.body.angularVelocity
			if angularVelocity:length() > SPINNER_ANGULAR_THRESHOLD then
				if self.specialHitsToDie and self.specialHitsToDie > 0 then
					specialCollisionDamageFraction = 1.0 / self.specialHitsToDie
				else
					specialCollisionDamageFraction = MEDIUM_DAMAGE
				end
				specialCollision = true
			end
		end

		-- Collision damage
		if not isSafeCollisionShape( other:getShapeUuid() ) then

			local massThresholdSmall = 35.0 --3x3 wood blocks
			local massThresholdLarge = 4000.0
			local speedThresholdSlow = 3.0
			local speedThresholdFast = 34.0

			local impactSpeedDiff = math.max( ( otherPointVelocity - selfPointVelocity ):dot( collisionNormal ), 0.0 )
			local impactSpeedOther = math.max( otherPointVelocity:dot( collisionNormal ), 0.0 )
			local impactSpeed = math.min( impactSpeedDiff, impactSpeedOther )
			local tweakedSpeed = impactSpeed * impactSpeed
			local otherMass = 0
			if type(other) == "Shape" and sm.exists( other ) then
				otherMass = other:getBody().mass
			end

			if tweakedSpeed >= speedThresholdSlow * speedThresholdSlow and otherMass >= massThresholdSmall then

				if tweakedSpeed < speedThresholdFast * speedThresholdFast then
					if otherMass < massThresholdLarge then
						collisionDamageFraction = SMALL_DAMAGE
						collisionTumbleTicks = SMALL_TUMBLE_TICK_TIME
					else
						collisionDamageFraction = MEDIUM_DAMAGE
						collisionTumbleTicks = MEDIUM_TUMBLE_TICK_TIME
					end
				else
					if otherMass < massThresholdLarge then
						collisionDamageFraction = MEDIUM_DAMAGE
						collisionTumbleTicks = SMALL_TUMBLE_TICK_TIME
					else
						collisionDamageFraction = LARGE_DAMAGE
						collisionTumbleTicks = LARGE_TUMBLE_TICK_TIME
					end
				end
			end

		end
	end

	local damageFraction = math.max( math.max( fallDamageFraction, collisionDamageFraction ), specialCollisionDamageFraction )
	local tumbleTicks = specialCollision and 0 or math.max( fallTumbleTicks, collisionTumbleTicks )

	return damageFraction, tumbleTicks
end

function ApplyKnockback( targetCharacter, direction, power )

	local impulseDirection = direction
	impulseDirection.z = 0
	if impulseDirection:length() >= FLT_EPSILON then
		impulseDirection = impulseDirection:normalize()
		local rightVector =  impulseDirection:cross( sm.vec3.new( 0, 0, 1 ) )
		impulseDirection = impulseDirection:rotate( 0.523598776, rightVector ) -- 30 degrees
	elseif direction:length() >= FLT_EPSILON then
		impulseDirection = direction:normalize()
	end

	local massImpulse = power / ( 5000.0 / 10.0 )
	local massImpulseSqrt = power / ( 5000.0 / 12.0 )
	local impulse = math.min( targetCharacter.mass * massImpulse + math.sqrt( targetCharacter.mass ) * massImpulseSqrt, power )
	impulse = math.min( impulse, MAX_CHARACTER_KNOCKBACK_VELOCITY * targetCharacter.mass )

	if targetCharacter:isTumbling() then
		targetCharacter:applyTumblingImpulse( impulseDirection * impulse )
	else
		sm.physics.applyImpulse( targetCharacter, impulseDirection * impulse )
	end

end

function GetClosestPlayer( worldPosition, maxDistance )
	local closestPlayer = nil
	local closestDd = maxDistance and ( maxDistance * maxDistance ) or math.huge
	local players = sm.player.getAllPlayers()
	for _, player in ipairs( players ) do
		if player.character then
			local dd = ( player.character.worldPosition - worldPosition ):length2()
			if dd <= closestDd then
				closestPlayer = player
				closestDd = dd
			end
		end
	end
	return closestPlayer
end

local ToolItems = {
	[tostring( tool_connect )] = obj_tool_connect,
	[tostring( tool_paint )] = obj_tool_paint,
	[tostring( tool_weld )] = obj_tool_weld,
	[tostring( tool_spudgun )] = obj_tool_spudgun,
	[tostring( tool_shotgun )] = obj_tool_frier,
	[tostring( tool_gatling )] = obj_tool_spudling
}
function GetToolProxyItem( toolUuid )
	return ToolItems[tostring( toolUuid )]
end

function FindFirstInteractable( uuid )
	local bodies = sm.body.getAllBodies()
	for _, body in ipairs( bodies ) do
		for _, shape in ipairs( body:getShapes() ) do
			if tostring( shape:getShapeUuid() ) == uuid then
				return shape:getInteractable()
			end
		end
	end	
end

function FindFirstInteractableWithinCell( uuid, x, y )
	local bodies = sm.body.getAllBodies()
	for _, body in ipairs( bodies ) do
		for _, shape in ipairs( body:getShapes() ) do
			if tostring( shape:getShapeUuid() ) == uuid then
				local ix, iy = getCell( shape:getWorldPosition().x, shape:getWorldPosition().y )
				if ix == x and iy == y then
					return shape:getInteractable()
				end
			end
		end
	end	
end

function FindInteractablesWithinCell( uuid, x, y )
	local tbl = {}
	local bodies = sm.body.getAllBodies()
	for _, body in ipairs( bodies ) do
		for _, shape in ipairs( body:getShapes() ) do
			if tostring( shape:getShapeUuid() ) == uuid then
				local ix, iy = getCell( shape:getWorldPosition().x, shape:getWorldPosition().y )
				if ix == x and iy == y then
					table.insert( tbl, shape:getInteractable() )
				end
			end
		end
	end
	return tbl	
end

function ConstructionRayCast( constructionFilters )

	local valid, result = sm.localPlayer.getRaycast( 7.5 )
	if valid then
		for _, filter in ipairs( constructionFilters ) do
			if result.type == filter then

				local groundPointOffset = -( sm.construction.constants.subdivideRatio_2 - 0.04 + sm.construction.constants.shapeSpacing + 0.005 )
				local pointLocal = result.pointLocal + result.normalLocal * groundPointOffset

				-- Compute grid pos
				local size = sm.vec3.new( 3, 3, 1 )
				local size_2 = sm.vec3.new( 1, 1, 0 )
				local a = pointLocal * sm.construction.constants.subdivisions
				local gridPos = sm.vec3.new( math.floor( a.x ), math.floor( a.y ), a.z ) - size_2

				-- Compute world pos
				local worldPos = gridPos * sm.construction.constants.subdivideRatio + ( size * sm.construction.constants.subdivideRatio ) * 0.5

				return valid, worldPos, result.normalWorld
			end
		end
	end
	return false, nil, nil
end

local function getWorld( userdataObject )
	if userdataObject and isAnyOf( type( userdataObject ), { "Character", "Body", "Player", "Unit", "Shape", "Interactable", "Joint", "World" } ) then
		if sm.exists( userdataObject ) then
			if type( userdataObject ) == "Character" or type( userdataObject ) == "Body" then
				return userdataObject:getWorld()
			elseif type( userdataObject ) == "Player" or type( userdataObject ) == "Unit" then
				if userdataObject.character then
					return userdataObject.character:getWorld()
				end
			elseif type( userdataObject ) == "Shape" or type( userdataObject ) == "Interactable" then
				if userdataObject.body then
					return userdataObject.body:getWorld()
				end
			elseif type( userdataObject ) == "Joint" then
				local hostShape = userdataObject:getShapeA()
				if hostShape and hostShape.body then
					return hostShape.body:getWorld()
				end
			elseif type( userdataObject ) == "World" then
				return userdataObject
			end
			return nil
		else
			return nil
		end
	end
	sm.log.warning( "Tried to get world for an unsupported type: "..type( userdataObject ) )
	return nil
end

function InSameWorld( userdataObjectA, userdataObjectB )
	local worldA = getWorld( userdataObjectA )
	local worldB = getWorld( userdataObjectB )

	local result = ( worldA ~= nil and worldB ~= nil and worldA == worldB )
	return result
end

function FindAttackableShape( worldPosition, radius, attackLevel )
	local nearbyShapes = sm.shape.shapesInSphere( worldPosition, radius )
	local destructableNearbyShapes = {}
	for _, shape in ipairs( nearbyShapes )do
		local shapeQualityLevel = sm.item.getQualityLevel( shape.shapeUuid )
		if shape.destructable and attackLevel >= shapeQualityLevel and shapeQualityLevel > 0 then
			destructableNearbyShapes[#destructableNearbyShapes+1] = shape
		end
	end
	if #destructableNearbyShapes > 0 then
		local targetShape = destructableNearbyShapes[math.random( 1, #destructableNearbyShapes )]
		local targetPosition = targetShape.worldPosition
		if sm.item.isBlock( targetShape.shapeUuid ) then
			local targetLocalPosition = targetShape:getClosestBlockLocalPosition( worldPosition )
			targetPosition = targetShape.body:transformPoint( ( targetLocalPosition + sm.vec3.new( 0.5, 0.5, 0.5 ) ) * 0.25 )
		end
		return targetShape, targetPosition
	end
	return nil, nil
end

-- Color interploate
function colourLerp(c1, c2, t)
    local r = sm.util.lerp(c1.r, c2.r, t)
    local g = sm.util.lerp(c1.g, c2.g, t)
    local b = sm.util.lerp(c1.b, c2.b, t)
    return sm.color.new(r,g,b)
end

--returns whatever the raycast hit
function Raycast_GetHitObj(raycastResult)
    return raycastResult:getShape() or raycastResult:getBody() or raycastResult:getCharacter() or raycastResult:getHarvestable() or raycastResult:getJoint() or raycastResult.type
end


Line = class()
local line_up = sm.vec3.new(0,1,0)

---@param thickness number
---@param colour Color
---@param soundEffect string
---@param endParticle string
function Line:init( thickness, colour, soundEffect, endParticle )
    self.effect = sm.effect.createEffect("ShapeRenderable")
    self.effect:setParameter("uuid", sm.uuid.new("b6cedcb3-8cee-4132-843f-c9efed50af7c"))
    self.effect:setParameter("color", colour)
    self.effect:setScale( sm.vec3.one() * thickness )

    if soundEffect then
        self.sound = sm.effect.createEffect( soundEffect )
    end

    self.colour = colour
    self.thickness = thickness
    self.endParticle = endParticle
    self.spinTime = 0
end


---@param startPos Vec3
---@param endPos Vec3
---@param dt number
---@param spinSpeed number
function Line:update( startPos, endPos, dt, spinSpeed )
    local delta = endPos - startPos
    local length = delta:length()

    if length < 0.0001 then return end

    local rot = sm.vec3.getRotation(line_up, delta)
    self.spinTime = self.spinTime + (dt or 0) * (spinSpeed or 0)
    rot = rot * sm.quat.angleAxis( math.rad(self.spinTime), line_up )

    local distance = sm.vec3.new(length, self.thickness, self.thickness)

    self.effect:setPosition(startPos + delta * 0.5)
    self.effect:setScale(distance)
    self.effect:setRotation(rot)

    if self.endParticle then
        sm.particle.createParticle( self.endParticle, endPos, sm.quat.identity(), self.colour )
    end

    if self.sound then
        self.sound:setPosition(startPos)
        if not self.sound:isPlaying() then
            self.sound:start()
        end
    end

    if not self.effect:isPlaying() then
        self.effect:start()
    end
end

function Line:stop()
    self.effect:stopImmediate()

    if self.sound then
        self.sound:stopImmediate()
    end
end

--[[
usage:
Draws a line from the player character to the point theyre aiming at(only for the person who owns the tool)
```lua
Tool = class()
function Tool:client_onCreate()
    self.line = Line()
    self.line:init( 0.1, sm.color.new(1,1,1) )
end

function Tool:client_onEquippedUpdate( lmb )
    local shouldStop = not lmb
    if lmb then
        local hit, result = sm.localPlayer.getPlayer(7.5)
        shouldStop = not hit

        if hit then
            self.line:update( self.tool:getPosition(), result.pointWorld )
        end
    end

    if shouldStop and self.line.effect:isPlaying() then
        self.line:stop()
    end
end
```]]


--convert a blueprint to dynamic or static (for importing with sm.creation)
function convertBlueprint( bp, dynamic )
  local bodies = bp.bodies
  if #bodies ~= 0 then
    for k, body in pairs( bodies ) do
      bp.bodies[k].type = dynamic and 0 or 1
    end
  end
end
--Example usage:
--Load the blueprint file with `sm.json.open`, then call this function with the blueprint table as the first param. The second parameter decides between static and dynamic, `true` = dynamic, `false` or `nil` = static.
--Then convert the blueprint table to a json string using `sm.json.writeJsonString` and import it with `sm.creation.importFromString`. Don't forget to enable the `importTransforms` parameter, else it won't apply the setting.

