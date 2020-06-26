-- usb_class_hub.lua

-- a typical class has these functions
-- cls.parseSetup(setup, context),  update setup.html, setup.name field in setup, and return it
-- cls.parseSetupData(setup, data, context)    return a html to describe the data
-- cls.transferHandler(xfer, tansaction, timestamp_string, updateGraph, parserContext)  return  one of nil , true, "done"
-- cls.descriptorParser(data, offset, context)   return a parsed descriptor
-- cls.getName(descriptor, context)              return a field name table
-- HUB class definition  usb_20.pdf  11.23, 11.24

local html = require("html")
local usb_defs = require("usb_defs")
local gb = require("graph_builder")
local setup_parser = require("usb_setup_parser")
require("usb_register_class")
local bf = _G.bf
local fmt = string.format
local unpack = string.unpack
local cls = {}
cls.name = "Hub class"

local CLEAR_TT_BUFFER = 8
local RESET_TT        = 9
local GET_TT_STATE    = 10
local STOP_TT         = 11

local function hub_feat_sel(wValue)
    if       wValue == 0 then return "C_HUB_LOCAL_POWER"
    elseif   wValue == 1 then return "C_HUB_OVER_CURRENT"
    end
    return "Unknown Feature selector"
end

local port_feature_list = {
    [0 ] = "PORT_CONNECTION"      ,
    [1 ] = "PORT_ENABLE"          ,
    [2 ] = "PORT_SUSPEND"         ,
    [3 ] = "PORT_OVER_CURRENT"    ,
    [4 ] = "PORT_RESET"           ,
    [8 ] = "PORT_POWER"           ,
    [9 ] = "PORT_LOW_SPEED"       ,
    [16] =  "C_PORT_CONNECTION"   ,
    [17] =  "C_PORT_ENABLE"       ,
    [18] =  "C_PORT_SUSPEND"      ,
    [19] =  "C_PORT_OVER_CURRENT" ,
    [20] =  "C_PORT_RESET"        ,
    [21] =  "PORT_TEST"           ,
    [22] =  "PORT_INDICATOR"      ,
}

local function port_feat_sel(value)
    return port_feature_list[value] or "Unknwon selector"
end

bf.wIndex_hub_port_feature = {
    name = "wIndex",
    bits = 16,
    {name = "[8..15] Selector", mask = 0xff00,},
    {name = "[0..7] Port", mask = 0x00ff},
}

port_feature_list.name = "[8..15] Selector"
port_feature_list.mask = 0xff00
bf.wIndex_hub_port_feature_test = {
    name = "wIndex",
    bits = 16,
    port_feature_list,
    {name = "[0..7] Port", mask = 0x00ff},
}

local function port_feat_index(wValue, wIndex)
    if port_feature_list[wValue] == "PORT_TEST" then
        return html.expandBitFiled(wIndex, bf.wIndex_hub_port_feature_test, true)
    else
        return html.expandBitFiled(wIndex, bf.wIndex_hub_port_feature, true)
    end
end

bf.hub_status = {
    name = "wHubStatus",
    bits = 16,
    { name = "Local Power Source", mask = 1<<0, [0] = "good",  [1] = "lost",    },
    { name = "Over-current", mask = 1<<1, [0] = "No Over-current",  [1] = "over-current condition exists", },
    { name = "Reserved", mask = 0xfffc },
}

bf.hub_change_status = {
    name = "wHubChange",
    bits = 16,
    { name = "Local Power Status Change", mask = 1<<0, [0] = "no change",  [1] = "changed",    },
    { name = "Over-Current Change", mask = 1<<1, [0] = "no change",  [1] = "changed", },
    { name = "Reserved", mask = 0xfffc },
}

local function hubStatus(data, context)
    data = data .. "\x00\x00\x00\x00"
    local s,cs = unpack("I2I2", data)
    return html.makeTable{
        title = "Hub Status & Change Status",
        header = {"Field", "Value", "Description"},
        html.expandBitFiled(s, bf.hub_status),
        html.expandBitFiled(cs, bf.hub_change_status),
    }
