-- usb_class_audio.lua

-- a typical class has these functions
-- cls.parse_setup(setup, context),  update setup.html, setup.name field in setup, and return it
-- cls.parse_setup_data(setup, data, context)    return a html to describe the data
-- cls.on_transaction(self, param, data, needDetail, forceBegin)  return macro_defs.RES_xxx
-- cls.descriptor_parser(data, offset, context)   return a parsed descriptor
-- cls.get_name(descriptor, context)              return a field name table
-- Audio class definition  https://www.usb.org/sites/default/files/audio10.pdf

local html = require("html")
local macro_defs = require("macro_defs")
local rndis = require("decoder_rndis")
local setup_parser = require("usb_setup_parser")
require("usb_register_class")

local fmt = string.format
local unpack = string.unpack
local cls = {}
cls.name = "Audio Data"

local audio_as_decoder = {}
local function install_decoder(decoder)
    for k,v in pairs(decoder.audio_decoder) do
        assert(not audio_as_decoder[k], "Audio Decoder already exist for " .. k)
        audio_as_decoder[k] = v
    end
end
install_decoder( require("decoder_audio_payload_typeI") )

local req2str = {
    [0x00] = "Undefined",
    [0x01] = "Set Cur",
    [0x81] = "Get Cur",
    [0x02] = "Set Min",
    [0x82] = "Get Min",
    [0x03] = "Set Max",
    [0x83] = "Get Max",
    [0x04] = "Set Res",
    [0x84] = "Get Res",
    [0x05] = "Set Mem",
    [0x85] = "Get Mem",
    [0xff] = "Get Stat",
}

local field_wIndex_audio = html.create_field([[
    struct{
        // wIndex
        uint16_t Itf_or_EP:8;
        uint16_t Entity_ID:8;
    }
]])

local field_wValue_audio = html.create_field([[
    struct{
        // wValue
        uint16_t reserved:8;
        uint16_t selector:8;
    }
]])

local audio_render_selector

function cls.parse_setup(setup, context)
    if (setup.recip ~= "Interface" and setup.recip ~= "Endpoint") or setup.type ~= "Class" then
        return
    end
    local bRequest_desc = req2str[setup.bRequest] or "Audio Unknown"
    setup.name = bRequest_desc
    setup.title = "Audio Request"
    setup.render.bRequest = bRequest_desc
    setup.render.wValue = field_wValue_audio
    setup.render.wIndex = field_wIndex_audio
    setup.render.title = "Audio Request " .. bRequest_desc
    audio_render_selector(setup, context)
end

function cls.parse_setup_data(setup, data, context)
    if setup.audio_data_render then
        local res = setup.audio_data_render(data)
        return res
    end
end

local struct_audio_sync_endpoint_desc = html.create_struct([[
    uint8_t  bLength;          // {format = "dec"}
    uint8_t  bDescriptorType;  // _G.get_descriptor_name
    // bEndpointAddress
    uint8_t  EndpointAddress:4;
    uint8_t  Reserved:3;
    uint8_t  Direction:1;     // {[0] ="OUT", [1]="IN"}
    // bmAttributes
    uint8_t  Type:2;          // {[0]="Control", [1]="Isochronous", [2]="Bulk", [3]="Interrupt"}
    uint8_t  SyncType:2;      // {[0]="No Synchonisation", [1]="Asynchronous", [2]="Adaptive", [3]="Synchronous"}
    uint8_t  UsageType:2;     // {[0]="Data Endpoint", [1]="Feedback Endpoint", [2]="Explicit Feedback Data Endpoint", [3]="Reserved"}
    uint8_t  PacketPerFrame:2;// {[0]="1", [1]="2", [2]="3", [3]="Reserved"}
    uint16_t wMaxPacketSize;  // {format = "dec"}
    uint8_t  bInterval;
    uint8_t  bRefresh;
    uint8_t  bSynchAddress;   // must be zero
]])

local function make_ac_interface(name, info)
    local builder = html.create_struct(info)
    return function(data, offset, context)
        return builder:build(data:sub(offset), "AC Interface " .. name .. " Descriptor")
    end
end
local function make_as_interface(name, info)
    local builder = html.create_struct(info)
    return function(data, offset, context)
        return builder:build(data:sub(offset), "AS Interface " .. name .. " Descriptor")
    end
