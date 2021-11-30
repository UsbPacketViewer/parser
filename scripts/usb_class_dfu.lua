-- usb_class_dfu.lua
-- protocol are defined at: https://usb.org/sites/default/files/DFU_1.1.pdf
-- qianfan Zhao <qianfanguijin@163.com>

local html = require("html")
require("usb_setup_parser")
require("usb_register_class")

local cls = {}
cls.name = "DFU"

local DFU_FUNCTIONAL_DESCRIPTOR = 0x21

local struct_dfu_functional_descriptor = html.create_struct([[
    struct {
        uint8_t  bLength;          // {format = "dec"}
        uint8_t  bDescriptorType;
        //bmAttributes;
        uint8_t  bitCanDnload:1;
        uint8_t  bitCanUpload:1;
        uint8_t  bitMainfestationTolerant:1;
        uint8_t  bitWillDetach:1;
        uint8_t  reserved:4;
        uint16_t wDetachtimeOut; // {format = "dec"}
        uint16_t wTransferSize; // {format = "dec"}
        uint16_t bcdDFUVersion;
    }]], {
        bDescriptorType = {
            [DFU_FUNCTIONAL_DESCRIPTOR] = "DFU FUNCTIONAL",
        }
    }
)

function cls.descriptor_parser(data, offset, context)
    local t = data:byte(offset+1)

    if t == DFU_FUNCTIONAL_DESCRIPTOR then
        local rawData = data:sub(offset)
        local res = struct_dfu_functional_descriptor:build(rawData, "DFU Functionnal Descriptor")
        res.rawData = rawData
        return res
    end
end

local DFU_DETACH        = 0
local DFU_DNLOAD        = 1
local DFU_UPLOAD        = 2
local DFU_GETSTATUS     = 3
local DFU_CLRSTATUS     = 4
local DFU_GETSTATE      = 5
local DFU_ABORT         = 6

local dfu_request_names = {
    [DFU_DETACH]    = "DFU_DETACH",
    [DFU_DNLOAD]    = "DFU_DNLOAD",
    [DFU_UPLOAD]    = "DFU_UPLOAD",
    [DFU_GETSTATUS] = "DFU_GETSTATUS",
    [DFU_CLRSTATUS] = "DFU_CLRSTATUS",
    [DFU_GETSTATE]  = "DFU_GETSTATE",
    [DFU_ABORT]     = "DFU_ABORT",
}

local dfu_request_wValue_render = {
    [DFU_DETACH] = html.create_field([[
        struct {
            // wValue
            uint16_t wTimeout:16; // {format = "dec"}
        }
    ]])[1],
    [DFU_DNLOAD] = html.create_field([[
        struct {
            // wValue
            uint16_t wBlockNum:16; // {format = "dec"}
        }
    ]])[1],
    [DFU_UPLOAD] = html.create_field([[
        struct {
            // wValue
            uint16_t wBlockNum:16; // {format = "dec"}
        }
    ]])[1],
}

function cls.parse_setup(setup, context)
    local cmd = setup.bRequest
    local name = dfu_request_names[cmd]

    if setup.recip ~= "Interface" or setup.type ~= "Class" or name == nil then
        return
    end

    setup.title = name
    setup.render.title = name
    setup.render.bRequest = name

    if cmd == DFU_DNLOAD or cmd == DFU_UPLOAD then
        setup.name = string.format("%d", setup.wValue)
    else
        setup.name = name
    end

    local wValue_render = dfu_request_wValue_render[setup.bRequest]
    if wValue_render then
        setup.render.wValue = wValue_render
    end
end

local struct_dfu_getstatus = html.create_struct([[
    struct {
        uint8_t  bStatus;
        uint24_t bwPollTimeout; // {format = "dec"}
        uint8_t  bState;
        uint8_t  iString;
    }]], {
        bStatus = {
            [0x00] = "OK",
            [0x01] = "errTARGET",
            [0x02] = "errFILE",
            [0x03] = "errWRITE",
            [0x04] = "errERASE",
            [0x05] = "errCHECK_ERASED",
            [0x06] = "errPROG",
            [0x07] = "errVERIFY",
            [0x08] = "errADDRESS",
            [0x09] = "errNOTDONE",
            [0x0a] = "errFIRMWARE",
            [0x0b] = "errVENDOR",
            [0x0c] = "errUSBR",
            [0x0d] = "errPOR",
            [0x0e] = "errUNKNOWN",
            [0x0f] = "errSTALLEDPKT",
        },
        bState = {
            [0x00] = "appIDLE",
            [0x01] = "appDETACH",
            [0x02] = "dfuIDLE",
            [0x03] = "dfuDNLOAD-SYNC",
            [0x04] = "dfuDNBUSY",
            [0x05] = "dfuDNLOAD-IDLE",
            [0x06] = "dfuMANIFEST-SYNC",
            [0x07] = "dfuMANIFEST",
            [0x08] = "dfuMANIFEST-WAIT-RESET",
            [0x09] = "dfuUPLOAD-IDLE",
            [0x0a] = "dfuERROR",
        },
    }
)

function dfu_dnload_parser(setup, data, context)
    return string.format("<h1>DFU Download Data</h1> \
                          Display in data window, size = %d",
                          setup.wLength)
end

function dfu_getstatus_parser(setup, data, context)
    return struct_dfu_getstatus:build(data, "DFU STATUS").html
end

local dfu_request_parsers = {
    [DFU_DNLOAD] = dfu_dnload_parser,
    [DFU_GETSTATUS] = dfu_getstatus_parser,
}

function cls.parse_setup_data(setup, data, context)
    local parser = dfu_request_parsers[setup.bRequest]

    if parser then
        return parser(setup, data, context)
    end
end

cls.bInterfaceClass     = 0xFE
cls.bInterfaceSubClass  = 0x01
cls.bInterfaceProtocol  = 0x02

function cls.get_name(desc, context)
    return {
        bInterfaceClass = "DFU",
        bInterfaceSubClass = "DFU",
        bInterfaceProtocol = "DFU",
    }
end

register_class_handler(cls)
package.loaded["usb_class_dfu"] = cls
