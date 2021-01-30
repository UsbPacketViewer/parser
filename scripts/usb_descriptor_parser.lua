-- usb_descriptor_parser.lua
local macro_defs = require("macro_defs")
local html = require("html")
local parser = {}
local descTable = {}
local fmt = string.format
local unpack = string.unpack

local last_vid = 0
_G.render_vid = function(vid)
    last_vid = vid
    return '<a href="https://usb-ids.gowdy.us/read/UD/'..fmt("%04x", vid)..'">Who\'s that?</a>'
end
_G.render_pid = function(pid)
    return '<a href="https://usb-ids.gowdy.us/read/UD/'..fmt("%04x/%04x", (last_vid or 0), pid)..'">What\'s it?</a>'
end

local function make_desc_parser(name, info)
    local builder = html.create_struct(info)
    return function(data, offset, context)
        local rawData = data:sub(offset)
        local res = builder:build(rawData, name .. " Descriptor")
        res.rawData = rawData
        return res
    end
end

local parse_unknown_desc = make_desc_parser("Unknown", [[
    struct {
        uint8_t bLength;          // {format = "dec"}
        uint8_t bDescriptorType;  // _G.get_descriptor_name
        uint8_t data[bLength];
    }
]])

descTable[macro_defs.DEVICE_DESC] = make_desc_parser("Device", [[
    uint8_t  bLength;          // {format = "dec"}
    uint8_t  bDescriptorType;  // _G.get_descriptor_name
    uint16_t bcdUSB;
    uint8_t  bDeviceClass;
    uint8_t  bDeviceSubClass;
    uint8_t  bDeviceProtocol;
    uint8_t  bMaxPacketSize;
    uint16_t idVendor;        // _G.render_vid
    uint16_t idProduct;       // _G.render_pid
    uint16_t bcdDevice;
    uint8_t  iManufacturer;
    uint8_t  iProduct;
    uint8_t  iSerial;
    uint8_t  bNumConfigurations;
]])


descTable[macro_defs.DEV_QUAL_DESC] = make_desc_parser("Device Qualifier", [[
    uint8_t  bLength;          // {format = "dec"}
    uint8_t  bDescriptorType;  // _G.get_descriptor_name
    uint16_t bcdUSB;
    uint8_t  bDeviceClass;
    uint8_t  bDeviceSubClass;
    uint8_t  bDeviceProtocol;
    uint8_t  bMaxPacketSize;
    uint8_t  bNumConfigurations;
    uint8_t  bReserved;
]])

descTable[macro_defs.CFG_DESC] = make_desc_parser("Config", [[
    uint8_t  bLength;          // {format = "dec"}
    uint8_t  bDescriptorType;  // _G.get_descriptor_name
    uint16_t wTotalLength;
    uint8_t  bNumInterfaces;
    uint8_t  bConfigurationValue;
    uint8_t  iConfiguration;
    // bmAttributes
    uint8_t  Reserved:5;
    uint8_t  RemoteWakeup:1; { [0]="No", [1]="Yes" }
    uint8_t  SelfPowered:1;  { [0]="No", [1]="Yes" }
    uint8_t  Reserved:1;
    uint8_t  bMaxPower;      // {format="dec", comment = "x 2mA"}
]])

descTable[macro_defs.STRING_DESC] = make_desc_parser("String",[[
    uint8_t  bLength;             // {format = "dec"}
    uint8_t  bDescriptorType;     // _G.get_descriptor_name
    uint16_t wString[bLength-2];  // {format = "unicode"}
]])

local currentInterface = {}
_G.get_InterfaceClass = function()
    return currentInterface.bInterfaceClass or ""
end
_G.get_InterfaceSubClass = function()
    return currentInterface.bInterfaceSubClass or ""
end
_G.get_InterfaceProtocol = function()
    return currentInterface.bInterfaceProtocol or ""
end

