-- file_base.lua
-- encoding: utf-8
--[[
    there are 3 API for file read/write operation
    the read/write operation running in a separator with different lua context


valid_filter()
    get the valid filter, return a filter string in Qt file filter format, e.g.  "Wireshark Capture file (*.pcap);;All files (*.*)"


-- read the packet from a file
-- name            file name
-- open_handler    called when got a new packet
-- context         internal use, just passed to open_handler
-- return value   total read packet count
open_file(name, open_handler, context)

-- when got a new packet call this function
-- context        passed from open_file
-- ts             timestamp in second
-- nano           timestamp in nano second
-- pkt            raw pkt data
-- cur            current read position
-- total          total file size
open_handler(context, ts, nano, pkt, cur, total)

-- write the packet into a file
-- name            file name
-- write_handler   call this function to get a packet, if return nil means no more packets
-- context         internal use, just passed to write_handler
-- return value   total write packet count
write_file(name, write_handler, context)

-- when got a new packet call this function
-- context        passed from open_file
-- return value(ts,nano,pkt)
--              ts             timestamp in second
--              nano           timestamp in nano second
--              pkt            raw pkt data
ts, nano, pkt = write_handler(context)
]]

local handlers = {}

function toHex(data)
    local res = ""
    if not data then return "<null>" end
    for i=1,#data do
        res = res .. string.format( "%x", data:byte(i))
    end
    return res
end

function register_filehandler(fh)
    assert(fh and fh.name, "file handler must have a name")
    if not handlers[fh.name] then
        handlers[#handlers+1] = fh
        handlers[fh.name] = fh
    else
        log(fh.name, "already exsit")
    end
end

function open_file(name, packet_handler, context)
    local file, e = io.open(name, "rb")
    assert(file ,e)
    local fh = nil
    local totalLen = file:seek("end")

    for i,v in ipairs(handlers) do
        file:seek("set", 0)
        if v.init_read and v:init_read(file) then
            fh = v
            break
        end
    end
    local pkt_count = 0
    while fh do
        local ts, nano, pkt, status = fh:read_packet(file)
        if ts and nano and pkt then
            packet_handler(context, ts, nano, pkt, status or 0, file:seek(), totalLen)
            pkt_count = pkt_count + 1
        else
            break
        end
    end
    file:close()
    assert(fh, "Unknown file format")
    return pkt_count
end

function write_file(name, packet_handler, context)
    local p1, p2 = string.find(name, "%.%w+$")
    local fh = nil
    if p1 and p2 then
        local ext = name:sub(p1,p2)
        for i,v in ipairs(handlers) do
            if string.find(v.extension, ext) then
                fh = v
            end
        end
    end
    if not fh then return error("Unknown file format to write " .. name) end
    local file, e = io.open(name, "w+b")
    assert(file ,e)
    local pkt_count = 0
    if fh.init_write and fh:init_write(file) then
        while true do
            local ts, nano, pkt, status = packet_handler(context)
            local res = nil
            if ts and nano and pkt then
                res = fh:write_packet(file, ts, nano, pkt, status or 0)
            end
            if not res then
                break
            end
            pkt_count = pkt_count + 1
        end
    end

    file:close()
    return pkt_count
end

function valid_filter()
    local res = ""
    local sep = ""
    for i,v in ipairs(handlers) do
        if v.extension then
            local n = v.description or v.name
            res = res .. sep .. n.." (" .. v.extension .. ")"
            sep = ";;"
        end
    end
    res = res .. sep .. "All files (*.*)"
    return res
end

package.loaded["file_base"] = "file_base"
