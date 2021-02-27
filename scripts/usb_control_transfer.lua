-- usb_control_transfer.lua
-- control transfer parser

local html = require("html")
local fmt = string.format
local unpack = string.unpack
local setup_parser = require("usb_setup_parser")
local macro_defs = require("macro_defs")

local function on_transaction(self, param, data, needDetail, forceBegin)
    local addr, ep, pid, ack = param:byte(1), param:byte(2), param:byte(3), param:byte(4)
    local context
    if needDetail then
        self.detail = self.detail or {}
        context = self.detail
    else
        self.simple = self.simple or {}
        context = self.simple
    end
    self.addr = addr
    self.interfaces = self.interfaces or {}
    self.interface_data = self.interface_data or {}
    context.state = context.state or macro_defs.ST_SETUP
    if forceBegin or (pid == macro_defs.PID_SETUP) then
        context.state = macro_defs.ST_SETUP
    end

    if (context.state ~= macro_defs.ST_SETUP) and (ack ~= macro_defs.PID_ACK) then
        if ack == macro_defs.PID_STALL then
            context.status = "stall"
            if needDetail then
                return macro_defs.RES_END, self.upv.make_xact_res("Stall Ack", "", data), self.upv.make_xfer_res(context)
            else
                return macro_defs.RES_END
            end
        end
        context.status = "error"
        if needDetail then
            return macro_defs.RES_END, self.upv.make_xact_res("Error Ack", "", data), self.upv.make_xfer_res(context)
        else
            return macro_defs.RES_END
        end
    end

    if context.state == macro_defs.ST_SETUP then
        -- setup stage
        if (pid == macro_defs.PID_SETUP) and (#data == 8) then
            -- got setup packet
            local len = unpack("I2", data, 7)
            if len == 0 then
                if data:byte(1) > 127 then
                    -- wrong condition
                    context.state = macro_defs.ST_STATUS_OUT
                else
                    context.state = macro_defs.ST_STATUS_IN
                end
            else
                if data:byte(1) > 127 then
                    context.state = macro_defs.ST_DATA_IN
                else
                    context.state = macro_defs.ST_DATA_OUT
                end
            end
            context.setup = {
                data = data
            }
            context.data = ""
            if needDetail then
                context.setup = setup_parser.parse_setup(context.setup.data, self)
                context.infoHtml = context.setup.html
                context.title = "Control Out"
                if data:byte(1) > 127 then
                    context.title = "Control In"
                end
                context.name = context.setup.title or "Request"
                context.desc = context.setup.name
                context.status = "incomp"
                return macro_defs.RES_BEGIN, self.upv.make_xact_res("Setup", context.infoHtml, data), self.upv.make_xfer_res(context)
            end
            return macro_defs.RES_BEGIN
        else
            return macro_defs.RES_NONE
        end
    elseif context.state == macro_defs.ST_DATA_IN then
        -- data in stage
        if (pid == macro_defs.PID_IN) then
            context.data = context.data .. data
            if needDetail then
                local t = setup_parser.parse_data(context.setup, context.data, self)
                return macro_defs.RES_MORE, self.upv.make_xact_res("Data In", t, context.data), self.upv.make_xfer_res(context)
            end
            return macro_defs.RES_MORE
        elseif pid == macro_defs.PID_OUT then
            -- status out stage
            local setupType = context.setup.data:sub(1,4)
            context.state = macro_defs.ST_SETUP
            if needDetail then
                local t = setup_parser.parse_data(context.setup, context.data, self)
                context.infoHtml = context.infoHtml .. t
                context.status = "success"
                return macro_defs.RES_END, self.upv.make_xact_res("Status Out", "", context.data), self.upv.make_xfer_res(context)
            else
                if addr ~= 0 then
                    if setupType == "\x80\x06\x00\x01" then
                        self:setup_device_handler(context.data)
                    elseif setupType == "\x80\x06\x00\x02" then
                        self:setup_interface_handler(context.data)
                    end
                end
            end
            return macro_defs.RES_END
        else
            return macro_defs.RES_NONE
        end
    elseif context.state == macro_defs.ST_DATA_OUT then
        -- data out stage
        if pid == macro_defs.PID_OUT then
            context.data = context.data .. data
            if needDetail then
                local t = setup_parser.parse_data(context.setup, context.data, self)
                return macro_defs.RES_MORE, self.upv.make_xact_res("Data Out", t, context.data), self.upv.make_xfer_res(context)
            end
            return macro_defs.RES_MORE
        elseif pid == macro_defs.PID_IN then
            -- status in stage
            context.state = macro_defs.ST_SETUP
            if needDetail then
                local t = setup_parser.parse_data(context.setup, context.data, self)
                context.infoHtml = context.infoHtml .. t
                context.status = "success"
                return macro_defs.RES_END, self.upv.make_xact_res("Status In", "", context.data), self.upv.make_xfer_res(context)
            end
            return macro_defs.RES_END
        else
            return macro_defs.RES_NONE
        end
    elseif context.state == macro_defs.ST_STATUS_IN then
        -- status in stage
        if pid == macro_defs.PID_IN then
            context.state = macro_defs.ST_SETUP
            if needDetail then
                context.status = "success"
                return macro_defs.RES_END, self.upv.make_xact_res("Status In", "", context.data), self.upv.make_xfer_res(context)
            end
            return macro_defs.RES_END
        else
            return macro_defs.RES_NONE
        end
    elseif context.state == macro_defs.ST_STATUS_OUT then
        -- status out stage
        if pid == macro_defs.PID_OUT then
            context.state = macro_defs.ST_SETUP
            if needDetail then
                context.status = "success"
                return macro_defs.RES_END, self.upv.make_xact_res("Status Out", "", context.data), self.upv.make_xfer_res(context)
            end
            return macro_defs.RES_END
        else
            return macro_defs.RES_NONE
        end
    else
        context.state = macro_defs.ST_SETUP
        return macro_defs.RES_NONE
    end
end

local function get_endpoint_interface(self, endpoint)
    return self.endpoint_itf[endpoint], self.endpoint_alt[endpoint]
end

local function get_interface_class(self, index)
    return self.interfaces[index]
end

local function get_interface_data(self, itf, alt)
    return self.interface_data[itf]
end

local function current_interface_data(self)
    return get_interface_data(self, self.current_itf_n, self.current_itf_alt)
end

local function set_current_interface(self, itf_desc)
    self.current_itf_n = itf_desc:byte(3)
    self.current_itf_alt = itf_desc:byte(4)
end

local function current_device(self)
    return self.device_parser or {}
end
-- get class by full descriptor info
local function find_class(self, itf_desc, iad_desc)
    local iad = nil
    if iad_desc then
        iad = iad_desc.rawData
    end
    return self.upv:find_parser_by_interface(itf_desc.rawData, iad)
end

-- setup device handler by device descriptor
local function setup_device_handler(self, device_desc)
    if #device_desc == 18 then
        local mps, vid, pid = unpack("I1I2I2", device_desc, 8)
        self.upv:set_device_mps(self.addr, mps)
        self.device_parser = self.upv:find_parser_by_vid_pid(vid, pid)
        local devClass = self.upv:find_parser_by_interface("1" .. device_desc)
        if devClass then
            self.device_parser = self.device_parser or {}
            self.device_parser.deviceClass = self.device_parser.deviceClass or devClass
        end
    end
end

-- setup interface handler by config descriptor
local function setup_interface_handler(self, config_desc)
    -- fast parse the config descriptor
    local i = 1
    local itf_desc = nil
    local iad_desc = nil
    local iad_cnt = 0
    local total = #config_desc
    local cur_itf_n = 0
    local cur_alt_n = 0
    local decoder = nil
    local eps = {}
    local mpss = {}
    while (i + 1) < total do
        local len = config_desc:byte(i)
        local t =   config_desc:byte(i+1)
        if len < 2 then break end
        if len + i > #config_desc + 1 then
            break
        end
        if t == macro_defs.IAD_DESC then
            if #eps > 0 then
                if decoder then
                    self.upv:setup_decoder(self.addr, eps, decoder, mpss)
                end
                eps = {}
                mpss = {}
            end
            iad_desc = config_desc:sub(i, i + len - 1)
            iad_cnt = iad_desc:byte(4)
        elseif t == macro_defs.INTERFACE_DESC then
            if #eps > 0 then
                if decoder then
                    self.upv:setup_decoder(self.addr, eps, decoder, mpss)
                end
                eps = {}
                mpss = {}
            end
            itf_desc = config_desc:sub(i, i + len - 1)
            cur_itf_n = itf_desc:byte(3)
            cur_alt_n = itf_desc:byte(4)
            self.interface_data[cur_itf_n] = self.interface_data[cur_itf_n] or {}
            local handler = nil
            decoder = nil
            if self.device_parser and self.device_parser.get_interface_handler then
                handler = self.device_parser.get_interface_handler(self, cur_itf_n)
            end
            if not handler then
                handler = self.upv:find_parser_by_interface(itf_desc, iad_desc)
            end
            if handler then
                self.interfaces[cur_itf_n] = handler
                if handler.make_decoder then
                    decoder = handler.make_decoder(self.upv)
                end
            end
            if iad_cnt > 0 then
                iad_cnt = iad_cnt - 1
            end
            if iad_cnt == 0 then
                iad_desc = nil
            end
        elseif t == macro_defs.ENDPOINT_DESC then
            local ep = config_desc:byte(i+2)
            self.endpoint_itf = self.endpoint_itf or {}
            self.endpoint_itf[ep] = cur_itf_n
            self.endpoint_alt = self.endpoint_alt or {}
            self.endpoint_alt[ep] = cur_alt_n
            local mps = config_desc:byte(i+4) + (config_desc:byte(i+5) * 256)
            eps[#eps+1] = ep
            mpss[#mpss+1] = mps
        end
        i = i + len
    end

    if #eps > 0 then
        if decoder then
            self.upv:setup_decoder(self.addr, eps, decoder, mpss)
        end
        eps = {}
        mpss = {}
    end

end

local function make_control_xfer_decoder(upv)
    local res = {}
    res.on_transaction = on_transaction
    res.setup_device_handler = setup_device_handler
    res.setup_interface_handler = setup_interface_handler
    res.get_interface_class = get_interface_class
    res.get_endpoint_interface = get_endpoint_interface
    res.current_interface_data = current_interface_data
    res.set_current_interface = set_current_interface
    res.get_interface_data = get_interface_data
    res.current_device = current_device
    res.find_class = find_class
    res.upv = upv
    return res
end

package.loaded["usb_control_transfer"] = make_control_xfer_decoder
