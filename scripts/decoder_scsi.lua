-- scsi.lua
-- scsi command, data, status parser
-- https://www.usb.org/sites/default/files/usbmassbulk_10.pdf

local scsi = {}
local fmt = string.format
local unpack = string.unpack
local util = require("util")
local html = require("html")

local SCSI_CMD_TEST_UNIT_READY               = 0x00
local SCSI_CMD_REQUEST_SENSE                 = 0x03
local SCSI_CMD_INQUIRY                       = 0x12
local SCSI_CMD_MODE_SELECT_6                 = 0x15
local SCSI_CMD_MODE_SENSE_6                  = 0x1A
local SCSI_CMD_MODE_SELECT_10                = 0x55
local SCSI_CMD_MODE_SENSE_10                 = 0x5A
local SCSI_CMD_START_STOP_UNIT               = 0x1B
local SCSI_CMD_PREVENT_ALLOW_MEDIUM_REMOVAL  = 0x1E
local SCSI_CMD_READ_CAPACITY_10              = 0x25
local SCSI_CMD_READ_FORMAT_CAPACITY          = 0x23
local SCSI_CMD_READ_10                       = 0x28
local SCSI_CMD_WRITE_10                      = 0x2A
local SCSI_CMD_VERIFY_10                     = 0x2F
local SCSI_CMD_SYNC_CACHE_10                 = 0x35

local VPD_CODE = {
    VPD_SUPPORTED_VPDS      = 0x0 ,
    VPD_UNIT_SERIAL_NUM     = 0x80,
    VPD_IMP_OP_DEF          = 0x81,    -- /* obsolete in SPC-2 */
    VPD_ASCII_OP_DEF        = 0x82,    -- /* obsolete in SPC-2 */
    VPD_DEVICE_ID           = 0x83,
    VPD_SOFTW_INF_ID        = 0x84,
    VPD_MAN_NET_ADDR        = 0x85,
    VPD_EXT_INQ             = 0x86,
    VPD_MODE_PG_POLICY      = 0x87,
    VPD_SCSI_PORTS          = 0x88,
    VPD_ATA_INFO            = 0x89,
    VPD_POWER_CONDITION     = 0x8a,
    VPD_DEVICE_CONSTITUENTS = 0x8b,
    VPD_CFA_PROFILE_INFO    = 0x8c,
    VPD_POWER_CONSUMPTION   = 0x8d,
    VPD_3PARTY_COPY         = 0x8f,
    VPD_PROTO_LU            = 0x90,
    VPD_PROTO_PORT          = 0x91,
    VPD_SCSI_FEATURE_SETS   = 0x92,     -- /* spc5r11 */
    VPD_BLOCK_LIMITS        = 0xb0,     -- /* SBC-3 */
    VPD_SA_DEV_CAP          = 0xb0,     -- /* SSC-3 */
    VPD_OSD_INFO            = 0xb0,     -- /* OSD */
    VPD_BLOCK_DEV_CHARS     = 0xb1,     -- /* SBC-3 */
    VPD_MAN_ASS_SN          = 0xb1,     -- /* SSC-3, ADC-2 */
    VPD_SECURITY_TOKEN      = 0xb1,     -- /* OSD */
    VPD_ES_DEV_CHARS        = 0xb1,     -- /* SES-4 */
    VPD_TA_SUPPORTED        = 0xb2,     -- /* SSC-3 */
    VPD_LB_PROVISIONING     = 0xb2,     -- /* SBC-3 */
    VPD_REFERRALS           = 0xb3,     -- /* SBC-3 */
    VPD_AUTOMATION_DEV_SN   = 0xb3,     -- /* SSC-3 */
    VPD_SUP_BLOCK_LENS      = 0xb4,     -- /* sbc4r01 */
    VPD_DTDE_ADDRESS        = 0xb4,     -- /* SSC-4 */
    VPD_BLOCK_DEV_C_EXTENS  = 0xb5,     -- /* sbc4r02 */
    VPD_LB_PROTECTION       = 0xb5,     -- /* SSC-5 */
    VPD_ZBC_DEV_CHARS       = 0xb6,     -- /* zbc-r01b */
    VPD_BLOCK_LIMITS_EXT    = 0xb7,     -- /* sbc4r08 */
}

local VPD_NAME = {}
for k,v in pairs(VPD_CODE) do
    VPD_NAME[v] = k
end