end
-- audio terminal types
-- https://www.usb.org/sites/default/files/termt10.pdf
_G.audio_terminal_types = {
    [0x0100] = "USB Undefined",
    [0x0101] = "USB Stream",
    [0x01ff] = "USB Vendor specific",

    [0x0200] = "Input Undefined",

    [0x0201] = "Microphone",
    [0x0202] = "Desktop Microphone",
    [0x0203] = "Personal Microphone",
    [0x0204] = "Omni-directional Microphone",
    [0x0205] = "Microphone Array",
    [0x0206] = "Processing Microphone Array",

    [0x0300] = "Output Undefined",
    [0x0301] = "Speaker",
    [0x0302] = "Headphones",
    [0x0303] = "Head Mounted Display Audio",
    [0x0304] = "Desktop speaker",
    [0x0305] = "Room speaker",
    [0x0306] = "Communication speaker",
    [0x0307] = "Low frequency effects speaker",

    [0x0400] = "Bi-directional Undefined",      
    [0x0401] = "Handset",                       
    [0x0402] = "Headset",                       
    [0x0403] = "Speakerphone",                  
    [0x0404] = "Echo-suppressing speakerphone", 
    [0x0405] = "Echo-canceling speakerphone",   

    [0x0500] = "Telephony Undefined", 
    [0x0501] = "Phone line",          
    [0x0502] = "Telephone",           
    [0x0503] = "Down Line Phone",     

    [0x0600] = "External Undefined",        
    [0x0601] = "Analog connector",          
    [0x0602] = "Digital audio interface",   
    [0x0604] = "Legacy audio connector",    
    [0x0605] = "S/PDIF interface",          
    [0x0606] = "1394 DA stream",            
    [0x0607] = "1394 DV stream soundtrack", 

    [0x0700] = "Embedded Undefined",
    [0x0701] = "Level Calibration Noise Source",
    [0x0702] = "Equalization Noise",
    [0x0704] = "DAT",
    [0x0705] = "DCC",
    [0x0706] = "MiniDisk",
    [0x0707] = "Analog Tape",
    [0x0708] = "Phonograph",
    [0x0709] = "VCR Audio",
    [0x070A] = "Video Disc Audio",
    [0x070B] = "DVD Audio",
    [0x070C] = "TV Tuner Audio",
    [0x070D] = "Satellite Receiver Audio",
    [0x070E] = "Cable Tuner Audio",
    [0x070F] = "DSS Audio",
    [0x0710] = "Radio Receiver",
    [0x0711] = "Radio Transmitter",
    [0x0712] = "Multi-track Recorder",
    [0x0713] = "Synthesizer",
}
_G.audio_process_types = {
[0x00] = "PROCESS_UNDEFINED",
[0x01] = "UP/DOWNMIX_PROCESS",
[0x02] = "DOLBY_PROLOGIC_PROCESS",
[0x03] = "3D_STEREO_EXTENDER_PROCESS",
[0x04] = "REVERBERATION_PROCESS",
[0x05] = "CHORUS_PROCESS",
[0x06] = "DYN_RANGE_COMP_PROCESS",
}

