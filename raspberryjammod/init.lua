-- Note: The x-coordinate is reversed in sign between minetest and minecraft,
-- and the API compensates for this.

-- fix path --
if string.find(package.path, "%\\%?") then
     package.path = package.path .. ";" .. string.gsub(package.path, "bin%\\lua%\\%?%.lua", "mods\\raspberryjammod\\?.lua")
     package.cpath = package.cpath .. ";" .. string.gsub(package.cpath, "bin%\\%?", "mods\\raspberryjammod\\?")
else
     package.path = package.path .. ";" .. string.gsub(package.path, "bin%/lua%/%?%.lua", "mods/raspberryjammod/?.lua")
     package.cpath = package.cpath .. ";" .. string.gsub(package.cpath, "bin%/%?", "mods/raspberryjammod/?")
end

local block = require("block")
local socket = require("socket")
local server = socket.bind("*", 4711)
server:settimeout(0)
local clientlist = {}
restrict_to_sword = 1
block_hits = {}
chat_record = {}

minetest.register_globalstep(function(dtime)
    local newclient,err = server:accept()
    if not err then
       newclient:settimeout(0)
       table.insert(clientlist, newclient)
       print("RJM client connected")
    end
    for i = 1, #clientlist do
       local err = false
       local line
       while not err do
         line,err = clientlist[i]:receive()
         if err == "closed" then
            table.remove(clientlist,i)
            print("RJM client disconnected")
         elseif not err then
            local response = handle_command(line)
            if response then clientlist[i]:send(response.."\n") end
         end
       end
    end
end)

minetest.register_on_punchnode(function(pos, oldnode, puncher, pointed_thing)
    -- TODO: find a way to get right clicks
    -- TODO: find a way to get clicked side
    if (puncher:is_player()) then
       local item = puncher:get_wielded_item()
       if not restrict_to_sword or (item and item:get_name():find("%:sword")) then
          table.insert(block_hits, ""..(-pos.x)..","..pos.y..","..pos.z..",7,"..getentityid(puncher))
       end
    end
end)

minetest.register_on_chat_message(function(name, message)
    local id = getplayeridbyname(name)
    if (message.sub(1,3) == "/py") then
        print("TODO")
    else
        table.insert(chat_record, id .. "," .. message:gsub("%|", "&#124;"))
    end
end)

function getplayeridbyname(name)
    -- TODO: handle multiplayer
    return 1
end

function getplayer(id)
    -- TODO: handle multiplayer
    return minetest.get_connected_players()[1]
end

function getentityid(entity)
    if not entity:is_player() then
       return 0x7FFFFFFF
    else
       -- TODO: handle multiplayer
       return 1
    end
end

function handle_entity(cmd, id, args)
    local entity = getplayer(id)
    if cmd == "getPos" then
        local pos = entity:getpos()
        return ""..(-pos.x)..","..(pos.y-0.5)..","..(pos.z)
    elseif cmd == "getTile" then
        local pos = entity:getpos()
        return ""..math.floor(-pos.x)..","..math.floor(pos.y-0.4999)..","..math.floor(pos.z)
    elseif cmd == "setPos" then
        entity:setpos({x=-tonumber(args[1]), y=tonumber(args[2])+0.5, z=tonumber(args[3])})
    elseif cmd == "setTile" then
        entity:setpos({x=-(0.5+tonumber(args[1])), y=tonumber(args[2])+0.5, z=0.5+tonumber(args[3])})
    elseif cmd == "getPitch" then
        return ""..(entity:get_look_pitch() * -180 / math.pi)
    elseif cmd == "getRotation" then
        return ""..((90 - entity:get_look_yaw() * 180 / math.pi) % 360)
    elseif cmd == "getDirection" then
        local dir = entity:get_look_dir()
        return ""..(-dir.x)..","..(dir.y)..","..(dir.z)
    elseif cmd == "setPitch" then
        -- TODO: For mysterious reasons, set_look_pitch() and get_look_pitch()
        -- values are opposite sign, so we don't negate here. Ideally, the mod
        -- would detect this to make sure that if it's fixed in the next version
        -- this wouldn't be an issue.
        entity:set_look_pitch(tonumber(args[1]) * math.pi / 180)
    elseif cmd == "setRotation" then
        -- TODO: For mysterious reasons, set_look_yaw() and get_look_yaw()
        -- values differ by pi/2. Ideally, the mod
        -- would detect this to make sure that if it's fixed in the next version
        -- this wouldn't be an issue.
        entity:set_look_yaw((-tonumber(args[1])) * math.pi / 180)
    elseif cmd == "setDirection" then
        -- TODO: Fix set_look_yaw() and get_look_yaw() compensation.
        local x = tonumber(args[1])
        local y = tonumber(args[2])
        local z = tonumber(args[3])
        local xz = math.sqrt(x*x+z*z)
        if xz >= 1e-9 then
           entity:set_look_yaw(- math.atan2(-x,z))
        end
        if x*x + y*y + z*z >= 1e-18 then
           entity:set_look_pitch(math.atan2(-y, xz))
        end
    end
    return nil
end

