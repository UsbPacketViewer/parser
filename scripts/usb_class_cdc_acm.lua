-- usb_class_cdc_acm.lua

-- a typical class has these functions
-- cls.parseSetup(setup, context),  update setup.html, setup.name field in setup, and return it
-- cls.parseSetupData(setup, data, context)    return a html to describe the data
-- cls.transferHandler(xfer, tansaction, timestamp_string, updateGraph, parserContext)  return  one of nil , true, "done"
-- cls.descriptorParser(data, offset, context)   return a parsed descriptor
-- cls.getName(descriptor, context)              return a field name table
-- HID class definition  https://www.usb.org/sites/default/files/CDC1.2_WMC1.1_012011.zip

local html = require("html")
local usb_defs = require("usb_defs")
local gb = require("graph_builder")
local rndis = require("rndis")
require("usb_setup_parser")
require("usb_register_class")

local fmt = string.format
local unpack = string.unpack
local cls = {}
cls.name = "CDC ACM class"

_G.bf = _G.bf or {}

_G.bf.ACM_bmCapabilities = {
    name = "bmCapabilities",
    bits = 8,
    {name = "COMM",    mask = 0x01 },
    {name = "LINE",    mask = 0x02 },
    {name = "BREAK",   mask = 0x04 },
    {name = "NETWORK", mask = 0x08 },
}
_G.bf.wValue_cdc_controal_line_state = {
    name = "wValue",
    bits = 16,
    {name = "DTR",    mask = 0x0001 },
    {name = "RTS",    mask = 0x0002 },
}

local bf = _G.bf

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



local function cdc_parseSetup(setup, context, extData)
    if extData and #extData>=8 then
        setup = setup or {}
        setup.recip = "Interface"
        setup.type = "Class"
        setup.bmRequest = unpack("I1", extData, 1)
        setup.bRequest  = unpack("I1", extData, 2)
        setup.wValue    = unpack("I1", extData, 3)
        setup.wIndex    = unpack("I1", extData, 5)
        setup.wLength   = unpack("I1", extData, 7)
        extData = extData:sub(9)
    end
    if setup.recip ~= "Interface" or setup.type ~= "Class" then
        return nil
    end
    local bRequest_desc = req2str[setup.bRequest] or "CDC Unknown Req"
    local reportId = setup.wValue & 0xff
    local value = setup.wValue >> 8

    local wValue_desc = ""
    local extHtml = ""
    local wValueField = {"wValue", fmt("0x%04X", setup.wValue), ""}
    if extData then
        if setup.bRequest == CDC_SERIAL_STATE then
            bRequest_desc = "SERIAL_STATE"
            extHtml = html.makeStruct(extData, "Serial State", [[
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
            ]]).html
        end
    else
        if bRequest_desc == "SET_CONTROL_LINE_STATE"then
            wValueField = html.expandBitFiled(setup.wValue, bf.wValue_cdc_controal_line_state)
        elseif bRequest_desc == "SEND_BREAK" then
            --wValue_desc = fmt("Report ID %d, IDLE: %d", reportId, value )
            wValueField = {"wValue", fmt("%d", setup.wValue), ""}
        end
    end
    local wIndex_desc = fmt("Interface: %d", setup.wIndex)

    setup.name = shortName[bRequest_desc] or "CDC Unknown"
    setup.html = html.makeTable{
        title = "CDC " .. bRequest_desc,
        header = {"Field", "Value", "Description"},
        html.expandBitFiled(setup.bmRequest, bf.bmRequest),
        {"bRequest", fmt("%d",       setup.bRequest),  bRequest_desc  },
        wValueField,
        {"wIndex",   fmt("%d",       setup.wIndex),    wIndex_desc    },
        {"wLength",  fmt("%d",       setup.wLength),   ""   },
    }
    setup.html = setup.html .. extHtml
    return setup
end

function cls.parseSetup(setup, context)
    return cdc_parseSetup(setup, context)
end

