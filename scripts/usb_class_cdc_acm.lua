-- usb_class_cdc_acm.lua

-- a typical class has these functions
-- cls.parse_setup(setup, context),  update setup.html, setup.name field in setup, and return it
-- cls.parse_setup_data(setup, data, context)    return a html to describe the data
-- cls.on_transaction(self, param, data, needDetail, forceBegin)  return macro_defs.RES_xxx
-- cls.descriptor_parser(data, offset, context)   return a parsed descriptor
-- cls.get_name(descriptor, context)              return a field name table
-- HID class definition  https://www.usb.org/sites/default/files/CDC1.2_WMC1.1_012011.zip

local html = require("html")
local macro_defs = require("macro_defs")
local rndis = require("decoder_rndis")
local setup_parser = require("usb_setup_parser")
require("usb_register_class")

local fmt = string.format
local unpack = string.unpack
local cls = {}
cls.name = "CDC Notify Data"

local field_cdc_control_line_state = html.create_field([[
    struct{
        //wValue
        uint16_t  DTR:1;
        uint16_t  RTS:1;
        uint16_t  reserved:14;
    }
]])

local req2str = {
    [0x00] = "SEND_ENCAPSULATED_COMMAND",
    [0x01] = "GET_ENCAPSULATED_RESPONSE",
    [0x02] = "SET_COMM_FEATURE",
    [0x03] = "GET_COMM_FEATURE",
    [0x04] = "CLEAR_COMM_FEATURE",
    [0x20] = "SET_LINE_CODING",
    [0x21] = "GET_LINE_CODING",
    [0x22] = "SET_CONTROL_LINE_STATE",
    [0x23] = "SEND_BREAK",
}

local shortName = {
    SEND_ENCAPSULATED_COMMAND = "Send Enc Cmd",
    GET_ENCAPSULATED_RESPONSE = "Get Enc Resp",
    SET_COMM_FEATURE = "Set Comm Feat",
    GET_COMM_FEATURE = "Get Comm Feat",
    CLEAR_COMM_FEATURE = "Clr Comm Feat",
    SET_LINE_CODING = "Set Ln Coding",
    GET_LINE_CODING = "Get Ln Coding",
    SET_CONTROL_LINE_STATE = "Set Ctrl Ln",
    SEND_BREAK = "Send break",
}

local CDC_RING_DETECT                  = 0x09
local CDC_SERIAL_STATE                 = 0x20

local struct_serial_state = html.create_struct([[
    typedef struct _tusb_cdc_line_state
    {
        uint16_t CDC:1;
        uint16_t DSR:1;
        uint16_t Break:1;
        uint16_t Ring:1;
        uint16_t FramingError:1;
        uint16_t ParityError:1;
        uint16_t Overrun:1;
        uint16_t revserved: 9;
    }tusb_cdc_line_state_t;
]])

local function cdc_parse_notify_data(self, data)
    if #data > 8 then
        self.is_cdc_data = true
        local setup = setup_parser.parse_setup(data:sub(1,8), self)
        self.is_cdc_data = false
        if setup.bRequest == CDC_SERIAL_STATE then
            setup.html = setup.html .. struct_serial_state:build(data:sub(9), "Serial State").html
            return setup
        end
        return nil
    end
end

function cls.parse_setup(setup, context)
    if setup.recip ~= "Interface" or setup.type ~= "Class" then
        return
    end
    local bRequest_desc = req2str[setup.bRequest] or "CDC Unknown Req"

    local wValueField = nil
    if context.is_cdc_data then
        if setup.bRequest == CDC_SERIAL_STATE then
            bRequest_desc = "SERIAL_STATE"
        end
    else
        if bRequest_desc == "SET_CONTROL_LINE_STATE"then
            wValueField = field_cdc_control_line_state
        end
    end
    setup.name = shortName[bRequest_desc] or "CDC Unknown"
    setup.title = "CDC Request"
    setup.render.bRequest = bRequest_desc
    setup.render.wValue = wValueField
    setup.render.wIndex = "Interface"
    setup.render.title = "CDC Request " .. bRequest_desc
end

local struct_line_coding = html.create_struct([[
    struct{
        uint32_t baudrate;
        uint8_t  stopbits;
        uint8_t  parity;
        uint8_t  databits;
    };
]], {
    baudrate = {format = "dec"},
    databits = {format = "dec"},
    stopbits = {[0] = "1 Stop", [1] = "1.5 Stop", [2] = "2 Stop"},
    parity =   {[0] = "None", [1] = "ODD", [2] = "EVEN", [3] = "MARK", [4] = "SPACE"},
})

