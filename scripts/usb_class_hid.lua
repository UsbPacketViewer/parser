-- usb_class_hid.lua

-- a typical class has these functions
-- cls.parse_setup(setup, context),  update setup.html, setup.name field in setup, and return it
-- cls.parse_setup_data(setup, data, context)    return a html to describe the data
-- cls.on_transaction(self, param, data, needDetail, forceBegin)  return macro_defs.RES_xxx
-- cls.descriptor_parser(data, offset, context)   return a parsed descriptor
-- cls.get_name(descriptor, context)              return a field name table
-- HID class definition  https://www.usb.org/sites/default/files/documents/hid1_11.pdf

local html = require("html")
local macro_defs = require("macro_defs")
require("usb_setup_parser")
require("usb_register_class")

local fmt = string.format
local unpack = string.unpack
local cls = {}
cls.name = "HID"

local KEY_A = 0x04
local KEY_Z = 0x1d
local KEY_1 = 0x1e
local KEY_0 = 0x27
local KEY_F1 = 0x3a
local KEY_F12 = 0x45
local KEY_ENTER = 0x28
local num = "1234567890"
local function key2str(key)
    if key == 0 then return '[None]'
    elseif key == 1 then return '[ERR_OVF]'
    elseif key >= KEY_A and key<= KEY_Z then
        return string.char( string.byte("A",1) + key - 4 )
    elseif key >= KEY_1 and key <= KEY_0 then
        local p = key-0x1e+1
        return num:sub(p,p)
    elseif key >= KEY_F1 and key <= KEY_F12 then
        return "F" .. (key - KEY_F1 + 1)
    elseif key == KEY_ENTER then
        return "Enter"
    end
    return "[unknown]"
end

_G.hid_key_name = key2str

local field_wValue_hid_report = html.create_field([[
    struct{
        // wValue
        uint16_t ReportID:8;
        uint16_t ReportType:8; // {[1] = "Input", [2] = "Output", [3] = "Feature"}
    }
]])

local field_wValue_hid_idle = html.create_field([[
    struct{
        // wValue
        uint16_t ReportID:8;
        uint16_t IdleValue:8;
    }
]])

local struct_boot_mouse_data = html.create_struct([[
    struct{
        uint8_t  button1:1;  // {[0]="Released", [1]= "pressed"}
        uint8_t  button2:1;  // {[0]="Released", [1]= "pressed"}
        uint8_t  button3:1;  // {[0]="Released", [1]= "pressed"}
        uint8_t  reserved:5;
        int8_t   x;          // {format = "dec"}
        int8_t   y;          // {format = "dec"}
        uint8_t  reserved;
    }
]])

local struct_boot_key_data = html.create_struct([[
    struct{
        // Modifier
        uint8_t  LeftCtrl:1;    // {[0]="Released", [1]= "pressed"}
        uint8_t  LeftShift:1;   // {[0]="Released", [1]= "pressed"}
        uint8_t  LeftAlt:1;     // {[0]="Released", [1]= "pressed"}
        uint8_t  LeftMeta:1;    // {[0]="Released", [1]= "pressed"}
        uint8_t  RightCtrl:1;   // {[0]="Released", [1]= "pressed"}
        uint8_t  RightShift:1;  // {[0]="Released", [1]= "pressed"}
        uint8_t  RightAlt:1;    // {[0]="Released", [1]= "pressed"}
        uint8_t  RightMeta:1;   // {[0]="Released", [1]= "pressed"}
        uint8_t  reserved;
        {
        uint8_t  key;           // _G.hid_key_name
        }[6];
    }
]])

local req2str = {
    [1] = "GET_REPORT",
    [2] = "GET_IDLE",
    [3] = "GET_PROTOCOL",
    [9] = "SET_REPORT",
    [10] = "SET_IDLE",
    [11] = "SET_PROTOCOL",
}

function cls.parse_setup(setup, context)
    if setup.recip ~= "Interface" or setup.type ~= "Class" then
        return
    end
    local bRequest_desc = req2str[setup.bRequest] or "HID Unknown Req"
    local wValueField = nil
    if bRequest_desc == "GET_REPORT" or bRequest_desc == "SET_REPORT" then
        wValueField = field_wValue_hid_report
    elseif bRequest_desc == "GET_IDLE" or bRequest_desc == "SET_IDLE" then
        wValueField = field_wValue_hid_idle
    elseif bRequest_desc == "GET_PROTOCOL" or bRequest_desc == "SET_PROTOCOL" then
    end
    setup.name = bRequest_desc
    setup.title = "HID Request"
    setup.render.title = "HID Req " .. bRequest_desc
    setup.render.bRequest = bRequest_desc
    setup.render.wValue = wValueField
    setup.render.wIndex = "Interface"
end

