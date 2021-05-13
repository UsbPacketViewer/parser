-- usb_class_video.lua

-- a typical class has these functions
-- cls.parse_setup(setup, context),  update setup.html, setup.name field in setup, and return it
-- cls.parse_setup_data(setup, data, context)    return a html to describe the data
-- cls.on_transaction(self, param, data, needDetail, forceBegin)  return macro_defs.RES_xxx
-- cls.descriptor_parser(data, offset, context)   return a parsed descriptor
-- cls.get_name(descriptor, context)              return a field name table
-- Video class definition  https://www.usb.org/sites/default/files/USB_Video_Class_1_5.zip

local html = require("html")
local macro_defs = require("macro_defs")
local rndis = require("decoder_rndis")
local setup_parser = require("usb_setup_parser")
require("usb_register_class")

local fmt = string.format
local unpack = string.unpack
local cls = {}

local video_vs_desc_parser = {}
local video_vs_decoder = {}

local function install_decoder(decoder)
    for k,v in pairs(decoder.video_as) do
        assert(not video_vs_desc_parser[k], "Video Format already exist for " .. k)
        video_vs_desc_parser[k] = v
    end
    for k,v in pairs(decoder.video_decoder) do
        assert(not video_vs_decoder[k], "Video Decoder already exist for " .. k)
        video_vs_decoder[k] = v
    end
end
install_decoder( require("decoder_video_payload_mjpeg") )



local req2str = {
    [0x00] = "Undefined",
    [0x01] = "Set Cur",
    [0x11] = "Set Cur All",
    [0x81] = "Get Cur",
    [0x82] = "Get Min",
    [0x83] = "Get Max",
    [0x84] = "Get Res",
    [0x85] = "Get Len",
    [0x86] = "Get Info",
    [0x87] = "Get Def",
    [0x91] = "Get Cur All",
    [0x92] = "Get Min All",
    [0x93] = "Get Max All",
    [0x94] = "Get Res All",
    [0x87] = "Get Def All",
}

local field_wIndex_video = html.create_field([[
    struct{
        // wIndex
        uint16_t Itf_or_EP:8;
        uint16_t Entity_ID:8;
    }
]])

local field_wValue_video = html.create_field([[
    struct{
        // wValue
        uint16_t reserved:8;
        uint16_t selector:8;
    }
]])

local function video_setup_data_parser(name, info)
    local builder = html.create_struct(info)
    return function(data, offset, context)
        return builder:build(data:sub(offset), name)
    end
end

local video_request_data_parser = {
    [0x86] = video_setup_data_parser("Control Capabilities and Status",[[
        // bmCapabilities
        uint8_t D0:1; // Supports GET value requests
        uint8_t D1:1; // Supports SET value requests
        uint8_t D2:1; // Disabled due to automatic mode (under device control)
        uint8_t D3:1; // Autoupdate Control
        uint8_t D4:1; // Asynchronous Control
        uint8_t D5:1; // Disabled due to incompatibility with Commit state
        uint8_t reserved:2;
    ]])
}

local video_render_selector

function cls.parse_setup(setup, context)
    if (setup.recip ~= "Interface" and setup.recip ~= "Endpoint") or setup.type ~= "Class" then
        return
    end
    local bRequest_desc = req2str[setup.bRequest] or "Video Unknown"
    setup.name = bRequest_desc
    setup.title = "Video Request"
    setup.render.bRequest = bRequest_desc
    setup.render.wValue = field_wValue_video
    setup.render.wIndex = field_wIndex_video
    setup.render.title = "Video Request " .. bRequest_desc
    video_render_selector(setup, context)
end

function cls.parse_setup_data(setup, data, context)
    if setup.type == "Class" and video_request_data_parser[setup.bRequest] then
        return video_request_data_parser[setup.bRequest](data, 1, context).html
    end
    if setup.video_data_render then
        local res = setup.video_data_render(data)
        return res
    end
end

local function make_vc_interface(name, info)
    local builder = html.create_struct(info)
    return function(data, offset, context)
        return builder:build(data:sub(offset), "VC Interface " .. name .. " Descriptor")
    end
end
local function make_vs_interface(name, info)
    local builder = html.create_struct(info)
    return function(data, offset, context)
        return builder:build(data:sub(offset), "VS Interface " .. name .. " Descriptor")
    end
end
-- video terminal types
_G.video_terminal_types = {
    [0x0100] = "TT Vendor Specific",
    [0x0101] = "TT Stream",

    [0x0200] = "ITT Vendor Specific",
    [0x0201] = "ITT Camera",
    [0x0202] = "ITT Media Transport Input",

    [0x0300] = "OTT Vendor Specific",
    [0x0301] = "OTT Display",
    [0x0202] = "OTT Media Transport Output",

    [0x0400] = "External Vendor Specific",
    [0x0401] = "Composite Connector",                       
    [0x0402] = "SVideo Connector",
    [0x0403] = "Component Connector",                  
}

