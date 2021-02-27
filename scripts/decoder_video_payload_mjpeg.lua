-- decoder_video_payload_mjpeg.lua
-- Video class definition  https://www.usb.org/sites/default/files/USB_Video_Class_1_5.zip
-- MJPEG payload definition in USB_Video_Payload_MJPEG_1.5.pdf

local html = require("html")
local decoder = {}

local struct_VS_FORMAT_MJPEG = html.create_struct([[
    uint8_t   bLength;
    uint8_t   bDescriptorType;      // CS_INTERFACE
    uint8_t   bDescriptorSubtype;   // VS_FORMAT_MJPEG
    uint8_t   bFormatIndex;
    uint8_t   bNumFrameDescriptors;
    // bmFlags
    uint8_t   FixedSizeSamples:1;
    uint8_t   reserved:7;
    uint8_t   bDefaultFrameIndex;
    uint8_t   bAspectRatioX;
    uint8_t   bAspectRatioY;
    // bmInterlaceFlags
    uint8_t   Interlaced_stream_or_variable:1; // {[0] = "No", [1] = "Yes"}
    uint8_t   Fields_per_frame:1; // {[0] = "2 fields", [1] = "1 fields"}
    uint8_t   Field_1_first:1; // {[0] = "No", [1] = "Yes"}
    uint8_t   Reserved1:1;
    uint8_t   Field_pattern:2; // {[0] = "Field 1 only", [1] = "Field 2 only", [2] = "Regular pattern of fields 1 and 2", [3] = "Random pattern of fields 1 and 2"}
    uint8_t   Reserved2:2;
    uint8_t   bCopyProtect; // {[0] = "No restrictions", [1] = "Restrict duplication"}
]])

local struct_VS_FRAME_MJPEG = html.create_struct([[
    uint8_t   bLength;
    uint8_t   bDescriptorType;      // CS_INTERFACE
    uint8_t   bDescriptorSubtype;   // VS_FRAME_MJPEG
    uint8_t   bFrameIndex;
    // bmCapabilities
    uint8_t   Still_image_supported:1;
    uint8_t   Fixed_frame_rate:1;
    uint8_t   reserved:6;
    uint16_t  wWidth; // {format = "dec"}
    uint16_t  wHeight; // {format = "dec"}
    uint32_t  dwMinBitRate; // {format = "dec"}
    uint32_t  dwMaxBitRate; // {format = "dec"}
    uint32_t  dwMaxVideoFrameBufferSize; // {format = "dec"}
    uint32_t  dwDefaultFrameInterval; // {format = "dec"}  
    uint8_t   bFrameIntervalType;  // { [0] = "Continuous 1:min,2:max,3:step" }
    {
        uint32_t  dwFrameInterval;
    }[ (bFrameIntervalType == 0) and 3 or bFrameIntervalType ];

]])

decoder.video_as = {}
decoder.video_decoder = {}

decoder.video_as[0x06] = function(data, offset, context)
    return struct_VS_FORMAT_MJPEG:build(data:sub(offset), "VS Interface MJPEG format Descriptor")
end
decoder.video_as[0x07] = function(data, offset, context)
    return struct_VS_FRAME_MJPEG:build(data:sub(offset), "VS Interface MJPEG frame Descriptor")
end

local function fix_length(len)
    return function()
        return len
    end
end

local function get_tag(data, offset)
    if offset+1 <= #data then
        return data:byte(offset)*256 + data:byte(offset+1)
    end
    return 0x0000
end

local function get_length(data, offset)
    return data:byte(offset) * 256 + data:byte(offset+1)
end

local jpeg_tag = {
    [0xffc0] = {"SOF Start of Frame",            get_length    },
    [0xffc4] = {"DHT Define Huffman Table",      get_length    },
    [0xffd0] = {"RST Restart count",             fix_length(0) },
    [0xffd8] = {"SOI Start of image",            fix_length(0) },
    [0xffd9] = {"EOI End of Image",              fix_length(0) },
    [0xffda] = {"SOS Start of Scan",             get_length    },
    [0xffdb] = {"DQT Define Quantization Table", get_length    },
    [0xffdd] = {"DRI Define Restart Interval",   fix_length(4) },
    [0xffe0] = {"APP Application Marker",        get_length    },
    [0xfffe] = {"COM Comment",                   get_length    },
}

for i=1,0x0f do
    jpeg_tag[0xffe0+i] = jpeg_tag[0xffe0]
end
for i=1,0x07 do
    jpeg_tag[0xffd0+i] = jpeg_tag[0xffd0]
end


decoder.video_decoder[0x06] = {
    name = "MJPEG",
    decode = function(data, context)
        local tb = {
            title = "MJPEG Frame - JPEG data",
            header = {"Seg", "Offset", "Len", "Description"},
        }
        local i = 1
        while i < #data do
            local tag_v = get_tag(data, i)
            local tag = jpeg_tag[tag_v]
            i = i + 2
            if tag then
                local data_len = tag[2](data, i)
                tb[#tb+1] = { tag[1]:sub(1,3), string.format("0x%x", i - 3), data_len, string.format("(%04x)", tag_v) .. tag[1]:sub(4) }
                i = i + data_len
                if tag_v == 0xffda then
                    local tt = data:find("\xff\xd9", i)
                    tb[#tb+1] = {"Image Data", string.format("0x%x", i - 1), tt-i+1, "Entropy coded image data"}
                    i = tt
                end
            end
        end
        return html.make_table(tb) .. "<h2>Save the data as xxx.jpg to view it</h2>"
    end
}

package.loaded["decoder_video_payload_mjpeg"] = decoder
