-- decoder_audio_payload_typeI.lua
local html = require("html")
local decoder = {}
local unpack = string.unpack

decoder.audio_decoder = {}


local function PCM_parser(data, context)
    local r = ""
    local cnt = 0
    for i=1,#data,2 do
        local v = unpack("i2", data, i)
        r = r .. tostring(v) .. ","
        cnt = cnt + 1
        if cnt == 16 then
            r = r .. "<br>"
            cnt = 0
        end
    end
    return r
end

local function PCM8_parser(data, context)
    local r = ""
    local cnt = 0
    for i=1,#data do
        local v = unpack("I1", data, i)
        r = r .. tostring(v) .. ","
        cnt = cnt + 1
        if cnt == 16 then
            r = r .. "<br>"
            cnt = 0
        end
    end
    return r
end

local function Float_parser(data, context)
    local r = ""
    local cnt = 0
    for i=1,#data,4 do
        local v = unpack("f", data, i)
        r = r .. tostring(v) .. ","
        cnt = cnt + 1
        if cnt == 16 then
            r = r .. "<br>"
            cnt = 0
        end
    end
    return r
end

local function ALAW_parser(data, context)
    local r = ""
    local cnt = 0
    for i=1,#data,1 do
        local v = unpack("i8", data, i)
        r = r .. tostring(v) .. ","
        cnt = cnt + 1
        if cnt == 16 then
            r = r .. "<br>"
            cnt = 0
        end
    end
    return r
end

function make_decoder(id, name, parser)
    decoder.audio_decoder[id] = {
        name = name,
        decode = function(data, context)
            return "<h1>" .. name .. " Data</h1>" .. parser(data, context)
        end
    }
end

make_decoder(0x0001, "PCM",  PCM_parser)
make_decoder(0x0002, "PCM8", PCM8_parser)
make_decoder(0x0003, "IEEE_FLOAT", Float_parser)
make_decoder(0x0004, "ALAW", ALAW_parser)
make_decoder(0x0005, "MULAW", ALAW_parser)

package.loaded["decoder_audio_payload_typeI"] = decoder
