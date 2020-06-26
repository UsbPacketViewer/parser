-- graph_builder.lua
-- encoding: utf-8

local fmt = string.format
local unpack = string.unpack


local gb = {}
local name2Color = {
    SETUP = {"#FFFF00" },
    IN =    {"#FFFF00" },
    OUT =   {"#FFFF00" },
    SOF =   {"#999900", "white"},
    PING =  {"#999900", "white"},

    DATA0 = {"#543119", "white"},
    DATA1 = {"#191970", "white"},
    DATA2 = {"#4F4406", "white"},
    MDATA = {"#6D056D", "white"},

    ACK   = {"#98FB98" },
    NAK   = {"#FFC0CB", "black"},
    NYET  = {"#FFC0CB", "black"},
    STALL = {"#00FF7F", "black"},

    PRE   = {"#98FB98", "black"},
    SPLIT = {"red"  , "white"},
    
    CRC   = {"#696969", "white"},
    CRC5  = {"#696969", "white"},
    CRC16 = {"#696969", "white"},
    ERROR = {"red"  , "white"},
    TS    = {"white"},
    FRAME = {"#65068E", "white"},
    ADDR  = {"#808080", "white"},
    ENDP  = {"#C0C0C0", "black"},
    TOGGLE= {"#2F4F4F", "white"},
    DATA  = {"#8B0000", "white"},
    XFER  = {"#1E90FF", "white"},
    TRANS = {"#84C1FF"},
    PACKET= {"#ECF5FF"},
    REQ   = {"#B9B973"},
    INCOMPLETE = {"#2F4F4F", "white"},

    SPEED = {"darkgreen", "white"},
}
gb.name2Color = name2Color
gb.C = name2Color

gb.F_PACKET =     "("
gb.F_TRANSACTION= "["
gb.F_XFER       = "{"
gb.F_ACK =        "A"
gb.F_NAK =        "N"
gb.F_NYET =       "N"
gb.F_STALL =      "S"
gb.F_SOF =        "F"
gb.F_INCOMPLETE = "I"
gb.F_ISO =        "O"
gb.F_ERROR =      "E"
gb.F_PING  =      "P"

local function addr2str(addr, ep)
    return "ad:"..addr.."ep:"..ep
end
local function str2addr(str)
    local a, e = 0, 0
    string.gsub(str, "ad:(%d+)ep:(%d+)", function(x,y)
        a = x
        e = y
    end)
    return a, e
end
gb.addr2str = addr2str
gb.str2addr = str2addr

local function graphToString(t1)
    local totalWidth = 0
    local str = ""
    for i,v in ipairs(t1) do
        totalWidth = totalWidth + v.width
        local t =  ";(" .. v.name .. "," .. v.data .. "," .. v.color .. "," .. v.width
        if v.sep then v.textColor = v.textColor or "black" end
        if v.textColor then t = t .. "," .. v.textColor end
        if v.sep then
            t = t .. "," .. v.sep
            totalWidth = totalWidth + v.sep
        end
        str = str .. t .. ")"
    end
    return tonumber(totalWidth+10) .. str .. ";" .. t1.flags
end

