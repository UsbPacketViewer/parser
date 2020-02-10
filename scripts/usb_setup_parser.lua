-- usb_setup_parser.lua
-- encoding: utf-8

local parser = {}
local fmt = string.format
local unpack = string.unpack
local html = require("html")
local usb_defs = require("usb_defs")
local desc_parser = require("usb_descriptor_parser")

function parser.parseSetup(data, context)
    local setup = {}
    setup.data = data
    local bmRequest, bRequest, wValue, wIndex, wLength = unpack("I1I1I2I2I2", setup.data .. "\xff\xff\xff\xff\xff\xff\xff\xff")
    setup.bmRequest = bmRequest
    setup.bRequest = bRequest
    setup.wValue = wValue
    setup.wIndex = wIndex
    setup.wLength = wLength
    local dir = bmRequest >= 0x80 and "D2H" or "H2D"

    local typStr
    local typ = (bmRequest >> 5) & 3
    if     typ == 0 then typStr = "Standard"
    elseif typ == 1 then typStr = "Class"
    elseif typ == 2 then typStr = "Vendor"
    else                 typStr = "Reserved"
    end
    setup.type = typStr

    local recipStr
    local recip = bmRequest & 0x1f
    if     recip == 0 then recipStr = "Device"
    elseif recip == 1 then recipStr = "Interface"
    elseif recip == 2 then recipStr = "Endpoint"
    elseif recip == 3 then recipStr = "Other"
    else                   recipStr = "Reserved"
    end
    local bmRequest_desc = "(" .. dir .. ", " .. typStr .. ", " .. recipStr .. ")"

    local bRequest_desc = ""
    if       typStr == "Standard" then
        bRequest_desc = usb_defs.stdRequestName(bRequest)
    elseif   typStr == "Class" then
        bRequest_desc = " class specified " .. bRequest
    elseif   typStr == "Vendor" then
        bRequest_desc = " Vendor specified " .. bRequest
    end

    local wValue_desc = ""
    if (bRequest == usb_defs.CLEAR_FEATURE) or (bRequest == usb_defs.SET_FEATURE) then
        wValue_desc = fmt("(Feature: %d)", wValue)
    elseif bRequest == usb_defs.SET_ADDRESS then
        wValue_desc = fmt("(Address: %d)", wValue)
    elseif (bRequest == usb_defs.GET_DESCRIPTOR) or (bRequest == usb_defs.SET_DESCRIPTOR) then
        wValue_desc = fmt("(Descriptor: %s/%d)", usb_defs.descriptorName(wValue>>8), wValue&0xff)
    elseif bRequest == usb_defs.SET_CONFIG then
        wValue_desc = fmt("(Config: %d)", wValue)
    end

    local wIndex_desc = ""
    if (wValue > 0) and ((bRequest == usb_defs.GET_DESCRIPTOR) or (bRequest == usb_defs.SET_DESCRIPTOR)) then
        wIndex_desc = fmt("(Language: 0x%04x)", wIndex)
    else
    end

    setup.html = html.makeTable{
        title = typStr .. " request",
        header = {"Value", "Description"},
        width = {80, 400},
        {fmt("0x%02x",   bmRequest), "bmRequest " .. bmRequest_desc },
        {fmt("%d",     bRequest),    "bRequest  " .. bRequest_desc  },
        {fmt("0x%02x",   wValue),    "wValue " .. wValue_desc    },
        {fmt("%d",     wIndex),      "wIndex" .. wIndex_desc    },
        {fmt("%d",     wLength),     "wLength"   },
    }
    
    setup.name = bRequest_desc
    return setup
end

function parser.parseData(setup, data, context)
    if setup.type == "Standard" and (setup.bRequest == usb_defs.GET_DESCRIPTOR or bRequest == usb_defs.SET_DESCRIPTOR) then
        if setup.wValue >> 8 == usb_defs.REPORT_DESC then
        else
            local descInfo = desc_parser.parse(data, context)
            return descInfo.html
        end
    end
    return "<p><h1>Get " .. #data .. " bytes data</h1></p> Display in data window"
end

package.loaded["usb_setup_parser"] = parser