function cls.parseSetupData(setup, data, context)
    local s = req2str[setup.bRequest]
    if s then 
        if s == "SET_LINE_CODING" or s == "GET_LINE_CODING" then
            local r = html.makeStruct(data, "Line Coding", [[
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
            return r.html
        elseif s == "SEND_ENCAPSULATED_COMMAND" then
            return rndis.parseCommand(data, context)
        elseif s == "GET_ENCAPSULATED_RESPONSE" then
            return rndis.parseResponse(data, context)
        end
    end
    return nil
end

function cls.transferHandler(xfer, trans, ts, updateGraph, context)
    local name = "CDC Line Status"
    local dataBlock = gb.data("")
    local data = ""
    if trans.data then
        dataBlock = gb.data(trans.data)
        data = trans.data
    end
    xfer.infoData = data
    local f = gb.F_NAK
    local flagBlock = gb.block("NAK", "", gb.C.NAK)
    xfer.infoData = data
    xfer.infoHtml = "<h1>CDC Line Status Nak</h1>"
    if trans.state == "ACK" then
        f = gb.F_ACK
        flagBlock = gb.block("ACK", "", gb.C.ACK)
        xfer.infoHtml = cdc_parseSetup(nil, context, data).html
    end
    local addr,ep = gb.str2addr(xfer.addrStr)
    local res = gb.ts(name, ts, gb.C.XFER, xfer.speed) .. gb.addr(addr) .. gb.endp(ep) 
             .. dataBlock .. flagBlock
             .. gb.F_XFER .. f .. xfer.addrStr
    trans.infoHtml = xfer.infoHtml
    updateGraph( res, xfer.id, xfer)
    return "done"
end

function cls.dataTransferHandler(xfer, trans, ts, updateGraph, context)
    local desc = context:getEpDesc()
    if desc and desc.dataInterface then
        if desc.dataInterface.bInterfaceProtocol == 0xff then
            trans.desc = "CDC RNDIS Data"
            trans.infoHtml = rndis.parseData(trans.data, context)
            trans.parent = nil
            return "done"
        end
    end
    trans.desc = "CDC Data"
    trans.infoHtml = "<h1>CDC Data</h1>"
    trans.parent = nil
    return "done"
end

-- 0x00 -- Header Functional Descriptor, which marks the beginning of the concatenated set of functional descriptors for the interface.
-- 0x01 -- Call Management Functional Descriptor.
-- 0x02 -- Abstract Control Management Functional Descriptor.
-- 0x03 -- Direct Line Management Functional Descriptor.
-- 0x04 -- Telephone Ringer Functional Descriptor.
-- 0x05 -- Telephone Call and Line State Reporting Capabilities Functional Descriptor.
-- 0x06 -- Union Functional Descriptor

function cls.descriptorParser(data, offset, context)

    if unpack("I1", data, offset + 1) ~= usb_defs.CS_INTERFACE then
        return nil
    end
    local desc = {}
    local subType = unpack("I1", data, offset + 2)
    desc.bLength =            unpack("I1", data, offset)
    desc.bDescriptorType =    unpack("I1", data, offset + 1)
    desc.bDescriptorSubtype = subType
    local tb = {}
    tb.header = {"Field", "Value", "Description"}
    tb[#tb+1] = { "bLength", desc.bLength, ""}
    tb[#tb+1] = { "bDescriptorType", desc.bDescriptorType, "CS_INTERFACE" }
    tb[#tb+1] = { "bDescriptorSubtype", desc.bDescriptorSubtype, "" }
    if     subType == 0x00 then
        tb.title = "Header Functional Descriptor"
        local ver = unpack("I2", data, offset + 3)
        tb[#tb+1] = { "bcdCDC", fmt("0x%04x", ver), "" }
    elseif subType == 0x01 then
        tb.title = "Call Management Functional Descriptor"
        local cap = unpack("I1", data, offset + 3)
        local bData = unpack("I1", data, offset + 4)
        tb[#tb+1] = { "bmCapabilities", fmt("0x%02x", cap), "" }
        tb[#tb+1] = { "bDataInterface", fmt("%d", bData), "" }
    elseif subType == 0x02 then
        tb.title = "Abstract Control Management Functional Descriptor"
        local cap = unpack("I1", data, offset + 3)
         tb[#tb+1] = html.expandBitFiled(cap, bf.ACM_bmCapabilities)
    elseif subType == 0x06 then
        tb.title = "Union Functional Descriptor"
        local bMasterInterface = unpack("I1", data, offset + 3)
        local bSlaveInterface0 = unpack("I1", data, offset + 4)
        tb[#tb+1] = { "bMasterInterface", fmt("%d", bMasterInterface), "" }
        tb[#tb+1] = { "bSlaveInterface0", fmt("%d", bSlaveInterface0), "" }
    else
        return nil
    end
    desc.html = html.makeTable(tb)
    return desc
end

cls.bInterfaceClass     = 2
cls.bInterfaceSubClass  = 2
cls.bInterfaceProtocol  = nil

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
function cls.getName(desc, context)
    local name = protoName[desc.bInterfaceProtocol] or "RESERVED"
    return {
        bInterfaceClass = "CDC",
        bInterfaceSubClass = "ACM",
        bInterfaceProtocol = name,
    }
end
register_class_handler(cls)
package.loaded["usb_class_cdc_acm"] = cls
