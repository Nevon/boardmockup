Class = require "lib.class"
require "lib.LUBE"

local server = true
local conn
local numConnected = 0

Marker = Class{function(self, id, kind)
	self.id = id
	self.kind = kind
	self.radius = 37
	self.x = math.random(0, 1125)
	self.y = math.random(0, 590)	
end}

function Marker:draw()
	if self.kind == 'detective' then
		love.graphics.setColor(255,0,0,255)
		love.graphics.circle('fill', self.x, self.y, self.radius, self.radius)
		love.graphics.setColor(255,255,255,255)
	elseif self.kind == 'criminal' then
		love.graphics.setColor(0,255,0,255)
		love.graphics.circle('fill', self.x, self.y, self.radius, self.radius)
		love.graphics.setColor(255,255,255,255)
	else
		love.graphics.setColor(0,0,0,255)
		love.graphics.circle('fill', self.x, self.y, self.radius, self.radius)
		love.graphics.setColor(255,255,255,255)
	end
end

function Marker:moved(x, y, remote)
	print (self.kind .. " (" .. self.id .. ") " .. "was moved to " .. x .. "/" .. y)

	self.x = x
	self.y = y

	love.audio.play('sounds/place.ogg')

	--Move 
	local thisMarker
	for i,v in ipairs(markers) do
		if self.id == v.id then
			thisMarker = table.remove(markers, i)
			break
		end
	end

	table.insert(markers, thisMarker)

	if not remote then
		conn:send(("moved:%d:%d:%d\n"):format(self.id, x, y))
	end
end

function Marker:clicked(x, y)
	--Point in rect
	if distance(self.x, self.y, x, y) <= self.radius then
		print (self.kind .. ' ('.. self.id ..') was clicked')
		return true
	else
		return false
	end
end

function ripairs(t)
  local max = 1
  while t[max] ~= nil do
    max = max + 1
  end
  local function ripairs_it(t, i)
    i = i-1
    local v = t[i]
    if v ~= nil then
      return i,v
    else
      return nil
    end
  end
  return ripairs_it, t, max
end

function distance(x1, y1, x2, y2)

	local dx=x2-x1
	local dy=y2-y1

	return math.sqrt(math.pow(dx,2)+math.pow(dy,2))
end