local function graphConcat(t1, t2)
    if type(t2) == "string" then
        t1.flags = t1.flags or ""
        local p1 = t2:find("[%({%[]")
        if p1 == 1 then t1.flags = "" end
        t1.flags = t1.flags .. t2
        return t1
    end
    for i,v in ipairs(t2) do
        t1[#t1+1] = v
    end
    t1.flags = t1.flags or ""
    t1.flags = t1.flags .. (t2.flags or "")
    return t1
end

local graph_meta = {
    __tostring = graphToString,
    __concat = graphConcat,
}

local function makeData(name, data, color, width, textColor, sep)
    assert(color, "Color is nil")
    if      type(color) == "table" then
        textColor = color[2]
        color = color[1]
    end
    
    local d =  {
        name = name,
        data = data,
        color = color,
        textColor = textColor,
        width = width,
        sep = sep,
    }
    return setmetatable({d}, graph_meta)
end

local function makeTimestamp(name, ts, color, speed)
    speed = speed or "X"
    speed = speed:sub(1,1)
    return makeData(name, ts, color or name2Color.TS[1], 180, name2Color.TS[2] or "black")
    .. makeData("S", speed, name2Color.SPEED[1], 20, name2Color.SPEED[2], 20)
end

local function errorData(reason)
    return makeData("PACKET ERROR", reason, name2Color.ERROR, 350) .. gb.F_PACKET .. gb.F_ERROR
end


local function makeToken(token, hasCRC)
    local color = name2Color[token.name] or name2Color.ERROR
    local res = makeData(token.name, token.pid, color[1], 60, color[2])
    local flags = ""
    if token.name == "SOF" then
        res = res..makeData("FRAME", token.frame, name2Color.FRAME[1], 60, name2Color.FRAME[2])
        flags = flags .. gb.F_SOF
    else
        res = res..makeData("ADDR", token.addr, name2Color.ADDR[1], 60, name2Color.ADDR[2])
        res = res..makeData("ENDP", token.ep, name2Color.ENDP[1], 60, name2Color.ENDP[2])
        if token.name == "PING" then
            flags = flags .. gb.F_PING
        end
        flags = flags .. addr2str(token.addr, token.ep)
    end
    if hasCRC then
        res = res..makeData("CRC5" , token.crc5, name2Color.CRC[1], 60, name2Color.CRC[2])
    end
    return res .. gb.F_PACKET .. flags
end

local epType2str = {
    [0] = "Control",
    [1] = "Isoch",
    [2] = "Bulk",
    [3] = "Interrupt",
}
local function makeSplitPacket(token, hasCRC)
    local color = name2Color[token.name] or {}
    local prefix = token.isStart and "S" or "C"
    local res = makeData(prefix..token.name, token.pid, color[1], 60, color[2])
    res = res..makeData("ADDR", token.addr, name2Color.ADDR[1], 60, name2Color.ADDR[2])
    res = res..makeData("PORT", token.port, name2Color.ENDP[1], 60, name2Color.ENDP[2])
    local flags =  token.epType == 1 and gb.F_ISO or ""
    local speed = token.isLowSpeed and "Low Speed" or "Full Speed"
    local epType = epType2str[token.epType] or "Unknown"
    res = res..makeData(epType, speed, name2Color.DATA[1], 120, name2Color.DATA[2])
    local se = token.isLowSpeed and "1 " or "0 "
    se = se .. (token.isEnd and "1" or "0")
    res = res..makeData("S E", se, name2Color.TOGGLE, 60)
    if hasCRC then
        res = res..makeData("CRC5" , token.crc5, name2Color.CRC[1], 60, name2Color.CRC[2])
    end
    return res .. gb.F_PACKET .. flags
end

local function makeUnknownPacket(token)
    local pid = "Unknwon"
    if token then
        pid = token.pid or pid
    end
    return makeData("Unknown", pid, name2Color.ERROR, 60) .. gb.F_PACKET .. gb.F_ERROR
end

local function makeDataContent(data)
    data = data or ""
    local hex = ""
    for i=1,#data do
        if i > 8 then
            hex = hex .. "..."
            break
        end
        hex = hex .. fmt("%02X ", unpack("I1", data, i))
    end
    return makeData("DATA ( " .. (#data) .. "bytes)" , hex, name2Color.DATA, 300)
end

local function makeDataPacket(data, hasCRC)
    local color = name2Color[data.name] or {}
    local res = makeData(data.name, data.pid, color[1], 60, color[2])
    res = res .. makeDataContent(data.data)
    if hasCRC then
        res = res .. makeData("CRC16" , data.crc16, name2Color.CRC[1], 60, name2Color.CRC[2])
    end
    return res .. gb.F_PACKET
end

local function makeAckPacket(ack)
    local color = name2Color[ack.name] or {}
    local res = makeData(ack.name, ack.pid, color[1], 60, color[2])
    local flags = ""
    if ack.name ~= "PRE" and ack.name ~= "SPLIT" then
        flags = ack.name:sub(1,1)
    end
    return res .. gb.F_PACKET .. flags
end

gb.block = function(name, data, color, width, textColor, sep)
    width = width or 60
    color = color or name2Color.TS
    data = data or ""
    return makeData(name, data, color, width, textColor, sep) .. gb.F_PACKET .. gb.F_ERROR
end
gb.ts = function(name, ts, color, speed)
    color = color or name2Color.TS
    assert(type(color) == "table")
    return makeTimestamp(name, ts, color, speed)
end
gb.error = errorData
gb.addr = function(addr, n)
    return makeData(n or "ADDR", addr, name2Color.ADDR, 60)
end
gb.endp = function(ep, n)
    return makeData(n or "ENDP", ep, name2Color.ENDP, 60)
end
gb.req = function(req, n)
    return makeData(n or "Request", req, name2Color.REQ, 120)
end
gb.incomp = function(n, w)
    return makeData(n or "Incomplete", "", name2Color.INCOMPLETE, w or 120)
end
gb.data = function(d, hasCRC)
    if type(d) == "string" then return makeDataContent(d) end
    if d.isData then return makeDataPacket(d, hasCRC) end
    if d.isToken then return makeToken(d, hasCRC) end
    if d.isHandshake then return makeAckPacket(d) end
    if d.isSplit then return makeSplitPacket(d, hasCRC) end
    return makeUnknownPacket(d)
end
gb.wild = function(d, ts)
    if d.name == "PRE" then
        return gb.ts("Preamble " .. tostring(d.id) , ts or "", name2Color.ACK, d.speed) .. gb.data(d, true) .. gb.F_ACK
    end
    return gb.ts("Wild packet " .. tostring(d.id) , ts or "", name2Color.ERROR, d.speed) .. gb.data(d, true) .. gb.F_ERROR
end

gb.success = function(info)
    return gb.block(info or "success", "", gb.C.ACK)
end


package.loaded["graph_builder"] = gb
