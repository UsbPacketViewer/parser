-- allwinner sunxi FEL and FES decode

-- protocol are defined in linux-sunxi.org, about more informations:
-- FEL: https://linux-sunxi.org/FEL/Protocol
-- FES: https://linux-sunxi.org/FES

-- qianfan Zhao <qianfanguijin@163.com>

local html = require("html")
local macro_defs = require("macro_defs")
require("usb_register_class")

local fmt = string.format
local unpack = string.unpack

local DIRECTION_DEVICE_TO_HOST = 0x11
local DIRECTION_HOST_TO_DEVICE = 0x12

local struct_fel_awuc = html.create_struct([[
    struct {
        uint32_t magic;
        uint32_t tag;
        uint32_t data_transfer_len;
        uint16_t unused1;
        uint8_t  unused2;
        uint8_t  cmd_len;
        uint8_t  direction;
        uint8_t  unused3;
        uint32_t data_len;
        uint8_t  unused4[10];
    }]], {
        direction = {
            [0x00] = "RESERVED",
            [DIRECTION_DEVICE_TO_HOST] = "-> Host",
            [DIRECTION_HOST_TO_DEVICE] = "-> Device",
            format = "hex",
        }
    }
)

-- AWUC command used in FEL, started with AWUC, 32 bytes.
local function parse_fel_awuc(data, self)
    local cbw = {}

    if self.is_new_cmd == false and #data ~= 32 then
        cbw.html = "<h1>Wrong FEL AWUC length</h1>"
        return cbw
    end

    self.cbw_direction = unpack("I1", data, 17)
    cbw = struct_fel_awuc:build(data, "FEL AWUC")
    cbw.name = "FEL"

    return cbw
end

local struct_awus = html.create_struct([[
    struct {
        uint32_t magic;
        uint32_t tag;
        uint32_t residue;
        uint8_t  status;
    }]], {
        status = {
            [0] = "Passed",
            [1] = "Failed",
        }
    }
)

local function parse_awus(cbw, data, self)
    local csw = {}

    csw.status = "error"
    csw.name = "AWUS"

    if #data ~= 13 then
        csw.html = "<h1>Wrong AWUS length</h1>"
        return csw
    end

    local r = struct_awus:build(data, "AWUS")
    csw.html = r.html

    if r.status == 0 then
        csw.status = "success"
    end

    return csw
end

-- FEL command sets:
local FEL_CMD_VERIFY                    = 0x0001
local FEL_CMD_SWITCH_ROLE               = 0x0002
local FEL_CMD_IS_READY                  = 0x0003
local FEL_CMD_GET_CMD_SET_VER           = 0x0004
local FEL_CMD_DISCONNECT                = 0x0010
local FEL_CMD_DOWNLOAD                  = 0x0101
local FEL_CMD_EXEC                      = 0x0102
local FEL_CMD_READ                      = 0x0103

-- FES command sets:
local FES_CMD_TRANSFER                  = 0x0201
local FES_CMD_DOWNLOAD                  = 0x0206
local FES_CMD_UPLOAD                    = 0x0207
local FES_CMD_QUERY_STORAGE             = 0x0209
local FES_CMD_FLASH_SET_ON              = 0x020a
local FES_CMD_VERIFY_VALUE              = 0x020c
local FES_CMD_VERIFY_STATUS             = 0x020d

local command_names = {
    [FEL_CMD_VERIFY]                    = "Verify",
    [FEL_CMD_SWITCH_ROLE]               = "Switch",
    [FEL_CMD_IS_READY]                  = "Ready?",
    [FEL_CMD_GET_CMD_SET_VER]           = "Version",
    [FEL_CMD_DISCONNECT]                = "Disconnect",
    [FEL_CMD_DOWNLOAD]                  = "Download",
    [FEL_CMD_EXEC]                      = "Exec",
    [FEL_CMD_READ]                      = "Read",
    [FES_CMD_TRANSFER]                  = "Transfer",
    [FES_CMD_DOWNLOAD]                  = "Download",
    [FES_CMD_UPLOAD]                    = "Upload",
    [FES_CMD_QUERY_STORAGE]             = "Storage?",
    [FES_CMD_FLASH_SET_ON]              = "FlashON",
    [FES_CMD_VERIFY_VALUE]              = "VerifyVal",
    [FES_CMD_VERIFY_STATUS]             = "VerifySt",

    -- not a command, it is reported by device.
    -- create it to make the parser happy.
    [0xffff]                            = "Status",
}

