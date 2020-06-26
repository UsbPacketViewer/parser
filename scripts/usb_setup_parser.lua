-- usb_setup_parser.lua
-- encoding: utf-8

local parser = {}
local fmt = string.format
local unpack = string.unpack
local html = require("html")
local usb_defs = require("usb_defs")
local desc_parser = require("usb_descriptor_parser")
_G.bf = _G.bf or {}
_G.bf.bmRequest = {
    name = "bmRequest",
    {name = "Recipient", mask = 0x1f, [0]= "Device", [1] = "Interface", [2] = "Endpoint" ,[3]="Other"},
    {name = "Type",      mask = 0x60, [0] = "Standard", [1]="Class",[2]="Vendor",[3]="Reserved"},
    {name = "Direction", mask = 0x80, [0]="Host to Device", [1]="Device to Host"}
}

_G.bf.wValue_getDescriptor = {
    name = "wValue",
    bits = 16,
    {name = "[8..15] Type", mask = 0xff00,
        [1] = "Device Descriptor",
        [2] = "Configuration Descriptor",
        [3] = "String Descriptor",
        [4] = "Interface Descriptor",
        [5] = "Endpoint Descriptor",
        [6] = "Device Qualifier Descriptor",
        [7] = "Other Speed Descriptor",
        [8] = "Interface Power Descriptor",
        [9] = "OTG Descriptor",
        [0x22] = "Report Descriptor",
        [0x29] = "Hub Descriptor",
    },
    {name = "[0..7] Index", mask = 0x00ff},
}

_G.bf.get_device_status = {
    name = "wStatus",
    bits = 16,
    {name = "Self Powered", mask = 0x0001, [0] = "Bus Powered", [1] = "Self Powered"},
    {name = "Remote Wakeup", mask = 0x0002, [0] = "Disabled", [1] = "Enabled"},
    {name = "Reserved", mask = 0xfffc},
}

local bf = _G.bf

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
    setup.recip = recipStr
    
    if recipStr == "Interface" then
        local cls = context:getInterfaceClass(wIndex)
        if cls and cls.parseSetup then
            local r = cls.parseSetup(setup, context)
            if r then return r end
        end
    elseif recipStr == "Device" or recipStr == "Other" then
        if typStr == "Class" then
            local cls = context:currentDevice().deviceClass
            if cls and cls.parseSetup then
                local r = cls.parseSetup(setup, context)
                if r then return r end
            end
        end
    end

    local dev = context:currentDevice()
    if dev and dev.parseSetup then
        local r = dev.parseSetup(setup, context)
        if r then return r end
    end

    

    local bRequest_desc = ""
    if       typStr == "Standard" then
        bRequest_desc = usb_defs.stdRequestName(bRequest)
    elseif   typStr == "Class" then
        bRequest_desc = " class req " .. bRequest
    elseif   typStr == "Vendor" then
        bRequest_desc = " Vendor req " .. bRequest
    end

    local wValue_desc = ""
    local WValue_field = { "wValue",    fmt("0x%04x",   wValue), "" }
    if typStr == "Standard" then
        if (bRequest == usb_defs.CLEAR_FEATURE) or (bRequest == usb_defs.SET_FEATURE) then
            wValue_desc = fmt("Feature: %d", wValue)
            WValue_field[3] = wValue_desc
        elseif bRequest == usb_defs.SET_ADDRESS then
            wValue_desc = fmt("Address: %d", wValue)
            WValue_field[3] = wValue_desc
        elseif (bRequest == usb_defs.GET_DESCRIPTOR) or (bRequest == usb_defs.SET_DESCRIPTOR) then
            WValue_field = html.expandBitFiled(wValue, bf.wValue_getDescriptor, true)
        elseif bRequest == usb_defs.SET_CONFIG then
            wValue_desc = fmt("Config: %d", wValue)
            WValue_field[3] = wValue_desc
        end
    end

    local wIndex_desc = ""
    if recipStr == "Device" then
        if (wValue > 0) and ((bRequest == usb_defs.GET_DESCRIPTOR) or (bRequest == usb_defs.SET_DESCRIPTOR)) then
            wIndex_desc = fmt("Language ID: 0x%04x", wIndex)
        else
        end
    elseif recipStr == "Interface" then
        wIndex_desc = fmt("Interface: %d", wIndex)
    elseif recipStr == "Endpoint" then
        wIndex_desc = fmt("Endpoint: 0x%02X", wIndex & 0xff)
    end

    setup.html = html.makeTable{
        title = typStr .. " request",
        header = {"Field", "Value", "Description"},
        html.expandBitFiled(bmRequest, bf.bmRequest),
        {"bRequest",  fmt("%d",       bRequest),    bRequest_desc  },
        WValue_field,
        {"wIndex",    fmt("%d",       wIndex),      wIndex_desc    },
        {"wLength",   fmt("%d",       wLength),     ""},
    }
    
    setup.name = bRequest_desc
    return setup
end

function parser.parseData(setup, data, context)
    if setup.recip == "Interface" then
        local cls = context:getInterfaceClass(setup.wIndex)
        if cls and cls.parseSetupData then
            local r = cls.parseSetupData(setup, data, context)
            if r then return r end
        end
    elseif setup.recip == "Device" or setup.recip == "Other" then
        if setup.type == "Class" then
            local cls = context:currentDevice().deviceClass
            if cls and cls.parseSetupData then
                local r = cls.parseSetupData(setup, data, context)
                if r then return r end
            end
        end
    end

    local dev = context:currentDevice()
    if dev and dev.parseSetupData then
        local r = dev.parseSetupData(setup, data, context)
        if r then return r end
    end

    if setup.type == "Standard" then
        if (setup.bRequest == usb_defs.GET_DESCRIPTOR or bRequest == usb_defs.SET_DESCRIPTOR) then
            if (setup.wValue >> 8) <= usb_defs.MAX_STD_DESC then
                local descInfo = desc_parser.parse(data, context)
                return descInfo.html
            end
        elseif setup.bRequest == usb_defs.GET_STATUS and #data >= 2 then
            return html.makeTable{
                title = "Device Status",
                header = {"Field", "Value", "Description"},
                html.expandBitFiled(unpack("I2", data), bf.get_device_status),
            }
        end
    end
    return "<p><h1>Get " .. #data .. " bytes data</h1></p> Display in data window"
end

package.loaded["usb_setup_parser"] = parser