local DEVICE_TYPE = {
    [0x00] = "BLOCK_DEVICE",
    [0x01] = "SEQ_DEVICE",
    [0x02] = "PRINTER",
    [0x03] = "PROCESSOR",
    [0x04] = "WRITE_ONCE",
    [0x05] = "CD_DVD",
}

local struct_inquiry_std_data = html.create_struct( [[
    typedef struct
    {
      uint8_t peripheral_device_type: 5;   /**< \ref scsi_peripheral_device_type */
      uint8_t peripheral_qualifier  : 3;
    
      uint8_t reserved1 : 7;
      uint8_t removable : 1;
    
      uint8_t version;
    
      uint8_t response_data_format : 4;  /**< muse be 2 */
      uint8_t hierarchical_support : 1;  
      uint8_t normal_aca           : 1;
      uint8_t reserved2            : 2;
    
      uint8_t additional_length;
    
      uint8_t protect                    : 1;
      uint8_t reserved3                  : 2;
      uint8_t third_party_copy           : 1;
      uint8_t target_port_group_support  : 2;
      uint8_t access_control_coordinator : 1;
      uint8_t scc_support                : 1;
    
      uint8_t addr16                     : 1;
      uint8_t reserved4                  : 3;
      uint8_t multi_port                 : 1;
      uint8_t vendor1                    : 1; // vendor specific
      uint8_t enclosure_service          : 1;
      uint8_t reserved5                  : 1;
    
      uint8_t vendor2                    : 1; // vendor specific
      uint8_t cmd_queue                  : 1;
      uint8_t reserved6                  : 6;
    
      uint8_t vid[8];
      uint8_t pid[16];
      uint8_t product_version[4];
    }scsi_inquiry_std_response_t;]], 
      { additional_length = {format="dec"},
        peripheral_device_type = DEVICE_TYPE,
        vid = {format = "str"},
        pid = {format = "str"},
        product_version = {format = "str"},
    }, true)

local function parse_inquiry_std_data(cbw, data, context)
    local r = struct_inquiry_std_data:build(data, "Inquiry Std Response")
    return r.html
end

local function parse_inquiry_vpd_data(cbw, data, context)
    local len = unpack(">I2", data, 3)
    local vpd = unpack(">I1", data, 2)
    local data_field = ""
    if vpd == VPD_CODE.VPD_SUPPORTED_VPDS then
        for i=1,len do
            data_field = data_field .. "uint8_t  VPD; \n"
        end
    else
        data_field = "uint8_t data[]; \n"
    end
    local struct_temp = html.create_struct([[
        typedef struct
        {
          uint8_t peripheral_device_type: 5;   /**< \ref scsi_peripheral_device_type */
          uint8_t peripheral_qualifier  : 3;
          uint8_t page_code;
          uint16_t length;
          ]]..data_field..[[
        }scsi_inquiry_vpd_response_t;]], 
          { length = {format="dec"},
            peripheral_device_type = DEVICE_TYPE,
            VPD = VPD_NAME,
            page_code = VPD_NAME,
        }, true);
    local r = struct_temp:build(data, "Inquiry VPD Response")
    return r.html
end

local struct_inquiry_cmd = html.create_struct([[
    typedef struct
    {
      uint8_t cmd_code;            /**< SCSI OpCode for \ref SCSI_CMD_INQUIRY */
      uint8_t EVPD:       1;       /**< Enable Vital Product Data */
      uint8_t CMDDT:      1;       /**< Command Support Data */
      uint8_t reserved1:  6;
      uint8_t page_code;           /**< Page code */
      uint8_t length[2];           /**< allocate length for IN data */
      uint8_t control;             /**< */
    }scsi_inquiry_cmd_t;]], 
      { length = {format="dec"}}, true)

local function parse_inquiry_cmd(cbw, cmd, context)
    local r = struct_inquiry_cmd:build(cmd, "Inquiry")
    if (r.EVPD & 0x01) == 0 then
        cbw.data_parser = parse_inquiry_std_data
        r.name = "Inquiry Std"
    else
        cbw.data_parser = parse_inquiry_vpd_data
        r.name = "Inquiry VPD"
    end
    return r
end

