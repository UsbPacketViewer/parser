-- usb_defs.lua
-- usd defines form https://www.bugblat.com/products/ezsniff/index.html scripts folder
--============================================
local STD_REQ_NAME ={ "Get Status"
                    , "Clear Feature"
                    , "Reserved"
                    , "Set Feature"
                    , "Reserved"
                    , "Set Address"
                    , "Get Descriptor"
                    , "Set Descriptor"
                    , "Get Config"
                    , "Set Config"
                    , "Get Interface"
                    , "Set Interface"
                    , "Sync Frame"
                    }
local STD_DESCRIPTOR_NAME = { "Undefined"
                            , "Device"
                            , "Configuration"
                            , "String"
                            , "Interface"
                            , "Endpoint"
                            , "Device Qualifier"
                            , "Other Speed"
                            , "Interface Power"
                            , "OTG"
                            }

--============================================
local usb_defs = {
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

  HID_DESC        = 0x21,
  REPORT_DESC     = 0x22,
  HUB_DESC        = 0x29,

  MAX_KNOWN_DESCRIPTOR = 0x29,

  -- map type codes to strings
  stdRequestName = function(ix)
    if ix < #STD_REQ_NAME then return STD_REQ_NAME[ix+1]
    else                       return "Application Specific"
    end
  end,

  descriptorName = function(ix)
    if (ix>=0) and (ix < #STD_DESCRIPTOR_NAME)
                       then return STD_DESCRIPTOR_NAME[ix+1]
    elseif ix == 0x21  then return "HID"
    elseif ix == 0x22  then return "Report"
    elseif ix == 0x29  then return "Hub"
    else                    return "Unknown"
    end
  end
  }

package.loaded["usb_defs"] = usb_defs

-- EOF =======================================
--[[
--]]