local function default_cmd_parser(data, self)
    local cmd = unpack("I2", data)

    return string.format("<h1>%s</h1>", command_names[cmd] or "???")
end

local function cmd_build_html(cmd, data, b)
    local name = command_names[cmd] or "???"

    return b:build(data, name)
end

local function parse_fel_cmd_verify(data, self)
    -- AWUC + VERIFY + AWUS
    -- AWUC + VERIFY RESULT(to host) 32B + AWUS
    self.trans_len = 32
    return default_cmd_parser(data, self)
end

local struct_fel_cmd_download = html.create_struct([[
    struct {
        uint32_t cmd;
        uint32_t addr;
        uint32_t len;
        uint32_t unused;
    }]]
)

local function parse_fel_cmd_download(data, self)
    local b = cmd_build_html(FEL_CMD_DOWNLOAD, data, struct_fel_cmd_download)
    self.trans_len = b.len

    return b.html
end

local function parse_fel_cmd_exec(data, self)
    self.trans_len = 0
    -- FEL_CMD_EXEC has the same struct with FEL_CMD_DOWNLOAD
    return cmd_build_html(FEL_CMD_EXEC, data, struct_fel_cmd_download).html
end

local function parse_fel_cmd_read(data, self)
    -- FEL_CMD_READ has the same struct with FEL_CMD_DOWNLOAD
    local b = cmd_build_html(FEL_CMD_READ, data, struct_fel_cmd_download)

    self.trans_len = b.len
    return b.html
end

local struct_fes_cmd_transfer = html.create_struct([[
    struct {
        uint16_t cmd;
        uint16_t tag;
        uint32_t addr;
        uint32_t len;
        uint8_t  logic_unit:4;
        uint8_t  media_index:4;
        uint8_t  res:4;
        uint8_t  dir:2;
        uint8_t  ooc:2;
        uint16_t unused;
    }]], {
        dir = {
            [0] = "download",
            [1] = "download",
            [2] = "upload",
        }
    }
)

local function parse_fes_cmd_transfer(data, self)
    self.trans_len = unpack("I4", data, 9)

    return cmd_build_html(FES_CMD_TRANSFER, data, struct_fes_cmd_transfer).html
end

-- parse the command host send to device
local fel_command_parses = {
    [FEL_CMD_VERIFY]                = parse_fel_cmd_verify,
    [FEL_CMD_SWITCH_ROLE]           = default_cmd_parser,
    [FEL_CMD_IS_READY]              = default_cmd_parser,
    [FEL_CMD_GET_CMD_SET_VER]       = default_cmd_parser,
    [FEL_CMD_DISCONNECT]            = default_cmd_parser,
    [FEL_CMD_DOWNLOAD]              = parse_fel_cmd_download,
    [FEL_CMD_EXEC]                  = parse_fel_cmd_exec,
    [FEL_CMD_READ]                  = parse_fel_cmd_read,
    [FES_CMD_TRANSFER]              = parse_fes_cmd_transfer,
}

local struct_fes_trans_param = html.create_struct([[
    struct {
        uint16_t cmd;
        uint16_t tag;
        uint32_t addr;
        uint32_t len;
        uint32_t data_type;
    }]], {
        data_type = {
            [0x7f00] = "DRAM",
            [0x7f01] = "MBR",
            [0x7f02] = "BOOT1",
            [0x7f03] = "BOOT0",
            [0x7f04] = "ERASE",
            [0x7f05] = "PMU",
            [0x7f06] = "UNSEQ_READ",
            [0x7f07] = "UNSEQ_WRITE",
            [0x7f10] = "FULLIMG_SIZE",
            [0x17f00] = "(finish)DRAM",
            [0x17f01] = "(finish)MBR",
            [0x17f02] = "(finish)BOOT1",
            [0x17f03] = "(finish)BOOT0",
            [0x17f04] = "(finish)ERASE",
            [0x17f05] = "(finish)PMU",
            [0x17f06] = "(finish)UNSEQ_READ",
            [0x17f07] = "(finish)UNSEQ_WRITE",
            [0x17f10] = "(finish)FULLIMG_SIZE",
        }
    }
)

local function parse_fes_cmd_download(data, self)
    self.trans_len = unpack("I4", data, 9)

    return cmd_build_html(FES_CMD_DOWNLOAD, data, struct_fes_trans_param).html
end