end

bf.port_status = {
    name = "wPortStatus",
    bits = 16,
    { name = "Connect",      mask = 1<<0, [0] = "disconnected",  [1] = "connected",    },
    { name = "Enabled",      mask = 1<<1, [0] = "Disabled",  [1] = "Enabled", },
    { name = "Suspend",      mask = 1<<2, [0] = "Not Suspend",  [1] = "Suspend/Resuming", },
    { name = "Over-current", mask = 1<<3, [0] = "No",  [1] = "Over-current occur", },
    { name = "Reset",        mask = 1<<4, [0] = "not asserted",  [1] = "Asserted", },
    { name = "Reserved",     mask = 0xe0                                           },
    { name = "Power",        mask = 1<<8, [0] = "Power off",  [1] = "Power on", },
    { name = "Low Speed",    mask = 1<<9, [0] = "Full/High Speed",  [1] = "Low Speed", },
    { name = "High Speed",   mask = 1<<10,[0] = "Full Speed",  [1] = "High Speed", },
    { name = "Test Mode",   mask = 1<<11,[0] = "Not Test Mode",  [1] = "Test Mode", },
    { name = "Indicator Control",   mask = 1<<12,[0] = "default",  [1] = "Software control", },
    { name = "Reserved",     mask = 0xe000},
}

bf.port_change_status = {
    name = "wPortChange",
    bits = 16,
    { name = "Connect",      mask = 1<<0, [0] = "No Change",  [1] = "Changed",    },
    { name = "Enabled",      mask = 1<<1, [0] = "No Change",  [1] = "Disable by Port_Error condition", },
    { name = "Suspend",      mask = 1<<2, [0] = "No Change",  [1] = "Resuming Complete", },
    { name = "Over-current", mask = 1<<3, [0] = "No Change",  [1] = "Over-current changed", },
    { name = "Reset",        mask = 1<<4, [0] = "No Change",  [1] = "Reset complete", },
    { name = "Reserved",     mask = 0xffe0                                          },
}

local function portStatus(data, context)
    data = data .. "\x00\x00\x00\x00"
    local s,cs = unpack("I2I2", data)
    return html.makeTable{
        title = "Port Status & Change Status",
        header = {"Field", "Value", "Description"},
        html.expandBitFiled(s, bf.port_status),
        html.expandBitFiled(cs, bf.port_change_status),
    }
end


bf.wValue_clear_tt_buffer = {
    name = "wValue",
    bits = 16,
    { name = "Endpoint Number",      mask = 0xf },
    { name = "Device Addr",          mask = 0x7f0 },
    { name = "Endpoint Type",        mask = 0x1800, [0] = "Control", [1] = "ISO", [2] = "Bulk", [3] = "Interrupt" },
    { name = "Reserved",             mask = 0x6000 },
    { name = "Direction",            mask = 0x8000, [0] = "OUT", [1] = "IN" },
}

