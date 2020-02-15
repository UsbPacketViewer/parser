-- parser.lua
-- encoding: utf-8

local html = require("html")
local gb = require("graph_builder")
local parser_init = require("parser_init")
local transactionParser = require("usb_transaction")
local fmt = string.format
local unpack = string.unpack

local function parse_token(name, color, textColor)
    return function(pkt, ts, id)
        local r = {}
        if #pkt ~= 3 then return gb.error("Token packet length wrong " .. #pkt) end
        local v = fmt("0x%02X", unpack("I1", pkt))
        r.pid = v
        v = unpack("I2", pkt, 2)
        if name == "SOF" then
            local frame = v & 0x7ff
            r.frame = frame
        else
            local addr = v & 0x7f
            local ep =  (v >> 7) & 0xf
            r.addr = addr
            r.ep = ep
        end
        local crc5 = (v >> 11) & 0x3f
        crc5 = fmt("0x%02X", crc5)
        r.name = name
        r.isToken = true
        r.id = id
        r.crc5 = crc5
        r.graph = gb.ts("Packet " .. id, ts, gb.C.PACKET) .. gb.data(r, true)
        return r
    end
end

local function parse_data(name, color, textColor)
    return function(pkt, ts, id)
        if #pkt < 3 then return gb.error("Data packet length wrong " .. #pkt) end
        local r = {}
        local v = fmt("0x%02X", unpack("I1", pkt))
        r.pid = v
        local crc16 = unpack("I2", pkt, #pkt-1)
        crc16 = fmt("0x%04X", crc16)
        r.name = name
        r.data = pkt:sub(2, #pkt-2)
        r.isData = true
        r.id = id
        r.crc16 = crc16
        r.graph = gb.ts("Packet " .. id, ts, gb.C.PACKET) .. gb.data(r, true)
        return r
    end
end

local function parse_handshake(name, color, textColor)
    return function(pkt, ts, id)
        if #pkt ~= 1 then return gb.error("Handshake packet length wrong " .. #pkt) end
        local v = fmt("0x%02X", unpack("I1", pkt))
        local r = {}
        r.pid = v
        r.name = name
        r.isHandshake = true
        r.id = id
        r.graph = gb.ts("Packet " .. id, ts, gb.C.PACKET) .. gb.data(r, true)
        return r
    end
end

local function parse_special(name, color, textColor)
    return function(pkt, ts, id)
        if #pkt ~= 1 then return gb.error("Special packet length wrong " .. #pkt) end
        local v = fmt("0x%02X", unpack("I1", pkt))
        local r = {}
        r.pid = v
        r.name = name
        r.isSpecial = true
        r.id = id
        r.graph = gb.ts("Packet " .. id, ts, gb.C.PACKET) .. gb.data(r, true)
        return r
    end
end

local pid_map = {
    [0xe1] = parse_token("OUT"),         -- OUT
    [0x69] = parse_token("IN"),          -- IN
    [0xa5] = parse_token("SOF"),         -- SOF
    [0x2d] = parse_token("SETUP"),       -- SETUP
    [0xb4] = parse_token("PING"),        -- PING

    [0xd2] = parse_handshake("ACK"),     -- ACK
    [0x5a] = parse_handshake("NAK"),     -- NAK
    [0x1e] = parse_handshake("STALL"),   -- STALL
    [0x96] = parse_handshake("NYET"),    -- NYET

    [0xc3] = parse_data("DATA0"),        -- DATA0
    [0x4b] = parse_data("DATA1"),        -- DATA1
    [0x87] = parse_data("DATA2"),        -- DATA2
    [0x0f] = parse_data("MDATA"),        -- MDATA

    [0x3c] = parse_special("PRE"),       -- PRE
    [0x78] = parse_special("SPLIT"),     -- SPLIT
}

local parserContext

function parser_reset()
    parserContext = {}
    parserContext.id2trans = {}
    parserContext.id2xfer = {}
    parser_init(parserContext)
end

parser_reset()

local function on_packet(pkt, ts, id, updateGraph)
    local pid = unpack("I1", pkt)
    local parser = pid_map[pid]
    if parser then
        local res = parser(pkt, ts, id)
        transactionParser(ts, res, id, updateGraph, parserContext)
    else
        updateGraph(errorData(fmt("Unknown PID 0x%02X", pid)) , id, {id=id})
    end
end

local function elementId(ele)
    if ele.parent then
        if ele.parent.parent then
            return ele.parent.parent.id, ele.parent.id, ele.id
        end
        return ele.parent.id, ele.id, -1
    end
    return ele.id, -1, -1
end

function parser_append_packet(ts, nano, pkt, id, transId, handler, context)
    local timestamp = fmt("%d.%09d", ts, nano)
    on_packet(pkt, timestamp, id, function(content, id, element)
        local id1, id2, id3 = elementId(element)
        local r = handler(context, tostring(content), transId, id, id1, id2 or -1, id3 or -1)
        assert(r>=0, "update graph content fail " .. tostring(r) .. tostring(content) .. fmt("%d %d %d",id1,id2,id3) )
    end)
    return 1
end

function parser_get_info(id1, id2, id3)
    id1 = id1 or -1
    id2 = id2 or -1
    id3 = id3 or -1
    local raw = fmt("<h1>Unknown data</h1> (%d,%d,%d)",id1,id2,id3)
    
    local transId = -1
    local xferId = -1

    -- didn't parse at packet level
    if id3 > 0 then return "", "<h1>Packet not parsed</h1>" end
    if id2 > 0 then
        transId = id2
    else
        xferId = id1
        transId = id1
    end

    if xferId > 0 then
        local xfer = parserContext.id2xfer[id1]
        if xfer then
            return xfer.infoData or "",  xfer.infoHtml or raw
        end
    end

    if transId > 0 then
        local trans = parserContext.id2trans[transId]
        if trans then
            local d = trans.infoData
            if not d then
                if #trans.pkts > 1 and trans.pkts[2].isData then
                    d = trans.pkts[2].data
                end
            end
            return d or "",  trans.infoHtml or raw
        end
    end
    return "", raw
end

package.loaded["parser"] = "parser"