local struct_request_sense_data = html.create_struct([[
    typedef struct
    {
      uint8_t response_code : 7;
      uint8_t valid         : 1;
    
      uint8_t reserved1;
    
      uint8_t sense_key     : 4;
      uint8_t reserved2    : 1;
      uint8_t incorrect_length: 1; /**< Incorrect length indicator */
      uint8_t end_of_medium : 1;
      uint8_t filemark      : 1;
    
      uint8_t  information[4];
      uint8_t  add_sense_len;
      uint8_t  command_specific_info[4];
      uint8_t  add_sense_code;
      uint8_t  add_sense_qualifier;
      uint8_t  field_replaceable_unit_code;
    
      uint8_t  sense_ks_2:7;
      uint8_t  sense_ks_valid:1;
    
      uint8_t  sense_ks_1;
      uint8_t  sense_ks_0;
    
    } scsi_sense_fixed_resp_t;]], 
    {
        add_sense_len = {
            format="dec"
        },
        response_code = {
            [0x70] = "FIX_CURRENT",
            [0x71] = "FIX_DEFERRED",
            [0x72] = "DESC_CURRENT",
            [0x73] = "DESC_DEFERRED",
        },
        sense_key = {
            [0x00] = "NONE",
            [0x01] = "RECOVERED_ERROR",
            [0x02] = "NOT_READY",
            [0x03] = "MEDIUM_ERROR",
            [0x04] = "HARDWARE_ERROR",
            [0x05] = "ILLEGAL_REQUEST",
            [0x06] = "UNIT_ATTENTION",
            [0x07] = "DATA_PROTECT",
            [0x08] = "FIRMWARE_ERROR",
            [0x0b] = "ABORTED_COMMAND",
            [0x0c] = "EQUAL",
            [0x0d] = "VOLUME_OVERFLOW",
            [0x0e] = "MISCOMPARE",
        },
        add_sense_code={
            [0x20] = "INVALID_CDB",
            [0x24] = "INVALID_FIELED_IN_COMMAND",
            [0x1A] = "PARAMETER_LIST_LENGTH_ERROR",
            [0x26] = "INVALID_FIELD_IN_PARAMETER_LIST",
            [0x21] = "ADDRESS_OUT_OF_RANGE",
            [0x3A] = "MEDIUM_NOT_PRESENT",
            [0x28] = "MEDIUM_HAVE_CHANGED",
            [0x27] = "WRITE_PROTECTED",
            [0x11] = "UNRECOVERED_READ_ERROR",
            [0x03] = "WRITE_FAULT",
        }
    }, true)

local function parse_request_sense_data(cbw, data, context)
    local r = struct_request_sense_data:build(data, "Sense Response")
    return r.html
end

local struct_request_sense_cmd = html.create_struct( [[
    typedef struct
    {
      uint8_t cmd_code;
      uint8_t descriptor:1; 
      uint8_t reserved1: 7;
      uint8_t reserved2;
      uint8_t reserved3;
      uint8_t length;
      uint8_t control;
    }scsi_request_sense_cmd_t;]], 
      { length = {format="dec"}}, true)

local function parse_request_sense_cmd(cbw, cmd, context)
    local r = struct_request_sense_cmd:build(cmd, "Request Sense")
    cbw.data_parser = parse_request_sense_data
    return r
end

local struct_read_format_cap_data = html.create_struct([[
    struct {
        uint8_t unknown;
        uint8_t unknown;
        uint8_t unknown;
        uint8_t unknown;
        uint32_t block_count;
        uint8_t unknown;
        uint8_t  bloc_size[3];
    };]], 
      { bloc_size = {format="hex"}}, true)

local function parse_read_format_cap_data(cbw, data, context)
    local r = struct_read_format_cap_data:build(data, "Read Format Cap Data")
    return r.html
end

local struct_read_format_cap_cmd = html.create_struct([[
    struct {
        uint8_t cmd_code;
        uint8_t data[];
      };]], 
      {}, true)

local function parse_read_format_cap_cmd(cbw, cmd, context)
    local r = struct_read_format_cap_cmd:build(cmd, "Read Format Cap")
    cbw.data_parser = parse_read_format_cap_data
    return r
end

local struct_read_cap10_data = html.create_struct([[
    typedef struct {
        uint8_t last_logical_block_address[4];
        uint8_t block_size[4];
      } scsi_read_capacity_10_resp_t;
]], {last_logical_block_address = {format="hex"},
block_size = {format="hex"},}, true)

local function parse_read_cap10_data(cbw, data, context)
    local r = struct_read_cap10_data:build(data, "Read Cap 10 Data")
    return r.html
end

