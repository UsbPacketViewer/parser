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
local class_map = {}
local iad_map = {}

local function cls2key(cls)
    local res = ""
    if cls.bInterfaceClass then
        res = res .. string.char(cls.bInterfaceClass)
        if cls.bInterfaceSubClass then
            res = res .. string.char(cls.bInterfaceSubClass)
            if cls.bInterfaceProtocol then
                res = res .. string.char(cls.bInterfaceProtocol)
            end
        end
    end
    return res
end

local function parse_ep_require(eps)
    local res = {}
    for i,v in ipairs(eps) do
        res[#res+1] = tonumber(v:sub(#v,#v))
    end
    return res
end

local function check_ep_require(self, eps)
    local ep_cnt = #self.ep_require
    local ep_res = {}
    local ep_opt_cnt = 0
    for j,v in ipairs(self.ep_require) do
        if v >= 4 then
            ep_res[j] = 255
            ep_opt_cnt = ep_opt_cnt + 1
        end
    end

    for i=1,#eps do
        local ep = eps[i]
        for j,v in ipairs(self.ep_require) do
            if v == 1 or v == 5 then
                if (ep & 0x80) == 0x80 then
                    ep_res[j] = ep
                    ep_cnt = ep_cnt - 1
                    break
                end
            elseif v == 0 or v == 4 then
                if (ep & 0x80) == 0x00 then
                    ep_res[j] = ep
                    ep_cnt = ep_cnt - 1
                    break
                end
            else
                ep_res[j] = ep
                ep_cnt = ep_cnt - 1
                break
            end
        end
    end
    if ep_cnt > ep_opt_cnt then
        error("fail to parse endpoint requirement\n" .. debug.traceback())
    end
    return ep_res
end
-- context related on needDetail or pid
local function get_context(self, needDetail, pid)
    local context
    if needDetail then
        self.detail = self.detail or {}
        context = self.detail
    else
        self.simple = self.simple or {}
        context = self.simple
    end
    if pid then
        context.pid_map = context.pid_map or {}
        context.pid_map[pid] = context.pid_map[pid] or {}
        context = context.pid_map[pid]
    end
    return context
end


local function get_endpoint_interface_data(self, addr, ep)
    local dev = self.upv.get_decoder(addr, 0)
    if not dev then return {} end
    local itf, alt = dev:get_endpoint_interface(ep)
    return dev:get_interface_data(itf, alt)
end

function register_class_handler(cls)
    local old = class_handlers[cls.name]
    cls.ep_require = parse_ep_require(cls.endpoints or {})
    cls.make_decoder = function(upv)
        local res = {}
        res.on_transaction = cls.on_transaction
        res.upv = upv
        res.name = cls.name
        res.ep_require = cls.ep_require
        res.check_ep_require = check_ep_require
        res.get_context = get_context
        res.class_handler = cls
        res.get_endpoint_interface_data = get_endpoint_interface_data
        return res
    end
    class_handlers[cls.name] = cls
    if cls.iad then
        local key = cls2key(cls)
        local iadKey= cls2key(cls.iad)
        iad_map[iadKey] = iad_map[iadKey] or {}
        iad_map[iadKey][key] = cls
    else
        local key = cls2key(cls)
        class_map[key] = cls
    end
    return old
end

local function find_something(map, key)
    while #key > 1 do
        local t = map[key]
        if t then return t end
        key = string.sub(key, 1, #key-1)
    end
    return map[key]
end

function find_class_handler(itf_desc, iad_desc)
    local key = nil
    if     type(itf_desc) == "table" then
        key = cls2key(itf_desc)
    elseif type(itf_desc) == "string" then
        key = string.sub(itf_desc,6,8)
    else
        error("wrong itf desc" .. type(itf_desc))
        return nil
    end
    if iad_desc then
        local iad_key = nil
        if     type(itf_desc) == "table" then
            iad_key = cls2key(iad_desc)
        elseif type(itf_desc) == "string" then
            iad_key = string.sub(iad_desc,5,7)
        else
            error("wrong iad desc")
            return nil
        end
        local map = find_something(iad_map, iad_key)
        if map then
            return find_something(map, key)
        end
        return nil
    end
    return find_something(class_map, key)
end

local device_handlers = {}
local device_handlers_map = {}
local pack = string.pack
function register_device_handler(dev, vid, pid)
    local t = pack("I2I2",vid,pid)
    local old = device_handlers[t]
    device_handlers[t] = dev
    device_handlers_map[dev.name] = dev
    return old
end

function find_device_handler(vid, pid)
    local t = pack("I2I2",vid,pid)
    return device_handlers[t]
end

function get_register_handler()
    local res = ""
    local sep = ""
    local n1 = {}
    
    for k,v in pairs(class_handlers) do
        n1[#n1+1] = k
    end

    table.sort(n1)

    for i,k in ipairs(n1) do
        local v = class_handlers[k]
        if v.endpoints then
            res = res .. sep .. k .. ":".. table.concat(v.endpoints, ",")
            sep = ";"
        end
    end

    --[[
    local n2 = {}
    for k,v in pairs(device_handlers_map) do
        n2[#n2+1] = k
    end
    table.sort(n2)

    for i,k in ipairs(n2) do
        local v = device_handlers_map[k]
        if v.endpoints then
            res = res .. sep .. k .. ":".. table.concat(v.endpoints, ",")
            sep = ";"
        end
    end
    ]]
    return res
end

function find_handler_by_name(name)
    return class_handlers[name] -- or device_handlers_map[name]
end

local function register(context)
end

package.loaded["usb_register_class"] = register
