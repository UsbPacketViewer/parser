-- parser_init.lua
local setupParser = require("usb_setup_parser")
local usb_register_class = require("usb_register_class")

local function setEpDesc(context, addrStr, dir, desc)
    context.epDescMap = context.epDescMap or {}
    dir = dir or context.epDir
    context.epDescMap[dir] = context.epDescMap[dir] or {}
    context.epDescMap[dir][addrStr] = desc
end

local function getEpDesc(context, addrStr, dir)
    addrStr = addrStr or context.addrStr
    dir = dir or context.epDir
    local r = nil
    if context.epDescMap and context.epDescMap[dir] then
        r = context.epDescMap[dir][addrStr]
    end
    return r
end

local function setEpClass(context, addrStr, dir, classHandler)
    addrStr = addrStr or context.addrStr
    context.epClassMap = context.epClassMap or {}
    dir = dir or context.epDir
    context.epClassMap[dir] = context.epClassMap[dir] or {}
    context.epClassMap[dir][addrStr] = classHandler
end

local function getEpClass(context, addrStr, dir)
    addrStr = addrStr or context.addrStr
    dir = dir or context.epDir
    local r = nil
    if context.epClassMap and context.epClassMap[dir] then
        r = context.epClassMap[dir][addrStr]
    end
    return r
end

local function getInterfaceId(itfDesc)
    if type(itfDesc) == "number" then
        return itfDesc, 0
    end
    assert(type(itfDesc) == "table", "interface descriptor must table")
    local bAlternate = itfDesc.bAlternateSetting
    local bInterface = itfDesc.bInterfaceNumber
    assert(bInterface and bAlternate, "interface descriptor field wrong")
    return bInterface, bAlternate
end

local function setInterfaceClass(context, classInfo, itfDesc)
    local dev = context:currentDevice()
    local bInterface, bAlternate = getInterfaceId(itfDesc)
    dev.interfaces = dev.interfaces or {}
    dev.interfaces[bInterface] = dev.interfaces[bInterface] or {}
    dev.interfaces[bInterface].class = classInfo
    dev.interfaces[bInterface].alternate = dev.interfaces[bInterface].alternate or {}
    dev.interfaces[bInterface].alternate[bAlternate] = classInfo
end

local function getInterfaceClass(context, itfDesc)
    local dev = context:currentDevice()
    local bInterface, bAlternate = getInterfaceId(itfDesc)
    local r = nil
    if dev and dev.interfaces then
        if dev.interfaces[bInterface] then
            r = dev.interfaces[bInterface].class
            if bAlternate and dev.interfaces[bInterface].alternate and dev.interfaces[bInterface].alternate[bAlternate] then
                r = dev.interfaces[bInterface].alternate[bAlternate] or r
            end
        end
    end
    return r
end

local function currentDevice(context, addrStr)
    addrStr = addrStr or context.addrStr
    local p1, p2 = addrStr:find("ep:")
    if p1 then
        local addr = addrStr:sub(1, p1-1)
        context.deviceMap = context.deviceMap or {}
        if not context.deviceMap[addr] then
            context.deviceMap[addr] = {}
        end
        return context.deviceMap[addr]
    end
    return nil
end

local function getClassCode(interfaceDesc)
    assert(type(interfaceDesc) == "table", "require interface desc")
    assert(interfaceDesc.bInterfaceClass, "require interface desc, bInterfaceClass")
    --assert(interfaceDesc.bInterfaceSubClass, "require interface desc, bInterfaceSubClass")
    --assert(interfaceDesc.bInterfaceProtocol, "require interface desc, bInterfaceProtocol")
    local bSubClass = interfaceDesc.bInterfaceSubClass
    local bProtocol = interfaceDesc.bInterfaceProtocol
    local bClass = interfaceDesc.bInterfaceClass
    if bSubClass == 0xff then bSubClass = nil end
    if bProtocol == 0xff then bProtocol = nil end
    return bClass, bSubClass, bProtocol
end

local function regClass(context, classHandler, interfaceDesc)
    interfaceDesc = interfaceDesc or classHandler
    local bClass, bSubClass, bProtocol = getClassCode(interfaceDesc)
    context.classMap = context.classMap or {}
    context.classMap[bClass] = classHandler
    if bSubClass then
        context.classMap[bClass][bSubClass] = classHandler
        if bProtocol then
            context.classMap[bClass][bSubClass][bProtocol] = classHandler
        end
    end
end

local function getClass(context, interfaceDesc)
    local bClass, bSubClass, bProtocol = getClassCode(interfaceDesc)
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
    context.setEpDesc = setEpDesc
    context.getEpDesc = getEpDesc
    context.regClass = regClass
    context.getClass = getClass
    context.isShortPacket = isShortPacket
    context.parseSetupRequest = parseSetupRequest
    context.parseSetupData = parseSetupData
    context.currentDevice = currentDevice
    context.setInterfaceClass = setInterfaceClass
    context.getInterfaceClass = getInterfaceClass
    usb_register_class(context)
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

package.loaded["parser_init"] = init