function cls.parse_setup_data(setup, data, context)
    local s = req2str[setup.bRequest]
    if s then 
        if s == "SET_LINE_CODING" or s == "GET_LINE_CODING" then
            local r = struct_line_coding:build(data, "Line Coding")
            return r.html
        elseif s == "SEND_ENCAPSULATED_COMMAND" then
            return rndis.parseCommand(data, context)
        elseif s == "GET_ENCAPSULATED_RESPONSE" then
            return rndis.parseResponse(data, context)
        end
    end
    return nil
end

local function rndis_on_transaction(self, param, data, needDetail, forceBegin)
    local addr, ep, pid, ack = param:byte(1), param:byte(2), param:byte(3), param:byte(4)
    if ack ~= macro_defs.PID_ACK then
        return macro_defs.RES_NONE
    end
    local context = self:get_context(needDetail, pid)
    self.addr = addr
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
        context.title = "CDC Rndis DATA"
        context.name = "CDC DATA"
        context.desc = "Rndis DATA"
        context.infoHtml = ""
        if endMark == macro_defs.RES_END then
            context.infoHtml  =  rndis.parse_data(context.data, context)
            context.status = "success"
        end
        local xfer_res = self.upv.make_xfer_res(context)
        if endMark == macro_defs.RES_END then
            context.data = ""
        end
        return res, self.upv.make_xact_res("CDC Rndis Data", "", data), xfer_res
    end
    if endMark ~= 0 then
        context.data = ""
    end
    return res
end

local function data_on_transaction(self, param, data, needDetail, forceBegin)
    local addr, ep, pid, ack = param:byte(1), param:byte(2), param:byte(3), param:byte(4)
    if ack ~= macro_defs.PID_ACK then
        return macro_defs.RES_NONE
    end
    self.addr = addr
    if needDetail then
        local context = {}
        context.data = data
        context.status = "success"
        context.title = "CDC RAW DATA"
        context.name = "CDC DATA"
        context.desc = "CDC DATA"
        context.infoHtml = "Raw Data"
        return macro_defs.RES_BEGIN_END, self.upv.make_xact_res("CDC Raw Data", "Raw Data", data), self.upv.make_xfer_res(context)
    end
    return macro_defs.RES_BEGIN_END
end

function cls.on_transaction(self, param, data, needDetail, forceBegin)
    local addr, ep, pid, ack = param:byte(1), param:byte(2), param:byte(3), param:byte(4)
    if pid ~= macro_defs.PID_IN then
        return macro_defs.RES_NONE
    end
    if ack ~= macro_defs.PID_ACK then
        return macro_defs.RES_NONE
    end
    if needDetail then
        local status = "success"
        local info = cdc_parse_notify_data(self, data)
        local html = ""
        if not info then
            status = "error"
            html = "Wrong line status data"
        else
            html = info.html
        end
        return macro_defs.RES_BEGIN_END, self.upv.make_xact_res("Hub Notify", html, data), self.upv.make_xfer_res({
            title = "CDC Line status",
            name  = "CDC Notify",
            desc  = "Line Sts",
            status = status,
            infoHtml = html,
            data = data,
        })
    end
    return macro_defs.RES_BEGIN_END
end

-- 0x00 -- Header Functional Descriptor, which marks the beginning of the concatenated set of functional descriptors for the interface.
-- 0x01 -- Call Management Functional Descriptor.
-- 0x02 -- Abstract Control Management Functional Descriptor.
-- 0x03 -- Direct Line Management Functional Descriptor.
-- 0x04 -- Telephone Ringer Functional Descriptor.
-- 0x05 -- Telephone Call and Line State Reporting Capabilities Functional Descriptor.
-- 0x06 -- Union Functional Descriptor

_G.cdc_interface_desc_type = {
    [0x00] = "Header",
    [0x01] = "Call Management",
    [0x02] = "Abstract Control Management",
    [0x03] = "Direct Line Management",
    [0x04] = "Telephone Ringer",
    [0x05] = "Telephone Call and Line State Reporting Capabilities",
    [0x06] = "Union",
}

local function build_desc(name, info)
    local builder = html.create_struct(info)
    return function(data, offset, context)
        return builder:build(data:sub(offset), name)
    end
end