function parse_node(args, start)
    local nodenum
    if #args < start then
        nodenum = 0
    elseif #args == start then
        nodenum = block.Block(tonumber(args[start]),0)
    else
        nodenum = block.Block(tonumber(args[start]),tonumber(args[start+1]))
    end
    local node = block.BLOCK[nodenum]
    if node == nil then
        node = block.BLOCK[bit.band(nodenum,0xFFF)]
        if not node then
            node = block.BLOCK[STONE]
        end
    end
    return node
end

function handle_world(cmd, args)
    if cmd == "setBlock" then
        local node = parse_node(args, 4)
        minetest.set_node({x=-tonumber(args[1]),y=tonumber(args[2]),z=tonumber(args[3])},node)
    elseif cmd == "setNode" then
        minetest.set_node({x=-tonumber(args[1]),y=tonumber(args[2]),z=tonumber(args[3])},{name=args[4]})
    elseif cmd == "setBlocks" then
        local node = parse_node(args, 7)
        x1 = math.min(-tonumber(args[1]),-tonumber(args[4]))
        x2 = math.max(-tonumber(args[1]),-tonumber(args[4]))
        y1 = math.min(tonumber(args[2]),tonumber(args[5]))
        y2 = math.max(tonumber(args[2]),tonumber(args[5]))
        z1 = math.min(tonumber(args[3]),tonumber(args[6]))
        z2 = math.max(tonumber(args[3]),tonumber(args[6]))
        for ycoord = y1,y2 do
          for xcoord = x1,x2 do
            for zcoord = z1,z2 do
               minetest.set_node({x=xcoord,y=ycoord,z=zcoord},node)
            end
          end
        end
    elseif cmd == "setNodes" then
        local node = {node = args[7]}
        x1 = math.min(-tonumber(args[1]),-tonumber(args[4]))
        x2 = math.max(-tonumber(args[1]),-tonumber(args[4]))
        y1 = math.min(tonumber(args[2]),tonumber(args[5]))
        y2 = math.max(tonumber(args[2]),tonumber(args[5]))
        z1 = math.min(tonumber(args[3]),tonumber(args[6]))
        z2 = math.max(tonumber(args[3]),tonumber(args[6]))
        for ycoord = y1,y2 do
          for xcoord = x1,x2 do
            for zcoord = z1,z2 do
               minetest.set_node({x=xcoord,y=ycoord,z=zcoord},node)
            end
          end
        end
    elseif cmd == "getNode" then
        return minetest.get_node({x=-tonumber(args[1]),y=tonumber(args[2]),z=tonumber(args[3])}).name
    elseif cmd == "getBlockWithData" or cmd == "getBlock" then
        node = minetest.get_node({x=-tonumber(args[1]),y=tonumber(args[2]),z=tonumber(args[3])})
        local id, meta
        if node == "ignore" then
            id = block.AIR
            meta = 0
        else
            id = block.STONE
            meta = 0
            for key,value in pairs(block.BLOCK) do
                if value.name == node.name then
                    id = math.floor(bit.band(key,0xFFF))
                    meta = math.floor(bit.rshift(key,12))
                    break
                end
            end
        end
        if cmd == "getBlock" then
            return ""..id
        else
            return ""..id..","..meta
        end
    elseif cmd == "getHeight" then
        -- TODO: Handle larger heights than 1024
        local xcoord = -tonumber(args[1])
        local zcoord = tonumber(args[2])
        for ycoord = 1024,-1024,-1 do
            name = minetest.get_node({x=xcoord,y=ycoord,z=zcoord}).name
            if name ~= "ignore" and name ~= "air" then
                return ""..ycoord
            end
        end
        return "-1025"
    elseif cmd == "getPlayerId" then
        return "1"
    elseif cmd == "getPlayerIds" then
        return "1"
    end
    return nil

end

function handle_events(cmd, args)
    if (cmd == "setting") then
       if (args[1] == "restrict_to_sword") then
           restrict_to_sword = tonumber(args[2])
       end
    elseif (cmd == "block.hits") then
       local h = block_hits
       block_hits = {}
       return table.concat(h, "|")
    elseif (cmd == "chat.posts") then
       local c = chat_record
       chat_record = {}
       return table.concat(c, "|")
    elseif (cmd == "clear") then
       block_hits = {}
       chat_record = {}
    end
    return nil
end

function handle_command(line)
    local cmd, argtext = string.match(line, "([^(]+)%((.*)%)")
    if not cmd then return end
    local args = {}
    for arg in string.gmatch(argtext, "([^,]+)") do
        table.insert(args, arg)
    end
    if cmd:sub(1,6) == "world." then
        return handle_world(cmd:sub(7),args)
    elseif cmd:sub(1,7) == "player." then
        return handle_entity(cmd:sub(8),1,args)
    elseif cmd:sub(1,7) == "entity." then
        local player = tonumber(args[1])
        table.remove(args,1)
        return handle_entity(cmd:sub(8),player,args)
    elseif cmd:sub(1,7) == "events." then
        return handle_events(cmd:sub(8),args)
    elseif cmd == "chat.post" then
        minetest.chat_send_all(argtext)
    end
    return nil
end