function cls.parseSetup(setup, context)
    local wValue_field = nil
    local wIndex_field = {"wIndex",   fmt("%d",       setup.wIndex),    ""    }
    if setup.recip == "Device" and setup.type == "Class" then
        if       setup.bRequest == usb_defs.GET_DESCRIPTOR then
            setup.name = "Hub Get Desc"
            wValue_field = html.expandBitFiled(setup.wValue, bf.wValue_getDescriptor, true)
        elseif   setup.bRequest == usb_defs.SET_DESCRIPTOR then
            setup.name = "Hub Set Desc"
            wValue_field = html.expandBitFiled(setup.wValue, bf.wValue_getDescriptor, true)
        elseif   setup.bRequest == usb_defs.CLEAR_FEATURE then
            setup.name = "Hub Clear Feat"
            wValue_field = {"wValue",   fmt("%d",       setup.wValue),    hub_feat_sel(setup.wValue)    }
        elseif   setup.bRequest == usb_defs.SET_FEATURE then
            setup.name = "Hub Set Feat"
            wValue_field = {"wValue",   fmt("%d",       setup.wValue),    hub_feat_sel(setup.wValue)    }
        elseif   setup.bRequest == usb_defs.GET_STATUS then
            setup.name = "Hub Get Status"
            wValue_field = {"wValue",   fmt("%d",       setup.wValue),    ""   }
        else
            return nil
        end
    elseif setup.recip == "Other" and setup.type == "Class" then
        -- port setup
        wValue_field = {"wValue",   fmt("%d",       setup.wValue),    ""   }
        if setup.bRequest == usb_defs.GET_STATUS then
            setup.name = "Port Get Status"
            wIndex_field [3] = "Port"
        elseif setup.bRequest == usb_defs.CLEAR_FEATURE then
            setup.name = "Port Clear Feat"
            wValue_field[3] = port_feat_sel(setup.wValue)
            wIndex_field = port_feat_index(setup.wValue, setup.wIndex)
        elseif setup.bRequest == usb_defs.SET_FEATURE then
            setup.name = "Port Set Feat"
            wValue_field[3] = port_feat_sel(setup.wValue)
            wIndex_field = port_feat_index(setup.wValue, setup.wIndex)
        elseif setup.bRequest == CLEAR_TT_BUFFER then
            setup.name = "Hub Clear TT"
            wValue_field = html.expandBitFiled(setup.wValue, bf.wValue_clear_tt_buffer)
            wIndex_field [3] = "TT Port"
        elseif setup.bRequest == RESET_TT then
            setup.name = "Hub Reset TT"
            wIndex_field [3] = "Port"
        elseif setup.bRequest == GET_TT_STATE then
            setup.name = "Hub Get TT State"
            wValue_field [3] = "TT Flags"
            wIndex_field [3] = "Port"
        elseif setup.bRequest == STOP_TT then
            setup.name = "Hub Stop TT"
            wIndex_field [3] = "Port"
        else
            return nil
        end
    end
    setup.html = html.makeTable{
        title = setup.name,
        header = {"Field", "Value", "Description"},
        html.expandBitFiled(setup.bmRequest, bf.bmRequest),
        {"bRequest", fmt("%d",       setup.bRequest),  usb_defs.stdRequestName(setup.bRequest)  },
        wValue_field,
        wIndex_field,
        {"wLength",  fmt("%d",       setup.wLength),   ""    },
    }
    return setup
end

function cls.parseSetupData(setup, data, context)
    if setup.recip == "Device" and setup.type == "Class" then
        if      setup.bRequest == usb_defs.GET_DESCRIPTOR or setup.bRequest == usb_defs.SET_DESCRIPTOR then
            local r = cls.descriptorParser(data, 1, context)
            if r then return r.html end
        elseif  setup.bRequest == usb_defs.GET_STATUS then
            return hubStatus(data, context)
        end
    elseif setup.recip == "Other" and setup.type == "Class" then
        if  setup.bRequest == usb_defs.GET_STATUS then
            return portStatus(data, context)
        end
    end
    return nil
end


_G.bf.hub_wHubCharacteristics = {
    name = "wHubCharacteristics",
    bits = 16,

    {name = "Logical Power Switching Mode", mask = 0x0003, {[0] = "Global", [1] = "Individual", [2] = "Reserved.", [3] = "Reserved."}},
    {name = "Compound Device", mask = 0x0004, [0] = "not part of a compound device", [1] = "part of a compound device"},
    {name = "Over-current Protection Mode", mask = 0x0018, [0] = "Global", [1] = "Individual", [2] = "No Protection", [2] = "No Protection"},
    {name = "TT Think Time", mask = 0x0060, [0] = "8 FS bit", [1] = "16 FS bit", [2] = "24 FS bit", [3] = "32 FS bit"},
    {name = "Port Indicators", mask = 0x0080, [0] = "not supported", [1] = "supported"},

}

