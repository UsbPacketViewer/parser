-- usb_setup_parser.lua
-- encoding: utf-8

local parser = {}
local fmt = string.format
local unpack = string.unpack
local html = require("html")
local macro_defs = require("macro_defs")
local desc_parser = require("usb_descriptor_parser")

local field_bmRequest = html.create_field([[
    struct{
        // bmRequest
        uint8_t   Recipient:5; // {[0] = "Device", [1] = "Interface", [2] = "Endpoint" ,[3]="Other"}
        uint8_t   Type:2;      // {[0] = "Standard", [1]="Class",[2]="Vendor",[3]="Reserved"}
        uint8_t   Direction:1; // {[0] = "Host to Device", [1]="Device to Host"}
    }
]])

local field_wValue_get_desc = html.create_field([[
    struct{
        // wValue
        uint16_t  Index:8;
        uint16_t  Type:8;   // _G.get_descriptor_name
    }
]])

local struct_device_status = html.create_struct([[
    struct{
        // wStatus
        uint16_t SelfPowered:1;   // {[0] = "Bus Powered", [1] = "Self Powered"}
        uint16_t RemoteWakeUp:1;  // {[0] = "Disabled", [1] = "Enabled"}
        uint16_t reserved:14;
    }
]])

local function render_field(setup, field, default)
    local render = setup.render[field] or default
    if render then
        if type(render) == "string" then
            return {field,  fmt("%d", setup[field]),  render }
        elseif type(render) == "table" then
            return html.expand_bit_field(setup[field], render)
        elseif type(render) == "function" then
            return {field,  fmt("%d", setup[field]), render(setup[field])}
        end
    end
    return nil
end

function parser.parse_setup(data, context)
    local setup = {}
    setup.data = data
    local bmRequest, bRequest, wValue, wIndex, wLength = unpack("I1I1I2I2I2", setup.data .. "\xff\xff\xff\xff\xff\xff\xff\xff")
    setup.bmRequest = bmRequest
    setup.bRequest = bRequest
    setup.wValue = wValue
    setup.wIndex = wIndex
    setup.wLength = wLength
    setup.render = {}

    local typStr
    local reqTitle = "Unknwon Req"
    local typ = (bmRequest >> 5) & 3
    if     typ == 0 then
        typStr = "Standard"
        reqTitle = "Standard Req"
    elseif typ == 1 then
        typStr = "Class"
        reqTitle = "Class Req"
    elseif typ == 2 then
        typStr = "Vendor"
        reqTitle = "Vendor Req"
    else                 typStr = "Reserved"
    end
    setup.type = typStr

    local recipStr
    local recip = bmRequest & 0x1f
    if     recip == 0 then recipStr = "Device"
    elseif recip == 1 then recipStr = "Interface"
    elseif recip == 2 then recipStr = "Endpoint"
    elseif recip == 3 then recipStr = "Other"
    else                   recipStr = "Reserved"
    end
    setup.recip = recipStr
    if typStr == "Class" and recipStr == "Endpoint" then
        local itf = context:get_endpoint_interface(wIndex & 0xff)
        local cls = context.get_interface_class and context:get_interface_class(itf)
        cls = cls or context.class_handler
        if cls and cls.parse_setup then
            local r = cls.parse_setup(setup, context)
            if r then return r end
        end
    end
    if recipStr == "Interface" then
        local cls = context.get_interface_class and context:get_interface_class(wIndex & 0xff)
        cls = cls or context.class_handler
        if cls and cls.parse_setup then
            local r = cls.parse_setup(setup, context)
            if r then return r end
        end
    elseif recipStr == "Device" or recipStr == "Other" then
        if typStr == "Class" and context.current_device then
            local cls = context:current_device().deviceClass
            if cls and cls.parse_setup then
                local r = cls.parse_setup(setup, context)
                if r then return r end
            end
        end
    end

    local dev = context.current_device and context:current_device()
    if dev and dev.parse_setup then
        local r = dev.parse_setup(setup, context)
        if r then return r end
    end

    local bRequest_desc = ""
    if       typStr == "Standard" then
        bRequest_desc = get_std_request_name(bRequest)
    elseif   typStr == "Class" then
        bRequest_desc = " Class Req " .. bRequest
    elseif   typStr == "Vendor" then
        bRequest_desc = " Vendor Req " .. bRequest
    end

    local wValue_field = ""
    if typStr == "Standard" then
        if (bRequest == macro_defs.CLEAR_FEATURE) or (bRequest == macro_defs.SET_FEATURE) then
            wValue_field = fmt("Feature: %d", wValue)
        elseif bRequest == macro_defs.SET_ADDRESS then
            wValue_field = fmt("Address: %d", wValue)
        elseif (bRequest == macro_defs.GET_DESCRIPTOR) or (bRequest == macro_defs.SET_DESCRIPTOR) then
            wValue_field =  field_wValue_get_desc
        elseif bRequest == macro_defs.SET_CONFIG then
            wValue_field = fmt("Config: %d", wValue)
        end
    end

    local wIndex_desc = ""
    if recipStr == "Device" then
        if (wValue > 0) and ((bRequest == macro_defs.GET_DESCRIPTOR) or (bRequest == macro_defs.SET_DESCRIPTOR)) then
            wIndex_desc = fmt("Language ID: 0x%04x", wIndex)
        else
        end
    elseif recipStr == "Interface" then
        wIndex_desc = fmt("Interface: %d", wIndex)
    elseif recipStr == "Endpoint" then
        wIndex_desc = fmt("Endpoint: 0x%02X", wIndex & 0xff)
    end
    setup.html = html.make_table{
        title =  setup.render.title or (typStr .. " Request"),
        header = {"Field", "Value", "Description"},
        render_field(setup, "bmRequest", field_bmRequest),
        render_field(setup, "bRequest", bRequest_desc),
        render_field(setup, "wValue", wValue_field),
        render_field(setup, "wIndex", wIndex_desc),
        render_field(setup, "wLength", ""),
    }
    setup.title = setup.title or reqTitle
    setup.name = setup.name or (typStr == "Standard" and get_std_request_name(bRequest, wValue, wIndex) or bRequest_desc)
    return setup