local struct_read_cap10_cmd = html.create_struct([[
    typedef struct
    {
      uint8_t  cmd_code;
      uint8_t  reserved1;
      uint8_t  logical_block_address[4];
      uint8_t  reserved2[2];
      uint8_t  partial_medium_indicator:1;
      uint8_t  reserved3:7;
      uint8_t  control;
    } scsi_read_capacity_10_cmd_t;
]], {}, true)

local function parse_read_cap10_cmd(cbw, cmd, context)
    local r = struct_read_cap10_cmd:build(cmd, "Read Cap 10")
    cbw.data_parser = parse_read_cap10_data
    return r
end

local struct_mode_sense6_data = html.create_struct([[
    typedef struct 
    {
      uint8_t mode_data_length;
      uint8_t medium_type;
    
      uint8_t reserved1:4;
      uint8_t DPO_FUA:1;     /**< [Disable Page Out] and [Force Unit Access] in the Read10 command is valid or not */
      uint8_t reserved2:2;
      uint8_t write_protect:1;
    
      uint8_t block_desc_length;
    }scsi_mode_6_resp_header_t;
]],{ mode_data_length = {format = "dec"},
block_desc_length = {format = "dec"},
}, true)
local function parse_mode_sense6_data(cbw, data, context)
    local r = struct_mode_sense6_data:build(data, "Mode Sense 6 Data")
    return r.html
end

local struct_mode_sense6_cmd = html.create_struct([[
    typedef struct 
    {
      uint8_t cmd_code;
    
      uint8_t reserved1:3;
      uint8_t disable_block_descriptor: 1;
      uint8_t reserved2:4;
    
      uint8_t page_code:6;
      uint8_t page_control:2;

      uint8_t subpage_code;
      uint8_t length;
      uint8_t control;
    }scsi_mode_sense_6_cmd_t;
]],{ length = {format = "dec"} }, true)
local function parse_mode_sense6_cmd(cbw, cmd, context)
    local r = struct_mode_sense6_cmd:build(cmd, "Mode Sense 6")
    cbw.data_parser = parse_mode_sense6_data
    return r
end

local function parse_rw_10_data(cbw, data, context)
    return "<br><h1>Read/Write Raw Data</h1>See data Window<br>"
end

local struct_rw_10_cmd = html.create_struct([[
    typedef struct 
    {
      uint8_t cmd_code;
      uint8_t  reserved1:2;
      uint8_t  RARC:1;     /**<  rebuild assist recovery control */
      uint8_t  FUA:1;      /**<  Force Unit Access */
      uint8_t  DPO:1;      /**<  Disable Page Out */
      uint8_t  protect_info:3;
      uint8_t logical_block_addr[4];
      uint8_t group_number:5;
      uint8_t reserved2:3;
      uint8_t transfer_length[2];
      uint8_t control;
    }scsi_read_10_cmd_t, scsi_write_10_cmd_t;
]], { logical_block_addr = {format="hex"},
  transfer_length = {format="hex"}
}, true)

local function parse_rw_10_cmd(cbw, cmd, context, isRead)
    return struct_rw_10_cmd:build(cmd, isRead and "Read 10" or "Write 10")
end
local function parse_read_10_cmd(cbw, cmd, context)
    local r = parse_rw_10_cmd(cbw, cmd, context, true)
    cbw.data_parser = parse_rw_10_data
    return r
end

local function parse_write_10_cmd(cbw, cmd, context)
    local r = parse_rw_10_cmd(cbw, cmd, context, false)
    cbw.data_parser = parse_rw_10_data
    return r
end

local struct_test_unit_ready = html.create_struct([[
    typedef struct 
    {
      uint8_t cmd_code;
    };]], {}, true)

local function parse_test_unit_ready_cmd(cbw, cmd, context)
    return struct_test_unit_ready:build(cmd, "Test Unit Ready")
end

local struct_start_stop_unit = html.create_struct([[
    typedef struct
    {
      uint8_t cmd_code;
    
      uint8_t immediate:1;
      uint8_t reserved1:7;
    
      uint8_t reserved2;
    
      uint8_t power_cond_modifier:4;
      uint8_t reserved3:4;
    
      uint8_t start:1;
      uint8_t load_eject:1;
      uint8_t no_flush:1;
      uint8_t reserved4:1;
      uint8_t power_cond:4;    /**  Power Condition */
    
      uint8_t control;
    }scsi_start_stop_cmd_t;]], {
        power_cond = {
            [0x00] = "START_VALID",
            [0x01] = "ACTIVE",
            [0x02] = "IDLE",
            [0x03] = "STANDBY",
            [0x07] = "LU_CONTROL",
            [0x0a] = "FORCE_IDLE_0",
            [0x0b] = "FORCE_STANDBY_0",
        }
    }, true)

