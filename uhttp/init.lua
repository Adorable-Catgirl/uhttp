local server = require("server")
local socket = require("socket-lanes")

local function new_server(http_port, config)
	local svr = {
		hooks = {
			ClientConnect = {},
			PathLookup = {},
			PathFound = {},
			ThreadCreation = {},
			SendData = {},
			ErrorPage = {},
			LuaError = {}
		},
		handles = {},
		sock = assert(socket.tcp()),
		threads={}
	}
	svr.log = config.log or function()end
	assert(svr.sock:bind("*", http_port or 8080))
	svr.sock:listen()
	if (config.ssl) then
		svr.secsock = assert(socket.tcp())
		assert(svr.secsock:bind("*", config.ssl.port or 8888))
		svr.secsock:listen()
		svr.ssl = config.ssl
	end
	setmetatable(svr, {__index=server})
	svr:new_thread()
	print("Server started on:")
	print("\thttp://localhost:"..http_port)
	if (config.ssl) then
		print("\thttps://localhost:"..config.ssl.port)
	end
	return svr
end

return new_server
