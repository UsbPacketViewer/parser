-- usb_class_hid.lua

-- a typical class has these functions
-- cls.parseSetup(setup, context),  update setup.html, setup.name field in setup, and return it
-- cls.parseSetupData(setup, data, context)    return a html to describe the data
-- cls.transferHandler(xfer, tansaction, timestamp_string, updateGraph, parserContext)  return  one of nil , true, "done"
-- cls.descriptorParser(data, offset, context)   return a parsed descriptor
-- HID class definition  https://usb.org/sites/default/files/documents/hid1_11.pdf

local html = require("html")
local usb_defs = require("usb_defs")
local gb = require("graph_builder")
require("usb_setup_parser")

local fmt = string.format
local unpack = string.unpack
local cls = {}
cls.name = "HID class"

local modStr = {
    "Left Ctrl", "Left Shift", "Left Alt", "Left Meta",
    "Right Ctrl", "Right Shift", "Right Alt", "Right Meta",
}

_G.bf = _G.bf or {}

_G.bf.wValue_hid_report = {
    name = "wValue",
    bits = 16,
    {name = "[8..15] Type", mask = 0xff00,
        [1] = "Input Report",
        [2] = "Output Report",
        [3] = "Feature Report",
    },
    {name = "[0..7] Report ID", mask = 0x00ff},
}

_G.bf.wValue_hid_idle = {
    name = "wValue",
    bits = 16,
    {name = "[8..15] Idle Value", mask = 0xff00},
    {name = "[0..7] Report ID", mask = 0x00ff},
}

_G.bf.key_modifier = {
    name = "Modifier",
    { mask = 1<<0, [0] = "Left Ctrl Released",  [1] = "Left Ctrl Pressed",    },
    { mask = 1<<1, [0] = "Left Shift Released", [1] = "Left Shift Pressed",   },
    { mask = 1<<2, [0] = "Left Alt Released",   [1] = "Left Alt Pressed",     },
    { mask = 1<<3, [0] = "Left Meta Released",  [1] = "Left Meta Pressed",    },
    { mask = 1<<4, [0] = "Right Ctrl Released", [1] = "Right Ctrl Pressed",   },
    { mask = 1<<5, [0] = "Right Shift Released",[1] = "Right Shift Pressed",  },
    { mask = 1<<6, [0] = "Right Alt Released",  [1] = "Right Alt Pressed",    },
    { mask = 1<<7, [0] = "Right Meta Released", [1] = "Right Meta Pressed",   },
}

_G.bf.mouse_button = {
    name = "Button",
    { mask = 1<<0, [0] = "Button 1 released", [1] = "Button 1 pressed"  },
    { mask = 1<<1, [0] = "Button 2 released", [1] = "Button 2 pressed"  },
    { mask = 1<<2, [0] = "Button 3 released", [1] = "Button 3 pressed"  },
}

local bf = _G.bf

local function mod2str(mod)
    local r = ""
    local sep = ""
    for i=1,8 do
        if (mod & (1<<(i-1))) ~= 0 then
            r = r .. sep .. modStr[i]
            sep = ", "
        end
    end
    return #r < 1 and "None" or r
end

local KEY_A = 0x04
local KEY_Z = 0x1d
local KEY_1 = 0x1e
local KEY_0 = 0x27
local KEY_F1 = 0x3a
local KEY_F12 = 0x45
local KEY_ENTER = 0x28
local num = "1234567890"
local function key2str(key)
    if key == 0 then return '[None]'
    elseif key == 1 then return '[ERR_OVF]'
    elseif key >= KEY_A and key<= KEY_Z then
        return string.char( string.byte("A",1) + key - 4 )
    elseif key >= KEY_1 and key <= KEY_0 then
        local p = key-0x1e+1
        return num:sub(p,p)
    elseif key >= KEY_F1 and key <= KEY_F12 then
        return "F" .. (key - KEY_F1 + 1)
    elseif key == KEY_ENTER then
        return "Enter"
    end
    return "[unknown]"
end


local req2str = {
    [1] = "GET_REPORT",
    [2] = "GET_IDLE",
    [3] = "GET_PROTOCOL",
    [9] = "SET_REPORT",
    [10] = "SET_IDLE",
    [11] = "SET_PROTOCOL",
}

local rpt2str = {
    [1] = "Input Report",
    [2] = "Output Report",
    [3] = "Feature Report",
}

function cls.parseSetup(setup, context)
    if setup.recip ~= "Interface" or setup.type ~= "Class" then
        return nil
    end
    local bRequest_desc = req2str[setup.bRequest] or "HID Unknown Req"
    local reportId = setup.wValue & 0xff
    local value = setup.wValue >> 8

    local wValue_desc = ""
    local wValueField = {"wValue", fmt("0x%04X", setup.wValue), ""}
    if bRequest_desc == "GET_REPORT" or bRequest_desc == "SET_REPORT" then
        --wValue_desc = fmt("Report ID %d, ", reportId ) .. (rpt2str[value] or "Unknown")
        wValueField = html.expandBitFiled(setup.wValue, bf.wValue_hid_report, true)
    elseif bRequest_desc == "GET_IDLE" or bRequest_desc == "SET_IDLE" then
        --wValue_desc = fmt("Report ID %d, IDLE: %d", reportId, value )
        wValueField = html.expandBitFiled(setup.wValue, bf.wValue_hid_idle, true)
    elseif bRequest_desc == "GET_PROTOCOL" or bRequest_desc == "SET_PROTOCOL" then
    end
    local wIndex_desc = fmt("Interface: %d", setup.wIndex)

    setup.name = bRequest_desc
    setup.html = html.makeTable{
        title = "HID " .. bRequest_desc,
        header = {"Field", "Value", "Description"},
        html.expandBitFiled(setup.bmRequest, bf.bmRequest),
        {"bRequest", fmt("%d",       setup.bRequest),  bRequest_desc  },
        wValueField,
        {"wIndex",   fmt("%d",       setup.wIndex),    wIndex_desc    },
        {"wLength",  fmt("%d",       setup.wLength),   ""   },
    }
    return setup
