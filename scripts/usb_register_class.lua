-- usb_register_class.lua
--[[
local hid = require("usb_class_hid")
local bot = require("usb_class_msc_bot")
local cdc_acm = require("usb_class_cdc_acm")
local data = require("usb_class_data")

local function register(context)
    context:regClass(hid)
    context:regClass(bot)
    context:regClass(cdc_acm)
    context:regClass(data)
end
--]]

local class_handlers = {}
function register_class_handler(cls)
    local old = class_handlers[cls.name]
    class_handlers[cls.name] = cls
    if parser_reset then
        parser_reset()
    end
    return old
end


local device_handlers = {}
function register_device_handler(cls, vid, pid)
    local t = string.format("vid%04x_pid%04x", vid, pid)
    local old = device_handlers[t]
    device_handlers[t] = cls
    if parser_reset then
        parser_reset()
    end
    return old
end

local function register(context)
    for k,v in pairs(class_handlers) do
        context:regClass(v)
    end

    for k,v in pairs(device_handlers) do
        local vid = 0
        local pid = 0
        string.gsub(k, "vid([%x]+)_pid([%x]+)", function(v, p)
            vid = tonumber(v, 16)
            pid = tonumber(p, 16)
        end)
        context:regVendorProduct(v, vid, pid)
    end
end



package.loaded["usb_register_class"] = register
