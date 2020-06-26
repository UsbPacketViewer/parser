-- rndis.lua
local html = require("html")
local eth = require("ethernet")
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

local msgHandler


local function parseMessage(data, context)
    data = data or ""
    local header = html.makeStruct(data, "RNDIS Data",[[
        typedef struct{
            uint32_t MessageType;
            uint32_t MessageLength;
        }
    ]])
    if not msgType[header.MessageType] or not msgHandler[header.MessageType] then
        return "<h1>Unknown Message Type " .. string.format("0x%08X", header.MessageType) .."</h1>"
    end
    return msgHandler[header.MessageType](data, context)
end

rndis.parseData = parseMessage
rndis.parseResponse = parseMessage
rndis.parseCommand = parseMessage

local function REMOTE_NDIS_PACKET_MSG_Handler(data, context)
    local header = html.makeStruct(data, "RNDIS Data",[[
        typedef struct{
            uint32_t MessageType;
            uint32_t MessageLength;
            uint32_t DataOffset;
            uint32_t DataLength;
            uint32_t OOBDataOffset;
            uint32_t OOBDataLength;
            uint32_t NumOOBDataElements;
            uint32_t PerPacketInfoOffset;
            uint32_t PerPacketInfoLength;
            uint32_t DeviceVcHandle;
            uint32_t Reserved;
            }rndis_data_packet_t;
    ]], {
        MessageType = msgType,
        MessageLength = {format = "dec"},
        DataLength = {format = "dec"},
    })
    data = data:sub(45)
    local bodyHtml = eth.parseData(data, context)
    return header.html .. bodyHtml
end

local function REMOTE_NDIS_INITIALIZE_MSG_Handler(data, context)
    local header = html.makeStruct(data, "RNDIS Data",[[
        typedef struct{
            uint32_t MessageType;
            uint32_t MessageLength;
            uint32_t RequestId;
            uint32_t MajorVersion;
            uint32_t MinorVersion;
            uint32_t MaxTransferSize;
            }rndis_initialize_msg_t;
    ]], {
        MessageType = msgType,
        MessageLength = {format = "dec"},
    })
    return header.html
end