local struct_fes_cmd_verify_status = html.create_struct([[
    struct {
        uint16_t cmd;
        uint16_t tag;
        uint32_t start;
        uint32_t size;
        uint32_t data_tag;
    }]]
)

local function parse_fes_cmd_verify_status(data, self)
    self.trans_len = 12
    self.cbw_direction = DIRECTION_DEVICE_TO_HOST
    return cmd_build_html(FES_CMD_VERIFY_STATUS, data, struct_fes_cmd_verify_status).html
end

local function parse_fes_cmd_query_storage(data, self)
    self.trans_len = 4
    self.cbw_direction = DIRECTION_DEVICE_TO_HOST

    return default_cmd_parser(data, self)
end

local function parse_fes_cmd_flash_set_on(data, self)
    self.trans_len = 0

    return default_cmd_parser(data, self)
end

local struct_fes_cmd_verify_value = html.create_struct([[
    struct {
        uint16_t cmd;
        uint16_t tag;
        uint32_t start;
        uint32_t size;
        uint32_t unused;
    }]]
)

local function parse_fes_cmd_verify_value(data, self)
    self.trans_len = 12
    self.cbw_direction = DIRECTION_DEVICE_TO_HOST

    return cmd_build_html(FES_CMD_VERIFY_VALUE, data, struct_fes_cmd_verify_value).html
end

local fes_command_parses = {
    [FES_CMD_DOWNLOAD]          = parse_fes_cmd_download,
    [FES_CMD_VERIFY_STATUS]     = parse_fes_cmd_verify_status,
    [FES_CMD_QUERY_STORAGE]     = parse_fes_cmd_query_storage,
    [FES_CMD_FLASH_SET_ON]      = parse_fes_cmd_flash_set_on,
    [FES_CMD_VERIFY_VALUE]      = parse_fes_cmd_verify_value,
}

-- AWUC command used in FES, 20 bytes and ending with AWUC
local function parse_fes_awuc(data, self)
    local cbw = { }
    local cmd = unpack("I2", data)
    local f = fes_command_parses[cmd]

    self.last_cmd = cmd
    cbw.name = command_names[cmd] or "???"

    -- set the default direction HOST_TO_DEVICE, the parse function
    -- should change the direction if it is DEVICE_TO_HOST.
    self.cbw_direction = DIRECTION_HOST_TO_DEVICE

    if f then
        cbw.html = f(data, self)
    else
        cbw.html = "<h1>doesn't support now</h1>"
    end

    return cbw
end

local struct_fel_cmd_data_verify = html.create_struct([[
    struct {
        uint8_t  magic[8];
        uint32_t platform_id_hw;
        uint32_t platform_id_fw;
        uint16_t mode;
        uint8_t  phoenix_data_flag;
        uint8_t  phoenix_data_len;
        uint32_t phoenix_data_start_addr;
        uint8_t  unused[2];
    }]]
)

local function parse_fes_cmd_data_verify(data, self)
    return cmd_build_html(FEL_CMD_VERIFY, data, struct_fel_cmd_data_verify).html
end

local function parse_fes_cmd_data_switch_role(data, self)
    return default_cmd_parser(data, self)
end

local struct_fel_cmd_data_is_ready = html.create_struct([[
    struct {
        uint16_t state;
        uint16_t interval_ms;
        uint8_t  unused[12];
    }]], {
        state = {
            [0x00] = "NULL",
            [0x01] = "BUSY",
            [0x02] = "READY",
            [0x03] = "FAIL",
            format = "dec",
        }
    }
)

local function parse_fes_cmd_data_is_ready(data, self)
    return cmd_build_html(FEL_CMD_IS_READY, data, struct_fel_cmd_data_is_ready).html
end

local function parse_fes_cmd_data_disconnect(data, self)
    return default_cmd_parser(data, self)
end

local struct_fes_cmd_verify_status = html.create_struct([[
    struct {
        uint32_t tag;
        uint32_t fes_crc;
        uint32_t media_crc;
    }]]
)

local function parse_fes_cmd_verify_status(data, self)
    return cmd_build_html(FES_CMD_VERIFY_STATUS, data, struct_fes_cmd_verify_status).html
end

local struct_fes_cmd_data_query_storage = html.create_struct([[
    struct {
        uint32_t storage;
    }]], {
        storage = {
            [0] = "NAND",
            [1] = "SD",
            [2] = "EMMC",
            [3] = "NOR",
        }
    }
)

