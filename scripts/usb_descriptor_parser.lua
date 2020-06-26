-- usb_descriptor_parser.lua
local usb_defs = require("usb_defs")
local html = require("html")
local gb = require("graph_builder")
local parser = {}
local descTable = {}
local fmt = string.format
local unpack = string.unpack
_G.bf = _G.bf or {}

_G.bf.confg_bmAttributes = {
    name = "bmAttributes",
    {name = "Reserved",      mask = 0x1f},
    {name = "Remote Wakeup", mask = 1<<5, [0]="No", [1]="Yes" },
    {name = "Self Powered",  mask = 1<<6, [0]="No", [1]="Yes" },
    {name = "Reserved",      mask = 1<<7},
}

_G.bf.endpoint_bmAttributes = {
    name = "bmAttributes",
    {name = "Type",      mask = 0x03, [0]="Control", [1]="Isochronous", [2]="Bulk", [3]="Interrupt"},
    {name = "Synchronisation Type", mask = 0x0c, [0]="No Synchonisation", [1]="Asynchronous", [2]="Adaptive", [3]="Synchronous"},
    {name = "Usage Type",mask = 0x30, [0]="Data Endpoint", [1]="Feedback Endpoint", [2]="Explicit Feedback Data Endpoint", [3]="Reserved"},
    {name = "Packet per frame", mask = 0xc0,  [0]="1", [1]="2", [2]="3", [3]="Reserved" },
}

_G.bf.endpoint_bEndpointAddress = {
    name = "bEndpointAddress",
    {name = "Direction", mask = 0x80, [0] ="OUT", [1]="IN"},
    {name = "Address",   mask = 0x0f },
    {name = "Reserved",  mask = 0x70}
}


local bf = _G.bf

local function makeString(data, offset, len)
    local r = ""
    for i=1, len do
        local l,h = unpack("I1I1", data, offset + i*2 - 2)
        if h == 0 then
            r = r .. string.char(l)
        else
            r = r .. "."
        end
    end
    return r
end

local function toD(v)    return fmt("%d", v) end
local function toHex2(v)  return fmt("0x%02X", v) end
local function toHex4(v)  return fmt("0x%04X", v) end
local function toDHex2(v)  return fmt("%d(0x%02X)", v, v) end

local prefix = {
    i =    {1, "I1", toD},
    b =    {1, "I1", toD},
    bm =   {1, "I1", toHex2},
    w =    {2, "I2", toD},
    bcd =  {2, "I2", toHex4},
    id  =  {2, "I2", toHex4},
}

