-- util.lua
local macro_defs = require("macro_defs")
local util = {}
util.toHex = function(data, sep, record_per_line, line_break)
    local res = ""
    sep = sep or ""
    record_per_line = record_per_line or 8
    line_break = line_break or "\n"
    local sssep = ""
    if not data then return "<null>" end
    local data_in_line = 0
    for i=1,#data do
        res = res .. sssep .. string.format( "%02X", data:byte(i))
        sssep = sep
        data_in_line = data_in_line + 1
        if data_in_line == record_per_line then
            sssep = ""
            res = res .. line_break
            data_in_line = 0
        end
    end
    return res
end

local STD_REQ_NAME ={
    "Get Status"      ,
    "Clear Feature"   ,
    "Reserved"        ,
    "Set Feature"     ,
    "Reserved"        ,
    "Set Address"     ,
    "Get Descriptor"  ,
    "Set Descriptor"  ,
    "Get Config"      ,
    "Set Config"      ,
    "Get Interface"   ,
    "Set Interface"   ,
    "Sync Frame"      ,
}

local STD_DESCRIPTOR_NAME = {
    "Undefined"         ,
    "Device"            ,
    "Configuration"     ,
    "String"            ,
    "Interface"         ,
    "Endpoint"          ,
    "Device Qualifier"  ,
    "Other Speed"       ,
    "Interface Power"   ,
    "OTG"               ,
}

_G.EP_IN = function(name)
    return name .. "1"
end

_G.EP_OUT = function(name)
    return name .. "0"
end

_G.get_std_request_name = function(v)
    if v < #STD_REQ_NAME then
        return STD_REQ_NAME[v+1]
    else
        return "Unknown Request"
    end
end

_G.get_descriptor_name = function(v)
    if (type(v) == "string") then
        error(debug.traceback())
    end
    if (v>=0) and (v < #STD_DESCRIPTOR_NAME) then
        return STD_DESCRIPTOR_NAME[v+1] .. " Descriptor"
    elseif v == macro_defs.HID_DESC then
      return "HID Descritpor"
    elseif v == macro_defs.REPORT_DESC then
        return "Report Descritpor"
    elseif v == macro_defs.FUNC_DESC then
        return "Function Descritpor"
    elseif v == macro_defs.HUB_DESC then
        return "HUB Descritpor"
    else
        return "Unknown Descritpor"
    end
end

package.loaded["util"] = util