local audio_ac_interface  = {
    [0x01] = make_ac_interface("Header", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;
        uint16_t  bcdADC;
        uint16_t  wTotalLength;
        uint8_t   bInCollection;
        {
            uint8_t baInterfaceNr;
        }[bInCollection];
    ]]),
    [0x02] = make_ac_interface("Input Terminal", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;
        uint8_t   bTerminalID;
        uint16_t  wTerminalType;       // _G.audio_terminal_types
        uint8_t   bAssocTerminal;
        uint8_t   bNrChannels;
        // wChannelConfig
        uint16_t  Left_Front:1;
        uint16_t  Right_Front:1;
        uint16_t  Center_Front:1;
        uint16_t  Low_Frequency_Enhancement:1;
        uint16_t  Left_Surround:1;
        uint16_t  Right_Surround:1;
        uint16_t  Left_of_Center:1;
        uint16_t  Right_of_Center:1;
        uint16_t  Surround:1;
        uint16_t  Side_Left:1;
        uint16_t  Side_Right:1;
        uint16_t  Top:1;
        uint16_t  reserved:6;
        uint8_t   iChannelNames;
        uint8_t   iTerminal;
    ]]),
    [0x03] = make_ac_interface("Output Terminal", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;
        uint8_t   bTerminalID;
        uint16_t  wTerminalType;       // _G.audio_terminal_types
        uint8_t   bAssocTerminal;
        uint8_t   bSourceID;
        uint8_t   iTerminal;
    ]]),
    [0x04] = make_ac_interface("Mixer Unit", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;
        uint8_t   bUnitID;
        uint8_t   bNrInPins;
        {
            uint8_t baSourceID;
        }[bNrInPins];
        uint8_t   bNrChannels;
        // wChannelConfig
        uint16_t  Left_Front:1;
        uint16_t  Right_Front:1;
        uint16_t  Center_Front:1;
        uint16_t  Low_Frequency_Enhancement:1;
        uint16_t  Left_Surround:1;
        uint16_t  Right_Surround:1;
        uint16_t  Left_of_Center:1;
        uint16_t  Right_of_Center:1;
        uint16_t  Surround:1;
        uint16_t  Side_Left:1;
        uint16_t  Side_Right:1;
        uint16_t  Top:1;
        uint16_t  reserved:6;
        uint8_t   iChannelNames;
        uint8_t   bmControls[ math.floor(bNrChannels* bNrInPins + 7 / 8) ];
        uint8_t   iMixer;
    ]]),
    [0x05] = make_ac_interface("Selector Unit", [[
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
    [0x06] = make_ac_interface("Feature Unit", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;
        uint8_t   bUnitID;
        uint8_t   bSourceID;
        uint8_t   bControlSize;
        {
            uint16_t bmaControls;
        }[bControlSize];
        uint8_t   iFeature;
    ]]),
    [0x07] = make_ac_interface("Processing Unit", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;
        uint8_t   bUnitID;
        uint16_t  wProcessType;         // _G.audio_process_types
        uint8_t   bNrInPins;
        {
            uint8_t baSourceID;
        }[bNrInPins];

        uint8_t  bNrChannels;
        // wChannelConfig
        uint16_t  Left_Front:1;
        uint16_t  Right_Front:1;
        uint16_t  Center_Front:1;
        uint16_t  Low_Frequency_Enhancement:1;
        uint16_t  Left_Surround:1;
        uint16_t  Right_Surround:1;
        uint16_t  Left_of_Center:1;
        uint16_t  Right_of_Center:1;
        uint16_t  Surround:1;
        uint16_t  Side_Left:1;
        uint16_t  Side_Right:1;
        uint16_t  Top:1;
        uint16_t  reserved:6;
        uint8_t   iChannelNames;
        uint8_t   bControlSize;
        uint8_t   bmControls[bControlSize];
        uint8_t   iProcessing;
        uint8_t   processData[];
    ]]),
    [0x08] = make_ac_interface("Extension Unit", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;
        uint8_t   bUnitID;
        uint16_t  wProcessType;         // _G.audio_process_types
        uint8_t   bNrInPins;
        {
            uint8_t baSourceID;
        }[bNrInPins];
        uint8_t  bNrChannels;
        // wChannelConfig
        uint16_t  Left_Front:1;
        uint16_t  Right_Front:1;
        uint16_t  Center_Front:1;
        uint16_t  Low_Frequency_Enhancement:1;
        uint16_t  Left_Surround:1;
        uint16_t  Right_Surround:1;
        uint16_t  Left_of_Center:1;
        uint16_t  Right_of_Center:1;
        uint16_t  Surround:1;
        uint16_t  Side_Left:1;
        uint16_t  Side_Right:1;
        uint16_t  Top:1;
        uint16_t  reserved:6;
        uint8_t   iChannelNames;
        uint8_t   bControlSize;
        uint8_t   bmControls[bControlSize];
        uint8_t   iExtension;
    ]]),
}

-- audio format types: https://www.usb.org/sites/default/files/frmts10.pdf
_G.audio_format_type = {
    [0x0000] = "TYPE_I_UNDEFINED",
    [0x0001] = "PCM",
    [0x0002] = "PCM8",
    [0x0003] = "IEEE_FLOAT",
    [0x0004] = "ALAW",
    [0x0005] = "MULAW",

    [0x1000] = "TYPE_II_UNDEFINED",
    [0x1001] = "MPEG",
    [0x1002] = "AC-3",

    [0x2000] = "TYPE_III_UNDEFINED",
    [0x2001] = "IEC1937_AC-3",
    [0x2002] = "IEC1937_MPEG-1_Layer1",
    [0x2003] = "IEC1937_MPEG-1_Layer2/3 or IEC1937_MPEG-2_NOEXT",
    [0x2004] = "IEC1937_MPEG-2_EXT",
    [0x2005] = "IEC1937_MPEG-2_Layer1_LS",
    [0x2006] = "IEC1937_MPEG-2_Layer2/3_LS",
}

