-- file_pcap.lua
-- encoding: utf-8
require("file_base")
local unpack = string.unpack
local pack = string.pack
local fmt = string.format
local DLT_USBLL = 288
local PCAP_MS_MAGIC = 0xa1b2c3d4
local PCAP_NANO_MAGIC = 0xa1b23c4d
local pcap_handler = {
    name = "pcap",
    description = "wireshark pcap file",
    extension = "*.pcap",
    init_read = function(self, file)
        local header = file:read(24)
        if not header then return false end
        if #header ~= 24  then return false end
        local magic =  unpack("I4", header)
        local dlt = unpack("I4", header, 21)
        if      magic == PCAP_MS_MAGIC and dlt == DLT_USBLL then
            self.mul = 1000
            return true
        elseif  magic == PCAP_NANO_MAGIC and dlt == DLT_USBLL then
            self.mul = 1
            return true
        end
        return false
    end,
    read_packet = function(self, file)
        local t = file:read(16)
        if not t then return nil end
        if #t < 16 then return nil end
        local ts, nano, act_len, org_len = unpack("I4I4I4I4", t)
        local pkt = file:read(act_len)
        if not pkt then return nil end
        if #pkt ~= act_len then return nil end
        return ts, nano*self.mul, pkt, 0
    end,
    init_write = function(self, file)
        file:write(pack("I4", PCAP_NANO_MAGIC))
        file:write("\x02\x00\x04\x00")
        file:write(pack("I4I4I4I4", 0,0,65535, DLT_USBLL))
        return true
    end,
    write_packet = function(self, file, ts, nano, pkt, status)
        file:write(pack("I4I4I4I4",ts,nano,#pkt,#pkt), pkt)
        return true
    end
}

register_file_handler(pcap_handler)

package.loaded["file_pcap"] = "file_pcap"
