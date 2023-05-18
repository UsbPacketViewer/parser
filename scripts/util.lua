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

local DESCRIPTOR_NAME = {
    [macro_defs.DEVICE_DESC    ] = "DevDesc",
    [macro_defs.CFG_DESC       ] = "CfgDesc",
    [macro_defs.STRING_DESC    ] = "StrDesc",
    [macro_defs.DEV_QUAL_DESC  ] = "QualDesc",
    [macro_defs.OTHER_DESC     ] = "OtherSpeed",
    [macro_defs.BOS_DESC       ] = "BOS Desc",
}

_G.EP_IN = function(name, optional)
    if optional then
        return name .. "5"
    end
    return name .. "1"
end

_G.EP_OUT = function(name, optional)
    if optional then
        return name .. "4"
    end
    return name .. "0"
end

_G.EP_INOUT = function(name, optional)
    if optional then
        return name .. "6"
    end
    return name .. "2"
end

_G.get_std_request_name = function(v, wValue, wIndex)
    if v < #STD_REQ_NAME then
        if (v == macro_defs.GET_DESCRIPTOR or v == macro_defs.GET_DESCRIPTOR) and wValue then
            local idx = wValue & 0xff
            local t = wValue >> 8
            local prefix = "Get "
            if v == macro_defs.SET_DESCRIPTOR then
                prefix = "Set "
            end
            local postfix = ""
            if t == macro_defs.CFG_DESC or t == macro_defs.STRING_DESC then
                postfix = ":"..idx
            end
            if DESCRIPTOR_NAME[t] then
                return prefix .. DESCRIPTOR_NAME[t] .. postfix
            end
        end
        local postfix = ""
        if v == macro_defs.SET_CONFIG and wValue then
            postfix = " :" .. wValue
        end
        if v == macro_defs.SET_INTERFACE and wIndex then
            return  "Set Itf :" .. wIndex
        end
        if v == macro_defs.GET_INTERFACE and wIndex then
            return  "Get Itf :" .. wIndex
        end
        return STD_REQ_NAME[v+1] .. postfix
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
    elseif v == macro_defs.REPORT_DESC then
        return "Report Descriptor"
    elseif v == macro_defs.FUNC_DESC then
        return "Function Descriptor"
    elseif v == macro_defs.HUB_DESC then
        return "HUB Descritpor"
    elseif v == macro_defs.IAD_DESC then
        return "IAD Descriptor"
    else
        return "Unknown Descriptor"
    end
end

package.loaded["util"] = util