local function parse_fes_cmd_data_query_storage(data, self)
    return cmd_build_html(FES_CMD_QUERY_STORAGE, data, struct_fes_cmd_data_query_storage).html
end

-- parse the command device response to host
local command_data_parses = {
    [FEL_CMD_VERIFY]                = parse_fes_cmd_data_verify,
    [FEL_CMD_SWITCH_ROLE]           = parse_fes_cmd_data_is_ready,
    [FEL_CMD_IS_READY]              = parse_fel_cmd_is_ready,
    [FEL_CMD_DISCONNECT]            = parse_fel_cmd_disconnect,

    [FES_CMD_VERIFY_STATUS]         = parse_fes_cmd_verify_status,
    [FES_CMD_QUERY_STORAGE]         = parse_fes_cmd_data_query_storage,

    -- VERIFY_VALUE has the same response with VERIFY_STATUS
    [FES_CMD_VERIFY_VALUE]          = parse_fes_cmd_verify_status,
}

local struct_app_report_status = html.create_struct([[
    struct {
        uint16_t mark;
        uint16_t tag;
        uint8_t  status;
        uint8_t  unused[3];
    }]]
)

local function parse_app_report_status(data, self)
    self.last_cmd = 0xffff
    return cmd_build_html(self.last_cmd, data, struct_app_report_status).html
end

local function parse_data(cbw, data, self)
    local default_debug_info = string.format("Debug informations<br> \
                         direction: 0x%x<br> \
                         last_cmd: 0x%x<br> \
                         trans_len: %d<br> \
                         data_size: %d",
                         self.cbw_direction or 0xFFFFFFFF,
                         self.last_cmd or 0xFFFFFFFF,
                         self.trans_len or -1,
                         #data
                        )

    if self.cbw_direction == DIRECTION_HOST_TO_DEVICE then
        if self.last_cmd == FES_CMD_TRANSFER or
           self.last_cmd == FES_CMD_DOWNLOAD or
           self.last_cmd == FEL_CMD_DOWNLOAD then
            if self.trans_len == #data then
                local length = self.trans_len

                self.trans_len = 0

                return string.format("<h1>TRANSFER DATA(to device)</h1><br>\
                                          See data Window<br>\
                                          length = %d<br>", length)
            else
                -- the command and transfer data doesn't match,
                -- clear state machine and try again
                self.last_cmd = 0
                self.trans_len = 0
                parse_data(cbw, data, self)
            end
        elseif self.is_new_cmd == false then -- FEL formater
            if #data == 16 then -- commnad
                local op = unpack("I2", data)
                local f = fel_command_parses[op]

                if f then
                    self.last_cmd = op
                    return f(data, self)
                end
            end
        end
    elseif self.cbw_direction == DIRECTION_DEVICE_TO_HOST then
        if self.last_cmd ~= 0 then
            if self.last_cmd == FES_CMD_TRANSFER or
               self.last_cmd == FEL_CMD_READ then
                if self.trans_len == #data then
                    local length = self.trans_len

                    self.trans_len = 0

                    return string.format("<h1>TRANSFER DATA(to host)</h1><br>\
                                          See data Window<br>\
                                          length = %d<br>", length)
                else
                    -- clear state machine and try again
                    self.last_cmd = 0
                    self.trans_len = 0
                    parse_data(cbw, data, self)
                end
            else
                local f = command_data_parses[self.last_cmd]

                -- clear self.trans_len so that on_transaction could clear last_cmd
                -- don't clear self.last_cmd due to we display the name of last_cmd
                -- in on_transaction.
                self.trans_len = 0

                if f then
                    local html = f(data, self)
                    if html then
                        return html
                    end
                end
            end
        end

        -- if the topper level doesn't match, try parser as report status
        -- CBW/CBS done, the device report status
        if #data == 8 then
            return parse_app_report_status(data, self)
        end
    end

    return "<h1>Unknow DATA</h1>" .. default_debug_info
end

local device = {}
device.name = "allwinner"

local cls = {}
cls.name = "FEL/FES"
cls.endpoints = { EP_IN("Incoming Data"), EP_OUT("Outgoing Data") }

