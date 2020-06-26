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
        xfer.speed = trans.speed
        if trans.token.name == "SETUP" then
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
    local t = validXferTrans[trans.token.name]
    assert( t, "Not a valid xfer transaction " ..  tostring(trans.token.name) )
    trans.addrStr = trans.addrStr or gb.addr2str(trans.token.addr, trans.token.ep)
    processXfer(trans, ts, updateGraph, parserContext)
end

local name2dir = {
    PING = "OUT", 
    OUT = "OUT",
    IN = "IN",
    SETUP = "OUT",
}

local function makeSOFGroup(ts, speed)
    return gb.ts("Timestamp", ts, gb.C.TRANS, speed)
        .. gb.block("SOFs", "", gb.C.SOF, 120)
        .. gb.F_TRANSACTION .. gb.F_SOF
end

--- transaction FSM
local transaction_FSM = {
--   [SPLIT]TOKEN              DATA             HANDSHAKE            STATE:  DONE: finished, TO: require next state
--  {"SOF",                                                "TO:SOF"         },
--  {"PRE",                                                "DONE:ACK"       },
-----------       Normal packet FSM       USB 2.0 Spec, Section 8.5
--[[01]]   {"SETUP",       "DATA0|DATA1",    "ACK|NAK|STALL",     "DONE:-1"        },
--[[02]]   {"OUT",         "DATA0|DATA1",                         "DONE:ISO"       },
--[[03]]   {"OUT",         "DATA0|DATA1",    "ACK|NAK|STALL",     "DONE:-1"        },
--[[03]]   {"OUT",         "DATA0|DATA1",    "NYET",              "DONE:ACK"       }, -- data with NYET should be ACK
--[[04]]   {"IN",          "DATA0|DATA1",    "ACK"          ,     "DONE:ACK"       },
--[[05]]   {"IN",          "DATA0|DATA1",                         "DONE:ISO"       },
--[[06]]   {"IN",                            "NAK|STALL",         "DONE:-1"        },
--[[07]]   {"IN",                            "ACK",               "DONE:NAK"       },
--[[08]]   {"PING",                          "ACK|NYET|NAK",      "DONE:-1"        },
-----------       Control Setup TT FSM   USB 2.0 Spec, Section 11.17.1
--[[09]]   {"SS:C_SETUP",  "DATA0|DATA1",    "NAK",               "DONE:NAK"       },
--[[10]]   {"SS:C_SETUP",  "DATA0|DATA1",    "ACK",               "TO:CS:C_SETUP"  },
--[[11]]   {"CS:C_SETUP",                    "ACK|NAK|STALL",     "DONE:-1"        },
--[[12]]   {"CS:C_SETUP",                    "NYET",              "TO:CS:C_SETUP"  },
-----------       Control Out TT FSM     USB 2.0 Spec, Section 11.17.1
--[[13]]   {"SS:C_OUT",    "DATA0|DATA1",    "NAK",               "DONE:NAK"       },
--[[14]]   {"SS:C_OUT",    "DATA0|DATA1",    "ACK",               "TO:CS:C_OUT"    },
--[[15]]   {"CS:C_OUT",                      "ACK|NAK|STALL",     "DONE:-1"        },
--[[16]]   {"CS:C_OUT",                      "NYET",              "TO:CS:C_OUT"    },
-----------       Control In TT FSM      USB 2.0 Spec, Section 11.17.1
--[[17]]   {"SS:C_IN",                       "NAK",               "DONE:NAK"       },
--[[18]]   {"SS:C_IN",                       "ACK",               "TO:CS:C_IN"     },
--[[19]]   {"CS:C_IN",     "DATA0|DATA1",                         "DONE:ACK"       },
--[[20]]   {"CS:C_IN",                       "NAK|STALL",         "DONE:-1"        },
--[[21]]   {"CS:C_IN",                       "NYET",              "TO:CS:C_IN"     },
-----------       Bulk Out TT FSM       USB 2.0 Spec, Section 11.17.1
--[[22]]   {"SS:B_OUT",    "DATA0|DATA1",    "NAK",               "DONE:NAK"       },
--[[23]]   {"SS:B_OUT",    "DATA0|DATA1",    "ACK",               "TO:CS:B_OUT"    },
--[[24]]   {"CS:B_OUT",                      "ACK|NAK|STALL",     "DONE:-1"        },
--[[25]]   {"CS:B_OUT",                      "NYET",              "TO:CS:B_OUT"    },
-----------       Bulk In TT FSM        USB 2.0 Spec, Section 11.17.1
--[[26]]   {"SS:B_IN",                       "NAK",               "DONE:NAK"       },
--[[27]]   {"SS:B_IN",                       "ACK",               "TO:CS:B_IN"     },
--[[28]]   {"CS:B_IN",     "DATA0|DATA1",                         "DONE:ACK"       },
--[[29]]   {"CS:B_IN",                       "NAK|STALL",         "DONE:-1"        },
--[[30]]   {"CS:B_IN",                       "NYET",              "TO:CS:B_IN"     },
-----------       Interrupt Out TT FSM  USB 2.0 Spec, Section 11.20.1
--[[31]]   {"SS:I_OUT",    "DATA0|DATA1",                         "TO:CS:I_OUT"    },
--[[32]]   {"CS:I_OUT",                      "ACK|NAK|STALL|ERR", "DONE:-1"        },
--[[33]]   {"CS:I_OUT",                      "NYET",              "TO:CS:I_OUT"    },
-----------       Interrupt In TT FSM   USB 2.0 Spec, Section 11.20.1
--[[34]]   {"SS:I_IN",                                            "TO:CS:I_IN"     },
--[[35]]   {"CS:I_IN",    "MDATA",                                "TO:CS:I_IN"     },
--[[36]]   {"CS:I_IN",    "DATA0|DATA1",                          "DONE:ACK"       },
--[[37]]   {"CS:I_IN",                       "NAK|STALL|ERR",     "DONE:-1"        },
--[[38]]   {"CS:I_IN",                       "NYET",              "TO:CS:I_IN"     },
-----------       Iso Out TT FSM        USB 2.0 Spec, Section 11.21.1
--[[39]]   {"SS:S_OUT",  "DATA0",                                 "DONE:ISO"       },
-----------       Iso In TT FSM         USB 2.0 Spec, Section 11.21.1
--[[40]]   {"SS:S_IN",                                            "TO:CS:S_IN"     },
--[[41]]   {"CS:S_IN",   "MDATA",                                 "TO:CS:S_IN"     },
--[[42]]   {"CS:S_IN",                       "NYET",              "TO:CS:S_IN"     },
--[[43]]   {"CS:S_IN",   "DATA0",                                 "DONE:ISO"       },
--[[44]]   {"CS:S_IN",                       "ERR",               "DONE:ERR"       },
}