local audio_as_interface  = {
    [0x01] = make_as_interface("General", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;
        uint8_t   bTerminalLink;
        uint8_t   bDelay;
        uint16_t  wFormatTag;           // _G.audio_format_type
    ]]),

    [0x02] = make_as_interface("Format Type", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;
        uint8_t   bFormatType;
        uint8_t   bNrChannels;
        uint8_t   bSubframeSize;
        uint8_t   bBitResolution;
        uint8_t   bSamFreqType;  // 0 - Continuous
        {
            uint24_t  sampleFreq; // {format = "dec"}
        }[ (bSamFreqType == 0) and 2 or bSamFreqType];
    ]]),
}

local struct_cs_audio_data_endpoint = html.create_struct([[
    uint8_t   bLength;
    uint8_t   bDescriptorType;      // CS_ENDPOINT
    uint8_t   bDescriptorSubtype;
    // bmAttributes
    uint8_t   Sampling_Frequency:1;
    uint8_t   Pitch:1;
    uint8_t   reserved:4;
    uint8_t   MaxPacketsOnly:1;
    uint8_t   bLockDelayUnits; // {[0] = "undefined", [1] = "Milliseconds", [2] = "Decoded PCM samples"}
    uint16_t   wLockDelay;
]])

local selector_map = {}
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
        selector = {
            [0x01] = "COPY_PROTECT_CONTROL",
        }
    },
    data = function(setup)
        return function(data)
            return html.create_struct([[
                uint8_t bCopyProtect; // {[0] = 'CPL0', [1] = 'CPL1', [2] = 'CPL2'
            ]]):build(data, "Terminal Control Data").html
        end
    end
}
selector_map[0x03] = selector_map[0x02]
selector_map[0x04] = {
    name = "Mixer Unit Control",
    wValue = [[
        struct{
            // wValue
            uint16_t OCN:8; // output channel number
            uint16_t ICN:8; // input channel number
        }
    ]],
    wIndex = [[
        struct{
            // wIndex
            uint16_t interface:8;
            uint16_t unit_id:8;
        }
    ]],
    data = function(setup)
        local info = "int16_t wMixer; // function(x) return tostring(x*(127.9961/32767)) ..' db' end"
        if setup.wValue == 0xffff then
            info = "{\nint16_t wMixer; // function(x) return tostring(x*(127.9961/32767)) ..' db' end }[".. (setup.wLength/2) .. "];"
        end
        return function(data)
            return html.create_struct("struct {\n" .. info .. "\n}"):build(data, "Feature Unit Control Data").html
        end
    end
}
selector_map[0x05] = {
    name = "Selector Unit Control",
    wValue = [[
        struct{
            uint16_t wValue;
        }
    ]],
    wIndex = [[
        struct{
            // wIndex
            uint16_t interface:8;
            uint16_t unit_id:8;
        }
    ]],
    data = function(setup)
        return function(data)
            return html.create_struct([[
                uint8_t bSelector;
            ]]):build(data, "Selector Control Data").html
        end
    end
}

