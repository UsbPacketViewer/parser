require("file_base")
local col_w = { 5,5,4,24,14,8 }
local col_name = {"Index","PID","Len","Data(Hex)","Description","Delta"}

function toCol(s, colWidth, pad)
    pad = pad or ' '
    s = tostring(s)
    if #s<colWidth then
        return s .. string.rep(pad, colWidth-#s)
    end
    return s
end
function writeRow(file, rowData, pad)
    for i=1,#col_w do
        file:write(toCol(rowData[i] or "", col_w[i], pad), ' ')
    end
    file:write('\n')
end

local unpack = string.unpack
local function parse_token(name)
    return function(pkt)
        local r = {name, "", ""}
        pkt = pkt .. "\x00\x00\x00"
        local v = unpack("I2", pkt, 2)
        if name == "SOF" then
            local frame = v & 0x7ff
            r[4] = 'FRAME:' .. frame
        else
            local addr = v & 0x7f
            local ep =  (v >> 7) & 0xf
            r[4] = "ADDR: " .. addr .. '.' .. ep
        end
        return r
    end
end
local function parse_handshake(name)
    return function(pkt)
        return {name}
    end
end

local function toHex(data)
    local res = ""
    local sep = ""
    if #data<=8 then
        for i=1,#data do
            res = res .. sep .. string.format("%02X", data:byte(i))
            if i == 4 then res = res .. ' ' end
            sep = ' '
        end
        return res
    end
    
    local rt = {}
    while #data>0 do
        local t = data:sub(1,8)
        rt[#rt+1] = toHex(t)
        if #t < 8 then break end
        data = data:sub(9)
    end
    return rt
end

local function parse_data(name)
    return function(pkt)
        return {name, #pkt-3, toHex(pkt:sub(2,#pkt-2))}
    end
end

local function parse_split(name)
    return function(pkt)
        pkt = pkt .. "\x00\x00\x00\x00"
        local res = {name,"",""}
        local hub, port, crc = unpack("I1I1I1", pkt, 2)
        local addr = hub & 0x7f
        local port = port & 0x7f
        res[4] = "Hub " .. addr..":"..port
        return res
    end
end

local pid_map = {
    [0xe1] = parse_token("OUT"),         -- OUT
    [0x69] = parse_token("IN"),          -- IN
    [0xa5] = parse_token("SOF"),         -- SOF
    [0x2d] = parse_token("SETUP"),       -- SETUP
    [0xb4] = parse_token("PING"),        -- PING

    [0xd2] = parse_handshake("ACK"),     -- ACK
    [0x5a] = parse_handshake("NAK"),     -- NAK
    [0x1e] = parse_handshake("STALL"),   -- STALL
    [0x96] = parse_handshake("NYET"),    -- NYET

    [0xc3] = parse_data("DATA0"),        -- DATA0
    [0x4b] = parse_data("DATA1"),        -- DATA1
    [0x87] = parse_data("DATA2"),        -- DATA2
    [0x0f] = parse_data("MDATA"),        -- MDATA

    [0x3c] = parse_handshake("PRE"),     -- PRE_ERR
    [0x78] = parse_split("SPLIT"),       -- SPLIT
}

local function dt2str(dt)
    if dt>1000000000*60 then
        return string.format("%.2f m", dt/(1000000000*60))
    elseif dt>1000000000 then
        return string.format("%.2f s", dt/1000000000)
    elseif dt>1000000 then
        return string.format("%.2f ms", dt/1000000)
    elseif dt>1000 then
        return string.format("%.2f us", dt/1000)
    end
    return string.format("%.2f ns", dt)
end

local text_handler = {
    name = "text",
    description = "export as text file",
    extension = "*.txt",
    init_write = function(self, file)
        file:write("USB Packet Viewer text file\n");
        file:write("Date: ", os.date(),"\n\n")
        self.writeRow = function(rowData, pad)
            writeRow(file, rowData, pad)
        end
        self.writeRow(col_name);
        self.writeRow({},'-');
        file:write("\n")
        self.index = 0
        self.lastTime = nil
        return true
    end,
    write_packet = function(self, file, ts, nano, pkt, status)
        if #pkt > 0 and pid_map[pkt:byte(1)] then
            self.index = self.index + 1
            local dt = '0'
            local curT = ts*1000000000 + nano
            if self.lastTime then
                local delta = curT - self.lastTime
                dt = dt2str(delta)
                self.lastTime = curT
            else
                self.lastTime = curT
            end
            local r = pid_map[pkt:byte(1)](pkt)
            if type(r[3]) == 'table' then
                for i=1,#r[3] do
                    self.writeRow({
                        self.index,
                        r[1],r[2],r[3][i],r[4],
                        dt
                    })
                    r[1]=''
                    r[2]=''
                    r[4]=''
                end
            else
                self.writeRow({
                    self.index,
                    r[1],r[2],r[3],r[4],
                    dt
                })
            end
        end
        return true
    end
}

register_file_handler(text_handler)
package.loaded["file_text"] = "file_text"