function cls.descriptorParser(data, offset, context)

    if unpack("I1", data, offset + 1) ~= usb_defs.HUB_DESC then
        return nil
    end
    local tb = {}
    local desc = {}
    tb.title = "Hub Descriptor"
    tb.header = {"Field", "Value", "Description"}
    desc.bLength =          unpack("I1", data, offset)
    desc.bDescriptorType =  unpack("I1", data, offset + 1)
    desc.bNbrPorts       =  unpack("I1", data, offset + 2)
    desc.wHubCharacteristics =  unpack("I2", data, offset + 3)
    desc.bPwrOn2PwrGood      =  unpack("I1", data, offset + 5)
    desc.bHubContrCurrent    =  unpack("I1", data, offset + 6)


    tb[#tb+1] = { "bLength", desc.bLength, ""}
    tb[#tb+1] = { "bDescriptorType", desc.bDescriptorType, "" }
    tb[#tb+1] = { "bNbrPorts", desc.bNbrPorts, "" }
    tb[#tb+1] = html.expandBitFiled(desc.wHubCharacteristics, bf.hub_wHubCharacteristics)
    tb[#tb+1] = { "bPwrOn2PwrGood", desc.bPwrOn2PwrGood, "unit 2ms" }
    tb[#tb+1] = { "bHubContrCurrent", desc.bHubContrCurrent, "unit 1mA" }

    offset = offset + 7
    local cost = math.modf((desc.bNbrPorts + 1 + 7) / 8)
    if #data < offset + cost - 1 then
        tb[#tb+1] = {"DeviceRemovable", "<Truncated>", ""}
    else
        local ss = ""
        for i=offset,offset + cost-1 do
            local t = unpack("I1", data, i)
            ss = fmt("%02x", t) .. ss
        end
        tb[#tb+1] = {"DeviceRemovable", "0x"..ss, ""}
        
    end
    offset = offset + cost

    if #data < offset + cost - 1 then
        tb[#tb+1] = {"PortPwrCtrlMask", "<Truncated>", ""}
    else
        local ss = ""
        for i=offset,offset + cost-1 do
            local t = unpack("I1", data, i)
            ss = fmt("%02x", t) .. ss
        end
        tb[#tb+1] = {"PortPwrCtrlMask", "0x"..ss, ""} 
    end

    desc.html = html.makeTable(tb)
    return desc
end



function cls.transferHandler(xfer, trans, ts, updateGraph, context)
    local desc = context:getEpDesc()
    local name = "Hub Notify Data"
    local dataBlock = gb.data("")
    local data = ""
    if trans.data then
        dataBlock = gb.data(trans.data)
        data = trans.data
    end
    xfer.infoData = data
    local f = gb.F_NAK
    local flagBlock = gb.block("NAK", "", gb.C.NAK)
    xfer.infoHtml = "<h1>Hub Nak</h1>"

    if trans.state == "ACK" then
        name = "Hub Notify Data"
        xfer.infoHtml = "<h1>Hub Notify data</h1>"
        f = gb.F_ACK
        flagBlock = gb.block("success", "", gb.C.ACK)
    end
    local addr,ep = gb.str2addr(xfer.addrStr)
    local res = gb.ts(name, ts, gb.C.XFER, xfer.speed) .. gb.addr(addr) .. gb.endp(ep) .. dataBlock .. flagBlock
             .. gb.F_XFER .. f .. xfer.addrStr
    trans.infoHtml = xfer.infoHtml
    updateGraph( res, xfer.id, xfer)
    return "done"
end


cls.bInterfaceClass     = 0x09
cls.bInterfaceSubClass  = 0x00
cls.bInterfaceProtocol  = nil

function cls.getName(desc, context)
    local proto = "Hub Protocol"
    if desc.bInterfaceProtocol == 1 then
        proto = "Single TT Protocol"
    elseif desc.bInterfaceProtocol == 2 then
            proto = "Multiple TT Protocol"
    end
    return {
        bInterfaceClass = "Hub Class",
        bInterfaceSubClass = "Hub Sub Class",
        bInterfaceProtocol = proto,
    }
end
register_class_handler(cls)
package.loaded["usb_class_hub"] = cls
