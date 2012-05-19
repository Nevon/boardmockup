Class = require "lib.class"
require "lib.LUBE"

local server = true
local conn

Card = Class{function(self, id)
	self.id = id
	self.value = (id % 13) + 2
	self.width = 75
	self.height = 107
	self.x = math.random(0, 1125)
	self.y = math.random(0, 590)
	local suit
	local color
	local name

	if id<13 then self.suit = "spades"
	elseif id < 26 then self.suit = "clubs"
	elseif id < 39 then self.suit = "hearts"
	elseif id < 52 then self.suit = "diamonds" end

	if self.suit == "spades" or self.suit == "clubs" then self.color = "black"
	else self.color = "red" end

	if self.value < 11 then self.name = self.value.." of "..self.suit
	elseif self.value == 11 then self.name = "Jack of "..self.suit
	elseif self.value == 12 then self.name = "Queen of "..self.suit
	elseif self.value == 13 then self.name = "King of "..self.suit
	elseif self.value == 14 then self.name = "Ace of "..self.suit end

	self.image = love.graphics.newImage("images/cards/"..self.suit.."-"..self.value.."-75.png")
end}

function Card:draw()
	love.graphics.draw(self.image, self.x, self.y);
end

function Card:moved(x, y, remote)
	print (self.name .. " (" .. self.id .. ") " .. "was moved to " .. x .. "/" .. y)

	self.x = x
	self.y = y

	love.audio.play('sounds/place.ogg')

	--Move 
	local thisCard
	for i,v in ipairs(deck) do
		if self.id == v.id then
			thisCard = table.remove(deck, i)
			break
		end
	end

	table.insert(deck, thisCard)

	if not remote then
		conn:send(("moved:%d:%d:%d"):format(self.id, x, y))
	end
end

function Card:clicked(x, y)
	--Point in rect
	if x>self.x and x<self.x+self.width
	and y>self.y and y<self.y+self.height then
		print (self.name .. ' was clicked')
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

local function serverRecv(data, clientid)
	if data == "getDeck" then
		for i = 1, #deck do
			conn:send(
				("%d:%d:%d\n"):format(deck[i].id, deck[i].x, deck[i].y),
				clientid)
		end
	elseif data:match("^moved:") then
		local id, x, y = data:match("^moved:(%d+):(%d+):(%d+)$")
		assert(id, "Invalid message")
		id, x, y = tonumber(id), tonumber(x), tonumber(y)
		for i, v in ipairs(deck) do
			if v.id == id then
				v:moved(x, y, true)
				break
			end
		end
	end
end

local function clientRecv(data)
	if data:match("^moved:") then
		local id, x, y = data:match("^moved:(%d+):(%d+):(%d+)$")
		assert(id, "Invalid message")
		id, x, y = tonumber(id), tonumber(x), tonumber(y)
		for i, v in ipairs(deck) do
			if v.id == id then
				v:moved(x, y, true)
				break
			end
		end
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
		conn:listen(3410)
		conn.callbacks.recv = serverRecv
	else
		local host = args[1]
		if not host then
			print("Invalid host, defaulting to localhost")
			host = "localhost"
		end
		conn = lube.tcpClient()
		conn.handshake = "helloCardboard"
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

local function prepareDeck()
	if server then
		--Shuffle the shit out of it
		for i=#deck, 1, -1 do
			local toMove = math.random(i)
			deck[toMove], deck[i] = deck[i], deck[toMove]
		end
	else
		local msg, line, id, x, y
		conn:send("getDeck")
		for i = 1, #deck do
			repeat
				local line = getLine()
				id, x, y = line:match("(%d+):(%d+):(%d+)")
				if not id then
					clientRecv(msg)
				end
			until id and x and y
			id, x, y = tonumber(id), tonumber(x), tonumber(y)
			deck[i]:construct(id)
			deck[i].x, deck[i].y = x, y
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
	--Initialize deck
	deck = {}
	for i = 0,51 do
		deck[i+1] = Card(i)
	end

	love.audio.play('sounds/shuffle.ogg')

	local nwArgs = {}
	for i = 2, #args do
		table.insert(nwArgs, args[i])
	end
	prepareNetwork(nwArgs)
	prepareDeck()
end

function love.update(dt)
	conn:update(dt)
end

function love.draw()
	love.graphics.draw(bg, 0, 0)

	for i,v in ipairs(deck) do
		v:draw()
	end
end

function love.mousepressed(x, y, button)
	for i,v in ripairs(deck) do
		if v:clicked(x, y) then
			selected = i
			break
		end
	end
end

function love.mousereleased(x, y, button)
	if selected then
		deck[selected]:moved(x,y)
		selected = false
	end
end