local cdc_desc = {
    [0x00] = build_desc("Header Functional Descriptor", [[
        struct{
            uint8_t   bLength;
            uint8_t   bDescriptorType;      // CS_INTERFACE
            uint8_t   bDescriptorSubtype;   // _G.cdc_interface_desc_type
            uint16_t  bcdCDC;
        }
    ]]),
    [0x01] = build_desc("Call Management Functional Descriptor", [[
        struct{
            uint8_t   bLength;
            uint8_t   bDescriptorType;      // CS_INTERFACE
            uint8_t   bDescriptorSubtype;   // _G.cdc_interface_desc_type
            uint8_t   bmCapabilities;
            uint8_t   bDataInterface;
        }
    ]]),
    [0x02] = build_desc("Abstract Control Management Functional Descriptor", [[
        struct{
            uint8_t   bLength;
            uint8_t   bDescriptorType;      // CS_INTERFACE
            uint8_t   bDescriptorSubtype;   // _G.cdc_interface_desc_type
            // bmCapabilities
            uint8_t   COMM:1;
            uint8_t   LINE:1;
            uint8_t   BREAK:1;
            uint8_t   NETWORK:1;
            uint8_t   reserved:4;
        }
    ]]),
    [0x06] = build_desc("Union Functional Descriptor", [[
        struct{
            uint8_t   bLength;
            uint8_t   bDescriptorType;      // CS_INTERFACE
            uint8_t   bDescriptorSubtype;   // _G.cdc_interface_desc_type
            uint8_t   bMasterInterface;
            uint8_t   bSlaveInterface0;
        }
    ]]),
}

function cls.descriptor_parser(data, offset, context)
    if unpack("I1", data, offset + 1) ~= macro_defs.CS_INTERFACE then
        return nil
    end
    local subType = unpack("I1", data, offset + 2)
    return cdc_desc[subType] and cdc_desc[subType](data, offset, context)
end

cls.bInterfaceClass     = 2
cls.bInterfaceSubClass  = 2
cls.bInterfaceProtocol  = nil
cls.endpoints = { EP_IN("Line status") }
cls.iad = {
    bInterfaceClass     = 2,
    bInterfaceSubClass  = 2,
    bInterfaceProtocol  = nil,
}

local protoName = {
    [0x00] ="No class specific" , --  USB specification No class specific protocol required
    [0x01] ="ITU-T V.250"       , --  AT Commands: V.250 etc
    [0x02] ="PCCA-101"          , --  AT Commands defined by PCCA-101
    [0x03] ="PCCA-101"          , --  AT Commands defined by PCCA-101 & Annex O
    [0x04] ="GSM 7.07"          , --  AT Commands defined by GSM 07.07
    [0x05] ="3GPP 27.07"        , --  AT Commands defined by 3GPP 27.007
    [0x06] ="C-S0017-0"         , --  AT Commands defined by TIA for CDMA
    [0x07] ="USB EEM"           , --  Ethernet Emulation Model
    [0xFE] ="External Protocol" , --  : Commands defined by Command Set Functional Descriptor
    [0xFF] ="Vendor-specific"   , --  USB Specification Vendor-specific
    --08-FDh                RESERVED (future use)
}
function cls.get_name(desc, context)
    local name = protoName[desc.bInterfaceProtocol] or "RESERVED"
    return {
        bInterfaceClass = "CDC",
        bInterfaceSubClass = "ACM",
        bInterfaceProtocol = name,
    }
end

register_class_handler(cls)

local rndis_data_cls = {}
for k,v in pairs(cls) do
    rndis_data_cls[k] = v
end
rndis_data_cls.name = "CDC Rndis Data"
rndis_data_cls.bInterfaceClass     = 10
rndis_data_cls.bInterfaceSubClass  = nil
rndis_data_cls.bInterfaceProtocol  = nil
rndis_data_cls.iad = {
    bInterfaceClass     = 2,
    bInterfaceSubClass  = 2,
    bInterfaceProtocol  = 0xff,
}
rndis_data_cls.endpoints = { EP_IN("Incoming Data"), EP_OUT("Outgoning Data") }
rndis_data_cls.on_transaction = rndis_on_transaction

function rndis_data_cls.get_name(desc, context)
    return {
        bInterfaceClass = "CDC Rndis Data",
    }
end
register_class_handler(rndis_data_cls)

local raw_data_cls = {}
for k,v in pairs(cls) do
    raw_data_cls[k] = v
end
raw_data_cls.name = "CDC Raw Data"
raw_data_cls.bInterfaceClass     = 10
raw_data_cls.bInterfaceSubClass  = nil
raw_data_cls.bInterfaceProtocol  = nil
raw_data_cls.iad = {
    bInterfaceClass     = 2,
    bInterfaceSubClass  = 2,
    bInterfaceProtocol  = nil,
}
raw_data_cls.endpoints = { EP_IN("Incoming Data"), EP_OUT("Outgoning Data") }
raw_data_cls.on_transaction = data_on_transaction

function raw_data_cls.get_name(desc, context)
    return {
        bInterfaceClass = "CDC Raw Data",
    }
end
register_class_handler(raw_data_cls)

package.loaded["usb_class_cdc_acm"] = cls
