
-- USB Packet Viewer parser
require("usb_register_class")
local make_control_xfer_decoder = require("usb_control_transfer")

local upv = {
    decoder = {},
    autoDecoder = {},
    mps_map = {},
    mps_guess = {}
}

function upv_reset_parser()
    upv.decoder = {}
    upv.autoDecoder = {}
    upv.mps_map = {}
    upv.mps_guess = {}
    collectgarbage()
end

local function get_decoder(addr, ep, autoDecoder)
    local decoder = upv.decoder[string.char(addr, ep)]
    if not decoder and autoDecoder then
        decoder = upv.autoDecoder[string.char(addr, ep)]
    end
    if (not decoder) and ( (ep & 0x7f) == 0) then
        -- create default decoder for control transfer
        local ctrl_xfer_decoder = make_control_xfer_decoder(upv)
        upv.decoder[string.char(addr, 0)] = ctrl_xfer_decoder
        upv.decoder[string.char(addr, 0x80)] = ctrl_xfer_decoder
        return ctrl_xfer_decoder
    end
    return decoder
end

local upv_register_decoder = upv_register_decoder
upv.setup_decoder = function(self, addr, eps, decoder, mpss)
    if mpss then
        for i,v in ipairs(mpss) do
            upv.mps_map[string.char(addr, eps[i])] = v
        end
    end

    local ep_res = decoder:check_ep_require(eps)
    local param = ""
    for i,v in ipairs(ep_res) do
        param = param .. string.char(addr, v)
    end
    local temp = upv.decoder
    upv.decoder = upv.autoDecoder
    upv_register_decoder(decoder.name, param)
    upv.decoder = temp
end

upv.is_short_packet = function(self, addr, ep, data)
    local key = string.char(addr, ep)
    local mps = upv.mps_map[key]
    if mps and #data < mps then return true end
    local l = #data
    if l < 8 then return true end
    if ((l-1) & l) ~= 0 then return true end
    mps = upv.mps_guess[key]
    if mps and (l<mps) then return true end
    upv.mps_guess[key] = mps
    return false
end
upv.set_device_mps = function(self, addr, mps)
    upv.mps_map[string.char(addr, 0x00)] = mps
    upv.mps_map[string.char(addr, 0x80)] = mps
end

local find_device_handler = find_device_handler
upv.find_parser_by_vid_pid = function(self, vid, pid)
    -- TODO: got decoder by VID PID
    return find_device_handler(vid, pid)
end

local find_class_handler = find_class_handler
upv.find_parser_by_interface = function(self, itf_desc, iad_desc)
    return find_class_handler(itf_desc, iad_desc)
end


function upv.make_xact_res(name, info, data)
    return name.."\0\0\0\0"..(info or "").."\0" .. (data or "")
end

function upv.make_xfer_res(context)
    return context.title    .. "\0"
        .. context.name     .. "\0"
        .. context.desc     .. "\0" 
        .. context.status   .. "\0" 
        .. context.infoHtml .. "\0" 
        .. context.data
end


function upv_parse_transaction(param, data, needDetail, forceBegin, autoDecoder)
    local addr, ep = param:byte(1), param:byte(2)
    local decoder = get_decoder(addr, ep, autoDecoder)
    if not decoder then return 0 end
    return decoder:on_transaction(param, data, needDetail, forceBegin)
end

function upv_valid_parser()
    return get_register_handler()
end

function upv_remove_decoder(name, eps)
    local i = 1
    while i < #eps do
        upv.decoder[eps:sub(i,i+1)] = nil
        upv.mps_map[eps:sub(i,i+1)] = nil
        upv.mps_guess[eps:sub(i,i+1)] = nil
        i = i + 2
    end
    return true
end

local find_handler_by_name = find_handler_by_name
function upv_add_decoder(name, eps)
    local handler = nil
    if name == "Control Transfer" then
        handler = {
            make_decoder = make_control_xfer_decoder
        }
    else
        handler = find_handler_by_name(name)
    end
    if handler and handler.make_decoder then
        local decoder = handler.make_decoder(upv)
        local i = 1
        while i < #eps do
            upv.decoder[eps:sub(i,i+1)] = decoder
            i = i + 2
        end
        return true
    end
    return false
end

package.loaded["upv_parser"] = upv
