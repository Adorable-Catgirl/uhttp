local thread = {}

--[[function thread:func_call(func, ...)
	if (self.thread.status ~= "running" and self.thread.status ~= "waiting") then
		return nil, "thread isn't running"
	end
	self.linda:send("fcall", func, ...)
	local calldat = {self.linda:receive("fret")}
	table.remove(calldat, 1)
	return table.unpack(calldat)
end]]

return function(tbl, key)
	return function(self, ...)
		if (self.thread.status ~= "running" and self.thread.status ~= "waiting") then
			return nil, "thread isn't running"
		end
		self.linda:send("fcall", {key, ...})
		local _, calldat = self.linda:receive(0.001, "fval")
		if not _ then return nil, "timeout" end
		return unpack(calldat)
	end
end

--return thread