function cls.parse_setup_data(setup, data, context)
    local s = req2str[setup.bRequest]
    if s then 
        return "<h1>" .. s .." data </h1>"
    end
    if (setup.bRequest == macro_defs.GET_DESCRIPTOR) and ((setup.wValue>>8) == macro_defs.REPORT_DESC) then
        return "<h1>Report descriptor </h1><br>Todo: parse it to analyze endpoint data"
    end
    return nil
end

local function key_on_transaction(self, param, data, needDetail, forceBegin)
    local addr, ep, pid, ack = param:byte(1), param:byte(2), param:byte(3), param:byte(4)
    if pid ~= macro_defs.PID_IN then
        return macro_defs.RES_NONE
    end
    if ack ~= macro_defs.PID_ACK then
        return macro_defs.RES_NONE
    end

    if needDetail then
        local infoHtml = struct_boot_key_data:build(data, "Maybe Boot Keyboard").html
        return macro_defs.RES_BEGIN_END, self.upv.make_xact_res("HID Key", infoHtml, data), self.upv.make_xfer_res({
            title = "HID Key Data",
            name  = "HID Data",
            desc  = "Boot Keyboard",
            status = "success",
            infoHtml = infoHtml,
            data = data,
        })
    end
    return macro_defs.RES_BEGIN_END
end

local function mouse_on_transaction(self, param, data, needDetail, forceBegin)
    local addr, ep, pid, ack = param:byte(1), param:byte(2), param:byte(3), param:byte(4)
    if pid ~= macro_defs.PID_IN then
        return macro_defs.RES_NONE
    end
    if ack ~= macro_defs.PID_ACK then
        return macro_defs.RES_NONE
    end
    if needDetail then
        local infoHtml = struct_boot_mouse_data:build(data, "Maybe Boot Mouse").html
        return macro_defs.RES_BEGIN_END, self.upv.make_xact_res("HID Mouse",infoHtml,data), self.upv.make_xfer_res({
            title = "HID Mouse Data",
            name  = "HID Data",
            desc  = "Boot Mouse",
            status = "success",
            infoHtml = infoHtml,
            data = data,
        })
    end
    return macro_defs.RES_BEGIN_END
end

local function hid_on_transaction(self, param, data, needDetail, forceBegin)
    local addr, ep, pid, ack = param:byte(1), param:byte(2), param:byte(3), param:byte(4)
    if pid ~= macro_defs.PID_IN and pid ~= macro_defs.PID_OUT then
        return macro_defs.RES_NONE
    end
    if ack ~= macro_defs.PID_ACK then
        return macro_defs.RES_NONE
    end
    if needDetail then
        local infoHtml = "<h1>HID data</h1><p>Need decode with report descriptor"
        return macro_defs.RES_BEGIN_END, self.upv.make_xact_res("Hub Notify", infoHtml, data), self.upv.make_xfer_res({
            title = "HID Data",
            name  = "HID Data",
            desc  = "HID Data",
            status = "success",
            infoHtml = infoHtml,
            data = data,
        })
    end
    return macro_defs.RES_BEGIN_END
end

local function xunpack(fmt, data, index, length)
    index = index or 1
    length = length or 1
    if #data + 1 < index + length then
        return 0
    end
    return unpack(fmt, data, index)
end

--function cls.descriptor_parser = nil

cls.bInterfaceClass     = 3
cls.bInterfaceSubClass  = nil
cls.bInterfaceProtocol  = nil
cls.endpoints = { EP_IN("HID Data") }

function cls.get_name(desc, context)
    local subName = "Reserved"
    if      desc.bInterfaceSubClass == 0  then
        subName = "No SubClass"
    elseif  desc.bInterfaceSubClass == 1  then
        subName = "Boot Interface"
    end
    local bootName = "Reserved"
    if     desc.bInterfaceProtocol == 0  then
        bootName = "None"
    elseif desc.bInterfaceProtocol == 1  then
        bootName = "Keyboard"
    elseif desc.bInterfaceProtocol == 2  then
        bootName = "Mouse"
    end
    return {
        bInterfaceClass = "HID",
        bInterfaceSubClass = subName,
        bInterfaceProtocol = bootName,
    }
end

local function build_hid_class(name, handler, subClass, protool)
    local r = {}
    for k,v in pairs(cls) do
        r[k] = v
    end
    r.name = name
    r.on_transaction = handler
    r.bInterfaceSubClass = subClass
    r.bInterfaceProtocol = protool
    return r
end

register_class_handler(build_hid_class("HID Boot Key", key_on_transaction, 1, 1))
register_class_handler(build_hid_class("HID Boot Mouse", mouse_on_transaction, 1, 2))
cls.endpoints = { EP_IN("Incoming Data", true), EP_OUT("Outgoing Data", true) }
register_class_handler(build_hid_class("HID User", hid_on_transaction, nil, nil))

package.loaded["usb_class_hid"] = cls
