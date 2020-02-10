-- iti1480a.lua
-- encoding: utf-8
require("file_base")
require("pcap_file")  -- not real used, just make sure pcap_file is the first format
local unpack = string.unpack
local pack = string.pack
local fmt = string.format

local ITI1480A_handler = {
    name = "ITI1480A",
    description = "ITI1480A file",
    extension = "*.usb",
    init_read = function(self, file)
        self.ts_utc = 0
        self.ts_offset = 0
        local ts = file:read(4)
        if unpack("I2", file:read(2)) == 0xc040 then
            file:seek("set", 0)
            return true
        end
        return false
    end,
    read_packet = function(self, file)
        local ts = file:read(4)
        if ts then
            local a,b,c,d = unpack("I1I1I1I1", ts)
            ts = (a<<4) | (b &0x0f) | (c<<20) | (d<<12)
            ts = ts * 1000 / 60
        else
            return nil
        end

        local data = file:read(2)
        if  data then data = unpack("I2", data) end
        local v = ""
        while true do
            data = file:read(2)
            if data then data = unpack("I2", data) end
            if data and data ~= 0xc000 then
                v = v .. string.char(data & 0xff)
            else
                break
            end
        end
        if ts and v then
            self.ts_offset = self.ts_offset + ts
            while self.ts_offset > 1000000000 do
                self.ts_utc = self.ts_utc + 1
                self.ts_offset = self.ts_offset - 1000000000
            end
            return self.ts_utc, math.floor(self.ts_offset + 0.5), v
        end
        return nil
    end,
    init_write = function(self, file)
        return true
    end,
    write_packet = function(self, file, ts, nano, pkt)
        self.last_ts = self.last_ts or (ts*1e9 + nano)
        local cur_ts = ts*1e9 + nano
        local d_ts = math.floor( (cur_ts - self.last_ts)*60/1000 + 0.5)
        local a = (d_ts >> 4) & 0xff
        local b = (d_ts & 0x0f) | 0x30
        local c = (d_ts >> 20) & 0xff
        local d = (d_ts >> 12) & 0xff
        file:write(pack("I1I1I1I1",a,b,c,d))
        file:write("\x40\xc0")
        for i=1,#pkt do
            file:write(pkt:sub(i,i), "\x80")
        end
        file:write("\x00\xc0")
        self.last_ts = cur_ts
        return true
    end
}

register_filehandler(ITI1480A_handler)

package.loaded["iti1480a"] = "iti1480a"