selector_map[0x06] = {
    name = "Feature Unit Control",
    wValue = [[
        struct{
            // wValue
            uint16_t channel_number:8;
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
            [0x01] = "MUTE_CONTROL",
            [0x02] = "VOLUME_CONTROL",
            [0x03] = "BASS_CONTROL",
            [0x04] = "MID_CONTROL",
            [0x05] = "TREBLE_CONTROL",
            [0x06] = "GRAPHIC_EQUALIZER_CONTROL",
            [0x07] = "AUTOMATIC_GAIN_CONTROL",
            [0x08] = "DELAY_CONTROL",
            [0x09] = "BASS_BOOST_CONTROL",
            [0x0A] = "LOUDNESS_CONTROL",
        }
    },
    data = function(setup)
        local info = ""
        if (setup.wValue & 0xff) == 0xff then
            info = select(setup.wValue >> 8
                ,"{\nuint8_t bMute; // {[0]='false', [1] = 'true'} \n}[" .. setup.wLength .. "];"
                ,"{\nint16_t wVolume; // function(x) return tostring(x*(127.9961/32767)) .. ' dB' end \n}[" .. (setup.wLength/2) .. "]; "
                ,"{\nint8_t  bBase;   // function(x) return tostring(x*(31.75/127)) .. ' dB' end \n}[" .. (setup.wLength) .. "];"
                ,"{\nint8_t  bMid;   // function(x)  return tostring(x*(31.75/127)) .. ' dB' end \n}[" .. (setup.wLength) .. "];"
                ,"{\nint8_t  bTreble;   // function(x) return tostring(x*(31.75/127)) .. ' dB' end \n}[" .. (setup.wLength) .. "];"
                ,"uint32_t bmBandsPresent;\n" ..
                 "{\nint8_t  bBand; // function(x) return tostring(x*(31.75/127)) .. ' dB' end \n}[" .. (setup.wLength-4) .. "];"
                ,"{\nuint8_t  bAGC;   // {[0]='false', [1] = 'true'} \n}[" .. (setup.wLength) .. "];"
                ,"{\nuint16_t wDelay; // function(x) return tostring(x*(1/64)) ..' ms' end \n}[" .. (setup.wLength/2) .. "]; "
                ,"{\nuint8_t  bBassBoost;   // {[0]='false', [1] = 'true'} \n}[" .. (setup.wLength) .. "];"
                ,"{\nuint8_t  bLoudness;   // {[0]='false', [1] = 'true'} \n}[" .. (setup.wLength) .. "];"
            )
        else
            info = select(setup.wValue >> 8
                ,"uint8_t bMute;  // {[0]='false', [1] = 'true'}"
                ,"int16_t wVolume; // function(x) return tostring(x*(127.9961/32767)) .. ' dB' end"
                ,"int8_t  bBase;   // function(x) return tostring(x*(31.75/127)) .. ' dB' end"
                ,"int8_t  bMid;   // function(x) return tostring(x*(31.75/127)) .. ' dB' end"
                ,"int8_t  bTreble;   // function(x) return tostring(x*(31.75/127)) .. ' dB' end"
                ,"uint32_t bmBandsPresent;\n" ..
                 "{\nint8_t  bBand; // function(x) return tostring(x*(31.75/127)) .. ' dB' end \n}[" .. (setup.wLength-4) .. "];"
                ,"uint8_t  bAGC;   // {[0]='false', [1] = 'true'}"
                ,"uint16_t  wDelay;   // function(x) return tostring(x*(1/64)) ..' ms' end"
                ,"uint8_t  bBassBoost;   // {[0]='false', [1] = 'true'}"
                ,"uint8_t  bLoudness;   // {[0]='false', [1] = 'true'}"
            )
        end
        return function(data)
            return html.create_struct("struct {\n" .. info .. "\n}"):build(data, "Feature Unit Control Data").html
        end
    end
}

selector_map[0x08] = {
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
                uint8_t bOn; // {[0] = 'false', [1] = 'true'
            ]]):build(data, "Extension Control Data").html
        end
    end
}

local processor_selector_map = {}
processor_selector_map[0x01] = {
    name = "UP/DOWNMIX_PROCESS",
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
            [0x01] = "UD_ENABLE_CONTROL",
            [0x02] = "UD_MODE_SELECT_CONTROL",
        }
    },
    data = function(setup)
        local sel = setup.wValue >> 8
        local info = ""
        if sel == 1 then
            info = "uint8_t  bEnable;   // {[0]='false', [1] = 'true'}"
        elseif sel == 2 then
            info = "uint8_t  bMode;"
        end
        return function(data)
            return html.create_struct("struct {\n" .. info .. "\n}"):build(data, "Process Data").html
        end
    end
}
processor_selector_map[0x02] = processor_selector_map[0x01]
processor_selector_map[0x02].name = "DOLBY_PROLOGIC_PROCESS"
processor_selector_map[0x02].wValue_info = {
    selector = {
        [0x01] = "DB_ENABLE_CONTROL",
        [0x02] = "DB_MODE_SELECT_CONTROL",
    }
}

processor_selector_map[0x03] = processor_selector_map[0x01]
processor_selector_map[0x03].name = "3D_STEREO_EXTENDER_PROCESS"
processor_selector_map[0x03].wValue_info = {
    selector = {
        [0x01] = "3D_ENABLE_CONTROL",
        [0x02] = "SPACIOUSNESS_CONTROL",
    }
}
processor_selector_map[0x03].data = function(setup)
    local sel = setup.wValue >> 8
    local info = ""
    if sel == 1 then
        info = "uint8_t  bEnable;   // {[0]='false', [1] = 'true'}"
    elseif sel == 2 then
        info = "uint8_t  bSpaciousness;"
    end
    return function(data)
        return html.create_struct("struct {\n" .. info .. "\n}"):build(data, "Process Data").html
    end
