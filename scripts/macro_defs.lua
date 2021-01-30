-- macro_defs.lua
-- constant value used as macros
local macro_defs = {
  -- the 16 USB PIDs
  PID_RESERVED    = 0,
  PID_OUT         = 1,
  PID_ACK         = 2,
  PID_DATA0       = 3,
  PID_PING        = 4,
  PID_SOF         = 5,
  PID_NYET        = 6,
  PID_DATA2       = 7,
  PID_SPLIT       = 8,
  PID_IN          = 9,
  PID_NAK         = 10,
  PID_DATA1       = 11,
  PID_ERR_PRE     = 12,
  PID_SETUP       = 13,
  PID_STALL       = 14,
  PID_MDATA       = 15,

  RES_NONE        = 0x00,
  RES_BEGIN       = 0x01,
  RES_END         = 0x02,
  RES_BEGIN_END   = 0x03,
  RES_MORE        = 0x04,

  -- the standard request codes
  GET_STATUS      = 0,
  CLEAR_FEATURE   = 1,
--RESERVED_2      = 2,
  SET_FEATURE     = 3,
--RESERVED_4      = 4,
  SET_ADDRESS     = 5,
  GET_DESCRIPTOR  = 6,
  SET_DESCRIPTOR  = 7,
  GET_CONFIG      = 8,
  SET_CONFIG      = 9,
  GET_INTERFACE   = 10,
  SET_INTERFACE   = 11,
  SYNC_FRAME      = 12,

  -- the descriptor type codes
  DEVICE_DESC     = 1,
  CFG_DESC        = 2,
  STRING_DESC     = 3,
  INTERFACE_DESC  = 4,
  ENDPOINT_DESC   = 5,
  DEV_QUAL_DESC   = 6,
  OTHER_DESC      = 7,
  UNUSED_8_DESC   = 8,
  OTG_DESC        = 9,
  IAD_DESC        = 0xB,
  BOS_DESC        = 0xF,
  MAX_STD_DESC    = 0x9,

  HID_DESC        = 0x21,
  REPORT_DESC     = 0x22,
  FUNC_DESC       = 0x24,
  HUB_DESC        = 0x29,

-- Functional Descriptor Type
  CS_INTERFACE    = 0x24,
  CS_ENDPOINT     = 0x25,

  MAX_KNOWN_DESCRIPTOR = 0x29,


  ST_CBW        = 0x01,   -- $macro
  ST_DATA       = 0x02,  -- $macro
  ST_CSW        = 0x03,

  ST_SETUP      = 0x01,   -- $macro
  ST_DATA_IN    = 0x02,   -- $macro
  ST_DATA_OUT   = 0x03,   -- $macro
  ST_STATUS_IN  = 0x04,   -- $macro
  ST_STATUS_OUT = 0x05,   -- $macro
  
}

package.loaded["macro_defs"] = macro_defs