end

function cls.parseSetupData(setup, data, context)
    local s = req2str[setup.bRequest]
    if s then 
        return "<h1>" .. s .." data </h1>"
    end
    if (setup.bRequest == usb_defs.GET_DESCRIPTOR) and ((setup.wValue>>8) == usb_defs.REPORT_DESC) then
        return "<h1>Report descriptor </h1><br>Todo: parse it to analyze endpoint data"
    end
    return nil
end

function cls.transferHandler(xfer, trans, ts, updateGraph, context)
    local desc = context:getEpDesc()
    local name = "HID data"
    local dataBlock = gb.data("")
    local data = ""
    if #trans.pkts > 1 and trans.pkts[2].isData then
        dataBlock = gb.data(trans.pkts[2].data)
        data = trans.pkts[2].data
    end
    xfer.infoData = data
    local f = gb.F_NAK
    local flagBlock = gb.block("NAK", "", gb.C.NAK)
    xfer.infoHtml = "<h1>HID Nak</h1>"

    if trans.state == "ACK" then
        if      desc.interfaceDesc.bInterfaceProtocol == 1 then
            name = "HID Key"
            local kid = -1
            function decode(t)
                local kc = 0
                local kd = "Trancated"
                local n = "Reserved"
                if #data > kid+1 then
                    kc = unpack("I1", data, kid+2)
                    if t == "key" then
                        kd = key2str(kc)
                        n = "Key" .. kid
                    elseif t == "mod" then
                        n = "Modifier"
                        kd = mod2str(kc)
                        n = html.expandBitFiled(kc, bf.key_modifier)
                    else
                        kd = ""
                    end
                    kc = fmt("0x%02X", kc)
                end
                kid = kid + 1
                if type(n) == "table" then
                    return n
                end
                return { n,  kc, kd  }
            end
            xfer.infoHtml = html.makeTable{
                title = "Maybe Boot Keyboard",
                header = {"Name", "Value", "Description"},
                decode("mod"),
                decode(),
                decode("key"),
                decode("key"),
                decode("key"),
                decode("key"),
                decode("key"),
                decode("key"),
            }
        elseif  desc.interfaceDesc.bInterfaceProtocol == 2 then
            name = "HID Mouse"
            local btnField = {"Button", "Truncated", ""}
            if #data > 0 then
                btnField = html.expandBitFiled( unpack("i1", data, 1), bf.mouse_button)
            end
            xfer.infoHtml = html.makeTable{
                title = "Maybe Boot Mouse",
                header = {"Name", "Value", "Description"},
                btnField,
                { "x",        #data>1 and unpack("i1", data, 2) or "Truncated", "" },
                { "y",        #data>2 and unpack("i1", data, 3) or "Truncated", "" },
            }
        else
            -- HID data, describe by report descriptor
            name = "HID Data"
            xfer.infoHtml = "<h1>HID data</h1>"
        end
        f = gb.F_ACK
        flagBlock = gb.block("success", "", gb.C.ACK)
    end
    local addr,ep = gb.str2addr(xfer.addrStr)
    local res = gb.ts(name, ts, gb.C.XFER) .. gb.addr(addr) .. gb.endp(ep) .. dataBlock .. flagBlock
             .. gb.F_XFER .. f .. xfer.addrStr
    trans.infoHtml = xfer.infoHtml
    updateGraph( res, xfer.id, xfer)
    -- HID alway done in a single transaction except in hybird mode
    return "done"
end

function cls.descriptorParser(data, offset, context)

    if unpack("I1", data, offset + 1) ~= usb_defs.HID_DESC then
        return nil
    end
    local tb = {}
    local desc = {}
    tb.title = "HID Descriptor"
    tb.header = {"Field", "Value", "Description"}
    desc.bLength =          unpack("I1", data, offset)
    desc.bDescriptorType =  unpack("I1", data, offset + 1)
    desc.bcdHID          =  unpack("I2", data, offset + 2)
    desc.bCountryCode    =  unpack("I1", data, offset + 4)
    desc.bNumDescriptors =  unpack("I1", data, offset + 5)

    tb[#tb+1] = { "bLength", desc.bLength, ""}
    tb[#tb+1] = { "bDescriptorType", desc.bDescriptorType, "" }
    tb[#tb+1] = { "bcdHID", fmt("0x%04X", desc.bcdHID), "" }
    tb[#tb+1] = { "bCountryCode", desc.bCountryCode, "" }
    tb[#tb+1] = { "bNumDescriptors", desc.bNumDescriptors, "" }

    for i=1, desc.bNumDescriptors do
        local t = unpack("I1", data, offset + 3 + i*3)
        desc["bDescriptorType" .. i] = t
        desc["wDescriptorLength" .. i] = unpack("I2", data, offset + 4 + i*3)
        if t == 0x22 then
            t = "Report Descriptor"
        elseif t == 0x23 then
            t = "Physical Descriptor"
        else
            t = "Unknwon"
        end
        tb[#tb+1] = { "bDescriptorType" .. i, desc["bDescriptorType" .. i], t}
        tb[#tb+1] = { "wDescriptorLength"..i, desc["wDescriptorLength" .. i], ""}
    end
    desc.html = html.makeTable(tb)
    return desc
end

cls.bInterfaceClass     = 3
cls.bInterfaceSubClass  = nil
cls.bInterfaceProtocol  = nil

package.loaded["usb_class_hid"] = cls
