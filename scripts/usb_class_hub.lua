-- usb_class_hub.lua

-- a typical class has these functions
-- cls.parse_setup(setup, context),  update setup.html, setup.name field in setup, and return it
-- cls.parse_setup_data(setup, data, context)    return a html to describe the data
-- cls.transferHandler(xfer, tansaction, timestamp_string, updateGraph, parserContext)  return  one of nil , true, "done"
-- cls.descriptor_parser(data, offset, context)   return a parsed descriptor
-- cls.get_name(descriptor, context)              return a field name table
-- HUB class definition  usb_20.pdf  11.23, 11.24

local html = require("html")
local macro_defs = require("macro_defs")
require("usb_register_class")
local fmt = string.format
local unpack = string.unpack
local cls = {}
cls.name = "HUB Notify Data"

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

_G.hub_port_feature_selection = port_feature_list

local field_wIndex_port_feature = html.create_field([[
    strcut{
        // wIndex
        uint16_t port:8;
        uint16_t selection:8; // _G.hub_port_feature_selection
    }
]])

local struct_hub_status = html.create_struct([[
    struct{
        // wHubStatus
        uint16_t LocalPowerSource:1; // {[0] = "good",  [1] = "lost"    }
        uint16_t OverCurrent:1;      // {[0] = "No Over-current",  [1] = "over-current condition exists" }
        uint16_t Reserved:14;
        // wHubChange
        uint16_t LocalPowerSourceChg:1; //  {[0] = "no change",  [1] = "changed"}
        uint16_t OverCurrentChg:1;      //  {[0] = "no change",  [1] = "changed"}
        uint16_t Reserved:14;
    }
]])

local function hubStatus(data, context)
    data = data .. "\x00\x00\x00\x00"
    local s,cs = unpack("I2I2", data)
    return struct_hub_status:build(data, "Hub Status & Change Status").html
end

local struct_port_status = html.create_struct([[
    struct{
        // wPortStatus
        uint16_t  Connect:1;          // {[0] = "disconnected",  [1] = "connected" }
        uint16_t  Enabled:1;          // {[0] = "Disabled",  [1] = "Enabled", }
        uint16_t  Suspend:1;          // {[0] = "Not Suspend",  [1] = "Suspend/Resuming", }
        uint16_t  OverCurrent:1;      // {[0] = "No",  [1] = "Over-current occur", }
        uint16_t  Reset:1;            // {[0] = "not asserted",  [1] = "Asserted", }
        uint16_t  Reserved:1;
        uint16_t  Power:1;            // {[0] = "Power off",  [1] = "Power on", }
        uint16_t  LowSpeed:1;         // {[0] = "Full/High Speed",  [1] = "Low Speed", }
        uint16_t  HighSpeed:1;        // {[0] = "Full Speed",  [1] = "High Speed", }
        uint16_t  TestMode:1;         // {[0] = "Not Test Mode",  [1] = "Test Mode", }
        uint16_t  IndicatorCtrl:1;    // {[0] = "default",  [1] = "Software control", }
        uint16_t  Reserved:5;
        // wPortChange
        uint16_t  ConnectChg:1;       // {[0] = "No Change",  [1] = "Changed",    }
        uint16_t  EnabledChg:1;       // {[0] = "No Change",  [1] = "Disable by Port_Error condition", }
        uint16_t  SuspendChg:1;       // {[0] = "No Change",  [1] = "Resuming Complete", }
        uint16_t  OverCurrentChg:1;   // {[0] = "No Change",  [1] = "Over-current changed", }
        uint16_t  ResetChg:1;         // {[0] = "No Change",  [1] = "Reset complete", }
        uint16_t  Reserved:13;
    }
]])

local function portStatus(data, context)
    data = data .. "\x00\x00\x00\x00"
    local s,cs = unpack("I2I2", data)
    return struct_port_status:build(data, "Port Status & Change Status").html
end

local field_clear_tt = html.create_field([[
    struct{
        // wIndex
        uint16_t EndpointNumber:4;
        uint16_t DeviceAddr:7;
        uint16_t EndpointType:2;   // {[0] = "Control", [1] = "ISO", [2] = "Bulk", [3] = "Interrupt" }
        uint16_t Reserved:2;
        uint16_t Direction:1;      // {[0] = "OUT", [1] = "IN" }
    }
]])

local hub_render = {
    [macro_defs.GET_DESCRIPTOR] = {"Hub Get Desc" },
    [macro_defs.SET_DESCRIPTOR] = {"Hub Set Desc" },
    [macro_defs.CLEAR_FEATURE]  = {"Hub Clear Feat", hub_feat_sel },
    [macro_defs.SET_FEATURE]    = {"Hub Set Feat", hub_feat_sel },
    [macro_defs.GET_STATUS]     = {"Hub Get Status"},
}