local video_vc_interface  = {
    [0x01] = make_vc_interface("Header", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;
        uint16_t  bcdUVC;
        uint16_t  wTotalLength;
        uint32_t  dwClockFrequency;  // function(x) return ""..x.."Hz" end
        uint8_t   bInCollection;
        {
            uint8_t baInterfaceNr;
        }[bInCollection];
    ]]),
    [0x02] = make_vc_interface("Input Terminal", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;
        uint8_t   bTerminalID;
        uint16_t  wTerminalType;       // _G.video_terminal_types
        uint8_t   bAssocTerminal;
        uint8_t   iTerminal;
        uint8_t   data[bLength-8];
    ]]),
    [0x03] = make_vc_interface("Output Terminal", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;
        uint8_t   bTerminalID;
        uint16_t  wTerminalType;       // _G.video_terminal_types
        uint8_t   bAssocTerminal;
        uint8_t   bSourceID;
        uint8_t   iTerminal;
        uint8_t   data[bLength-9];
    ]]),
    [0x04] = make_vc_interface("Selector Unit", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;
        uint8_t   bUnitID;
        uint8_t   bNrInPins;
        {
            uint8_t baSourceID;
        }[bNrInPins];
        uint8_t   iSelector;
    ]]),
    [0x05] = make_vc_interface("Processing Unit", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;
        uint8_t   bUnitID;
        uint8_t   bSourceID;
        uint16_t  wMaxMultiplier; // x 100
        uint8_t   bControlSize;
        uint8_t   bmControls[bControlSize];
        uint8_t   iProcessing;
        // bmVideoStandards
        uint8_t   None:1;
        uint8_t   NTSC_525:1;
        uint8_t   PAL_625:1;
        uint8_t   SECAM_625:1;
        uint8_t   NTSC_625:1;
        uint8_t   PAL_525:1;
        uint8_t   reserved:2;
    ]]),
    [0x06] = make_vc_interface("Extension Unit", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;
        uint8_t   bUnitID;
        uint8_t   guidExtensionCode[16];
        uint8_t   bNumControls;
        uint8_t   bNrInPins;
        {
            uint8_t baSourceID;
        }[bNrInPins];
        uint8_t   bControlSize;
        uint8_t   bmControls[bControlSize];
        uint8_t   iExtension;
    ]]),
    [0x07] = make_vc_interface("Encoding Unit", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;
        uint8_t   bUnitID;
        uint8_t   bSourceID;
        uint8_t   iEncoding;
        uint8_t   bControlSize;
        uint8_t   bmControls[bControlSize];
        uint8_t   mControlsRuntime[bControlSize];
    ]]),
}

local video_vs_interface  = {
    [0x01] = make_vs_interface("Input Header", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;
        uint8_t   bNumFormats;
        uint16_t  wTotalLength;
        // bEndpointAddress;
        uint8_t   endpoint:4;
        uint8_t   reserved1:3;
        uint8_t   direction:1;
        // bmInfo
        uint8_t   dynamic_changed_support:1;
        uint8_t   reserved2:7;
        uint8_t   bTerminalLink;
        uint8_t   bStillCaptureMethod;
        uint8_t   bTriggerSupport; // {[0] = "Not supported", [1] = "Supported"}
        uint8_t   bTriggerUsage; // {[0] = "Initiate still image capture", [1] = "General purpose button event"}
        uint8_t   bControlSize;
        {
            uint8_t bmaControls[bControlSize];
        }[bNumFormats];
    ]]),

    [0x02] = make_vs_interface("Output Header", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;
        uint8_t   bNumFormats;
        uint16_t  wTotalLength;
        // bEndpointAddress;
        uint8_t   endpoint:4;
        uint8_t   reserved1:3;
        uint8_t   direction:1;
        uint8_t   bTerminalLink;
        uint8_t   bControlSize;
        {
            uint8_t bmaControls[bControlSize];
        }[bNumFormats];
    ]]),

    [0x03] = make_vs_interface("Still Image Frame", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;
        uint8_t   bNumFormats;
        uint16_t  wTotalLength;
        // bEndpointAddress;
        uint8_t   endpoint:4;
        uint8_t   reserved1:3;
        uint8_t   direction:1;
        uint8_t   bNumImageSizePatterns;
        {
            uint16_t wWidth;
            uint16_t wHeight;
        }[bNumImageSizePatterns];
        uint8_t   bNumCompressionPattern;
        {
            uint8_t bCompression;
        }[bNumCompressionPattern];
    ]]),

    [0x0d] = make_vs_interface("Color Matching", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;
        uint8_t   bColorPrimaries; // {[0] = "Unspecified", [1] = "BT.709, sRGB", [2] = "BT.470-2 (M)", [3] = "BT.470-2 (B,G)", [4] = "SMPTE 170M", [5] = "SMPTE 240M"}
        uint8_t   bTransferCharacteristics; // {[0] = "Unspecified", [1] = "BT.709", [2] = "BT.470-2 (M)", [3] = "BT.470-2 (B,G)", [4] = "SMPTE 170M", [5] = "SMPTE 240M", [6] = "Linear (V = Lc)", [7] = "sRGB"}
        uint8_t   bMatrixCoefficients; // {[0] = "Unspecified", [1] = "BT.709", [2] = "FCC", [3] = "BT.470-2 (B,G)", [4] = "SMPTE 170M", [5] = "SMPTE 240M"}
    ]]),
}

local struct_cs_video_data_endpoint = html.create_struct([[
    uint8_t   bLength;
    uint8_t   bDescriptorType;      // CS_ENDPOINT
    uint8_t   bDescriptorSubtype;   // {[0] = "EP_UNDEFINED", [1] = "EP_GENERAL", [2] = "EP_ENDPOINT", [3] = "EP_INTERRUPT"}
    uint16_t   wMaxTransferSize;
]])

