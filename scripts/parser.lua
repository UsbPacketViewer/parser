-- parser.lua
-- encoding: utf-8

local html = require("html")
local gb = require("graph_builder")
local parser_init = require("parser_init")
local transactionParser = require("usb_transaction")
local fmt = string.format
local unpack = string.unpack

local function speed_from_status(status)
    local t = status & 0xf
    if     t == 1 then
        return "LOW"
    elseif t == 2 then
        return "FULL"
    elseif t == 3 then
        return "HIGH"
    elseif t == 4 then
        return "Super"
    end
    return "Unknown"
end

local function parse_token(name, color, textColor)
    return function(pkt, ts, status, id)
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
        local crc5 = (v >> 11) & 0x1f
        crc5 = fmt("0x%02X", crc5)
        r.name = name
        r.isToken = true
        r.id = id
        r.crc5 = crc5
        r.speed = speed_from_status(status)
        r.graph = gb.ts("Packet " .. id, ts, gb.C.PACKET, r.speed) .. gb.data(r, true)
        return r
    end
end

local function parse_data(name, color, textColor)
    return function(pkt, ts, status, id)
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
        r.speed = speed_from_status(status)
        r.graph = gb.ts("Packet " .. id, ts, gb.C.PACKET, r.speed) .. gb.data(r, true)
        return r
    end
end

local function parse_handshake(name, color, textColor)
    return function(pkt, ts, status, id)
        if #pkt ~= 1 then return gb.error("Handshake packet length wrong " .. #pkt) end
        local v = fmt("0x%02X", unpack("I1", pkt))
        local r = {}
        r.pid = v
        r.name = name
        r.isHandshake = true
        r.id = id
        r.speed = speed_from_status(status)
        r.graph = gb.ts("Packet " .. id, ts, gb.C.PACKET, r.speed) .. gb.data(r, true)
        return r
    end
end

local function parse_split(name, color, textColor)
    return function(pkt, ts, status, id)
        if #pkt ~= 4 then return gb.error("Special packet length wrong " .. #pkt) end
        local v = fmt("0x%02X", unpack("I1", pkt))
        local r = {}
        r.pid = v
        local hub, port, crc = unpack("I1I1I1", pkt, 2)
        r.name = name
        r.isSplit = true
        r.id = id
        r.addr = hub & 0x7f
        r.isStart = (hub & 0x80) == 0
        r.port = port & 0x7f
        r.isLowSpeed = (port & 0x80) ~= 0
        r.isEnd = (crc & 1) ~= 0
        r.epType = (crc >> 1) & 0x03
        r.crc5 = (crc >> 3) & 0x1f
        r.speed = speed_from_status(status)
        r.graph = gb.ts("Packet " .. id, ts, gb.C.PACKET, r.speed) .. gb.data(r, true)
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

    [0x3c] = parse_handshake("PRE"),     -- PRE_ERR
    [0x78] = parse_split("SPLIT"),       -- SPLIT
}

local parserContext

function parser_reset()
    parserContext = {}
    parserContext.id2trans = {}
    parserContext.id2xfer = {}
    parser_init(parserContext)
    collectgarbage()
end

parser_reset()

local wait_token = nil
local function on_packet(pkt, ts, status, id, updateGraph)
    local pid = unpack("I1", pkt)
    local parser = pid_map[pid]
    if parser then
        local res = parser(pkt, ts, status, id)
        if res.pid then
            if res.isSplit then
                wait_token = res
            else
                if wait_token then
                    wait_token.destAddr = res.addr
                    wait_token.destEp = res.ep
                    transactionParser(ts, wait_token, wait_token.id, updateGraph, parserContext)
                    wait_token = nil
                end
                transactionParser(ts, res, id, updateGraph, parserContext)
            end
        end
    else
        --updateGraph( gb.wild(parse_token("Unkown")(pkt, ts, status, id), ts) , id, {id=id})
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

function parser_append_packet(ts, nano, pkt, status, id, transId, handler, context)
    if #pkt < 1 then return 1 end
    local timestamp = fmt("%d.%09d", ts, nano)
    on_packet(pkt, timestamp, status, id, function(content, id, element)
        local id1, id2, id3 = elementId(element)
        local r = handler(context, tostring(content), transId, id, id1, id2 or -1, id3 or -1)
        assert(r>=0, "update graph content fail " .. tostring(r) .. tostring(content) .. fmt("%d %d %d",id1,id2,id3) )
    end)
    return 1
end

function parser_get_info_no_css(id1, id2, id3)
    id1 = id1 or -1
    id2 = id2 or -1
    id3 = id3 or -1
    local pkt = '<h1>Token not parsed</h1><br><br>Parser Version: 20200607'
    if id3 >= 0 then return "", pkt end
    local raw = fmt("<h1>Unknown data</h1> (%d,%d,%d)",id1,id2,id3)

    if id2>=0 then
        local trans = parserContext.id2trans[id2]
        if trans and trans.parent then
            local d = trans.infoData or trans.data
            return d or "",  trans.infoHtml or raw
        else
            return "", pkt
        end
    end

    if id1>= 0 then
        local trans = parserContext.id2trans[id1]
        if trans then
            if trans.parent then
                local xfer = parserContext.id2xfer[id1]
                return xfer.infoData or "",  xfer.infoHtml or raw
            else
                local d = trans.infoData or trans.data
                return d or "",  trans.infoHtml or raw
            end
        else
            return "", pkt
        end
    end
    return "", raw
end

function parser_get_info(id1, id2, id3)
	local d,h = parser_get_info_no_css(id1, id2, id3)
	return d, html.getCSS(isDark()) .. h
end

package.loaded["parser"] = "parser"