end

processor_selector_map[0x04] = processor_selector_map[0x01]
processor_selector_map[0x04].name = "REVERBERATION_PROCESS"
processor_selector_map[0x04].wValue_info = {
    selector = {
        [0x01] = "RV_ENABLE_CONTROL",
        [0x02] = "REVERB_LEVEL_CONTROL",
        [0x03] = "REVERB_TIME_CONTROL",
        [0x04] = "REVERB_FEEDBACK_CONTROL",
    }
}
processor_selector_map[0x04].data = function(setup)
    local sel = setup.wValue >> 8
    local info = ""
    if sel == 1 then
        info = "uint8_t  bEnable;   // {[0]='false', [1] = 'true'}"
    elseif sel == 2 then
        info = "uint8_t  bReverbLevel;"
    elseif sel == 3 then
        info = "uint16_t  wReverbTime; // function(x) return tostring(x*(1/256)) .. ' s' end"
    elseif sel == 4 then
        info = "uint8_t  bReverbFeedback;"
    end
    return function(data)
        return html.create_struct("struct {\n" .. info .. "\n}"):build(data, "Process Data").html
    end
end

processor_selector_map[0x05] = processor_selector_map[0x01]
processor_selector_map[0x05].name = "CHORUS_PROCESS"
processor_selector_map[0x05].wValue_info = {
    selector = {
        [0x01] = "CH_ENABLE_CONTROL",
        [0x02] = "CHORUS_LEVEL_CONTROL",
        [0x03] = "CHORUS_RATE_CONTROL",
        [0x04] = "CHORUS_DEPTH_CONTROL",
    }
}
processor_selector_map[0x05].data = function(setup)
    local sel = setup.wValue >> 8
    local info = ""
    if sel == 1 then
        info = "uint8_t  bEnable;   // {[0]='false', [1] = 'true'}"
    elseif sel == 2 then
        info = "uint8_t  bChorusLevel;"
    elseif sel == 3 then
        info = "uint16_t  wChorusRate; // function(x) return tostring(x*(1/256)) .. ' Hz' end"
    elseif sel == 4 then
        info = "uint16_t  wChorusDepth; // function(x) return tostring(x*(1/256)) .. ' ms' end"
    end
    return function(data)
        return html.create_struct("struct {\n" .. info .. "\n}"):build(data, "Process Data").html
    end
end

processor_selector_map[0x06] = processor_selector_map[0x01]
processor_selector_map[0x06].name = "DYN_RANGE_COMP_PROCESS"
processor_selector_map[0x06].wValue_info = {
    selector = {
        [0x01] = "DR_ENABLE_CONTROL",
        [0x02] = "COMPRESSION_RATE_CONTROL",
        [0x03] = "MAXAMPL_CONTROL",
        [0x04] = "THRESHOLD_CONTROL",
        [0x05] = "ATTACK_TIME",
        [0x06] = "RELEASE_TIME",
    }
}
processor_selector_map[0x06].data = function(setup)
    local sel = setup.wValue >> 8
    local info = ""
    if sel == 1 then
        info = "uint8_t  bEnable;   // {[0]='false', [1] = 'true'}"
    elseif sel == 2 then
        info = "uint16_t  wRatio; // function(x) return tostring(x*(1/256)) .. ' dB' end"
    elseif sel == 3 then
        info = "int16_t  wMaxAmpl; // function(x) return tostring(x*(1/256)) .. ' dB' end"
    elseif sel == 4 then
        info = "int16_t  wThreshold; // function(x) return tostring(x*(1/256)) .. ' dB' end"
    elseif sel == 5 then
        info = "uint16_t  wAttackTime; // function(x) return tostring(x*(1/256)) .. ' ms' end"
    elseif sel == 6 then
        info = "uint16_t  wAttackTime; // function(x) return tostring(x*(1/256)) .. ' ms' end"
    end
    return function(data)
        return html.create_struct("struct {\n" .. info .. "\n}"):build(data, "Process Data").html
    end
end