local function REMOTE_NDIS_INITIALIZE_CMPLT_Handler(data, context)
    local header = html.makeStruct(data, "RNDIS Data",[[
        typedef struct{
            uint32_t MessageType;
            uint32_t MessageLength;
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
    ]], {
        MessageType = msgType,
        MessageLength = {format = "dec"},
    })
    return header.html
end

local function REMOTE_NDIS_HALT_MSG_Handler(data, context)
    local header = html.makeStruct(data, "RNDIS Data",[[
        typedef struct{
            uint32_t MessageType;
            uint32_t MessageLength;
            uint32_t RequestId;
            } rndis_halt_msg_t;
    ]], {
        MessageType = msgType,
        MessageLength = {format = "dec"},
    })
    return header.html
end

local function REMOTE_NDIS_QUERY_MSG_Handler(data, context)
    local header = html.makeStruct(data, "RNDIS Data",[[
        typedef struct{
            uint32_t MessageType;
            uint32_t MessageLength;
            uint32_t RequestId;
            uint32_t Oid;
            uint32_t InformationBufferLength;
            uint32_t InformationBufferOffset;
            uint32_t DeviceVcHandle;
            } rndis_query_msg_t;
    ]], {
        MessageType = msgType,
        MessageLength = {format = "dec"},
    })
    return header.html
end

local function REMOTE_NDIS_QUERY_CMPLT_Handler(data, context)
    local header = html.makeStruct(data, "RNDIS Data",[[
        typedef struct{
            uint32_t MessageType;
            uint32_t MessageLength;
            uint32_t RequestId;
            uint32_t Status;
            uint32_t InformationBufferLength;
            uint32_t InformationBufferOffset;
            } rndis_query_cmplt_t;
    ]], {
        MessageType = msgType,
        MessageLength = {format = "dec"},
    })
    return header.html
end

local function REMOTE_NDIS_SET_MSG_Handler(data, context)
    local header = html.makeStruct(data, "RNDIS Data",[[
        typedef struct{
            uint32_t MessageType;
            uint32_t MessageLength;
            uint32_t RequestId;
            uint32_t Oid;
            uint32_t InformationBufferLength;
            uint32_t InformationBufferOffset;
            uint32_t DeviceVcHandle;
            } rndis_set_msg_t;
    ]], {
        MessageType = msgType,
        MessageLength = {format = "dec"},
    })
    return header.html
end

local function REMOTE_NDIS_SET_CMPLT_Handler(data, context)
    local header = html.makeStruct(data, "RNDIS Data",[[
        typedef struct{
            uint32_t MessageType;
            uint32_t MessageLength;
            uint32_t RequestId;
            uint32_t Status;
            }rndis_set_cmplt_t;
    ]], {
        MessageType = msgType,
        MessageLength = {format = "dec"},
    })
    return header.html
end

local function REMOTE_NDIS_RESET_MSG_Handler(data, context)
    local header = html.makeStruct(data, "RNDIS Data",[[
        typedef struct{
            uint32_t MessageType;
            uint32_t MessageLength;
            uint32_t Reserved;
            } rndis_reset_msg_t;
    ]], {
        MessageType = msgType,
        MessageLength = {format = "dec"},
    })
    return header.html
end

local function REMOTE_NDIS_RESET_CMPLT_Handler(data, context)
    local header = html.makeStruct(data, "RNDIS Data",[[
        typedef struct{
            uint32_t MessageType;
            uint32_t MessageLength;
            uint32_t Status;
            uint32_t AddressingReset;
            }  rndis_reset_cmplt_t;
    ]], {
        MessageType = msgType,
        MessageLength = {format = "dec"},
    })
    return header.html
end

local function REMOTE_NDIS_INDICATE_STATUS_MSG_Handler(data, context)
    local header = html.makeStruct(data, "RNDIS Data",[[
        typedef struct{
            uint32_t MessageType;
            uint32_t MessageLength;
            uint32_t Status;
            uint32_t StatusBufferLength;
            uint32_t StatusBufferOffset;
            }  rndis_indicate_status_t;
    ]], {
        MessageType = msgType,
        MessageLength = {format = "dec"},
    })
    return header.html
end

local function REMOTE_NDIS_KEEPALIVE_MSG_Handler(data, context)
    local header = html.makeStruct(data, "RNDIS Data",[[
        typedef struct{
            uint32_t MessageType;
            uint32_t MessageLength;
            uint32_t RequestId;
            }rndis_keepalive_msg_t;
    ]], {
        MessageType = msgType,
        MessageLength = {format = "dec"},
    })
    return header.html
end

local function REMOTE_NDIS_KEEPALIVE_CMPLT_Handler(data, context)
    local header = html.makeStruct(data, "RNDIS Data",[[
        typedef struct{
            uint32_t MessageType;
            uint32_t MessageLength;
            uint32_t RequestId;
            uint32_t Status;
            }rndis_keepalive_cmplt_t;
    ]], {
        MessageType = msgType,
        MessageLength = {format = "dec"},
    })
    return header.html
end

msgHandler = {
    [0x00000001] = REMOTE_NDIS_PACKET_MSG_Handler          , 
    [0X00000002] = REMOTE_NDIS_INITIALIZE_MSG_Handler      , 
    [0X00000003] = REMOTE_NDIS_HALT_MSG_Handler            , 
    [0X00000004] = REMOTE_NDIS_QUERY_MSG_Handler           , 
    [0X00000005] = REMOTE_NDIS_SET_MSG_Handler             , 
    [0X00000006] = REMOTE_NDIS_RESET_MSG_Handler           , 
    [0X00000007] = REMOTE_NDIS_INDICATE_STATUS_MSG_Handler , 
    [0X00000008] = REMOTE_NDIS_KEEPALIVE_MSG_Handler       , 
    [0X80000002] = REMOTE_NDIS_INITIALIZE_CMPLT_Handler    , 
    [0X80000004] = REMOTE_NDIS_QUERY_CMPLT_Handler         , 
    [0X80000005] = REMOTE_NDIS_SET_CMPLT_Handler           , 
    [0X80000006] = REMOTE_NDIS_RESET_CMPLT_Handler         , 
    [0X80000008] = REMOTE_NDIS_KEEPALIVE_CMPLT_Handler     , 
    }

package.loaded["rndis"] = rndis
