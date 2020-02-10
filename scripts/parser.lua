-- parser.lua
-- encoding: utf-8

local html = require("html")
local gb = require("graph_builder")
local setupParser = require("usb_setup_parser")
local proto_init = require("proto_init")
local controlXferHandler = require("control_transfer")
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

local function makeSOFGroup(ts)
    return gb.ts("Timestamp", ts, gb.C.TRANS)
        .. gb.block("SOFs", "", gb.C.SOF, 120)
        .. gb.F_TRANSACTION .. gb.F_SOF
end

local updateXfer

local function updateTransaction(trans, ts, updateGraph)
    local token = trans.pkts[1]
    local res = gb.data(token)
    local data = trans.pkts[2]
    trans.state = "INCOMPLETE"
    local ack = nil
    if data then
        if data.isData then
            res = res .. gb.data(data)
            ack = trans.pkts[3]
            if token.name ~= "SETUP" then
                trans.state = "ISO"
            end
        elseif data.isHandshake then
            ack = data
        end
    end
    if ack and ack.isHandshake then
        res = res .. gb.data(ack)
        if token.name == "SETUP" and #trans.pkts < 3 then
        else
            trans.state = ack.name
        end
    end

    if trans.state == "INCOMPLETE" then
        res = res .. gb.incomp()
    end
    local flags = trans.state:sub(1,1)
    if trans.state == "ISO" then flags = gb.F_ISO end
    if token.name == "PING" then flags = flags .. gb.F_PING end
    flags = flags .. gb.addr2str(token.addr, token.ep)
    updateXfer(trans, ts, updateGraph)
    res = gb.ts(trans.desc or "Transaction", ts, gb.C.TRANS) .. res .. gb.F_TRANSACTION .. flags
    updateGraph(res, trans.id, trans)
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
    proto_init(parserContext)
end

parser_reset()

local function transactionParser(ts, res, id, updateGraph)
    parserContext.transState = parserContext.transState or 0
    if     parserContext.transState == 0 then
        if res.isToken then
            if parserContext.lastTrans then
                if parserContext.lastTrans.name == "SOF" and res.name == "SOF" then
                    -- SOF packet
                    res.parent = parserContext.lastTrans
                    parserContext.lastTrans.pkts[#parserContext.lastTrans.pkts+1] = res
                    updateGraph(res.graph, id, res)
                    return
                end
            end
            parserContext.lastTrans = {
                pkts = {res},
                name = res.name,
                id = id
            }
            res.parent = parserContext.lastTrans
            parserContext.id2trans = parserContext.id2trans or {}
            parserContext.id2trans[id] = parserContext.lastTrans
            if res.name == "SOF" then
                updateGraph(makeSOFGroup(ts), id, parserContext.lastTrans)
            else
                parserContext.addr2trans = parserContext.addr2trans or {}
                parserContext.addr2trans[  gb.addr2str(res.addr, res.id) ] = parserContext.lastTrans
                updateTransaction(parserContext.lastTrans, ts, updateGraph)
                parserContext.transState = 1
            end
            updateGraph(res.graph, id, res)
        else
            updateGraph(gb.wild(res, ts), id, res)
            parserContext.transState = 0
        end
    elseif parserContext.transState == 1 then
        assert(parserContext.lastTrans, "last transaction not found")
        if res.isData or res.isHandshake then
            res.parent = parserContext.lastTrans
            parserContext.lastTrans.pkts[#parserContext.lastTrans.pkts+1] = res
            updateTransaction(parserContext.lastTrans, ts, updateGraph)
            if res.isData then
                parserContext.transState = 2
            else
                parserContext.transState = 0
                parserContext.lastTrans = nil
            end
            updateGraph(res.graph, id, res)
        else
            parserContext.transState = 0
            transactionParser(ts, res, id, updateGraph)
        end
    elseif parserContext.transState == 2 then
        assert(parserContext.lastTrans, "last transaction not found")
        if res.isHandshake then
            res.parent = parserContext.lastTrans
            parserContext.lastTrans.pkts[#parserContext.lastTrans.pkts+1] = res
            updateTransaction(parserContext.lastTrans, ts, updateGraph)
            parserContext.transState = 0
            parserContext.lastTrans = nil
            updateGraph(res.graph, id, res)
        else
            parserContext.transState = 0
            transactionParser(ts, res, id, updateGraph)
        end
    else
        assert(nil, "never reach here")
    end
end

local function processXfer(trans, ts, updateGraph)
    parserContext.ongoingXfer = parserContext.ongoingXfer or {}
    parserContext.addrStr = trans.addrStr
    local xfer = parserContext.ongoingXfer[trans.addrStr]
    if not xfer then
        xfer = {}
        xfer.id = trans.id
        xfer.addrStr = trans.addrStr
        if trans.pkts[1].name == "SETUP" then
            xfer.handler = controlXferHandler
        elseif parserContext:getEpClass(trans.addrStr) then
            xfer.handler = parserContext:getEpClass(trans.addrStr).xferHandler
            assert(xfer.handler, "class not have xfer handler")
        else
            -- unknown data transaction
            xfer = nil
        end
        if xfer then
            parserContext.ongoingXfer[trans.addrStr] = xfer
            parserContext.id2xfer = parserContext.id2xfer or {}
            parserContext.id2xfer[xfer.id] = xfer
        end
    end

    if xfer and xfer.handler then
        trans.parent = xfer
        local r = xfer:handler(trans, ts, updateGraph, parserContext)
        if not r then
            trans.parent = nil
            parserContext.ongoingXfer[xfer.addrStr] = nil
            processXfer(trans, ts, updateGraph)
        elseif r == "done" then
            parserContext.ongoingXfer[xfer.addrStr] = nil
        end
    end
end

local validXferTrans = {
    PING  = 1,
    IN    = 1,
    OUT   = 1,
    SETUP = 1
}

function updateXfer(trans, ts, updateGraph)
    assert(parserContext.id2trans[trans.id] == trans, "Transaction not register")
    local t = validXferTrans[trans.pkts[1].name]
    assert( t, "Not a valid xfer transaction " ..  tostring(trans.pkts[1].name) )
    trans.addrStr = trans.addrStr or gb.addr2str(trans.pkts[1].addr, trans.pkts[1].ep)
    processXfer(trans, ts, updateGraph)
end

local function on_packet(pkt, ts, id, updateGraph)
    local pid = unpack("I1", pkt)
    local parser = pid_map[pid]
    if parser then
        local res = parser(pkt, ts, id)
        transactionParser(ts, res, id, updateGraph)
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