local stream_selector_map = {}
stream_selector_map[0x1001] = {
    name = "MPEG Stream",
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
            [0x01] = "MP_DUAL_CHANNEL_CONTROL",
            [0x02] = "MP_SECOND_STEREO_CONTROL",
            [0x03] = "MP_MULTILINGUAL_CONTROL",
            [0x04] = "MP_DYN_RANGE_CONTROL",
            [0x05] = "MP_SCALING_CONTROL",
            [0x06] = "MP_HILO_SCALING_CONTROL",
        }
    },
    data = function(setup)
        local sel = setup.wValue >> 8
        local info = ""
        if sel == 1 then
            info = "uint8_t  bChannel2Enable;   // {[0]='false', [1] = 'true'}"
        elseif sel == 2 then
            info = "uint8_t  b2ndStereoEnable;  // {[0]='false', [1] = 'true'}"
        elseif sel == 3 then
            info = "uint8_t  bMultiLingual;  // {[0]='false', [1] = 'true'}"
        elseif sel == 4 then
            info = "uint8_t  bEnable;  // {[0]='false', [1] = 'true'}"
        elseif sel == 5 then
            info = "uint8_t  bScale;"
        elseif sel == 6 then
            info = "uint8_t  bLowScale; \n uint8_t  bHighScale;"
        end
        return function(data)
            return html.create_struct("struct {\n" .. info .. "\n}"):build(data, "MPEG Stream Control Data").html
        end
    end
}
stream_selector_map[0x1002] = {
    name = "AC-3 Stream",
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
            [0x01] = "AC_MODE_CONTROL",
            [0x02] = "AC_DYN_RANGE_CONTROL",
            [0x03] = "AC_SCALING_CONTROL",
            [0x04] = "AC_HILO_SCALING_CONTROL",
        }
    },
    data = function(setup)
        local sel = setup.wValue >> 8
        local info = ""
        if sel == 1 then
            info = "uint8_t  bMode;   // {[0]='RF', [1] = 'Line', [2] = 'Custom0', [3] = 'Custom1'}"
        elseif sel == 2 then
            info = "uint8_t  bEnable;  // {[0]='false', [1] = 'true'}"
        elseif sel == 3 then
            info = "uint8_t  bScale;"
        elseif sel == 4 then
            info = "uint8_t  bLowScale; \n uint8_t  bHighScale;"
        end
        return function(data)
            return html.create_struct("struct {\n" .. info .. "\n}"):build(data, "AC-3 Stream Control Data").html
        end
    end
}


local ep_control_selector_map = {
    name = "Endpoint Control",
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
            uint16_t endpoint:8;
            uint16_t zero:8;
        }
    ]],
    wValue_info = {
        selector = {
            [0x01] = "SAMPLING_FREQ_CONTROL",
            [0x02] = "PITCH_CONTROL",
        }
    },
    data = function(setup)
        local sel = setup.wValue >> 8
        local info = ""
        if sel == 1 then
            info = "uint24_t  tSampleFreq;   // {format = 'dec', comment='Hz'}"
        elseif sel == 2 then
            info = "uint8_t  bPitchEnable;  // {[0]='false', [1] = 'true'}"
        end
        return function(data)
            return html.create_struct("struct {\n" .. info .. "\n}"):build(data, "Endpoint Control Data").html
        end
    end
}

audio_render_selector = function(setup, context)
    local s = nil
    if setup.type == "Class" and setup.recip == "Endpoint"  then
        setup.audio_data_render = nil
        s = ep_control_selector_map
    end
    if not s then
        local id = setup.wIndex >>8
        local itf = setup.wIndex & 0xff
        local itf_data = context:get_interface_data(itf)
        setup.audio_data_render = nil
        if itf_data.audio_selector and itf_data.audio_selector[id] then
            s = itf_data.audio_selector[id]
        end
    end
    if s then
        setup.render.wValue = html.create_field(s.wValue, s.wValue_info)
        setup.render.wIndex = html.create_field(s.wIndex)
        setup.render.title = setup.render.title .. " (" .. s.name .. ")"
        setup.audio_data_render = s.data(setup)
    end
end

local function ac_parse_selector(data, offset, context)
    local t = data:byte(offset + 1)
    local subType = data:byte(offset + 2)
    local id = data:byte(offset + 3)
    local processType = data:byte(offset + 4)
    local itf_data = context:current_interface_data()
    itf_data.audio_selector = itf_data.audio_selector or {}
    if subType == 7 then
        -- process unit
        itf_data.audio_selector[id] = processor_selector_map[processType]
    elseif subType > 1 then
        if selector_map[subType] then
            itf_data.audio_selector[id] = selector_map[subType]
        end
    end
