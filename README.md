# uhttp
a decently small multithreaded HTTP server library

pretty simple usage really.

```lua
local uhttp = require("uhttp")

local server = uhttp(8080)

server:get("/", function(req, res)
  res.body = "Hello, world!"
  return 200
end)

server:get("/echo/(.+)", function(req, res)
  res.body = req.args[1]
  return 200
end

while true do
  server:poll()
end
```