local function parse_start_stop_unit_cmd(cbw, cmd, context)
    return struct_start_stop_unit:build(cmd, "Start/Stop Unit")
end

local scsi_cmd = {
    [SCSI_CMD_INQUIRY] = parse_inquiry_cmd,
    [SCSI_CMD_REQUEST_SENSE] = parse_request_sense_cmd,
    [SCSI_CMD_READ_FORMAT_CAPACITY] = parse_read_format_cap_cmd,
    [SCSI_CMD_READ_CAPACITY_10] = parse_read_cap10_cmd,
    [SCSI_CMD_MODE_SENSE_6] = parse_mode_sense6_cmd,
    [SCSI_CMD_READ_10] = parse_read_10_cmd,
    [SCSI_CMD_WRITE_10] = parse_write_10_cmd,
    [SCSI_CMD_TEST_UNIT_READY] = parse_test_unit_ready_cmd,
    [SCSI_CMD_START_STOP_UNIT] = parse_start_stop_unit_cmd,
}

local function parse_scsi_cmd(cbw, cmd, context)
    if #cmd < 1 then
        return {
            name = "SCSI Wrong",
            html = "<h1>SCSI command data length wrong</h1>"
        }
    end
    local cmd_code = unpack("I1", cmd)
    local scsi_cmd_parser = scsi_cmd[cmd_code]
    if not scsi_cmd_parser then
        return {
            name = "SCSI Unknown",
            html = "<h1>Unknown SCSI command: "..fmt("0x%02X", cmd_code).."</h1>"
        }
    end
    return scsi_cmd_parser(cbw, cmd, context)
end

local struct_cbw = html.create_struct([[
    struct {
        uint32_t dCBWSignature;
        uint32_t dCBWTag;
        uint32_t dCBWDataTransferLength;
        // bmCBWFlags
        uint8_t  Reserved:6;
        uint8_t  Obsolete:1;
        uint8_t  Direction:1; // {[0] = "Host to Device", [1] = "Device to Host"}
        uint8_t  bCBWLUN;
        uint8_t  bCBWCBLength;
        uint8_t  CBWCB[16];
    }
]])

local struct_csw = html.create_struct([[
    struct {
        uint32_t dCSWSignature;
        uint32_t dCSWTag;
        uint32_t dCSWDataResidue;
        uint8_t  bCSWStatus;
    }]], {
        bCSWStatus = {
            [0] = "Passed",
            [1] = "Failed",
            [2] = " Phase Error",
            format = "dec",
        }
        })


local function parse_csw(cbw, data, context)
    local csw = {}
    csw.status = "error"
    csw.name = "CSW"
    if #data ~= 13 then
        csw.html = "<h1>Wrong CSW length</h1>"
        return csw
    end
    local r = struct_csw:build(data, "Command Status Wrapper (CSW)")
    csw.html = r.html
    if r.bCSWStatus == 0 then
        csw.status = "success"
    end
    return csw
end

local function parse_cbw(data, context)
    local tb = {}
    local cbw = {}
    cbw.name = "CBW"
    if #data ~= 31 then
        cbw.html = "<h1>Wrong CBW length</h1>"
        return cbw
    end
    cbw = struct_cbw:build(data, "Command Block Wrapper (CBW)")
    local cmd = data:sub(16)
    cbw.scsi = parse_scsi_cmd(cbw, cmd, context)
    cbw.name = "CBW"
    if cbw.scsi and cbw.scsi.html then
        cbw.name = cbw.scsi.name
        cbw.html = cbw.html .. cbw.scsi.html
    end
    return cbw
end


function scsi.parse_cmd(data, context)
    return parse_cbw(data, context)
end

function scsi.parse_data(cbw, data, context)
    if cbw.data_parser then
        return cbw.data_parser(cbw, data, context)
    end
    return "<h1>Unknown SCSI DATA</h1>"
end

function scsi.parse_status(cbw, data, context)
    return parse_csw(cbw, data, context)
end




package.loaded["decoder_scsi"] = scsi