end

local function as_parse_selector(data, offset, context)
    local t = data:byte(offset + 1)
    local subType = data:byte(offset + 2)
    if subType == 1 then
        local itf_data = context:current_interface_data()
        format = data:byte(offset+5) + data:byte(offset+6) * 256
        -- AS ID always 0, [Universal Serial Bus Device Class Definition for Audio Data Formats] [2.3.8.1.2.1]
        itf_data.audio_selector = itf_data.audio_selector or {}
        itf_data.audio_selector[0] = stream_selector_map[format]
    end
end

local function as_descriptpr_parser(data, offset, context)
    local len = data:byte(offset)
    if #data < offset+len then return end
    local t = data:byte(offset + 1)
    local subType = data:byte(offset + 2)
    if t == macro_defs.ENDPOINT_DESC and len == 9 then
        return struct_audio_sync_endpoint_desc:build(data:sub(offset), "Endpoint Descriptor")
    end
    if t == macro_defs.CS_ENDPOINT then
        return struct_cs_audio_data_endpoint:build(data:sub(offset), "CS Endpoint Descriptor")
    end
    if t ~= macro_defs.CS_INTERFACE then
        return nil
    end
    if subType == 1 then
        local itf_data = context:current_interface_data()
        local audio_format = data:byte(offset+5) + data:byte(offset+6) * 256
        itf_data.audio_frame_decoder = audio_as_decoder[audio_format]
    end
    as_parse_selector(data, offset, context)
    return audio_as_interface[subType] and audio_as_interface[subType](data, offset, context)
end

local function ac_descriptor_parser(data, offset, context)
    local len = data:byte(offset)
    if #data < offset+len then return end
    local t = data:byte(offset + 1)
    local subType = data:byte(offset + 2)
    if t == macro_defs.ENDPOINT_DESC and len == 9 then
        return struct_audio_sync_endpoint_desc:build(data:sub(offset), "Endpoint Descriptor")
    end
    if t ~= macro_defs.CS_INTERFACE then
        return nil
    end
    ac_parse_selector(data, offset, context)
    return audio_ac_interface[subType] and audio_ac_interface[subType](data, offset, context)
end

function cls.on_transaction(self, param, data, needDetail, forceBegin)
    local addr, ep, pid, ack = param:byte(1), param:byte(2), param:byte(3), param:byte(4)
    if needDetail then
        local status = "success"
        local html = "<h1>Audio Data</h1>"
        local audio_format = "Unknown"
        local t = self:get_endpoint_interface_data(addr, ep)
        if t.audio_frame_decoder then
            audio_format = t.audio_frame_decoder.name
            html = t.audio_frame_decoder.decode(data, self)
        end
        return macro_defs.RES_BEGIN_END, self.upv.make_xact_res("Audio Stream", html, data), self.upv.make_xfer_res({
            title = "Audio Frame",
            name  = "Audio Format",
            desc  = audio_format,
            status = status,
            infoHtml = html,
            data = data,
        })
    end
    return macro_defs.RES_BEGIN_END
end

cls.bInterfaceClass     = 1
cls.bInterfaceSubClass  = 1
cls.bInterfaceProtocol  = nil
-- register endpoint for both direction
cls.endpoints = { EP_INOUT("Audio Data") }

local subClassName = {
    [0x01] ="Audio Control"    ,
    [0x02] ="Audio Streaming"  ,
    [0x03] ="MIDI Streaming"   ,
}
function cls.get_name(desc, context)
    local name = subClassName[desc.bInterfaceSubClass] or "UNDEFINED"
    return {
        bInterfaceClass = "Audio",
        bInterfaceSubClass = name,
        bInterfaceProtocol = "UNDEFINED",
    }
end


local reg_audio = function(subCls, eps)
    local t = {}
    for k,v in pairs(cls) do
        t[k] = v
    end
    t.bInterfaceSubClass = subCls
    register_class_handler(t)
end

cls.descriptor_parser = ac_descriptor_parser
reg_audio(1)
cls.descriptor_parser = as_descriptpr_parser
reg_audio(2)
reg_audio(3)
-- for interface in IAD
cls.iad = { bInterfaceClass     = 1 }
cls.descriptor_parser = ac_descriptor_parser
reg_audio(1)
cls.descriptor_parser = as_descriptpr_parser
reg_audio(2)
reg_audio(3)

package.loaded["usb_class_audio"] = cls