function cls.on_transaction(self, param, data, needDetail, forceBegin)
    local addr, ep, pid, ack = param:byte(1), param:byte(2), param:byte(3), param:byte(4)
    local context = self:get_context(needDetail)

    self.addr = addr
    self.cbw_direction = self.cbw_direction or DIRECTION_HOST_TO_DEVICE
    self.last_cmd = self.last_cmd or 0
    self.trans_len = self.trans_len or -1

    context.state = context.state or macro_defs.ST_CBW
    if forceBegin then
        context.state = macro_defs.ST_CBW
    end
    if #data == 32 and data:sub(1,4) == "AWUC" then
        context.state = macro_defs.ST_CBW
        self.is_new_cmd = false
    end
    if #data == 20 and data:sub(-4) == "AWUC" then
        -- allwinner fes new command
        context.state = macro_defs.ST_CBW
        self.is_new_cmd = true
    end
    if #data == 13 and data:sub(1,4) == "AWUS" then
        context.state = macro_defs.ST_CSW
    end

    if context.state == macro_defs.ST_CBW then
        if self.is_new_cmd == true and #data ~= 20 then
            return macro_defs.RES_NONE
        elseif self.is_new_cmd == false and #data ~= 32 then
            return macro_defs.RES_NONE
        end
        if ack ~= macro_defs.PID_ACK then
            return macro_defs.RES_NONE
        end

        local xfer_len = 0
        local parse_result
        local title

        if self.is_new_cmd == false then
            xfer_len = unpack("I4", data, 9)
            parse_result = parse_fel_awuc(data, self)
            title = "FEL"
        else
            parse_result = parse_fes_awuc(data, self)
            xfer_len = self.trans_len
            title = "FES"
        end

        if xfer_len > 0 then
            context.state = macro_defs.ST_DATA
        else
            context.state = macro_defs.ST_CSW
        end

        context.data = ""
        context.xfer_len = xfer_len
        if needDetail then
            context.cbw = parse_result
            context.infoHtml = context.cbw.html
            context.title = title
            context.name =  title
            context.desc = context.cbw.name
            context.status = "incomp"
            return macro_defs.RES_BEGIN, self.upv.make_xact_res("AWUC", context.cbw.html, data), self.upv.make_xfer_res(context)
        end
        return macro_defs.RES_BEGIN
    elseif context.state == macro_defs.ST_DATA then
        if ack == macro_defs.PID_STALL then
            context.state = macro_defs.ST_CSW
            if needDetail then
                context.status = "stall"
                return macro_defs.RES_MORE, self.upv.make_xact_res("Stall", "", data), self.upv.make_xfer_res(context)
            end
            return macro_defs.RES_MORE
        end
        context.data = context.data .. data
        if self.upv:is_short_packet(addr, ep, data) then
            context.state = macro_defs.ST_CSW
        elseif #context.data == context.xfer_len then
            context.state = macro_defs.ST_CSW
        end
        if needDetail then
            if context.state == macro_defs.ST_CSW then
                context.infoHtml = (context.infoHtml or "") .. parse_data(context.cbw, context.data, self)
                -- try update context.desc based on self.last_cmd if it is FEL command.
                -- because command defined in DATA sections.
                if self.is_new_cmd == false and self.last_cmd ~= 0 then
                    context.desc = command_names[self.last_cmd] or "???"
                end

                if self.trans_len <= 0 then
                    -- transfer is done
                    self.last_cmd = 0
                end
            end
            return macro_defs.RES_MORE, self.upv.make_xact_res("DATA", "", data), self.upv.make_xfer_res(context)
        end
        return macro_defs.RES_MORE
    elseif context.state == macro_defs.ST_CSW then
        if ack == macro_defs.PID_STALL then
            return macro_defs.RES_MORE
        end
        if ack ~= macro_defs.PID_ACK then
            return macro_defs.RES_END
        end
        if #data ~= 13 then
            return macro_defs.RES_END
        end
        if needDetail then
            local status = parse_awus(context.cbw, data, self)
            context.infoHtml = (context.infoHtml or "") .. status.html
            context.data = context.data or ""
            context.title = context.title or ""
            context.name = context.name or ""
            context.desc = context.desc or ""
            context.status = status.status
            return macro_defs.RES_END, self.upv.make_xact_res("AWUS", status.html, data), self.upv.make_xfer_res(context)
        end
        return macro_defs.RES_END
    else
        context.state = macro_defs.ST_CBW
        return macro_defs.RES_NONE
    end
end

function device.get_interface_handler(self, itf_number)
    return cls
end

register_device_handler(device, 0x1f3a, 0xefe8)
register_class_handler(cls)
package.loaded["usb_device_aw_efex"] = cls
