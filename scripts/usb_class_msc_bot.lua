-- usb_class_msc_bot.lua

-- a typical class has these functions
-- cls.parseSetup(setup, context),  update setup.html, setup.name field in setup, and return it
-- cls.parseSetupData(setup, data, context)    return a html to describe the data
-- cls.transferHandler(xfer, tansaction, timestamp_string, updateGraph, parserContext)  return  one of nil , true, "done"
-- cls.descriptorParser(data, offset, context)   return a parsed descriptor
-- cls.getName(descriptor, context)              return a field name table
-- MSC class definition  https://www.usb.org/sites/default/files/usbmassbulk_10.pdf

local html = require("html")
local usb_defs = require("usb_defs")
local gb = require("graph_builder")
require("usb_setup_parser")
require("usb_register_class")

local scsi = require("scsi")

local fmt = string.format
local unpack = string.unpack
local cls = {}
cls.name = "MSC BOT class"

local BOT_GET_MAX_LUN   = 0xfe
local BOT_RESET         = 0xff


function cls.parseSetup(setup, context)
    if setup.recip ~= "Interface" or setup.type ~= "Class" then
        return nil
    end
    local bRequest_desc = "MSC Unknown Request"
    if     setup.bRequest == BOT_GET_MAX_LUN then
        bRequest_desc = "Get Max LUN"
    elseif setup.bRequest == BOT_RESET then
        bRequest_desc = "BOT Reset"
    end
    local reportId = setup.wValue & 0xff
    local value = setup.wValue >> 8 
    local wIndex_desc = fmt("Interface: %d", setup.wIndex)
    setup.name = bRequest_desc
    setup.html = html.makeTable{
        title = "MSC " .. bRequest_desc,
        header = {"Field", "Value", "Description"},
        html.expandBitFiled(setup.bmRequest, bf.bmRequest),
        {"bRequest", fmt("%d",       setup.bRequest),  bRequest_desc  },
        {"wValue",   fmt("%d",       setup.wValue),    ""             },
        {"wIndex",   fmt("%d",       setup.wIndex),    wIndex_desc    },
        {"wLength",  fmt("%d",       setup.wLength),   ""   },
    }
    return setup
end

function cls.parseSetupData(setup, data, context)
    if setup.bRequest == BOT_GET_MAX_LUN then
        local lun = unpack("I1", data)
        return "<h1>Max Logic Unit Number " .. lun .."</h1>"
    end
    return nil
end

