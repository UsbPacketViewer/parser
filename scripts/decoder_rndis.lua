-- rndis.lua
local html = require("html")
local eth = require("decoder_ethernet")
local rndis = {}


local msgType = {
[0x00000001] = "REMOTE_NDIS_PACKET_MSG"          , 
[0X00000002] = "REMOTE_NDIS_INITIALIZE_MSG"      , 
[0X00000003] = "REMOTE_NDIS_HALT_MSG"            , 
[0X00000004] = "REMOTE_NDIS_QUERY_MSG"           , 
[0X00000005] = "REMOTE_NDIS_SET_MSG"             , 
[0X00000006] = "REMOTE_NDIS_RESET_MSG"           , 
[0X00000007] = "REMOTE_NDIS_INDICATE_STATUS_MSG" , 
[0X00000008] = "REMOTE_NDIS_KEEPALIVE_MSG"       , 
[0X80000002] = "REMOTE_NDIS_INITIALIZE_CMPLT"    , 
[0X80000004] = "REMOTE_NDIS_QUERY_CMPLT"         , 
[0X80000005] = "REMOTE_NDIS_SET_CMPLT"           , 
[0X80000006] = "REMOTE_NDIS_RESET_CMPLT"         , 
[0X80000008] = "REMOTE_NDIS_KEEPALIVE_CMPLT"     , 
}

_G.rndis_msg_type = msgType
local msgHandler

local struct_message = html.create_struct([[
    typedef struct{
        uint32_t MessageType;
        uint32_t MessageLength;
    }
]])

local function parseMessage(data, context)
    data = data or ""
    local header = struct_message:build(data, "RNDIS Data")
    if not msgType[header.MessageType] or not msgHandler[header.MessageType] then
        return "<h1>Unknown Message Type " .. string.format("0x%08X", header.MessageType) .."</h1>"
    end
    return msgHandler[header.MessageType](data, context)
end

rndis.parse_data = parseMessage
rndis.parseResponse = parseMessage
rndis.parseCommand = parseMessage

local struct_REMOTE_NDIS_PACKET_MSG = html.create_struct([[
    typedef struct{
        uint32_t MessageType;     // _G.rndis_msg_type
        uint32_t MessageLength;   // {format = "dec"}
        uint32_t DataOffset;
        uint32_t DataLength;      // {format = "dec"}
        uint32_t OOBDataOffset;
        uint32_t OOBDataLength;   // {format = "dec"}
        uint32_t NumOOBDataElements;
        uint32_t PerPacketInfoOffset;
        uint32_t PerPacketInfoLength;  // {format = "dec"}
        uint32_t DeviceVcHandle;
        uint32_t Reserved;
        }rndis_data_packet_t;
]])
local function REMOTE_NDIS_PACKET_MSG_Handler(data, context)
    local header = struct_REMOTE_NDIS_PACKET_MSG:build(data, "RNDIS Data")
    data = data:sub(45)
    local bodyHtml = eth.parse_data(data, context)
    return header.html .. bodyHtml
end

local struct_REMOTE_NDIS_INITIALIZE_MSG = html.create_struct([[
    typedef struct{
        uint32_t MessageType;     // _G.rndis_msg_type
        uint32_t MessageLength;   // {format = "dec"}
        uint32_t RequestId;
        uint32_t MajorVersion;
        uint32_t MinorVersion;
        uint32_t MaxTransferSize;
        }rndis_initialize_msg_t;
]])

local struct_REMOTE_NDIS_INITIALIZE_CMPLT = html.create_struct([[
    typedef struct{
        uint32_t MessageType;     // _G.rndis_msg_type
        uint32_t MessageLength;   // {format = "dec"}
        uint32_t RequestId;
        uint32_t Status;
        uint32_t MajorVersion;
        uint32_t MinorVersion;
        uint32_t DeviceFlags;
        uint32_t Medium;
        uint32_t MaxPacketsPerTransfer;
        uint32_t MaxTransferSize;
        uint32_t PacketAlignmentFactor;
        uint32_t AfListOffset;
        uint32_t AfListSize;
        } rndis_initialize_cmplt_t;
]])

local struct_REMOTE_NDIS_HALT_MSG = html.create_struct([[
    typedef struct{
        uint32_t MessageType;     // _G.rndis_msg_type
        uint32_t MessageLength;   // {format = "dec"}
        uint32_t RequestId;
        } rndis_halt_msg_t;
]])

local struct_REMOTE_NDIS_QUERY_MSG = html.create_struct([[
    typedef struct{
        uint32_t MessageType;     // _G.rndis_msg_type
        uint32_t MessageLength;   // {format = "dec"}
        uint32_t RequestId;
        uint32_t Oid;
        uint32_t InformationBufferLength;
        uint32_t InformationBufferOffset;
        uint32_t DeviceVcHandle;
        } rndis_query_msg_t;
]])