local selector_map = {}
selector_map[0x00] = {
    name = "Interface Control",
    wValue = [[
        struct{
            // wValue
            uint16_t zero:8;
            uint16_t selector:8;
        }
    ]],
    wIndex = [[
        struct{
            // wIndex
            uint16_t interface:8;
            uint16_t zero:8;
        }
    ]],
    wValue_info = {
        selector = {
            [0x01] = "VC_VIDEO_POWER_MODE_CONTROL",
            [0x02] = "VC_REQUEST_ERROR_CODE_CONTROL",
        }
    },
    data = function(setup)
        local sel = setup.wValue >> 8
        local info = ""
        local name = ""
        if sel == 1 then
            info = [[
                // bDevicePowerMode
                uint8_t Power_Mode:4; // {[0] = "Full power mode", [1] = "device dependent power mode"}
                uint8_t Device_dependent:1;
                uint8_t USB_Power:1;
                uint8_t Battery_Power:1;
                uint8_t AC_Power:1;
            ]]
            name = "Power Mode Control"
        elseif sel == 2 then
            info = [[uint8_t  bRequestErrorCode; // {[0] = "No error",[1]="Not Ready",[2]="Wrong state",[3]="Power",[4]="Out of range",[5]="Invalid unit",[6]="Invalid Control",[7]="Invalid Request",[8]="Invalid Range",[0xff]="Unknown"}]]
            name = "Request Error Code Control"
        end
        return function(data)
            return html.create_struct("struct {\n" .. info .. "\n}"):build(data, name).html
        end
    end
}

local camera_control = {
    [0x01] = {
        "Scanning Mode Control",
        [[uint8_t bScanningMode; // {[0] = "Interlaced", [1] = "Progressive"}]],
    },
    [0x02] = {
        "Auto-Exposure Mode Control",
        [[
            // bAutoExposureMode;
            uint8_t D0:1;        // Manual Mode
            uint8_t D1:1;        // Audo Mode
            uint8_t D2:1;        // Shutter Priority Mode
            uint8_t D3:1;        // Aperture Priority Mode
            uint8_t reserved:4;
        ]],
    },
    [0x03] = {
        "Auto-Exposure Priority Control",
        [[uint8_t bScanningMode; ]],
    },
    [0x04] = {
        "Exposure Time (Absolute) Control",
        [[uint32_t dwExposureTimeAbsolute; // {format = "dec", comment = " x 0.0001 sec"}]],
    },
    [0x05] = {
        "Exposure Time (Relative) Control",
        [[int8_t bExposureTimeRelative; // step ]],
    },
    [0x06] = {
        "Focus (Absolute) Control",
        [[uint16_t wFocusAbsolute; ]],
    },
    [0x07] = {
        "Focus (Relative) Control",
        [[int8_t bFocusRelative;
          uint8_t bSpeed;
        ]],
    },
    [0x08] = {
        "Focus, Auto Control",
        [[uint8_t bFocusAuto; ]],
    },
    [0x09] = {
        "Iris (Absolute) Control",
        [[uint16_t wIrisAbsolute; ]],
    },
    [0x0A] = {
        "Iris (Relative) Control",
        [[int8_t bIrisRelative; ]],
    },
    [0x0B] = {
        "Zoom (Absolute) Control",
        [[uint16_t wObjectiveFocalLength; ]],
    },
    [0x0C] = {
        "Zoom (Relative) Control",
        [[uint8_t bZoom; // {[0]="Stop", [1]="moving to telephoto direction", [0xff] = "moving to wide-angle direction"}
        uint8_t bDigitalZoom; // {[0] = "OFF", [1] = "ON"}
        uint8_t bSpeed;
         ]],
    },
    [0x0D] = {
        "PanTilt (Absolute) Control",
        [[int32_t dwPanAbsolute;
          int32_t dwTiltAbsolute;
         ]],
    },
    [0x0E] = {
        "PanTilt (Relative) Control",
        [[int8_t bPanRelative;
        uint8_t bPanSpeed;  // {format="dec"}
        int8_t bTiltRelative;
        uint8_t bTiltSpeed; // {format="dec"}
        ]],
    },
    [0x0F] = {
        "Roll (Absolute) Control",
        [[int16_t wRollAbsolute; ]],
    },
    [0x10] = {
        "Roll (Relative) Control",
        [[int8_t bRollRelative;
          uint8_t bRolSpeed;  // {format="dec"}
        ]],
    },
    [0x11] = {
        "Privacy Control",
        [[uint8_t bPrivacy; // {[0] = "Open", [1] = "Close"} ]],
    },
    [0x12] = {
        "Focus, Simple Range Control",
        [[uint8_t bFocus; // {[0]="Full range",[1]="macro",[2]="people",[3]="scene"}]],
    },
    [0x13] = {
        "Digital Window Control",
        [[uint16_t wWindow_Top; 
        uint16_t wWindow_Left; 
        uint16_t wWindow_Bottom; 
        uint16_t wWindow_Right; 
        uint16_t wNumSteps;
        // bmNumStepsUnits
        uint16_t D0:1;  // video frames
        uint16_t D1:1;  // milliseconds
        uint16_t  reserved:14;
        ]],
    },
    [0x14] = {
        "Digital Region of Interest (ROI) Control",
        [[uint16_t wROI_Top; 
        uint16_t wROI_Left; 
        uint16_t wROI_Bottom; 
        uint16_t wROI_Right; 
        // bmAutoControls
        uint16_t D0:1; // Auto Exposure
        uint16_t D1:1; // Auto Iris
        uint16_t D2:1; // Auto White Balance
        uint16_t D3:1; // Auto Focus
        uint16_t D4:1; // Auto Face Detect
        uint16_t D5:1; // Auto Detect and Track
        uint16_t D6:1; // Image Stabilization
        uint16_t D7:1; // Higher Quality
        uint16_t reserved:8;
        ]],
    },
}

selector_map[0x02] = {
    name = "Terminal Control",
    wValue = [[
        struct{
            // wValue
            uint16_t zero:8;
            uint16_t selector:8;
        }
    ]],
    wIndex = [[
        struct{
            // wIndex
            uint16_t interface:8;
            uint16_t terminal_id:8;
        }
    ]],
    wValue_info = {
        -- only camera need selectors
        selector = {
            [0x01] = "CT_SCANNING_MODE_CONTROL",
            [0x02] = "CT_AE_MODE_CONTROL",
            [0x03] = "CT_AE_PRIORITY_CONTROL",
            [0x04] = "CT_EXPOSURE_TIME_ABSOLUTE_CONTROL",
            [0x05] = "CT_EXPOSURE_TIME_RELATIVE_CONTROL",
            [0x06] = "CT_FOCUS_ABSOLUTE_CONTROL",
            [0x07] = "CT_FOCUS_RELATIVE_CONTROL",
            [0x08] = "CT_FOCUS_AUTO_CONTROL",
            [0x09] = "CT_IRIS_ABSOLUTE_CONTROL",
            [0x0A] = "CT_IRIS_RELATIVE_CONTROL",
            [0x0B] = "CT_ZOOM_ABSOLUTE_CONTROL",
            [0x0C] = "CT_ZOOM_RELATIVE_CONTROL",
            [0x0D] = "CT_PANTILT_ABSOLUTE_CONTROL",
            [0x0E] = "CT_PANTILT_RELATIVE_CONTROL",
            [0x0F] = "CT_ROLL_ABSOLUTE_CONTROL",
            [0x10] = "CT_ROLL_RELATIVE_CONTROL",
            [0x11] = "CT_PRIVACY_CONTROL",
            [0x12] = "CT_FOCUS_SIMPLE_CONTROL",
            [0x13] = "CT_WINDOW_CONTROL",
            [0x14] = "CT_REGION_OF_INTEREST_CONTROL",
        }
    },
    data = function(setup)
        local sel = setup.wValue >> 8
        local name = "Ternminal Control Data"
        local info = ""
        local t = camera_control[sel]
        if t then
            name = t[1] .. " Data"
            info = t[2]
        end
        return function(data)
            return html.create_struct("struct {\n" .. info .. "\n}"):build(data, name).html
        end
    end
}
selector_map[0x03] = selector_map[0x02]
selector_map[0x04] = {
    name = "Selector Unit Control",
    wValue = [[
        struct{
            // wValue
            uint16_t zero:8;
            uint16_t selector:8;
        }
    ]],
    wIndex = [[
        struct{
            // wIndex
            uint16_t interface:8;
            uint16_t terminal_id:8;
        }
    ]],
    wValue_info = {
        selector = {
            [1] = "SU_INPUT_SELECT_CONTROL"
        }
    },
    data = function(setup)
        local sel = setup.wValue >> 8
        local name = "Selector Unit Control Data"
        local info = ""
        if sel == 1 then
            info = [[ uint8_t bSelector; ]]
        end
        return function(data)
            return html.create_struct("struct {\n" .. info .. "\n}"):build(data, name).html
        end
    end
}

local process_unit_control = {
    [0x01] = { "Backlight Compensation Control", [[ uint16_t wBacklightCompensation; ]], }, 
    [0x02] = { "Brightness Control",             [[ int16_t wBrightness; ]], }, 
    [0x03] = { "Contrast Control",               [[ uint16_t wContrast; ]], }, 
    [0x04] = { "Gain Control",                   [[ uint16_t wGain; ]], }, 
    [0x05] = { "Power Line Frequency Control",   [[ uint8_t bPowerLineFrequency; // {[0]="Disabled",[1]="50Hz",[2]="60Hz",[3]="auto"}]], }, 
    [0x06] = { "Hue Control",                    [[ int16_t wHue; ]], }, 
    [0x07] = { "Saturation Control",             [[ uint16_t wSaturation; ]], }, 
    [0x08] = { "Sharpness Control",              [[ uint16_t wSharpness; ]], }, 
    [0x09] = { "Gamma Control",                     [[ uint16_t wGamma; ]], }, 
    [0x0A] = { "White Balance Temperature Control", [[ uint16_t wWhiteBalanceTemperature; ]], }, 
    [0x0B] = { "White Balance Temperature, Auto Control", [[ uint8_t bWhiteBalanceTemperatureAuto; ]], }, 
    [0x0C] = { "White Balance Component Control", [[ uint16_t wWhiteBalanceBlue;
                                                     uint16_t wWhiteBalanceRed; ]], }, 
    [0x0D] = { "White Balance Component, Auto Control", [[ uint8_t bWhiteBalanceComponentAuto; ]], }, 
    [0x0E] = { "Digital Multiplier Control",     [[ uint16_t wMultiplierStep; ]], }, 
    [0x0F] = { "Digital Multiplier Limit Control", [[ uint16_t wMultiplierLimit; ]], }, 
    [0x10] = { "Hue, Auto Control",              [[ uint8_t bHueAuto; ]], }, 
    [0x11] = { "Analog Video Standard Control", [[ uint8_t bVideoStandard; //{[0]="none",[1]="NTSC-525/60",[2]="PAL-625/50", [3]="SECAM – 625/50", [4]="NTSC – 625/50", [5]="PAL – 525/60"} ]], }, 
    [0x12] = { "Analog Video Lock Status Control", [[ uint8_t bStatus; // {[0]="Locked", [1]= "Not Locked"} ]], }, 
    [0x13] = { "Contrast, Auto Control",         [[ uint8_t bContrastAuto; ]], }, 
}

selector_map[0x05] = {
    name = "Processing Unit Control",
    wValue = [[
        struct{
            // wValue
            uint16_t zero:8;
            uint16_t selector:8;
        }
    ]],
    wIndex = [[
        struct{
            // wIndex
            uint16_t interface:8;
            uint16_t unit_id:8;
        }
    ]],
    wValue_info = {
        selector = {
            [0x01] = "PU_BACKLIGHT_COMPENSATION_CONTROL ",
            [0x02] = "PU_BRIGHTNESS_CONTROL ",
            [0x03] = "PU_CONTRAST_CONTROL ",
            [0x04] = "PU_GAIN_CONTROL ",
            [0x05] = "PU_POWER_LINE_FREQUENCY_CONTROL ",
            [0x06] = "PU_HUE_CONTROL ",
            [0x07] = "PU_SATURATION_CONTROL ",
            [0x08] = "PU_SHARPNESS_CONTROL ",
            [0x09] = "PU_GAMMA_CONTROL ",
            [0x0A] = "PU_WHITE_BALANCE_TEMPERATURE_CONTROL ",
            [0x0B] = "PU_WHITE_BALANCE_TEMPERATURE_AUTO_CONTROL ",
            [0x0C] = "PU_WHITE_BALANCE_COMPONENT_CONTROL ",
            [0x0D] = "PU_WHITE_BALANCE_COMPONENT_AUTO_CONTROL ",
            [0x0E] = "PU_DIGITAL_MULTIPLIER_CONTROL ",
            [0x0F] = "PU_DIGITAL_MULTIPLIER_LIMIT_CONTROL ",
            [0x10] = "PU_HUE_AUTO_CONTROL ",
            [0x11] = "PU_ANALOG_VIDEO_STANDARD_CONTROL ",
            [0x12] = "PU_ANALOG_LOCK_STATUS_CONTROL ",
            [0x13] = "PU_CONTRAST_AUTO_CONTROL ",
        }
    },
    data = function(setup)
        local sel = setup.wValue >> 8
        local name = "Processing Unit Control Data"
        local info = ""
        local t = process_unit_control[sel]
        if t then
            name = t[1] .. " Data"
            info = t[2]
        end
        return function(data)
            return html.create_struct("struct {\n" .. info .. "\n}"):build(data, name).html
        end
    end
}

local encode_unit_control = {
    [0x01] = { "Select Layer Control",  [[ uint16_t  wLayerOrViewID; ]] },
    [0x02] = { "Profile and Toolset Control",  
    [[uint16_t  wProfile; 
    uint16_t wConstrainedToolset;
    uint8_t bmSettings;]] },
    [0x03] = { "Video Resolution Control", 
    [[uint16_t  wWidth;
    uint16_t  wHeight; ]] },
    [0x04] = { "Minimum Frame Interval Control",  [[ uint32_t  dwFrameInterval;  // 100ns ]] },
    [0x05] = { "Slice Mode Control",  
    [[uint16_t  wSliceMode;
    uint16_t wSliceConfigSetting ]] },
    [0x06] = { "Rate Control Mode Control",  [[ uint8_t  bRateControlMode; // [0] = "Reserved", [1] = "Variable Bit Rate low delay (VBR)", [2] = "Constant bit rate (CBR)", [3] = "Constant QP", [4] = "Global VBR low delay (GVBR)", [5] = "Variable bit rate non-low delay (VBRN)", [6] = "Global VBR non-low delay (GVBRN)"]] },
    [0x07] = { "Average Bit Rate Control",  [[ uint32_t  dwAverageBitRate; ]] },
    [0x08] = { "CPB Size Control",  [[ uint32_t  dwCPBsize; // 16 bits]] },
    [0x09] = { "Peak Bit Rate Control",  [[ uint32_t  dwPeakBitRate; // 64 bits/s ]] },
    [0x0A] = { "Quantization Parameter Control", 
    [[uint16_t  wQpPrime_I;
    uint16_t  wQpPrime_P;
    uint16_t  wQpPrime_B;]] },
    [0x0B] = { "Synchronization and Long Term Reference Frame Control", 
    [[uint8_t  bSyncFrameType;
    uint16_t  wSyncFrameInterval;
    uint8_t  bGradualDecoderRefresh; ]] },
    [0x0C] = { "Long-Term Buffer Control",  [[ uint8_t  bNumHostControlLTRBuffers;
    uint8_t  bTrustMode; ]] },
    [0x0D] = { "Long-Term Reference Picture Control",  [[ uint8_t  bPutAtPositionInLTRBuffer;
    uint8_t  bLTRMode; ]] },
    [0x0E] = { "Long-Term Reference Validation Control",  [[ uint16_t  bmValidLTRs; ]] },
    [0x0F] = { "Level IDC Control",  [[ uint8_t  bLevelIDC; ]] },
    [0x10] = { "SEI Messages Control",  [[ uint32_t  bmSEIMessages1;
    uint32_t bmSEIMessages2; ]] },
    [0x11] = { "Quantization Parameter Range Control", 
    [[uint8_t  bMinQp;
    uint8_t  bMaxQp; ]] },
    [0x12] = { "Priority Control",  [[ uint8_t  bPriority; ]] },
    [0x13] = { "Start or Stop Layer Control",  [[ uint8_t  bUpdate; ]] },
    [0x14] = { "Error Resiliency Control",  [[ uint16_t  bmErrorResiliencyFeatures; ]] },
}

selector_map[0x07] = {
    name = "Encoding Unit Control",
    wValue = [[
        struct{
            // wValue
            uint16_t zero:8;
            uint16_t selector:8;
        }
    ]],
    wIndex = [[
        struct{
            // wIndex
            uint16_t interface:8;
            uint16_t unit_id:8;
        }
    ]],
    wValue_info = {
        selector = {
            [0x01] = "EU_SELECT_LAYER_CONTROL ",
            [0x02] = "EU_PROFILE_TOOLSET_CONTROL ",
            [0x03] = "EU_VIDEO_RESOLUTION_CONTROL ",
            [0x04] = "EU_ MIN_FRAME_INTERVAL_CONTROL ",
            [0x05] = "EU_ SLICE_MODE_CONTROL ",
            [0x06] = "EU_RATE_CONTROL_MODE_CONTROL ",
            [0x07] = "EU_AVERAGE_BITRATE_CONTROL ",
            [0x08] = "EU_CPB_SIZE_CONTROL ",
            [0x09] = "EU_PEAK_BIT_RATE_CONTROL ",
            [0x0A] = "EU_QUANTIZATION_PARAMS_CONTROL ",
            [0x0B] = "EU_SYNC_REF_FRAME_CONTROL ",
            [0x0C] = "EU_LTR_BUFFER_ CONTROL ",
            [0x0D] = "EU_LTR_PICTURE_CONTROL ",
            [0x0E] = "EU_LTR_VALIDATION_CONTROL ",
            [0x0F] = "EU_LEVEL_IDC_LIMIT_CONTROL ",
            [0x10] = "EU_SEI_PAYLOADTYPE_CONTROL ",
            [0x11] = "EU_QP_RANGE_CONTROL ",
            [0x12] = "EU_PRIORITY_CONTROL ",
            [0x13] = "EU_START_OR_STOP_LAYER_CONTROL ",
            [0x14] = "EU_ERROR_RESILIENCY_CONTROL ",
        }
    },
    data = function(setup)
        local sel = setup.wValue >> 8
        local name = "Encoding Control Data"
        local info = ""
        local t = encode_unit_control[sel]
        if t then
            name = t[1] .. " Data"
            info = t[2]
        end
        return function(data)
            return html.create_struct("struct {\n" .. info .. "\n}"):build(data, name).html
        end
    end
}


selector_map[0x06] = {
    name = "Extension Unit Control",
    wValue = [[
        struct{
            // wValue
            uint16_t zero:8;
            uint16_t selector:8;
        }
    ]],
    wIndex = [[
        struct{
            // wIndex
            uint16_t interface:8;
            uint16_t unit_id:8;
        }
    ]],
    wValue_info = {
        selector = {
            [0x01] = "XU_ENABLE_CONTROL",
        }
    },
    data = function(setup)
        return function(data)
            return html.create_struct([[
            ]]):build(data, "Extension Control Data").html
        end
    end
}

local vs_interface_control = {}
vs_interface_control[1] = {
    "VS Probe Control",
    [[
        // bmHint
        uint16_t D0:1; // dwFrameInterval
        uint16_t D1:1; // wKeyFrameRate
        uint16_t D2:1; // wPFrameRate
        uint16_t D3:1; // wCompQuality
        uint16_t D4:1; // wCompWindowSize
        uint16_t reserved:11;
        uint8_t  bFormatIndex;
        uint8_t  bFrameIndex;
        uint32_t dwFrameInterval; // { format = "dec", comment= "100ns"}
        uint16_t wKeyFrameRate;   // { format = "dec", comment= "Key frame rate in key-frame per video-frame units"}
        uint16_t wPFrameRate;     // { format = "dec", comment= "PFrame rate in PFrame/key frame units"}
        uint16_t wCompQuality;
        uint16_t wCompWindowSize;
        uint16_t wDelay;
        uint32_t dwMaxVideoFrameSize; // {format = "dec"}
        uint32_t dwMaxPayloadTransferSize; // {format = "dec"}
        uint32_t dwClockFrequency; // {format = "dec", comment = "Hz"}
        // bmFramingInfo
        uint8_t  D0:1;   // require Frame ID
        uint8_t  D1:1;   // require End of Frame
        uint8_t  D2:1;   // require End of Slice
        uint8_t  reserved2:5;
        uint8_t  bPreferedVersion; 
        uint8_t  bMinVersion;
        uint8_t  bMaxVersion;
        uint8_t  bUsage; // {format = "dec"}
        uint8_t  bBitDepthLuma;
        uint8_t  bmSettings;
        uint8_t  bMaxNumberOfRefFramesPlus1;
        // bmRateControlModes
        uint16_t First:4;  // {[0] = "Not applicable", [1] = "VBR with underflow allowed", [2] = "CBR", [3] = "Constant QP", [4] = "Global VBR, underflow allowed", [5] = "VBR without underflow", [6] = "Global VBR without underflow"}
        uint16_t Second:4; // {[0] = "Not applicable", [1] = "VBR with underflow allowed", [2] = "CBR", [3] = "Constant QP", [4] = "Global VBR, underflow allowed", [5] = "VBR without underflow", [6] = "Global VBR without underflow"}
        uint16_t Third:4;  // {[0] = "Not applicable", [1] = "VBR with underflow allowed", [2] = "CBR", [3] = "Constant QP", [4] = "Global VBR, underflow allowed", [5] = "VBR without underflow", [6] = "Global VBR without underflow"}
        uint16_t fourth:4; // {[0] = "Not applicable", [1] = "VBR with underflow allowed", [2] = "CBR", [3] = "Constant QP", [4] = "Global VBR, underflow allowed", [5] = "VBR without underflow", [6] = "Global VBR without underflow"}
        {
            uint16_t bmLayoutPerStream;
        }[4];
    ]]
}
vs_interface_control[2] = {"VS Commit Control", vs_interface_control[1][2]}
vs_interface_control[3] = {"VS Still Probe Control", [[
    uint8_t  bFormatIndex;
    uint8_t  bFrameIndex;
    uint8_t  bCompressionIndex;
    uint32_t dwMaxVideoFrameSize; // {format = "dec"}
    uint32_t dwMaxPayloadTransferSize; // {format = "dec"}
]]}
vs_interface_control[4] = {"VS Still Commit Control", vs_interface_control[3][2]}

vs_interface_control[5] = {"Still Image Trigger Control", [[
    uint8_t bTrigger; // {[0]="Normal operation", [1]="Transmit still image", [2] = "Transmit still image via dedicated bulk pipe", [3] = "Abort still image transmission"}
]]}
vs_interface_control[6] = {"Stream Error Code Control", [[
    uint8_t bStreamErrorCode; // {[0] ="No Error", [1]="Protected content",[2]="Input buffer underrun",[3]="Data discontinuity",[4]="Output buffer underrun",[5]="Output buffer overrun",[6]="Format change",[7]="Still image capture error"}
]]}

vs_interface_control[7] = {"Generate Key Frame Control", [[
    uint8_t  bGenerateKeyFrame; // {[0]="Normal operation", [1]="Generate Key Frame"}
]]}

vs_interface_control[8] = {"Update Frame Segment Control", [[
    uint8_t bStartFrameSegment;
    uint8_t bEndFrameSegment;
]]}
vs_interface_control[9] = {"Synch Delay Control", [[
    uint16_t  wDelay; // {format="dec", comment="ms"}
]]}


local stream_interface_control = {
    name = "Video Stream Interface Control",
    wValue = [[
        struct{
            // wValue
            uint16_t zero:8;
            uint16_t selector:8;
        }
    ]],
    wIndex = [[
        struct{
            // wIndex
            uint16_t interface:8;
            uint16_t zero:8;
        }
    ]],
    wValue_info = {
        selector = {
            [0x01] = "VS_PROBE_CONTROL ",
            [0x02] = "VS_COMMIT_CONTROL ",
            [0x03] = "VS_STILL_PROBE_CONTROL ",
            [0x04] = "VS_STILL_COMMIT_CONTROL ",
            [0x05] = "VS_STILL_IMAGE_TRIGGER_CONTROL ",
            [0x06] = "VS_STREAM_ERROR_CODE_CONTROL ",
            [0x07] = "VS_GENERATE_KEY_FRAME_CONTROL ",
            [0x08] = "VS_UPDATE_FRAME_SEGMENT_CONTROL ",
            [0x09] = "VS_SYNCH_DELAY_CONTROL ",
        }
    },
    data = function(setup)
        local sel = setup.wValue >> 8
        local name = "Video Stream Interface Control Data"
        local info = ""
        local t = vs_interface_control[sel]
        if t then
            name = t[1] .. " Data"
            info = t[2]
        end
        return function(data)
            return html.create_struct("struct {\n" .. info .. "\n}"):build(data, name).html
        end
    end
}

video_render_selector = function(setup, context)
    local s = nil
    if setup.type == "Class" and setup.recip == "Endpoint"  then
        --setup.video_data_render = nil
        --s = ep_control_selector_map
    end
    if not s then
        local id = setup.wIndex >>8
        local itf = setup.wIndex & 0xff
        local itf_data = context:get_interface_data(itf)
        setup.video_data_render = nil
        if itf_data.video_selector and itf_data.video_selector[id] then
            s = itf_data.video_selector[id]
        end
    end
    if s then
        setup.render.wValue = html.create_field(s.wValue, s.wValue_info)
        setup.render.wIndex = html.create_field(s.wIndex)
        setup.render.title = setup.render.title .. " (" .. s.name .. ")"
        setup.video_data_render = s.data(setup)
    end
end

local function vc_parse_selector(data, offset, context)
    local t = data:byte(offset + 1)
    local subType = data:byte(offset + 2)
    local id = data:byte(offset + 3)
    local processType = data:byte(offset + 4)
    local itf_data = context:current_interface_data()
    itf_data.video_selector = itf_data.video_selector or {}

    if subType > 1 then
        if selector_map[subType] then
            itf_data.video_selector[id] = selector_map[subType]
        end
    else
        itf_data.video_selector[0] = selector_map[0]
    end
end

local function vs_parse_selector(data, offset, context)
    local t = data:byte(offset + 1)
    local subType = data:byte(offset + 2)
    if subType == 1 then
        --format = data:byte(offset+5) + data:byte(offset+6) * 256
        local itf_data = context:current_interface_data()
        itf_data.video_selector = itf_data.video_selector or {}
        itf_data.video_selector[0] = stream_interface_control
    end
end

local function vs_descriptpr_parser(data, offset, context)
    local len = data:byte(offset)
    if #data < offset+len then return end
    local t = data:byte(offset + 1)
    local subType = data:byte(offset + 2)
    if t == macro_defs.CS_ENDPOINT then
        return struct_cs_video_data_endpoint:build(data:sub(offset), "CS Endpoint Descriptor")
    end
    if t ~= macro_defs.CS_INTERFACE then
        return nil
    end
    vs_parse_selector(data, offset, context)
    if video_vs_desc_parser[subType] then
        if video_vs_decoder[subType] then
            context:current_interface_data().video_frame_decoder = video_vs_decoder[subType]
        end
    end
    local parser = video_vs_interface[subType] or video_vs_desc_parser[subType]
    return  parser and parser(data, offset, context)
end

local function vc_descriptor_parser(data, offset, context)
    local len = data:byte(offset)
    if #data < offset+len then return end
    local t = data:byte(offset + 1)
    local subType = data:byte(offset + 2)
    if t ~= macro_defs.CS_INTERFACE then
        return nil
    end
    vc_parse_selector(data, offset, context)
    return video_vc_interface[subType] and video_vc_interface[subType](data, offset, context)
end

local struct_vs_header  = {
    html.create_struct([[
    uint8_t  bHeaderLength;
    // bmHeaderInfo
    uint8_t  Frame_ID:1;
    uint8_t  End_Of_Frame:1;
    uint8_t  Presentation_Time:1;
    uint8_t  Source_Clock:1;
    uint8_t  Payload_Specific:1;
    uint8_t  Still_Image:1;
    uint8_t  Error:1;
    uint8_t  End_Of_Header:1;
]]),
    html.create_struct([[
    uint8_t  bHeaderLength;
    // bmHeaderInfo
    uint8_t  Frame_ID:1;
    uint8_t  End_Of_Frame:1;
    uint8_t  Presentation_Time:1;
    uint8_t  Source_Clock:1;
    uint8_t  Payload_Specific:1;
    uint8_t  Still_Image:1;
    uint8_t  Error:1;
    uint8_t  End_Of_Header:1;
    uint32_t dwPresentationTime;
]]),

    html.create_struct([[
    uint8_t  bHeaderLength;
    // bmHeaderInfo
    uint8_t  Frame_ID:1;
    uint8_t  End_Of_Frame:1;
    uint8_t  Presentation_Time:1;
    uint8_t  Source_Clock:1;
    uint8_t  Payload_Specific:1;
    uint8_t  Still_Image:1;
    uint8_t  Error:1;
    uint8_t  End_Of_Header:1;
    uint32_t dwSourceClock;
    uint16_t SOF:11;
    uint16_t reserved:5;
]]),

    html.create_struct([[
    uint8_t  bHeaderLength;
    // bmHeaderInfo
    uint8_t  Frame_ID:1;
    uint8_t  End_Of_Frame:1;
    uint8_t  Presentation_Time:1;
    uint8_t  Source_Clock:1;
    uint8_t  Payload_Specific:1;
    uint8_t  Still_Image:1;
    uint8_t  Error:1;
    uint8_t  End_Of_Header:1;
    uint32_t dwPresentationTime;
    uint32_t dwSourceClock;
    uint16_t SOF:11;
    uint16_t reserved:5;
]])
}
local function parse_vs_payload(data)
    if #data < 2 then
        return "<h1>Video Stream</h1>"
    end
    local t = (data:byte(2) >> 2) & 0x03
    local html = struct_vs_header[t+1]:build(data, "Video Stream Payload Header").html
    return html
end

local function data_on_transaction(self, param, data, needDetail, forceBegin)
    local addr, ep, pid, ack = param:byte(1), param:byte(2), param:byte(3), param:byte(4)
    local context = self:get_context(needDetail, pid)
    self.addr = addr
    context.data = context.data or ""
    if forceBegin then
        context.data = ""
    end
    local endMark    = self.upv:is_short_packet(addr, ep, data) and macro_defs.RES_END or macro_defs.RES_NONE
    local begindMark = #context.data == 0 and macro_defs.RES_BEGIN or macro_defs.RES_NONE

    local res = endMark | begindMark
    if res == macro_defs.RES_NONE then res = macro_defs.RES_MORE end

    if #data > 2 then
        local header_len = data:byte(1)
        context.data = context.data .. data:sub(header_len + 1)
    end

    if needDetail then
        --context.data = (context.data or "") .. data
        context.status = "incomp"
        context.title = "Video Frame"
        context.name = "Video Format"
        context.desc = "Unknown"
        context.infoHtml = ""
        if endMark == macro_defs.RES_END then
            local t = self:get_endpoint_interface_data(addr, ep)
            context.infoHtml  =  "<h1>Video Frame</h1>"
            context.status = "success"
            if t.video_frame_decoder then
                context.desc = t.video_frame_decoder.name
                context.infoHtml = t.video_frame_decoder.decode(context.data, self)
            end
        end
        local xfer_res = self.upv.make_xfer_res(context)
        if endMark == macro_defs.RES_END then
            context.data = ""
        end
        return res, self.upv.make_xact_res("Video Stream", parse_vs_payload(data), data), xfer_res
    end
    if endMark ~= 0 then
        context.data = ""
    end
    return res
end

local struct_vc_status = html.create_struct([[
    uint8_t   bStatusType; // {[1] = "VideoControl interface", [2]= "VideoStream interface"}
    uint8_t   bOriginator;
    uint8_t   bEvent;       // { [0] = "Control Changed" }
    uint8_t   bSelector;
    uint8_t   bAttribute; // {[0] = "Value", [1] = "Info", [2] = "Failure", [3] = "Min", [4] = "Max"}
    uint8_t   bValue[];
]])

local struct_vs_status = html.create_struct([[
    uint8_t   bStatusType; // {[1] = "VideoControl interface", [2]= "VideoStream interface"}
    uint8_t   bOriginator;
    uint8_t   bEvent;    // { [0] = "Button Press" }
    {
        uint8_t   bValue;  // { [0] = "Released", [1] = "Pressed" }
    }[];
]])


local function status_on_transaction(self, param, data, needDetail, forceBegin)
    if needDetail then
        local status = "success"
        local html = "<h1>Video Status Data</h1>"
        if #data > 0 then
            if data:byte(1) == 1 then
                html = struct_vc_status:build(data, "VideoControl Interface Status Packet").html
            elseif data:byte(1) == 2 then
                html = struct_vs_status:build(data, "VideoStream Interface Status Packet").html
            end
        end
        return macro_defs.RES_BEGIN_END, self.upv.make_xact_res("Video Status", html, data), self.upv.make_xfer_res({
            title = "Video Status",
            name  = "Video Status",
            desc  = "Video Status",
            status = status,
            infoHtml = html,
            data = data,
        })
    end
    return macro_defs.RES_BEGIN_END
end

cls.bInterfaceClass     = 0x0e
cls.bInterfaceSubClass  = 0x01
cls.bInterfaceProtocol  = nil
-- register endpoint for both direction

local subClassName = {
    [0x01] ="Video Control"    ,
    [0x02] ="Video Streaming"  ,
    [0x03] ="Video Interface Collection"   ,
}
function cls.get_name(desc, context)
    local name = subClassName[desc.bInterfaceSubClass] or "UNDEFINED"
    local proto = desc.bInterfaceProtocol == 1 and "PROTOCOL_15" or "UNDEFINED"
    return {
        bInterfaceClass = "Video",
        bInterfaceSubClass = name,
        bInterfaceProtocol = proto,
    }
end


local reg_video = function(subCls, eps)
    local t = {}
    for k,v in pairs(cls) do
        t[k] = v
    end
    t.bInterfaceSubClass = subCls
    register_class_handler(t)
end

cls.name = "Video Status"
cls.endpoints = { EP_IN("Status Data") }
cls.descriptor_parser = vc_descriptor_parser
cls.on_transaction = status_on_transaction
reg_video(1)

cls.name = "Video Stream"
cls.endpoints = { EP_INOUT("Stream Data"), EP_INOUT("Still Image", true) }
cls.descriptor_parser = vs_descriptpr_parser
cls.on_transaction = data_on_transaction
reg_video(2)


-- for interface in IAD
cls.iad = { bInterfaceClass     = 0x0e }

cls.name = "Video Status"
cls.endpoints = { EP_IN("Status Data") }
cls.descriptor_parser = vc_descriptor_parser
cls.on_transaction = status_on_transaction
reg_video(1)

cls.name = "Video Stream"
cls.endpoints = { EP_INOUT("Stream Data"), EP_INOUT("Still Image", true) }
cls.descriptor_parser = vs_descriptpr_parser
cls.on_transaction = data_on_transaction
reg_video(2)

package.loaded["usb_class_video"] = cls