local function createDesc(name, desc)
    return function(data, offset, context, descriptionTable)
        local tb = {}
        local info = {}
        tb.title = name .. " Descriptor"
        tb.header = {"Field", "Value", "Description"}
        local lastVid = nil
        for i,v in ipairs(desc) do
            local p1, p2 = v:find("[A-Z]")
            assert(p1 and p1>1, "desc field name wrong")
            local t = prefix[v:sub(1, p1-1)]
            assert(t, "unkown prefix " .. v:sub(1, p1-1))
            local fieldLen = t[1]
            local fieldDisplay = ""
            local fieldValue = 0
            if offset + fieldLen - 1 > #data then
                fieldDisplay = "Truncated"
            else
                fieldValue = unpack(t[2], data, offset)
                if     type(t[3]) == "function" then
                    fieldDisplay = t[3](fieldValue)
                else
                    fieldDisplay = "error"
                end
            end
            offset = offset + fieldLen
            if desc[v] then
                tb[#tb+1] = html.expandBitFiled(fieldValue, desc[v])
            else
                local desc = ""
                if descriptionTable then
                    desc = descriptionTable[v]
                end
                tb[#tb+1] = {v, fieldDisplay, desc or ""}
            end
            if v == "idVendor" then
                lastVid = fieldValue
                tb[#tb][3] = '<a href="https://usb-ids.gowdy.us/read/UD/'..fmt("%04x", fieldValue)..'">Who\'s that?</a>'
            elseif v == "idProduct" then
                tb[#tb][3] = '<a href="https://usb-ids.gowdy.us/read/UD/'..fmt("%04x/%04x", (lastVid or 0), fieldValue)..'">What\'s it?</a>'
            end

            info[v] = fieldValue
        end
        info.html = html.makeTable(tb)
        return info
    end
end

local function parseStringDesc(data, offset, context)
    local tb = {}
    local info = {}
    tb.title = "String Descriptor"
    tb.header = {"Value", "Description"}
    info.bLength =          unpack("I1", data, offset)
    info.bDescriptorType =  unpack("I1", data, offset + 1)
    if #data + 1 >= offset + info.bLength then
        info.string = makeString(data, offset+2, (info.bLength/2)-1)
    else
        info.string = "<truncated>"
    end
    tb[#tb+1] = { info.bLength, "bLength" }
    tb[#tb+1] = { info.bDescriptorType, "bDescriptorType" }
    tb[#tb+1] = { "string", info.string}
    info.html = html.makeTable(tb)
    return info
end

local function toHex(data)
    local res = ""
    if not data then return "<null>" end
    for i=1,#data do
        res = res .. string.format( "%x", data:byte(i))
    end
    return res
end

local function parseUnknownDesc(data, offset, context)
    local tb = {}
    local info = {}
    tb.title = "Unknown Descriptor"
    tb.header = {"Value", "Description"}
    info.bLength =          unpack("I1", data, offset)
    info.bDescriptorType =  unpack("I1", data, offset + 1)
    info.data = data:sub(offset+2, offset+ info.bLength)
    tb[#tb+1] = { info.bLength, "bLength" }
    tb[#tb+1] = { info.bDescriptorType, "bDescriptorType" }
    tb[#tb+1] = { "data",  toHex(info.data) }
    info.html = html.makeTable(tb)
    return info
end

descTable[usb_defs.DEVICE_DESC] = createDesc("Device", {
    "bLength",
    "bDescriptorType",
    "bcdUSB",
    "bDeviceClass",
    "bDeviceSubClass",
    "bDeviceProtocol",
    "bMaxPacketSize",
    "idVendor",
    "idProduct",
    "bcdDevice",
    "iManufacturer",
    "iProduct",
    "iSerial",
    "bNumConfigurations",
    })


descTable[usb_defs.DEV_QUAL_DESC] = createDesc("Device Qualifier", {
    "bLength",
    "bDescriptorType",
    "bcdUSB",
    "bDeviceClass",
    "bDeviceSubClass",
    "bDeviceProtocol",
    "bMaxPacketSize",
    "bNumConfigurations",
    "bReserved",
    })

descTable[usb_defs.DEVICE_DESC] = createDesc("Device", {
    "bLength",
    "bDescriptorType",
    "bcdUSB",
    "bDeviceClass",
    "bDeviceSubClass",
    "bDeviceProtocol",
    "bMaxPacketSize",
    "idVendor",
    "idProduct",
    "bcdDevice",
    "iManufacturer",
    "iProduct",
    "iSerial",
    "bNumConfigurations",
    })

descTable[usb_defs.CFG_DESC] = createDesc("Config", {
    "bLength",
    "bDescriptorType",
    "wTotalLength",
    "bNumInterfaces",
    "bConfigurationValue",
    "iConfiguration",
    "bmAttributes",
    "bMaxPower",
    bmAttributes = bf.confg_bmAttributes,
    })

descTable[usb_defs.STRING_DESC] = parseStringDesc

descTable[usb_defs.INTERFACE_DESC] = createDesc("Interface", {
    "bLength",
    "bDescriptorType",
    "bInterfaceNumber",
    "bAlternateSetting",
    "bNumEndpoints",
    "bInterfaceClass",
    "bInterfaceSubClass",
    "bInterfaceProtocol",
    "iInterface",
    })

descTable[usb_defs.ENDPOINT_DESC] = createDesc("Endpoint", {
    "bLength",
    "bDescriptorType",
    "bEndpointAddress",
    "bmAttributes",
    "wMaxPacketSize",
    "bInterval",
    bEndpointAddress = bf.endpoint_bEndpointAddress,
    bmAttributes = bf.endpoint_bmAttributes,
    })

descTable[usb_defs.HID_DESC] = createDesc("HID", {
    "bLength",
    "bDescriptorType",
    "bcdHID",
    "bCountryCode",
    "bNumDescriptors",
    "bDescriptorType1",
    "wDescriptorLength1",
    })

descTable[usb_defs.IAD_DESC] = createDesc("IAD", {
    "bLength",
    "bDescriptorType",
    "bFirstInterface",
    "bInterfaceCount",
    "bFunctionClass",
    "bFunctionSubClass",
    "bFunctionProtocol",
    "iFunction",
    })

local function setDeviceDesc(descs, context)
    local dev = context:currentDevice()
    dev.deviceDesc = descs[1]
    if dev.deviceDesc.bMaxPacketSize then
        local descIn = {
            wMaxPacketSize = dev.deviceDesc.bMaxPacketSize,
            bEndpointAddress = 0x80,
            bmAttributes = 0,
        }
        context:setEpDesc(context.addrStr, "IN", descIn)
        local descOut = {
            wMaxPacketSize = dev.deviceDesc.bMaxPacketSize,
            bEndpointAddress = 0x00,
            bmAttributes = 0,
        }
        context:setEpDesc(context.addrStr, "OUT", descOut)
    end

    dev.deviceClass = context:getVendorProduct(dev.deviceDesc.idVendor, dev.deviceDesc.idProduct)
    dev.deviceClass = dev.deviceClass or context:getClass({
        bInterfaceClass = dev.deviceDesc.bDeviceClass,
        bInterfaceSubClass = dev.deviceDesc.bDeviceSubClass,
        bInterfaceProtocol = dev.deviceDesc.bDeviceProtocol,
    })
end

local function setConfigDesc(descs, context)
    local dev = context:currentDevice()
    dev.configDesc = descs
    dev.interfaces = {}
    local currentClass = nil
    local currentInterface = nil
    for i,v in ipairs(descs) do
        if v.bDescriptorType and v.bDescriptorType == usb_defs.INTERFACE_DESC then
            currentInterface = v
            currentClass = context:getClass(v)
            context:setInterfaceClass(currentClass, v)
        end
        if v.bDescriptorType and v.bDescriptorType == usb_defs.ENDPOINT_DESC then
            local ep = v.bEndpointAddress & 0x7f
            local dir = ( (v.bEndpointAddress & 0x80) == 0) and "OUT" or "IN"
            local ad, x = gb.str2addr(context.addrStr)
            local addrStr = gb.addr2str(ad, ep)
            v.interfaceDescIndex = i
            v.interfaceDesc = currentInterface
            v.configDesc = descs
            context:setEpDesc(addrStr, dir, v)
            context:setEpClass(addrStr, dir, currentClass)
        end
    end
end

local function gotDescriptor(descs, context)
    if not descs or #descs<1 then
        return
    end
    local dev = context:currentDevice()
    if dev and descs[1] then
        if     descs[1].bDescriptorType == usb_defs.DEVICE_DESC then        
            setDeviceDesc(descs, context)
        elseif descs[1].bDescriptorType == usb_defs.CFG_DESC then
            setConfigDesc(descs, context)
        end
    end
end
 
function parser.parse(data, context)
    local info = {}
    local offset = 1
    local lastInterface = nil
    while offset < #data do
        local t = data:byte(offset+1)
        local desc = nil
        if lastInterface then
            local cls = context:getClass(lastInterface)
            if cls and cls.descriptorParser then
                desc = cls.descriptorParser(data, offset, context)
            end
        end
        local parseFunc = descTable[t] or parseUnknownDesc
        if parseFunc then
            desc = desc or parseFunc(data, offset, context)
            if desc.bDescriptorType == usb_defs.INTERFACE_DESC then
                local cls = context:getClass(desc)
                if cls and cls.getName then
                    desc = parseFunc(data, offset, context, cls.getName(desc, context))
                end
                lastInterface = desc
            end
            offset = offset + desc.bLength
            info.html = info.html or ""
            info.html = info.html .. desc.html
            info[#info+1] = desc
        end
    end
    gotDescriptor(info, context)
    return info
end

package.loaded["usb_descriptor_parser"] = parser