descTable[macro_defs.INTERFACE_DESC] = make_desc_parser("Interface", [[
    uint8_t  bLength;          // {format = "dec"}
    uint8_t  bDescriptorType;  // _G.get_descriptor_name
    uint8_t  bInterfaceNumber;
    uint8_t  bAlternateSetting;
    uint8_t  bNumEndpoints;
    uint8_t  bInterfaceClass;      // _G.get_InterfaceClass
    uint8_t  bInterfaceSubClass;   // _G.get_InterfaceSubClass
    uint8_t  bInterfaceProtocol;   // _G.get_InterfaceProtocol
    uint8_t  iInterface;
]])

descTable[macro_defs.ENDPOINT_DESC] = make_desc_parser("Endpoint", [[
    uint8_t  bLength;          // {format = "dec"}
    uint8_t  bDescriptorType;  // _G.get_descriptor_name
    // bEndpointAddress
    uint8_t  EndpointAddress:4;
    uint8_t  Reserved:3;
    uint8_t  Direction:1;     // {[0] ="OUT", [1]="IN"}
    // bmAttributes
    uint8_t  Type:2;          // {[0]="Control", [1]="Isochronous", [2]="Bulk", [3]="Interrupt"}
    uint8_t  SyncType:2       // {[0]="No Synchonisation", [1]="Asynchronous", [2]="Adaptive", [3]="Synchronous"}
    uint8_t  UsageType:2      // {[0]="Data Endpoint", [1]="Feedback Endpoint", [2]="Explicit Feedback Data Endpoint", [3]="Reserved"}
    uint8_t  PacketPerFrame:2;// {[0]="1", [1]="2", [2]="3", [3]="Reserved"}
    uint16_t wMaxPacketSize;
    uint8_t  bInterval;
]])

descTable[macro_defs.HID_DESC] = make_desc_parser("HID", [[
    struct{
        uint8_t bLength;
        uint8_t bDescriptorType;   // _G.get_descriptor_name
        uint16_t bcdHID;
        uint8_t  bCountryCode;
        uint8_t  bNumDescriptors;
        {
            uint8_t bDescriptorType;  // {[0x22] = "Report Descriptor", [0x33] = "Physical Descriptor"}
            uint16_t wDescriptorLength; // {format="dec"}
        }[bNumDescriptors];
    }
]])

descTable[macro_defs.IAD_DESC] = make_desc_parser("IAD", [[
    uint8_t  bLength;          // {format = "dec"}
    uint8_t  bDescriptorType;  // _G.get_descriptor_name
    uint8_t  bFirstInterface;
    uint8_t  bInterfaceCount;
    uint8_t  bFunctionClass;
    uint8_t  bFunctionSubClass;
    uint8_t  bFunctionProtocol;
    uint8_t  iFunction;
]])
 
function parser.parse(data, context)
    local info = {}
    local offset = 1
    local lastInterface = nil
    local lastIad = nil
    local lastIadCount = 0
    while offset < #data do
        local t = data:byte(offset+1)
        local desc = nil
        if lastInterface then
            local cls = context:find_class(lastInterface, lastIad)
            if cls and cls.descriptor_parser then
                desc = cls.descriptor_parser(data, offset, context)
            end
        end
        local parseFunc = descTable[t] or parse_unknown_desc
        if parseFunc then
            desc = desc or parseFunc(data, offset, context)
            if desc.bDescriptorType == macro_defs.INTERFACE_DESC then
                local cls = context:find_class(desc, lastIad)
                if cls and cls.get_name then
                    currentInterface = cls.get_name(desc, context)
                    desc = parseFunc(data, offset, context)
                    currentInterface = {}
                end
                lastInterface = desc

                if lastIadCount > 0 then
                    lastIadCount = lastIadCount - 1
                end
                if lastIadCount == 0 then
                    lastIad = nil
                end
            elseif desc.bDescriptorType == macro_defs.IAD_DESC then
                lastIad = desc
                lastIadCount = desc.bInterfaceCount
            end
            offset = offset + desc.bLength
            info.html = info.html or ""
            info.html = info.html .. desc.html
            info[#info+1] = desc
            if desc.bLength < 2 then
                break
            end
        end
    end
    --gotDescriptor(info, context)
    return info
end

package.loaded["usb_descriptor_parser"] = parser

