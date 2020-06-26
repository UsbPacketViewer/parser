-- usb_class_data.lua

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
require("usb_setup_parser")
require("usb_register_class")

local fmt = string.format
local unpack = string.unpack
local cls = {}
cls.name = "General Data Interface class"

-- function cls.parseSetup(setup, context) end

-- function cls.parseSetupData(setup, data, context) return nil end

-- function cls.descriptorParser(data, offset, context) return nil end

function cls.transferHandler(xfer, trans, ts, updateGraph, context)
    local desc = context:getEpDesc()
    trans.parent = nil
    if desc.processed then
        if desc.dataHandler then
            trans.parent = xfer
            return desc.dataHandler(xfer, trans, ts, updateGraph, context)
        end
        return "done"
    end
    desc.processed = true
    if not desc then return "done" end
    if not desc.configDesc then return "done" end
    local lastInterface = nil
    local newHandler = nil
    local dataInterface = nil
    for i,v in ipairs(desc.configDesc) do
        if v == desc.interfaceDesc and lastInterface then
            local cls = context:getClass(lastInterface)
            if cls and cls.dataTransferHandler then
                newHandler = cls.dataTransferHandler
                dataInterface = lastInterface
                break
            end
        end
        if v.bDescriptorType == usb_defs.INTERFACE_DESC then
            lastInterface = v
        end
    end
    if not newHandler then return "done" end
    trans.parent = xfer
    desc.dataHandler = newHandler
    desc.dataInterface = dataInterface
    return newHandler(xfer, trans, ts, updateGraph, context)
end

cls.bInterfaceClass     = 0x0a
cls.bInterfaceSubClass  = nil
cls.bInterfaceProtocol  = nil

function cls.getName(desc, context)
    return {
        bInterfaceClass = "General data",
    }
end

register_class_handler(cls)
package.loaded["usb_class_data"] = cls
