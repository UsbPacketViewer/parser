-- usb_transaction.lua
local html = require("html")
local gb = require("graph_builder")
local controlXferHandler = require("usb_control_transfer")
local fmt = string.format
local unpack = string.unpack

local function processXfer(trans, ts, updateGraph, parserContext)
    parserContext.ongoingXfer = parserContext.ongoingXfer or {}
    parserContext.addrStr = trans.addrStr
    parserContext.epDir = trans.epDir
    local xfer = parserContext.ongoingXfer[trans.addrStr]
    if not xfer then
        xfer = {}
        xfer.id = trans.id
        xfer.addrStr = trans.addrStr
        if trans.pkts[1].name == "SETUP" then
            xfer.handler = controlXferHandler
        else
            local cls = parserContext:getEpClass(trans.addrStr)
            if cls and cls.transferHandler then
                xfer.handler = cls.transferHandler
                assert(xfer.handler, "class not have xfer handler")
            else
                -- unknown data transaction
                xfer = nil
            end
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
            processXfer(trans, ts, updateGraph, parserContext)
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

local function updateXfer(trans, ts, updateGraph, parserContext)
    assert(parserContext.id2trans[trans.id] == trans, "Transaction not register")
    local t = validXferTrans[trans.pkts[1].name]
    assert( t, "Not a valid xfer transaction " ..  tostring(trans.pkts[1].name) )
    trans.addrStr = trans.addrStr or gb.addr2str(trans.pkts[1].addr, trans.pkts[1].ep)
    processXfer(trans, ts, updateGraph, parserContext)
end

local name2dir = {
    PING = "OUT",
    OUT = "OUT",
    IN = "IN",
    SETUP = "OUT",
}

local function updateTransaction(trans, ts, updateGraph, parserContext)
    local token = trans.pkts[1]
    local res = gb.data(token)
    local data = trans.pkts[2]
    trans.epDir = name2dir[token.name]
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
    updateXfer(trans, ts, updateGraph, parserContext)
    res = gb.ts(trans.desc or "Transaction", ts, gb.C.TRANS) .. res .. gb.F_TRANSACTION .. flags
    updateGraph(res, trans.id, trans)
end

local function makeSOFGroup(ts)
    return gb.ts("Timestamp", ts, gb.C.TRANS)
        .. gb.block("SOFs", "", gb.C.SOF, 120)
        .. gb.F_TRANSACTION .. gb.F_SOF
end

local function transactionParser(ts, res, id, updateGraph, parserContext)
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
                updateTransaction(parserContext.lastTrans, ts, updateGraph, parserContext)
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
            updateTransaction(parserContext.lastTrans, ts, updateGraph, parserContext)
            if res.isData then
                parserContext.transState = 2
            else
                parserContext.transState = 0
                parserContext.lastTrans = nil
            end
            updateGraph(res.graph, id, res)
        else
            parserContext.transState = 0
            transactionParser(ts, res, id, updateGraph, parserContext)
        end
    elseif parserContext.transState == 2 then
        assert(parserContext.lastTrans, "last transaction not found")
        if res.isHandshake then
            res.parent = parserContext.lastTrans
            parserContext.lastTrans.pkts[#parserContext.lastTrans.pkts+1] = res
            updateTransaction(parserContext.lastTrans, ts, updateGraph, parserContext)
            parserContext.transState = 0
            parserContext.lastTrans = nil
            updateGraph(res.graph, id, res)
        else
            parserContext.transState = 0
            transactionParser(ts, res, id, updateGraph, parserContext)
        end
    else
        assert(nil, "never reach here")
    end
end


package.loaded["usb_transaction"] = transactionParser

