-- transaction parser in lua
local VALID_ADDR = {14}
local VALID_EP   = {3}
local VALID_TOKEN = {"IN"}
local VALID_ACK = {"ACK"}
local SHOW_DATA_DESC = false

require("file_base")


local VALID_ADDR_map = {}
local VALID_EP_map = {}
local VALID_TOKEN_map = {}
local VALID_ACK_map = {}

for k,v in ipairs(VALID_ADDR) do VALID_ADDR_map[v]=true end
for k,v in ipairs(VALID_EP) do VALID_EP_map[v]=true end
for k,v in ipairs(VALID_TOKEN) do VALID_TOKEN_map[v]=true end
for k,v in ipairs(VALID_ACK) do VALID_ACK_map[v]=true end

local function filter_data(self)
    if #VALID_ADDR > 0 then
        if not VALID_ADDR_map[self.addr] then
            return false
        end
    end

    if #VALID_EP > 0 then
        if not VALID_EP_map[self.ep] then
            return false
        end
    end

    if #VALID_TOKEN > 0 then
        if not VALID_TOKEN_map[self.token] then
            return false
        end
    end

    if #VALID_ACK > 0 then
        if not VALID_ACK_map[self.ack] then
            return false
        end
    end

    return true
end


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

local S_IDLE  = 0
local S_SETUP = 1
local S_DATA  = 2
local S_ACK   = 3
local function get_token(name)
    return function (pkt)
        pkt = pkt .. "\x00\x00\x00"
        local v = unpack("I2", pkt, 2)
        local addr = v & 0x7f
        local ep =  (v >> 7) & 0xf
        return S_SETUP, name, addr, ep
    end
end

local function get_data(name)
    return function (pkt)
        return S_DATA, name, pkt:sub(2,#pkt-2)
    end
end

local function get_ack(name)
    return function (pkt)
        return S_ACK, name
    end
end

local function parse_handshake(name)
    return function(pkt)
        return {name}
    end
end

local function toHex(data, max)
    local res = ""
    local sep = ""
    if not max then
        max = 8
    end
    if #data<=max then
        for i=1,#data do
            res = res .. sep .. string.format("%02X", data:byte(i))
            --if i == 4 then res = res .. ' ' end
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

-- local pid_map = {
--     [0xe1] = parse_token("OUT"),         -- OUT
--     [0x69] = parse_token("IN"),          -- IN
--     [0xa5] = parse_token("SOF"),         -- SOF
--     [0x2d] = parse_token("SETUP"),       -- SETUP
--     [0xb4] = parse_token("PING"),        -- PING

--     [0xd2] = parse_handshake("ACK"),     -- ACK
--     [0x5a] = parse_handshake("NAK"),     -- NAK
--     [0x1e] = parse_handshake("STALL"),   -- STALL
--     [0x96] = parse_handshake("NYET"),    -- NYET

--     [0xc3] = parse_data("DATA0"),        -- DATA0
--     [0x4b] = parse_data("DATA1"),        -- DATA1
--     [0x87] = parse_data("DATA2"),        -- DATA2
--     [0x0f] = parse_data("MDATA"),        -- MDATA

--     [0x3c] = parse_handshake("PRE"),     -- PRE_ERR
--     [0x78] = parse_split("SPLIT"),       -- SPLIT
-- }

local pid_map = {
    [0xe1] = get_token("OUT"),         -- OUT
    [0x69] = get_token("IN"),          -- IN
    --[0xa5] = parse_token("SOF"),         -- SOF
    [0x2d] = get_token("SETUP"),       -- SETUP
    --[0xb4] = parse_token("PING"),        -- PING

    [0xd2] = get_ack("ACK"),     -- ACK
    [0x5a] = get_ack("NAK"),     -- NAK
    [0x1e] = get_ack("STALL"),   -- STALL
    [0x96] = get_ack("NYET"),    -- NYET

    [0xc3] = get_data("DATA0"),        -- DATA0
    [0x4b] = get_data("DATA1"),        -- DATA1
    [0x87] = get_data("DATA2"),        -- DATA2
    [0x0f] = get_data("MDATA"),        -- MDATA

    -- [0x3c] = parse_handshake("PRE"),     -- PRE_ERR
    -- [0x78] = parse_split("SPLIT"),       -- SPLIT
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
    name = "transaction parse",
    description = "export transaction data",
    extension = "*.tra",
    init_write = function(self, file)
        file:write("USB Packet Viewer transaction data\n");
        file:write("Date: ", os.date(),"\n\n")
        -- self.writeRow = function(rowData, pad)
        --     writeRow(file, rowData, pad)
        -- end
        -- self.writeRow(col_name);
        -- self.writeRow({},'-');
        -- file:write("\n")
        self.index = 0
        self.lastTime = nil
        self.state = S_IDLE
        self.data = ""
        self.addr = 0
        self.ep = 0
        self.token = ""
        return true
    end,
    write_packet2 = function(self, file, ts, nano, pkt, status)
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
    end,
    write_packet = function(self,file,ts,nano,pkt, status)
        if #pkt<1 then
            return true
        end
        local act = pid_map[pkt:byte(1)]
        if not act then
            return true
        end
        local s, n, r1, r2 = act(pkt)
        if s == S_SETUP then
            if self.state == S_DATA then
                self.ack = "ISO"
                if filter_data(self) then
                    if SHOW_DATA_DESC then
                        file:write(self.token, " ", tostring(self.addr),".", tostring(self.ep), "  ", self.ack, " len =", #self.data, "\n")
                    end
                    file:write(toHex(self.data, 2048), "\n")
                end
                --file:write(self.token, tostring(self.addr),".", tostring(self.ep)," ISO ", toHex(self.data, 2048), "\n")
            end
            self.token = n
            self.state = S_SETUP
            self.addr = r1
            self.ep = r2
            self.data = ""
        elseif s == S_DATA then
            if self.state == S_SETUP then
                self.data = r1
                self.state = S_DATA
            else
                self.state = S_IDLE
            end
        elseif s == S_ACK then
            self.ack = n
            if self.state == S_DATA then
                if filter_data(self) then
                    if SHOW_DATA_DESC then
                        file:write(self.token, " ", tostring(self.addr),".", tostring(self.ep), "  ", self.ack, " len =", #self.data, "\n")
                    end
                    file:write(toHex(self.data, 2048), "\n")
                end
                --file:write(self.token, tostring(self.addr),".", tostring(self.ep)," "..n.." ", toHex(self.data, 2048), "\n")
            end
            self.state = S_IDLE
        end
        return true
    end
}

register_file_handler(text_handler)
package.loaded["file_tran_parser"] = "file_tran_parser"
