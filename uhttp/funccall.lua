local fcall = {}

function fcall.poll(linda)
	local _, calldat = linda:receive(0.001, "fcall")
	if (calldat) then
		local func = calldat[1]
		table.remove(calldat, 1)
		local retdat = {_G[func](unpack(calldat))}
		linda:send("fval", retdat)
	end
end

return fcall