local function bot_parser(xfer, trans, ts, updateGraph, context)
    xfer.state = xfer.state or 0
    xfer.name = "BOT SCSI CMD"
    if      xfer.state == 0 then
        -- SCSI command
        if trans.token.name == "OUT" and trans.state == "ACK" then
            xfer.cbw = scsi.parse_cmd(trans.data, context)
            xfer.infoHtml = xfer.cbw.html
            trans.infoHtml = xfer.cbw.html
            trans.desc = "CBW"
            if xfer.cbw.dCBWDataTransferLength > 0 then
                xfer.state = 1
            else
                xfer.state = 2
            end
        end
    elseif  xfer.state == 1 then
        -- SCSI data
        if trans.state == "ACK" then
            xfer.data = xfer.data or ""
            xfer.data = xfer.data .. (trans.data or "")
            trans.desc = "SCSI Data"
            if context:isShortPacket(xfer.addrStr, trans.data) then
                xfer.state = 2
            elseif #xfer.data >= xfer.cbw.dCBWDataTransferLength then
                xfer.state = 2
            end
            if xfer.state == 2 then
                local dataHtml = scsi.parse_data(xfer.cbw, xfer.data, context)
                xfer.infoHtml = xfer.infoHtml .. dataHtml
                trans.infoHtml = dataHtml or "<h1>BOT (last) data</h1>"
            else
                trans.infoHtml = "<h1>BOT partial data</h1>"
            end
        elseif trans.state == "NAK" then
            trans.desc = "SCSI NAK"
        elseif trans.state == "STALL" then
            trans.desc = "SCSI STALL"
            trans.infoHtml = "<h1>stall</h1>"
            xfer.state = 2
            xfer.status = "stall"
        end
    elseif  xfer.state == 2 then
        -- SCSI status
        if trans.token.name == "IN" then
            if trans.state == "ACK" then
                trans.desc = "CSW"
                local status = scsi.parse_status(xfer.cbw, trans.data, context)
                trans.infoHtml = status.html
                xfer.infoHtml = xfer.infoHtml .. status.html
                xfer.status = status.status
                xfer.infoData = xfer.data
                xfer.state = 4
            elseif trans.state == "NAK" then
                trans.desc = "SCSI NAK"
            elseif trans.state == "STALL" then
                trans.desc = "SCSI STALL"
                trans.infoHtml = "<h1>stall</h1>"
                xfer.state = 2
                xfer.status = "stall"
            end
        end
    end
    local addr,ep = gb.str2addr(xfer.addrStr)
    if xfer.state == 4 then
        xfer.state = 0
        assert(xfer.addrStr)
        if xfer.status == "success" then
            local res = gb.ts(xfer.name, ts, gb.C.XFER, xfer.speed) .. gb.req(xfer.cbw.name, "SCSI CMD")
            .. gb.addr(addr) .. gb.endp(ep) .. gb.data(xfer.data or "")
            .. gb.success(xfer.status) .. gb.F_XFER .. gb.F_ACK .. xfer.addrStr
            updateGraph( res, xfer.id, xfer)
        else
            local res = gb.ts(xfer.name, ts, gb.C.XFER, xfer.speed) .. gb.req(xfer.cbw.name, "SCSI CMD")
            .. gb.addr(addr) .. gb.endp(ep) .. gb.incomp(xfer.status, 60)
            .. gb.F_XFER .. gb.F_ERROR .. xfer.addrStr
            updateGraph( res, xfer.id, xfer)
        end
        return "done"
    end
    local n = xfer.cbw and xfer.cbw.name or "SCSI CMD"
    local res = gb.ts(xfer.name, ts, gb.C.XFER, xfer.speed) .. gb.req(n, "SCSI CMD") .. gb.addr(addr) .. gb.endp(ep) .. gb.incomp()
    .. gb.F_XFER .. gb.F_INCOMPLETE .. xfer.addrStr
    updateGraph( res, xfer.id, xfer)
    return true
end

function cls.transferHandler(xfer, trans, ts, updateGraph, context)
    local desc = context:getEpDesc()
    local dev = context:currentDevice()
    dev.botHandler = dev.botHandler or {}
    dev.botHandler[desc.interfaceDesc.bInterfaceNumber] = 
    dev.botHandler[desc.interfaceDesc.bInterfaceNumber] or {}
    local botXfer = dev.botHandler[desc.interfaceDesc.bInterfaceNumber].xfer
    if not botXfer then
        botXfer = {}
        botXfer.id = trans.id
        botXfer.addrStr = trans.addrStr
        botXfer.speed = trans.speed
    end
    trans.parent = botXfer
    dev.botHandler[desc.interfaceDesc.bInterfaceNumber].xfer = botXfer
    local res = bot_parser(botXfer, trans, ts, updateGraph, context)
    context.id2xfer[botXfer.id] = botXfer
    if res == "done" then
        dev.botHandler[desc.interfaceDesc.bInterfaceNumber].xfer = nil
    end
    return "done"
end

cls.bInterfaceClass     = 0x08
cls.bInterfaceSubClass  = 0x06
cls.bInterfaceProtocol  = 0x50

function cls.getName(desc, context)
    return {
        bInterfaceClass = "Mass Storage Class",
        bInterfaceSubClass = "SCSI transparent command set",
        bInterfaceProtocol = "Bulk Only Transport",
    }
end
register_class_handler(cls)
package.loaded["usb_class_msc_bot"] = cls