local port_render = {
    [macro_defs.CLEAR_FEATURE]  = {"Port Clear Feat", port_feat_sel, field_wIndex_port_feature},
    [macro_defs.SET_FEATURE]    = {"Port Set Feat", port_feat_sel, field_wIndex_port_feature},
    [macro_defs.GET_STATUS]     = {"Port Get Status", nil,         "port" },
    [CLEAR_TT_BUFFER]         = {"Hub Clear TT", field_clear_tt},
    [RESET_TT]                = {"Hub Reset TT", nil, "Port"},
    [GET_TT_STATE]            = {"Hub Get TT State", "TT Flags", "Port"},
    [STOP_TT]                 = {"Hub Stop TT", nil, "Port"},
}

function cls.parse_setup(setup, context)
    if setup.recip == "Device" and setup.type == "Class" then
        setup.name = hub_render[setup.bRequest] and hub_render[setup.bRequest][1]
        setup.render.wValue = hub_render[setup.bRequest] and hub_render[setup.bRequest][2]
        setup.render.wIndex = hub_render[setup.bRequest] and hub_render[setup.bRequest][3]
    elseif setup.recip == "Other" and setup.type == "Class" then
        setup.name = port_render[setup.bRequest] and port_render[setup.bRequest][1]
        setup.render.wValue = port_render[setup.bRequest] and port_render[setup.bRequest][2]
        setup.render.wIndex = port_render[setup.bRequest] and port_render[setup.bRequest][3]
    else
        return
    end
    setup.render.bRequest = setup.name
    setup.render.title = "HUB Requset" .. (setup.name or "")
    setup.title = "HUB Requset"
end

function cls.parse_setup_data(setup, data, context)
    if setup.recip == "Device" and setup.type == "Class" then
        if      setup.bRequest == macro_defs.GET_DESCRIPTOR or setup.bRequest == macro_defs.SET_DESCRIPTOR then
            local r = cls.descriptor_parser(data, 1, context)
            if r then return r.html end
        elseif  setup.bRequest == macro_defs.GET_STATUS then
            return hubStatus(data, context)
        end
    elseif setup.recip == "Other" and setup.type == "Class" then
        if  setup.bRequest == macro_defs.GET_STATUS then
            return portStatus(data, context)
        end
    end
    return nil
end

local struct_hub_desc = html.create_struct([[
    struct{
        uint8_t bLength;
        uint8_t bDescriptorType;              // _G.get_descriptor_name
        uint8_t bNbrPorts;
        // wHubCharacteristics
        uint16_t LogicalPowerSwitchingMode:2; // {[0] = "Global", [1] = "Individual", [2] = "Reserved.", [3] = "Reserved."}
        uint16_t Compound Device:1;           // {[0] = "not part of a compound device", [1] = "part of a compound device"}
        uint16_t OverCurrentProtMode:2;       // {[0] = "Global", [1] = "Individual", [2] = "No Protection", [2] = "No Protection"}
        uint16_t TT_ThinkTime:2;              // {[0] = "8 FS bit", [1] = "16 FS bit", [2] = "24 FS bit", [3] = "32 FS bit"}
        uint16_t PortIndicators:1;            // {[0] = "not supported", [1] = "supported"}
        uint16_t reserved:8;
        uint8_t  bPwrOn2PwrGood;              // unit 2ms
        uint8_t  bHubContrCurrent;            // unit 1mA
        uint8_t  DeviceRemovable;
        uint8_t  PortPwrCtrlMask;             
    }
]])

function cls.descriptor_parser(data, offset, context)
    if unpack("I1", data, offset + 1) ~= macro_defs.HUB_DESC then
        return nil
    end
    return struct_hub_desc:build(data:sub(offset), "Hub Descriptor")
end

cls.bInterfaceClass     = 0x09
cls.bInterfaceSubClass  = 0x00
cls.bInterfaceProtocol  = nil
cls.endpoints = { EP_IN("Hub Notify") }

function cls.on_transaction(self, param, data, needDetail, forceBegin)
    local addr, ep, pid, ack = param:byte(1), param:byte(2), param:byte(3), param:byte(4)
    if pid ~= macro_defs.PID_IN then
        return macro_defs.RES_NONE
    end
    if needDetail then
        return macro_defs.RES_BEGIN_END, self.upv.make_xact_res("Hub Notify"), self.upv.make_xfer_res({
            title = "Hub Notify Data",
            name  = "Notify Data",
            desc  = "Notify Data",
            status = "success",
            infoHtml = "<h1>Hub Notify data</h1>",
            data = data,
        })
    end
    return macro_defs.RES_BEGIN_END
end

function cls.get_name(desc, context)
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
