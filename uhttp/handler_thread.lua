--require("jit.v").start()
jit.on() --Ensure JIT is on.
print(pcall(function(...)
	local ssl = require("ssl")
	local socket = require("socket-lanes")
	local fcall = require("funccall")
	local lanes = require("lanes")
	local lt = os.clock()
	local last_fulltick = 0

	local args = {...}
	local clients = {}

	local uuid = args[1]
	local handlers = {}
	local hooks = args[2]

	local linda = args[4]

	local codes = require("codes")
	local error_template = [[
	<html>
		<head>
			<title>%c %r</title>
		</head>
		<body>
			<center>
				<h1>
					%c %r
				</h1>
			</center>
			<samp>
			%e
			</samp>
			<hr>
			<center>
				uhttp/%v LuaJIT/%l on %h
			</center>
		</body>
	</html>
	]]

	local function generate_message(code, headers, body)
		local request="HTTP/1.1 "..code.." "..codes[code].."\r\n"
		for k, v in pairs(headers) do
			if (k:lower() == "content-length") then
				error("Content-Length is not to be set by handler!", 1)
			end
			request = request .. k .. ": " .. v .. "\r\n"
		end
		request = request .. "Content-Length: "..#body.."\r\n\r\n"..body
		return request
	end

	


	local function sock_read_line(client)
		local data = ""
		local cr = false
		while true do
			local c = client:receive(1)
			if (c == "\r" and not cr) then
				cr = true
			elseif (c == "\n" and cr) then
				return data
			elseif (cr and c) then
				data = data .. "\r" .. c
			elseif (c) then
				data = data .. c
			else
				return data
			end
		end
	end

	local function read_request(client, fchar)
		--Read method, path, version.
		local line = sock_read_line(client)
		if fchar then
			line = fchar .. line
		end
		local req, path, version = line:match("(.-) (.-) HTTP/(.+)")
		if (version ~= "1.0" and version ~= "1.1") then
			return nil, "http version"
		end
		local headers = {}
		while line ~= "" do
			line = sock_read_line(client)
			if (line ~= "") then
				local k, v = line:match("([%w%-]-): (.+)")
				headers[k] = v
			end
		end
		local body = client:receive(tonumber(headers["Content-Length"]))
		return {
			method = req,
			path = path,
			version = version,
			headers = headers,
			body = body,
			client = client
		}
	end

	local function handle_request(req)
		print(req.method, req.path, ({req.client:getpeername()})[1])
		local res = {
			body = "",
			headers = {
				["Server"] = "uhttp/0.1 LuaJIT/"..jit.version:sub(8),
				["Connection-Type"] = "Keep-Alive",
				["Keep-Alive"] = "timeout=5, max=1000",
				["Content-Type"] = "text/html",
			},
			error = function(self, err, code)
				self.body = error_template
						:gsub("%%c", tostring(code))
						:gsub("%%r", codes[code])
						:gsub("%%v", "0.1")
						:gsub("%%l", jit.version:sub(8))
						:gsub("%%h", req.headers.Host)
						:gsub("%%e", err)
			end
		}
		local methods = handlers[req.method]
		if methods then
			for i=1, #methods do
				local rargs = {req.path:match("^"..methods[i].pattern.."$")}
				if (#rargs ~= 0) then
					req.args = rargs
					local succ, code = pcall(methods[i].handle, req, res)
					if not succ then
						req.client:send(generate_message(540, {
							["Server"] = "uhttp/0.1 LuaJIT/"..jit.version:sub(8),
							["Connection-Type"] = "Keep-Alive",
							["Keep-Alive"] = "timeout=5, max=1000",
							["Content-Type"] = "text/html",
						}, error_template
						:gsub("%%c", "540")
						:gsub("%%r", "Lua Error")
						:gsub("%%v", "0.1")
						:gsub("%%l", jit.version:sub(8))
						:gsub("%%h", req.headers.Host)
						:gsub("%%e", code)))
						return false
					elseif succ and not code then
						req.client:send(generate_message(541, {
							["Server"] = "uhttp/0.1 LuaJIT/"..jit.version:sub(8),
							["Connection-Type"] = "Keep-Alive",
							["Keep-Alive"] = "timeout=5, max=1000",
							["Content-Type"] = "text/html",
						}, error_template
						:gsub("%%c", "541")
						:gsub("%%r", "Handler Returned Nil")
						:gsub("%%v", "0.1")
						:gsub("%%l", jit.version:sub(8))
						:gsub("%%h", req.headers.Host)
						:gsub("%%e", "Handler for "..methods[i].pattern.." returned nil.")))
						return false
					end
					req.client:send(generate_message(code, res.headers, res.body))
					return true
				end
			end
		end
		req.client:send(generate_message(404, res.headers, error_template
			:gsub("%%c", "404")
			:gsub("%%r", "Not Found")
			:gsub("%%v", "0.1")
			:gsub("%%l", jit.version:sub(8))
			:gsub("%%h", req.headers.Host)
			:gsub("%%e", "")))
		return true
	end

	local function call_hook(stage, ...)
		for i=1, #hooks[stage] do
			local suc, err = pcall(...)
			if suc and err then return err end
			if not suc and err then print(err) end
		end
	end

	local last_poll = 0
	local last_con = 0

	--Functions able to be accessed with an fcall

	function ping()
		return true
	end

	function update_handlers(tbl)
		handlers = tbl
	end

	function update_hooks(tbl)
		hooks = tbl
	end

	function last_connection()
		return last_con
	end

	function poll()
		local stime = os.clock()
		for i=1, #clients do
			local client = clients[i]
			if (client.realsock:getpeername()) then --It's working
				client.socket:settimeout(0)
				local c = client.socket:receive(1)
				if (c) then
					client.socket:settimeout(0)
					handle_request(read_request(client.socket, c))
				end
			end
		end
		last_poll = os.clock()-stime
		if (not can_accept()) then
			print("WARNING: Polling loop is taking too long. (took "..last_poll.."s)")
		end
		local clis = {}
		for i=1, #clients do
			if (clients[i].time + 30 > os.time()) then
				clis[#clis] = clients[i]
			else
				clients[i].socket:close()
			end
		end
		clients = clis
	end

	function can_accept()
		return last_poll < 0.1
	end

	function num_clients()
		return #clients
	end

	function last_client()
		return last_con
	end

	function accept(fd, is_ssl)
		local client, err = socket.tcp(fd)
		client:settimeout(0)
		local sslsock
		last_con = os.time()
		if (is_ssl) then
			sslsock, err = ssl.wrap(client, {
					mode="server",
					protocol="any",
					key=is_ssl.key,
					certificate=is_ssl.cert,
					cafile=is_ssl.ca,
					--verify={"peer", "fail_if_no_peer_cert"},
					options="all",
					password="fuckme"
				})
			sslsock:dohandshake()
		end
		uuid = math.random(1, 2^32)
		local cli = {
			realsock = client,
			socket = sslsock or client,
			time = os.time()
		}
		clients[#clients+1] = cli
		return uuid
	end
	update_handlers(args[3])
	linda:send("ready", 0.25)
	while true do
		last_fulltick = os.clock()-lt
		lt = os.clock()
		poll()
		fcall.poll(linda)
		socket.sleep(0.001)
	end
end, ...))
