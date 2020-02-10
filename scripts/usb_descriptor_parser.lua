-- usb_descriptor_parser.lua
local usb_defs = require("usb_defs")
local html = require("html")
local parser = {}
local descTable = {}
local fmt = string.format
local unpack = string.unpack



local function parseString(fv, info, data, offset, context)
    local cnt = (info.bLength - 2)/2
    local r = ""
    local cost = 0
    for i=1,cnt do
        local l,h = unpack("I1I1", data, offset + cost)
        if h == 0 then
            r = r .. string.char(l)
        else
            r = r .. "."
        end
        cost = cost + 2
    end
    info.string = r
    return "string", cost, r
end

local prefix = {
    i =    {1, "I1", "%d"},
    b =    {1, "I1", "%d"},
    bm =   {1, "I1", "0x%02X"},
    w =    {2, "I2", "%d"},
    bcd =  {2, "I2", "0x%04X"},
    id  =  {2, "I2", "0x%04X"},
    str  = {2, "I2", parseString},
}

local function createDesc(name, desc)
    return function(data, offset, context)
        local tb = {}
        local info = {}
        tb.title = name .. " Descriptor"
        tb.header = {"Value", "Description"}
        tb.width = {80, 400}
        for i,v in ipairs(desc) do
            local p1, p2 = v:find("[A-Z]")
            assert(p1 and p1>1, "desc field name wrong")
            local t = prefix[v:sub(1, p1-1)]
            assert(t, "unkown prefix " .. v:sub(1, p1-1))
            local fv = unpack(t[2], data, offset)
            local fieldLen = t[1]
            if     type(t[3]) == "string" then
                fv = fmt(t[3], fv)
            elseif type(t[3]) == "function" then
                local a,b,c = t[3](fv, info, data, offset, context)
                fv = a or fv
                fieldLen = b or fieldLen
                v = c or v
            else
                fv = "error"
            end
            offset = offset + fieldLen
            tb[#tb+1] = { fv, v}
            info[v] = fv
        end
        info.html = html.makeTable(tb)
        return info
    end
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

descTable[usb_defs.CFG_DESC] = createDesc("Config", {
    "bLength",
    "bDescriptorType",
    "wTotalLength",
    "bNumInterfaces",
    "bConfigurationValue",
    "iConfiguration",
    "bmAttributes",
    "bMaxPower",
    })

descTable[usb_defs.STRING_DESC] = createDesc("String", {
    "bLength",
    "bDescriptorType",
    "strData",
    })

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


function parser.parse(data, context)
    local info = {}
    local offset = 1
    while offset < #data do
        local t = data:byte(offset+1)
        local p = descTable[t]
        if p then
            local desc = p(data, offset, context)
            offset = offset + desc.bLength
            info.html = info.html or ""
            info.html = info.html .. desc.html
            info[#info+1] = desc
        else
            info.html = info.html or ""
            info.html = info.html .. "<p><h1>unknown descriptor type " .. t .. "</h1></p>"
            offset = #data + 1
        end
    end
    return info
end

package.loaded["usb_descriptor_parser"] = parser