local struct_REMOTE_NDIS_QUERY_CMPLT = html.create_struct([[
    typedef struct{
        uint32_t MessageType;     // _G.rndis_msg_type
        uint32_t MessageLength;   // {format = "dec"}
        uint32_t RequestId;
        uint32_t Status;
        uint32_t InformationBufferLength;  // {format = "dec"}
        uint32_t InformationBufferOffset;
        } rndis_query_cmplt_t;
]])

local struct_REMOTE_NDIS_SET_MSG = html.create_struct([[
    typedef struct{
        uint32_t MessageType;     // _G.rndis_msg_type
        uint32_t MessageLength;   // {format = "dec"}
        uint32_t RequestId;
        uint32_t Oid;
        uint32_t InformationBufferLength;
        uint32_t InformationBufferOffset;
        uint32_t DeviceVcHandle;
        } rndis_set_msg_t;
]])

local struct_REMOTE_NDIS_SET_CMPLT = html.create_struct([[
    typedef struct{
        uint32_t MessageType;     // _G.rndis_msg_type
        uint32_t MessageLength;   // {format = "dec"}
        uint32_t RequestId;
        uint32_t Status;
        }rndis_set_cmplt_t;
]])

local struct_REMOTE_NDIS_RESET_MSG = html.create_struct([[
    typedef struct{
        uint32_t MessageType;     // _G.rndis_msg_type
        uint32_t MessageLength;   // {format = "dec"}
        uint32_t Reserved;
        } rndis_reset_msg_t;
]])

local struct_REMOTE_NDIS_RESET_CMPLT = html.create_struct([[
    typedef struct{
        uint32_t MessageType;     // _G.rndis_msg_type
        uint32_t MessageLength;   // {format = "dec"}
        uint32_t Status;
        uint32_t AddressingReset;
        }  rndis_reset_cmplt_t;
]])

local struct_REMOTE_NDIS_INDICATE_STATUS_MSG = html.create_struct([[
    typedef struct{
        uint32_t MessageType;     // _G.rndis_msg_type
        uint32_t MessageLength;   // {format = "dec"}
        uint32_t Status;
        uint32_t StatusBufferLength;
        uint32_t StatusBufferOffset;
        }  rndis_indicate_status_t;
]])

local struct_REMOTE_NDIS_KEEPALIVE_MSG = html.create_struct([[
    typedef struct{
        uint32_t MessageType;     // _G.rndis_msg_type
        uint32_t MessageLength;   // {format = "dec"}
        uint32_t RequestId;
        }rndis_keepalive_msg_t;
]])

local struct_REMOTE_NDIS_KEEPALIVE_CMPLT = html.create_struct([[
    typedef struct{
        uint32_t MessageType;     // _G.rndis_msg_type
        uint32_t MessageLength;   // {format = "dec"}
        uint32_t RequestId;
        uint32_t Status;
        }rndis_keepalive_cmplt_t;
]])

local function make_handler(struct_builder)
    return function(data, context)
        return struct_builder:build(data, "RNDIS Data").html
    end
end

msgHandler = {
    [0x00000001] = REMOTE_NDIS_PACKET_MSG_Handler                       , 
    [0X00000002] = make_handler(struct_REMOTE_NDIS_INITIALIZE_MSG)      , 
    [0X00000003] = make_handler(struct_REMOTE_NDIS_HALT_MSG)            , 
    [0X00000004] = make_handler(struct_REMOTE_NDIS_QUERY_MSG)           , 
    [0X00000005] = make_handler(struct_REMOTE_NDIS_SET_MSG)             , 
    [0X00000006] = make_handler(struct_REMOTE_NDIS_RESET_MSG)           , 
    [0X00000007] = make_handler(struct_REMOTE_NDIS_INDICATE_STATUS_MSG) , 
    [0X00000008] = make_handler(struct_REMOTE_NDIS_KEEPALIVE_MSG)       , 
    [0X80000002] = make_handler(struct_REMOTE_NDIS_INITIALIZE_CMPLT)    , 
    [0X80000004] = make_handler(struct_REMOTE_NDIS_QUERY_CMPLT)         , 
    [0X80000005] = make_handler(struct_REMOTE_NDIS_SET_CMPLT)           , 
    [0X80000006] = make_handler(struct_REMOTE_NDIS_RESET_CMPLT)         , 
    [0X80000008] = make_handler(struct_REMOTE_NDIS_KEEPALIVE_CMPLT)     , 
    }

package.loaded["decoder_rndis"] = rndis