_G.Packet_FSM = transaction_FSM

local xaction_fsm = {}
for i,v in ipairs(transaction_FSM) do
    local n = v[1]
    xaction_fsm[n] = xaction_fsm[n] or {}
    local t = xaction_fsm[n]
    t[#t+1] = v
    t[#t].id = i
end

local epType2flag = {
    [0] = "C",
    [1] = "S",
    [2] = "B",
    [3] = "I",
}

local function nextState(fsm)
    assert(fsm.state[fsm.row])
    local t = fsm.state[fsm.row][fsm.index]
    if not t then return t end
    local p1, p2 = t:find("TO:")
    if p1 == 1 and p2 == 3 then
        local n = t:sub(p2+1)
        local state = xaction_fsm[n]
        assert(state, "Unknown TO: " .. tostring(n))
        return state
    end
    return nil
end

local function isDone(fsm)
    assert(fsm.state[fsm.row])
    assert(fsm.state[fsm.row][fsm.index],
    fsm.state[fsm.row][1] .. "   index: " ..tostring(fsm.index) .. "  ID:" .. fsm.state[fsm.row].id .. "  ROW: " .. fsm.row)
    local t = fsm.state[fsm.row][fsm.index]
    local p1, p2 = t:find("DONE:")
    local res = nil
    local res_pkt = nil
    if p1 == 1 and p2 == 5 then
        local n = t:sub(p2+1)
        if tonumber(n) then
            local pkt = fsm.pkts[#fsm.pkts]
            if pkt.isHandshake then
                res = pkt.name
                res_pkt = pkt
            else
                error("State machine finished without handshake")
            end
        else
            local pkt = fsm.pkts[#fsm.pkts]
            if pkt.isHandshake then
                res_pkt = pkt
            end
            res = n
        end
    end
    if res == "PRE" then res = "ERR" end
    return res, res_pkt
end

local function fsm_check(state, name, index)
    local least = 1000
    local row = nil
    for i,v in ipairs(state) do
        if v[index] and v[index]:find(name) and not (v[index]:find("TO") or v[index]:find("DONE")) then
            if least > #v then
                least = #v
                row = i
            end
        end
    end
    return row
end

local function fsm_update(fsm, name, pkt)
    if name == "PRE" then name = "ERR" end
    local row = fsm_check(fsm.state, name, fsm.index)
    local dbg = name .. "   Restart"
    if row then
        dbg = fsm.state[row][1] .. "[" .. fsm.state[row].id .. "]    " .. name .. ": " .. fsm.index
        if pkt.isData then
            fsm.data = fsm.data or ""
            fsm.data = fsm.data .. pkt.data
            fsm.dataPkt = fsm.dataPkt or pkt
        end
        fsm.index = fsm.index + 1
        fsm.row = row
        fsm.pkts[#fsm.pkts+1] = pkt
        if #fsm.pkts == 1 then
            fsm.token = pkt
        end

        dbg = dbg .. " -> " .. fsm.index .. " Row: " .. row
        local state = nextState(fsm)
        if state then
            fsm.state = state
            fsm.index = 1
            dbg = dbg .. "  Next state " .. state[1][1]
        end
    end
    --print(dbg)
    return row
end

local function fsm_create(name)
    local state = xaction_fsm[name]
    if not state then return nil end
    return {
        state = state,
        index = 1,
        update = fsm_update,
        isDone = isDone,
        name = name,
        pkts = {},
    }
end

local function updateTransaction(trans, ts, updateGraph, parserContext)
    local token = trans.fsm.token
    local state, ack = trans.fsm:isDone()
    trans.epDir = name2dir[token.name]
    local res = gb.data(token)
    if state then
        if trans.fsm.dataPkt then
            res = res .. gb.data(trans.fsm.dataPkt)
        end
        if ack then
            res = res .. gb.data(ack)
        else
            res = res .. gb.block(state)
        end
        trans.state = state
    else
        trans.state = "INCOMPLETE"
        res = res .. gb.incomp()
    end
    trans.data = trans.fsm.data
    trans.token = trans.fsm.token

    local flags = trans.state:sub(1,1)
    if trans.state == "ISO" then flags = gb.F_ISO end
    if token.name == "PING" then flags = flags .. gb.F_PING end
    flags = flags .. gb.addr2str(token.addr, token.ep)
    updateXfer(trans, ts, updateGraph, parserContext)
    res = gb.ts(trans.desc or "Transaction", ts, gb.C.TRANS, trans.speed) .. res .. gb.F_TRANSACTION .. flags
    updateGraph(res, trans.id, trans)
end

local function transactionParser(ts, res, id, updateGraph, parserContext, depth)
    if depth and depth >= 3 then return end
    parserContext.port2trans = parserContext.port2trans or {}
    if res.isSplit then
        -- parse with token later
        parserContext.lastSplit = res
        if res.isStart then
            parserContext.port2trans[gb.addr2str(res.destAddr, res.destEp)] = nil
        end
        return
    end
    local name = res.name
    if res.isToken and parserContext.lastSplit then
        local split = parserContext.lastSplit
        parserContext.lastSplit = nil
        local prefix = split.isStart and "SS:" or "CS:"
        prefix = prefix .. (epType2flag[split.epType] or "") .. "_"
        name = prefix .. res.name
        res.split = split
        res.splitName = name
    end
    -- special process for SOF packets
    if res.name == "SOF" then
        if parserContext.lastTrans and parserContext.lastTrans.name == "SOF" then
            parserContext.lastTrans.pkts[#parserContext.lastTrans.pkts+1] = res
        else
            parserContext.lastTrans = {
                pkts = {res},
                name = res.name,
                id = id,
                speed = res.speed,
            }
            parserContext.id2trans[id] = parserContext.lastTrans
            updateGraph(makeSOFGroup(ts, res.speed), id, parserContext.lastTrans)
        end
        res.parent = parserContext.lastTrans
        updateGraph(res.graph, id, res)
        return
    elseif parserContext.lastTrans and parserContext.lastTrans.name == "SOF" then
        parserContext.lastTrans = nil
    end
    if res.split then
        if not res.split.isStart then
            local trans = parserContext.port2trans[gb.addr2str(res.split.destAddr, res.split.destEp)]
            if not trans  or not trans.fsm then
                -- CSPLIT without SSPLIT, make them wild
                updateGraph(gb.wild(res.split, ts), res.split.id, res.split)
                updateGraph(gb.wild(res, ts), id, res)
                return
            end
            parserContext.lastTrans = trans
        end
    end

    if not parserContext.lastTrans then
        local t = fsm_create(name)
        if not t then
            updateGraph(gb.wild(res, ts), id, res)
            return
        end
        parserContext.lastTrans = {
            name = res.name,
            id = id,
            fsm = t,
            speed = res.speed,
        }
        parserContext.id2trans[id] = parserContext.lastTrans
    end

    local trans = parserContext.lastTrans
    if res.split and res.split.isStart then
        parserContext.port2trans[gb.addr2str(res.split.destAddr, res.split.destEp)] = trans
    end

    local row = trans.fsm:update(name, res)
    if not row then
        -- state finished, maybe a new one
        parserContext.lastTrans = nil
        parserContext.lastSplit = res.split
        if res.split then
            parserContext.port2trans[gb.addr2str(res.split.destAddr, res.split.destEp)] = nil
        end
        depth = depth or 1
        transactionParser(ts, res, id, updateGraph, parserContext, depth + 1)
        return
    end

    updateTransaction(trans, ts, updateGraph, parserContext)

    if res.split then
        res.split.parent = trans
        updateGraph(res.split.graph, res.split.id, res.split)
    end
    res.parent = trans
    updateGraph(res.graph, id, res)

end

package.loaded["usb_transaction"] = transactionParser

