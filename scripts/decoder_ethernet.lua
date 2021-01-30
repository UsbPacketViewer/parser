-- ethernet.lua
local eth = {}
local html = require("html")
local struct_ip_header = html.create_struct([[
    struct{
        uint8_t  Length:4;  // Length * 4
        uint8_t  Version:4;
        uint8_t  DSCP:6;
        uint8_t  ECN:2;
        uint16_t TotalLength;
        uint16_t ID;
        uint16_t FragementOffset:13;
        uint16_t MoreFragement:1;
        uint16_t DontFragement:1;
        uint16_t Reserved:1;
        uint8_t  TTL;
        uint8_t  Protocol;
        uint16_t HeaderChecksum;
        uint8_t  SourceIP[4];
        uint8_t  DestIP[4];
    }
    ]], {
        TotalLength = {format = "dec"},
        TTL = {format = "dec"},
        SourceIP = {format = "ip"},
        DestIP = {format = "ip"},
        Protocol = { [6] = "TCP", [17] = "UDP", [1] = "ICMP", [2] = "IGMP",},
    }, true)

local function get_ip_html(data, context)
    local ipHeader = struct_ip_header:build(data, "IPv4")
    return ipHeader.html
end

local struct_arp_header = html.create_struct([[
    struct{
        uint16_t  HardwareType;
        uint16_t  ProtocalType;
        uint8_t   HardwareSize;
        uint8_t   ProtocalSize;
        uint16_t  OpCode;
        uint8_t   SenderMac[6];
        uint8_t   SenderIP[4];
        uint8_t   TargetMac[6];
        uint8_t   TargetIP[4];
    }
    ]], {
        HardwareType = { [1] = "Ethernet"},
        ProtocalType = {[0x0800] = "IPv4"},
        SenderIP = {format = "ip"},
        TargetIP = {format = "ip"},
        OpCode = { [1] = "Request", [2] = "Reply" },
    }, true)

local function get_arp_html(data, context)
    local arp = struct_arp_header:build(data, "ARP")
        return arp.html
end

local struct_eth_header = html.create_struct([[
    struct{
        uint8_t  Destination[6];
        uint8_t  Source[6];
        uint16_t Type;
    }
]], {
    Type = {[0x0800] = "IPv4", [0x0806] = "ARP"}
}, true)

eth.parse_data = function(data, context)
    local header = struct_eth_header:build(data, "Ethernet II")
    local bodyHtml = ""
    if header.Type == 0x0800 then
        bodyHtml = bodyHtml .. get_ip_html(data:sub(15), context)
    end
    if header.Type == 0x0806 then
        bodyHtml = bodyHtml .. get_arp_html(data:sub(15), context)
    end
    return header.html .. bodyHtml
end

package.loaded["decoder_ethernet"] = eth
