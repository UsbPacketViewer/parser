-- usb_device_ftdi.lua

local html = require("html")
local macro_defs = require("macro_defs")
require("usb_setup_parser")
require("usb_register_class")

local fmt = string.format
local unpack = string.unpack
local device = {}
device.name = "FTDI FT232"

local FTDI_RESET             = 0x00
local FTDI_MODEM_CTRL        = 0x01
local FTDI_SET_FLOW_CTRL     = 0x02
local FTDI_SET_BAUDRATE      = 0x03
local FTDI_SET_LN_CODE       = 0x04
local FTDI_POLL_STATUS       = 0x05
local FTDI_SET_EVENT_CHAR    = 0x06
local FTDI_SET_ERROR_CHAR    = 0x07
local FTDI_SET_LATENCY_TIMER = 0x09
local FTDI_GET_LATENCY_TIMER = 0x0A
local FTDI_SET_BITMODE       = 0x0B
local FTDI_READ_PINS         = 0x0C
local FTDI_READ_EEPROM       = 0x90
local FTDI_WRITE_EEPROM      = 0x91
local FTDI_ERASE_EEPROM      = 0x92

local ftdi_action = {
    [FTDI_RESET]             = {"Reset"},
    [FTDI_MODEM_CTRL]        = {"Modem Ctrl", "", ""},
    [FTDI_SET_FLOW_CTRL]     = {"Set Flow Ctrl", "", ""},
    [FTDI_SET_BAUDRATE]      = {"Set Baudrate", "low part", ""},
    [FTDI_SET_LN_CODE]       = {"Set Ln Code", "", ""},
    [FTDI_POLL_STATUS]       = {"Poll status", "", ""},
    [FTDI_SET_EVENT_CHAR]    = {"Set evt char"},
    [FTDI_SET_ERROR_CHAR]    = {"Set error char"},
    [FTDI_SET_LATENCY_TIMER] = {"Set Latence", "Latence"},
    [FTDI_GET_LATENCY_TIMER] = {"Get Latence", "", "", "Latence"},
    [FTDI_SET_BITMODE]       = {"Set bit mode"},
    [FTDI_READ_PINS]         = {"Read Pins", "", "", "Pin Data"},

    [FTDI_READ_EEPROM]       = {"Read EEPROM", "", "EE Location", "EEPROM DATA" },
    [FTDI_WRITE_EEPROM]      = {"Write EEPROM", "", "EE Location", "EEPROM DATA" },
    [FTDI_ERASE_EEPROM]      = {"Erase EEPROM", "", "" },
}

local wValue_render = {
    [FTDI_SET_LN_CODE] = html.create_field([[
    struct {
        // wValue
        uint16_t  data_bits:8;  // data bits
        uint16_t  parity:3;     // {[0] = "None", [1] = "Odd", [2] = "Even", [3] = "Mark" , [4] = "Space"}
        uint16_t  stop_bits:3;  // {[0] = "1 bits", [1] = "1.5 bits", [2] = "2 bits"}
        uint16_t  break:1;      // {[0] = "break off", [1] = "break on"}
        uint16_t  reserved:1;
    }
]]),
    [FTDI_MODEM_CTRL] = html.create_field([[
    struct {
        // wValue
        uint16_t  DTR:1;   // {[0] = "low", [1] = "high"}
        uint16_t  RTS:1;   // {[0] = "low", [1] = "high"}
        uint16_t  reserved:6;
        uint16_t  DTR_MASK:1;
        uint16_t  RTS_MASK:1;
        uint16_t  reserved:6;
    }
]]),
    [FTDI_SET_FLOW_CTRL] = html.create_field([[
    struct {
        // wValue
        uint16_t  reserved:8;
        uint16_t  RTS_CTS:1;   // {[0] = "off", [1] = "on"}
        uint16_t  DTR_DST:1;   // {[0] = "off", [1] = "on"}
        uint16_t  xOn_xOff:1;  // {[0] = "off", [1] = "on"}
        uint16_t  reserved:5;
    }
]]),
    [FTDI_SET_EVENT_CHAR] = html.create_field([[
    struct {
        // wValue
        uint16_t  event_char:8;
        uint16_t  enable:1;  // {[0] = "disable", [1] = "enable"}
        uint16_t  reserved:7;
    }
]]),
    [FTDI_SET_ERROR_CHAR] = html.create_field([[
    struct {
        // wValue
        uint16_t  error_char:8;
        uint16_t  enable:1;  // {[0] = "disable", [1] = "enable"}
        uint16_t  reserved:7;
    }
]]),
    [FTDI_SET_BITMODE] = html.create_field([[
    struct {
        // wValue
        uint16_t  mask:8;
        uint16_t  RESET:1;
        uint16_t  BITBANG:1;
        uint16_t  MPSSE:1;
        uint16_t  MCU:1;
        uint16_t  OPTO:1;
        uint16_t  CBUS:1;
        uint16_t  SYNCFF:1;
        uint16_t  FT1284:1;
    }
]])
}