do
    -- will hold the currently playing sources
    local sources = {}

    -- check for sources that finished playing and remove them
    -- add to love.update
    function love.audio.update()
        local remove = {}
        for _,s in pairs(sources) do
            if s:isStopped() then
                remove[#remove + 1] = s
            end
        end

        for i,s in ipairs(remove) do
            sources[s] = nil
        end
    end

    -- overwrite love.audio.play to create and register source if needed
    local play = love.audio.play
    function love.audio.play(what, how, loop)
        local src = what
        if type(what) ~= "userdata" or not what:typeOf("Source") then
            src = love.audio.newSource(what, how)
            src:setLooping(loop or false)
        end

        play(src)
        sources[src] = src
        return src
    end

    -- stops a source
    local stop = love.audio.stop
    function love.audio.stop(src)
        if not src then return end
        stop(src)
        sources[src] = nil
    end
end

local function clientRecv(data)
	data = data:match("^(.-)\n*$")
	if data:match("^moved:") then
		local id, x, y = data:match("^moved:(%d+):(%d+):(%d+)")
		assert(id, "Invalid message")
		id, x, y = tonumber(id), tonumber(x), tonumber(y)
		for i, v in ipairs(markers) do
			if v.id == id then
				v:moved(x, y, true)
				break
			end
		end
	end
end

local function serverRecv(data, clientid)
	data = data:match("^(.-)\n*$")
	if data:match("^getMarkers") then
		for i = 1, #markers do
			conn:send(
				("%d:%d:%d\n"):format(markers[i].id, markers[i].x, markers[i].y),
				clientid)
		end
	else
		return clientRecv(data)
	end
end

local function prepareNetwork(args)
	if args[1] == "client" then
		server = false
		table.remove(args, 1)
	else
		if args[1] == "server" then
			table.remove(args, 1)
		else
			print("Invalid mode, defaulting to server")
		end
		server = true
	end

	if server then
		conn = lube.tcpServer()
		conn.handshake = "helloCardboard"
		conn:setPing(true, 16, "areYouStillThere?\n")
		conn:listen(3410)
		conn.callbacks.recv = serverRecv
		conn.callbacks.connect = function() numConnected = numConnected + 1 end
		conn.callbacks.disconnect = function() numConnected = numConnected - 1 end
	else
		local host = args[1]
		if not host then
			print("Invalid host, defaulting to localhost")
			host = "localhost"
		end
		conn = lube.tcpClient()
		conn.handshake = "helloCardboard"
		conn:setPing(true, 2, "areYouStillThere?\n")
		assert(conn:connect(host, 3410, true))
		conn.callbacks.recv = clientRecv
	end
end

local getLine
do
	local msg
	local it

	local function getMsg()
		repeat
			msg = conn:receive()
			love.timer.sleep(0.005)
		until msg
	end

	function getLine()
		if not msg then
			getMsg()
			it = msg:gmatch("[^\n]+")
		end
		local line = it()
		if not line then
			msg = nil
			return getLine()
		end
		return line
	end
end

local function prepareMarkers()
	if server then
		--Shuffle the shit out of it
		for i=#markers, 1, -1 do
			local toMove = math.random(i)
			markers[toMove], markers[i] = markers[i], markers[toMove]
		end
	else
		local msg, line, id, x, y
		conn:send("getMarkers\n")
		for i = 1, #markers do
			repeat
				local line = getLine()
				id, x, y = line:match("(%d+):(%d+):(%d+)")
				if not id then
					clientRecv(msg)
				end
			until id and x and y
			id, x, y = tonumber(id), tonumber(x), tonumber(y)
			markers[i]:construct(id)
			markers[i].x, markers[i].y = x, y
			id, x, y = nil, nil, nil
		end
	end
end

function love.load(args)
	math.randomseed(os.time())
	math.random()
	math.random()
	math.random()
	
	bg = love.graphics.newImage('images/felt.png')
	selected = false
	--Initialize markers
	markers = {}
	for i = 0,4 do
		markers[i+1] = Marker(i, "blocks")
	end

	table.insert(markers, Marker(5, 'detective'))
	table.insert(markers, Marker(5, 'criminal'))	

	love.audio.play('sounds/shuffle.ogg')

	local nwArgs = {}
	for i = 2, #args do
		table.insert(nwArgs, args[i])
	end
	prepareNetwork(nwArgs)
	prepareMarkers()
end

function love.update(dt)
	conn:update(dt)
end

function love.draw()
	love.graphics.draw(bg, 0, 0)

	--Draw board
	for x=0,8 do
		for y=0,8 do
			love.graphics.rectangle('fill', 250+x*80+x*1, 35+y*80+y*1, 80, 80);
		end
	end

	for i,v in ipairs(markers) do
		v:draw()
	end

	if selected then
		x,y = love.mouse.getPosition()
		love.graphics.setColor(94,167,214, 177)
		love.graphics.circle('fill', x, y, 37, 37)
		love.graphics.setColor(157,190,250, 255)
		love.graphics.circle('line', x, y, 38, 38)
		love.graphics.setColor(255,255,255,255)
	end

	if server then
		love.graphics.print(numConnected .. " clients connected", 10, 10)
	end
end

function love.mousepressed(x, y, button)
	for i,v in ripairs(markers) do
		if v:clicked(x, y) then
			if button == 'l' then
				selected = v.id
			end
			break
		end
	end
end

function love.mousereleased(x, y, button)
	if selected then
		for i,v in ipairs(markers) do
			if v.id == selected then
				v:moved(math.ceil(x),math.ceil(y))
			end
		end
		selected = false
	end
end

function love.quit()
	if not server then
		conn:disconnect()
	end
end
