-- util.lua

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

package.loaded["util"] = util

