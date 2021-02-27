-- usb_class_msc_bot.lua

-- a typical class has these functions
-- cls.parse_setup(setup, context),  update setup.html, setup.name field in setup, and return it
-- cls.parse_setup_data(setup, data, context)    return a html to describe the data
-- cls.on_transaction(self, param, data, needDetail, forceBegin)  return macro_defs.RES_xxx
-- cls.descriptor_parser(data, offset, context)   return a parsed descriptor
-- cls.get_name(descriptor, context)              return a field name table
-- MSC class definition  https://www.usb.org/sites/default/files/usbmassbulk_10.pdf

local html = require("html")
local macro_defs = require("macro_defs")
require("usb_setup_parser")
require("usb_register_class")

local scsi = require("decoder_scsi")

local fmt = string.format
local unpack = string.unpack
local cls = {}
cls.name = "MSC BOT"

local BOT_GET_MAX_LUN   = 0xfe
local BOT_RESET         = 0xff

function cls.parse_setup(setup, context)
    if setup.recip ~= "Interface" or setup.type ~= "Class" then
        return
    end
    local bRequest_desc = "MSC Unknown Request"
    if     setup.bRequest == BOT_GET_MAX_LUN then
        bRequest_desc = "Get Max LUN"
    elseif setup.bRequest == BOT_RESET then
        bRequest_desc = "BOT Reset"
    end
    setup.name = bRequest_desc
    setup.title = "MSC Request"
    setup.render.title = "MSC Request " .. bRequest_desc
    setup.render.bRequest = bRequest_desc
end

function cls.parse_setup_data(setup, data, context)
    if setup.bRequest == BOT_GET_MAX_LUN then
        local lun = unpack("I1", data)
        return "<h1>Max Logic Unit Number " .. lun .."</h1>"
    end
    return nil
end

function cls.on_transaction(self, param, data, needDetail, forceBegin)
    local addr, ep, pid, ack = param:byte(1), param:byte(2), param:byte(3), param:byte(4)
    local context = self:get_context(needDetail)
    self.addr = addr
    context.state = context.state or macro_defs.ST_CBW
    if forceBegin then
        context.state = macro_defs.ST_CBW
    end
    if #data == 31 and data:sub(1,4) == "USBC" then
        context.state = macro_defs.ST_CBW
    end
    if #data == 13 and data:sub(1,4) == "USBS" then
        context.state = macro_defs.ST_CSW
    end

    if context.state == macro_defs.ST_CBW then
        if #data ~= 31 then
            return macro_defs.RES_NONE
        end
        if ack ~= macro_defs.PID_ACK then
            return macro_defs.RES_NONE
        end
        local xfer_len = unpack("I4", data, 9)
        if xfer_len > 0 then
            context.state = macro_defs.ST_DATA
        else
            context.state = macro_defs.ST_CSW
        end
        context.data = ""
        context.xfer_len = xfer_len
        if needDetail then
            context.cbw = scsi.parse_cmd(data, self)
            context.infoHtml = context.cbw.html
            context.title = "BOT SCSI CMD"
            context.name =  "SCSI CMD"
            context.desc = context.cbw.name
            context.status = "incomp"
            return macro_defs.RES_BEGIN, self.upv.make_xact_res("CBW", context.cbw.html, data), self.upv.make_xfer_res(context)
        end
        return macro_defs.RES_BEGIN
    elseif context.state == macro_defs.ST_DATA then
        if ack == macro_defs.PID_STALL then
            context.state = macro_defs.ST_CSW
            if needDetail then
                context.status = "stall"
                return macro_defs.RES_MORE, self.upv.make_xact_res("SCSI Stall", "", data), self.upv.make_xfer_res(context)
            end
            return macro_defs.RES_MORE
        end
        context.data = context.data .. data
        if self.upv:is_short_packet(addr, ep, data) then
            context.state = macro_defs.ST_CSW
        elseif #context.data == context.xfer_len then
            context.state = macro_defs.ST_CSW
        end
        if needDetail then
            if context.state == macro_defs.ST_CSW then
                context.infoHtml = (context.infoHtml or "") .. scsi.parse_data(context.cbw, context.data, self)
            end
            return macro_defs.RES_MORE, self.upv.make_xact_res("SCSI DATA", "", data), self.upv.make_xfer_res(context)
        end
        return macro_defs.RES_MORE
    elseif context.state == macro_defs.ST_CSW then
        if ack == macro_defs.PID_STALL then
            return macro_defs.RES_MORE
        end
        if ack ~= macro_defs.PID_ACK then
            return macro_defs.RES_END
        end
        if #data ~= 13 then
            return macro_defs.RES_END
        end
        if needDetail then
            local status = scsi.parse_status(context.cbw, data, self)
            context.infoHtml = (context.infoHtml or "") .. status.html
            context.data = context.data or ""
            context.title = context.title or ""
            context.name = context.name or ""
            context.desc = context.desc or ""
            context.status = status.status
            return macro_defs.RES_END, self.upv.make_xact_res("CSW", status.html, data), self.upv.make_xfer_res(context)
        end
        return macro_defs.RES_END
    else
        context.state = macro_defs.ST_CBW
        return macro_defs.RES_NONE
    end
end


cls.bInterfaceClass     = 0x08
cls.bInterfaceSubClass  = 0x06
cls.bInterfaceProtocol  = 0x50
cls.endpoints = { EP_IN("Incoming Data"), EP_OUT("Outgoing Data") }

function cls.get_name(desc, context)
    return {
        bInterfaceClass = "Mass Storage Class",
        bInterfaceSubClass = "SCSI transparent command set",
        bInterfaceProtocol = "Bulk Only Transport",
    }
end

register_class_handler(cls)
package.loaded["usb_class_msc_bot"] = cls
