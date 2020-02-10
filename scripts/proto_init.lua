-- proto_init.lua
local setupParser = require("usb_setup_parser")

local function setEpDesc(context, addrStr, desc)
    context.epDescMap = context.epDescMap or {}
    context.epDescMap[addrStr] = desc
end

local function getEpDesc(context, addrStr)
    if context.epDescMap then
        return context.epDescMap[addrStr]
    end
end

local function setEpClass(context, addrStr, classHandler)
    context.epClassMap = context.epClassMap or {}
    context.epClassMap[addrStr] = classHandler
end

local function getEpClass(context, addrStr)
    if context.epClassMap then
        return context.epClassMap[addrStr]
    end
end

local function getClassCode(bClass, bSubClass, bProtocol)
    if type(bClass) == "table" then
        assert(bClass.bInterfaceSubClass)
        assert(bClass.bInterfaceProtocol)
        assert(bClass.bInterfaceClass)
        bSubClass = bClass.bInterfaceSubClass
        bProtocol = bClass.bInterfaceProtocol
        bClass = bClass.bInterfaceClass
        if bSubClass == 0xff then bSubClass = nil end
        if bProtocol == 0xff then bProtocol = nil end
    end
    assert(bClass, "Class code not set")
    return bClass, bSubClass, bProtocol
end

local function regClass(context, classHandler, bClass, bSubClass, bProtocol)
    bClass, bSubClass, bProtocol = getClassCode(bClass, bSubClass, bProtocol)
    context.classMap = context.classMap or {}
    context.classMap[class] = classHandler
    if bSubClass then
        context.classMap[bClass][bSubClass] = classHandler
        if bProtocol then
            context.classMap[bClass][bSubClass][bProtocol] = classHandler
        end
    end
end

local function getClass(context, bClass, bSubClass, bProtocol)
    bClass, bSubClass, bProtocol = getClassCode(bClass, bSubClass, bProtocol)
    if context.classMap then
        local r = context.classMap[bClass]
        if not r or not bSubClass then return r end
        local t = r[bSubClass]
        if not t or not bProtocol then return r end
        r = t[bProtocol]
        return r or t
    end
    return nil
end

local function isShortPacket(context, addr, data)
    local desc = context:getEpDesc(addr)
    local wMaxPacketSize = nil
    if not desc then
        if addr:find("ep:0") then
        else
            wMaxPacketSize = 64
        end
    else
        wMaxPacketSize = desc.wMaxPacketSize
    end
    if not wMaxPacketSize then
        if #data < 8 then return true end
        if #data == 8 then return false end
        if #data < 64 then return true end
        return false
    end
    return #data < wMaxPacketSize
end

local function parseSetupRequest(context, setup)
    return setupParser.parseSetup(setup, context)
end

local function parseSetupData(context, setup, data)
    return setupParser.parseData(setup, data, context)
end

local function init(context)
    context.setEpClass = setEpClass
    context.getEpClass = getEpClass
    context.setEpDesc = setEpClass
    context.getEpDesc = getEpClass
    context.regClass = regClass
    context.getClass = getClass
    context.isShortPacket = isShortPacket
    context.parseSetupRequest = parseSetupRequest
    context.parseSetupData = parseSetupData
end

_G.lastError = ""
local err_handler = function(err)
    _G.lastError = err .. 
    debug.traceback()
end

function try(func, ...)
    _G.lastError = ""
    local args = {...}
    local r = { xpcall(func, err_handler, unpack(args))  }
    if r[1] then
        for i=2,#r do
            r[i-1] = r[i]
        end
        r[#r] = nil
        return unpack(r)
    end
    error(_G.lastError)
end

package.loaded["proto_init"] = init