end

function parser.parse_data(setup, data, context)
    if setup.type == "Class" and setup.recip == "Endpoint" then
        local itf = context:get_endpoint_interface(setup.wIndex & 0xff)
        local cls = context.get_interface_class and context:get_interface_class(itf)
        cls = cls or context.class_handler
        if cls and cls.parse_setup_data then
            local r = cls.parse_setup_data(setup, data, context)
            if r then return r end
        end
    end
    if setup.recip == "Interface" then
        local cls = context.get_interface_class and context:get_interface_class(setup.wIndex & 0xff)
        cls = cls or context.class_handler
        if cls and cls.parse_setup_data then
            local r = cls.parse_setup_data(setup, data, context)
            if r then return r end
        end
    elseif setup.recip == "Device" or setup.recip == "Other" then
        if setup.type == "Class" then
            local cls = context.current_device and context:current_device().deviceClass
            if cls and cls.parse_setup_data then
                local r = cls.parse_setup_data(setup, data, context)
                if r then return r end
            end
        end
    end

    local dev = context.current_device and context:current_device()
    if dev and dev.parse_setup_data then
        local r = dev.parse_setup_data(setup, data, context)
        if r then return r end
    end

    if setup.type == "Standard" then
        if (setup.bRequest == macro_defs.GET_DESCRIPTOR or bRequest == macro_defs.SET_DESCRIPTOR) then
            if (setup.wValue >> 8) <= macro_defs.MAX_STD_DESC then
                local descInfo = desc_parser.parse(data, context)
                return descInfo.html
            end
        elseif setup.bRequest == macro_defs.GET_STATUS and #data >= 2 then
            return struct_device_status:build(data, "Device Status").html
        end
    end
    return "<p><h1>Get " .. #data .. " bytes data</h1></p> Display in data window"
end

package.loaded["usb_setup_parser"] = parser