local wIndex_render = {
    [FTDI_SET_BAUDRATE] = html.create_field([[
    struct {
        // wValue
        uint16_t  index:8;
        uint16_t  baudrate:8;  // high part
    }
]])
}

local reset_value_desc = {
    [0] =  "Reset",
    [1] = "Purge Rx",
    [1] = "Purge Tx",
}

local struct_ftdi_status_header = html.create_struct([[
    struct {
        // wValue
        uint16_t  reserved:4;
        uint16_t  CTS:1;
        uint16_t  DTS:1;
        uint16_t  RI:1;
        uint16_t  RLSD:1;
        uint16_t  DataReady:1;
        uint16_t  Overrun:1;
        uint16_t  ParityError:1;
        uint16_t  FrameError:1;
        uint16_t  BreakInt:1;
        uint16_t  TransmitHolding:1;
        uint16_t  TransmitEmpty:1;
        uint16_t  RxFifoError:1;
    }
]])

function device.parse_setup(setup, context)
    if setup.type ~= "Vendor" then
        return
    end
    local action = ftdi_action[setup.bRequest]
    local bRequest_desc = "FTDI Unknown"
    local wValue_desc = nil
    local wIndex_desc = nil
    if action then
        bRequest_desc = action[1] or bRequest_desc
        wValue_desc = action[2] or wValue_desc
        wIndex_desc = action[3] or wIndex_desc
    end
    if setup.bRequest == FTDI_READ_EEPROM or setup.bRequest == FTDI_WRITE_EEPROM then
        bRequest_desc = bRequest_desc .. ":".. setup.wIndex
    end
    setup.title = "FTDI Request"
    setup.name = bRequest_desc
    setup.render.title  = "FTDI " .. bRequest_desc
    setup.render.bRequest = bRequest_desc
    setup.render.wValue = wValue_render[setup.bRequest] or wValue_desc
    setup.render.wIndex = wIndex_render[setup.bRequest] or wIndex_desc
end

local function make_ftdi_status(data)
    local v = 0
    if #data > 1 then
        v = unpack("I2", data)
    end
    return struct_ftdi_status_header:build(data, "FTDI Status").html
end

function device.parse_setup_data(setup, data, context)
    if setup.type ~= "Vendor" then
        return nil
    end
    if setup.bRequest == FTDI_POLL_STATUS then
        return make_ftdi_status(data)
    end
    local action = ftdi_action[setup.bRequest]
    local desc = "Unknown Data"
    if action then
        desc = action[4] or desc
    end
    return "<h1>"..desc.."</h1>"
end

local cls = {}
cls.name = "FTDI Data"
cls.endpoints = { EP_IN("Incoming Data"), EP_OUT("Outgoing Data") }

function cls.on_transaction(self, param, data, needDetail, forceBegin)
    local addr, ep, pid, ack = param:byte(1), param:byte(2), param:byte(3), param:byte(4)
    self.addr = addr
    if ack ~= macro_defs.PID_ACK then
        return macro_defs.RES_NONE
    end
    local context = self:get_context(needDetail, pid)
    context.data = context.data or ""
    if forceBegin then
        context.data = ""
    end
    local endMark    = self.upv:is_short_packet(addr, ep, data) and macro_defs.RES_END or macro_defs.RES_NONE
    local begindMark = #context.data == 0 and macro_defs.RES_BEGIN or macro_defs.RES_NONE
    context.data = context.data .. data
    if #context.data >= 4096 then
        endMark = macro_defs.RES_END
    end
    local res = endMark | begindMark
    if res == macro_defs.RES_NONE then res = macro_defs.RES_MORE end

    if needDetail then
        context.status = "incomp"
        context.title = "FTDI Data Xfer"
        context.name = "FTDI Data"
        context.desc = "FTDI Data"
        context.infoHtml = ""
        if pid == macro_defs.PID_IN and #context.data > 1 then
            context.infoHtml = make_ftdi_status(context.data)
        end
        if endMark ~= macro_defs.RES_NONE then
            context.status = "success"
        end
        local xfer_res = self.upv.make_xfer_res(context)
        if endMark ~= macro_defs.RES_NONE then
            context.data = ""
        end
        return res, self.upv.make_xact_res("FTDI Data", context.infoHtml, data), xfer_res
    end
    if endMark ~= macro_defs.RES_NONE then
        context.data = ""
    end
    return res
end

function device.get_interface_handler(self, itf_number)
    return cls
end

register_device_handler(device, 0x0403, 0x6001)

register_class_handler(cls)

package.loaded["usb_device_ftdi"] = device
