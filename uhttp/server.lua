--- Server Module
-- @module server

local server = {}

local lanes = require("lanes").configure()
local ssl = require("ssl")
local thread = require("thread")
local client = require("client")
local websocket = require("websocket")
local socket = require("socket-lanes")
local wsthread = loadfile("websocket_thread.lua")
local codes = require("codes")
local handthread = assert(loadfile("handler_thread.lua"))
local rand = io.open("/dev/urandom", "rb")
local function gen_uuid()
	return string.format(string.rep("%.2x", 16), rand:read(16):byte(1, 16))
end

local version = "1.1"

--- Handles an HTTP request path.
-- @tparam string method the HTTP method.
-- @tparam string path A pattern that matches a path. Results are returned as arguments
-- @tparam function func A function handling the path.
-- @returns self
function server:handle(method, path, func)
	self.handles[method] = self.handles[method] or {}
	self.handles[method][#self.handles[method]+1] = {pattern = path, handle = func}
	for i=1, #self.threads do
		self.threads[i]:update_handlers(self.handles)
	end
	return self
end

--- Hooks into the HTTP server
-- @tparam string stage The stage is the part of the 
-- @tparam function The function called when the hook is triggered.
function server:hook(stage, func)
	self.hooks[stage][#self.hooks[stage]+1] = func
	for i=1, #self.threads do
		self.threads[i]:update_hooks(self.handles)
	end
	return self
end

function server:websocket(path, wshandler)

end

local methods = {
	"get",
	"post",
	"head",
	"put",
	"delete",
	"connect",
	"options",
	"trace",
	"patch"
}

for i=1, #methods do
	server[methods[i]] = function(self, path, func)
		print(methods[i]:upper(), path)
		return self:handle(methods[i]:upper(), path, func)
	end
end

function server:poll()
	--[[for i=1, #self.threads do
		print(self.threads[i].thread.status)
		self.threads[i].linda:send("nfcall", "poll", self.hooks, self.handles)
	end]]
	self.sock:settimeout(0)
	local client = self.sock:acceptfd()
	while client do
		self:accept_client(client, false)
		client = self.sock:acceptfd()
	end
	if (self.ssl) then
		self.secsock:settimeout(0)
		client = self.secsock:acceptfd()
		while client do
			self:accept_client(client, true)
			client = self.secsock:acceptfd()
		end
	end
	if (os.time() % 30) then
		for i=1, #self.threads do
			self.threads.dead = not not self.threads[i]:ping()
		end
	end
	self:prune_threads()
	socket.sleep(0.003)
end

function server:new_thread()
	local thd = lanes.gen("*", handthread)
	local uuid = gen_uuid()
	local linda = lanes.linda()
	local thdd = thd(uuid, self.hooks, self.handles, linda)
	local thdw = {
		thread=thdd,
		linda=linda,
		uuid=uuid,
		dead=false
	}
	self.threads[#self.threads+1] = setmetatable(thdw, {__index=thread})
	while thdd.status == "pending" do end
	linda:receive("ready", 0.25)
	return thdw
end

function server:accept_client(client, is_secure)
	print("CLIENT_FD", client)
	for i=1, #self.threads do
		if (self.threads[i]:can_accept()) then
			local uuid = self.threads[i]:accept(client, is_secure and self.ssl)
			local cli = {
				uuid = uuid,
				thread = self.threads[i]
			}
			return setmetatable(cli, {__index=client})
		end
	end
	--If not...
	local thread = self:new_thread()
	local uuid = thread:accept(client, is_secure and self.ssl)
	local cli = {
		uuid = uuid,
		thread = thread
	}
	return setmetatable(cli, {__index=client})
end

function server:prune_threads()
	local threads = {}
	if (#self.threads == 1) then return end
	for i=1, #self.threads do
		if (self.threads[i].dead or (self.threads[i]:num_clients() == 0 and (0 or self.threads[i]:last_connection())+10 < os.clock())) then
			local thd = self.threads[i]
			thd.thread:cancel(-1, true)
		else
			threads[#threads+1] = self.threads[i]
		end
	end
	self.threads = threads
end

return server
