
local unpack = string.unpack
local fmt = string.format
local util = require("util")

local r = {}

r.getCSS = function(dark)
	if dark then
return [[
<style type="text/css">
h1,td{color:lightgray;}
tr#odd{background-color: black;}
tr#even {background-color: #333333;}
tr#head{background-color:#003366;}
table { border-collapse: collapse; } 
td{ border: 2px solid lightgray }
</style>]]
	else
return [[
<style type="text/css">
h1,td{color:black;}
tr#odd{background-color: white;}
tr#even {background-color: lightgray;}
tr#head{background-color:#66B3FF;}
table { border-collapse: collapse; } 
td{ border: 2px solid darkgray }
</style>]]
	end
end

r.makeTable = function(t)
	local tw = nil
	if t.width then
		tw = 0
		for i,v in ipairs(t.width) do
			tw = tw + v
		end
	end
	local r = ""
	if t.title then
		r = r .. "<p><h1>"..tostring(t.title) .. "</h1></p>"
	end
	r = r .. '<p><table border="0" ' .. (tw and "width = "..tw or "").. '>'
	r = r .. '<tr id="head">'
	local colCount = nil
	if t.header then
		for i,v in ipairs(t.header) do
			r = r .. '<td><font size="5"><b>' .. tostring(v) .. "</b></font></td>"
		end
		colCount = #t.header
	end
	colCount = colCount or (t[1] and #t[1] or 0)
	r = r .. "</tr>"
	for i,v in ipairs(t) do
		local trColor = (i&1)==1 and "odd" or "even"
		local trRowCount = 1
		local trRow = 1
		for j=1, colCount do
			if type(v[j]) == "table" then
				trRowCount = #v[j]
			end
		end
		while trRow <= trRowCount do
			r = r .. '<tr id="' .. trColor .. '">'
			for j=1, colCount do
				local w = ""
				if t.width and t.width[j] then
					w = " width=" .. t.width[j]
				end
				local rowSpan = ""
				local cell = tostring(v[j])
				if type(v[j]) ~= "table" then
					if trRowCount > 1 then
						if trRow == 1 then
							rowSpan = ' rowspan= "'..trRowCount..'" '
							r = r .. '<td'..w..rowSpan..'><font size="5">' .. cell .. "</font></td>"
						end
					else
						r = r .. '<td'..w..rowSpan..'><font size="5">' .. cell .. "</font></td>"
					end
				else
					cell = tostring(v[j][trRow])
					r = r .. '<td'..w..rowSpan..'><font size="5">' .. cell .. "</font></td>"
				end
			end
			r = r .. "</tr>"
			trRow = trRow + 1
		end
	end
	return r .. "</table></p>"
end


local function bfvalue(v, bits, mask, noMask)
	bits = bits or 8
	mask = mask or 0xffffffff
	local vStr = ""
	local bitMask = 1
	local rShift = 0
	local lsb = nil
	for i=1,bits do
		local t = (v & bitMask) == 0 and '0' or '1'
		if (mask & bitMask) == 0 then
			t = '.'
			rShift = i
		else
			lsb = lsb or rShift
		end
		vStr = t .. vStr
		if i~=bits and i % 8 == 0 then vStr = " " .. vStr end
		bitMask = bitMask << 1
	end
	lsb = lsb or rShift
	v = (v & mask) >> lsb
	if noMask then
		return string.format( "0x%0" .. math.floor(bits/4) .. "X", v), v
	end
	return vStr .. string.format( " (0x%0" .. math.floor(bits/4) .. "X)", v), v
end

local function fix(v)
	return "<font size=4><code>" .. v .. "</code></font>"
end

r.expandBitFiled = function(value, bf, noMask)
	value = value or 0
	local bits = bf.bits or 8
	local name = bf.name or ""
	if bf.name == "" then
		name = "[bit fields]"
	end
	local nameCol = { name }
	local bs, bv = bfvalue(value,bf.bits, nil, noMask)
	local valueCol = { fix(bs) }
	local descCol =  {  "" }

	for i,v in ipairs(bf) do
		local bs, bv = bfvalue(value, bits, v.mask, noMask)
		local desc = v[bv] or v.comment or ""
		if v.name then
			nameCol[#nameCol+1] = "&nbsp;" .. (v.name or "")
		end
		valueCol[#valueCol+1] = fix(bs)
		descCol[#descCol+1] = desc
	end
	if #nameCol == 1 then nameCol = nameCol[1] end
	return {nameCol, valueCol, descCol}
end

local type2size = {
	uint8_t =  1,
	uint16_t = 2,
	uint24_t = 3,
	uint32_t = 4,

	int8_t =  1,
	int16_t = 2,
	int24_t = 3,
	int32_t = 4,
}

local function hexFmt(v, len, isBig)
	isBig = isBig and ">" or "<"
	if type(v) == "string" then
		v = unpack(isBig .. "I" .. len, v)
	end
	return fmt("0x%0" .. (len*2) .. "X", v)
end

local function decFmt(v, len, isBig)
	isBig = isBig and ">" or "<"
	if type(v) == "string" then
		v = unpack(isBig .. "I" .. len, v)
	end
	return fmt("%d", v)
end

local function dataFmt(v, len)
	return util.toHex(v, " ", 8, "<br>")
end

local function strFmt(v, len)
	return tostring(v)
end

local fmt2str = {
	[hexFmt] = "hex",
	[decFmt] = "dec",
	[dataFmt] = "data",
	[strFmt] = "str",
}

local function format_comment(x)
	x = string.gsub(x, "^%s+", "")
	x = string.gsub(x, "^/[/%*<]+", "")
	x = string.gsub(x, "^%s+", "")

	x = string.gsub(x, "%s+$", "")
	x = string.gsub(x, "[%*/]+$", "")
	x = string.gsub(x, "%s+$", "")
	return x
end

local function parse_struct(desc, field, isBig)
	local r = {}
	field = field or {}
	local bf = nil
	local fieldNames = {}
	string.gsub(desc, "([^\n]*)\n", function(l)
		string.gsub(l, "^%s*([%w_]+)%s+([%w_]+)([^;]*);(.*)", function(t, n, q, comment)
			comment = format_comment(comment)
			local p1 = q:find(":")
			local p2, p3 = q:find("%[[%s%d%w_]*%]")
			local bitfield = nil
			local array = nil
			if p1 then
				bitfield = tonumber(q:sub(p1+1))
			elseif p2 then
				array = tonumber(q:sub(p2+1, p3-1))
				if not array then
					array = q:sub(p2+1, p3-1)
				end
			end
			assert(type2size[t], "unkown type " .. t)
			fieldNames[n] = 1
			if bitfield then
				bf = bf or {
					bits = type2size[t]*8,
					bit_pos = 0,
				}
				local f = {
					name = n,
					mask = ((1<<bitfield)-1)<<bf.bit_pos,
					comment = comment,
					pos = bf.bit_pos,
				}
				if field[n] then
					for k,v in pairs(field[n]) do
						f[k] = v
					end
					if field[n].name then
						bf.name = bf.name or field[n].name
					end
				end
				bf[#bf+1] = f
				bf.bit_pos = bf.bit_pos + bitfield
				if bf.bit_pos >= bf.bits then
					bf.name = bf.name or ""
					r[#r+1] = bf
					bf = nil
				end
			else
				local f = field[n]
				local formater = dataFmt
				local size = 0
				if array then
					local type_size = type2size[t]
					if type(array) == "string" then
						if fieldNames[array] then
							size = function(res, data, offset)
								return res[array] * type_size
							end
						else
							array = 0
						end
					end
					if type(array) == "number" then
						if array < 1 then
							size = function(res, data, offset)
								if #data >= offset then
									return #data - offset + 1
								end
								return 0
							end
						else
							size = type2size[t]*array
						end
					end
					formater = dataFmt
					if f and f.format then
						if f.format == "string" or f.format == "str" then
							formater = strFmt
						elseif f.format == "data" then
							formater = dataFmt
						elseif f.format == "hex" then
							formater = hexFmt
						elseif f.format == "dec" then
							formater = decFmt
						end
					end
				else
					formater = hexFmt
					array = 1
					size = type2size[t]*array
					if f and f.format then
						if f.format == "string" or f.format == "str" then
							formater = strFmt
						elseif f.format == "data" then
							formater = hexFmt
						elseif f.format == "hex" then
							formater = hexFmt
						elseif f.format == "dec" then
							formater = decFmt
						end
					end
				end
				local fieldBig = isBig
				if f and f.endian then fieldBig = f.endian == ">" end
				r[#r+1] = {n, formater, size,  fieldBig, f or comment }
			end
		end)
	end)
	return r
end

r.makeStruct = function(data, name, struct_desc, field_desc, isBig)
    local tb = {}
    local offset = 1
    tb.title = name
    tb.header = {"Filed", "Value", "Description"}
	local res = {}
	local info = parse_struct(struct_desc, field_desc, isBig)
    for i,v in ipairs(info) do
        if v.name then
			local bits = math.floor((v.bits or 8)/8)
			local unpack_fmt = "I"..bits
			if isBig then unpack_fmt = ">" .. unpack_fmt end
			local t = 0
			local truncated = #data + 1 < offset + bits
			if not truncated then
				t = unpack(unpack_fmt, data, offset)
			end
			tb[#tb+1] = r.expandBitFiled(t, v)
			if truncated then
				local vals = tb[#tb][2]
				for j=1,#vals do vals[j] = "&lt;Truncated&gt;" end
			end
            offset = offset + bits
			res[v.name] = t
			for j,fv in ipairs(v) do
				res[fv.name] = (t & fv.mask) >> fv.pos
			end
        else
			local n, formater, size, big, fields = v[1], v[2], v[3], v[4], v[5]
			local name_suffix = ""
			if type(size) == 'function' then
				size = size(res, data, offset)
				name_suffix = "[" .. tostring(size) .. "]"
			end
			local t =  data:sub(offset, offset+size-1)--  unpack(unpack_fmt, data, offset)
			local prefix = big and ">" or "<"
			local truncated = #data + 1 < offset + size
			if formater == hexFmt or formater == decFmt then
				t = 0
				if not truncated then
					t = unpack(prefix .."I"..size, data, offset)
				end
			end
			local desc = ""
            if type(fields) == "table" then
				desc = fields[t] or "<Unknown>"
			elseif type(fields) == "string" then
				desc = fields
			end
			local val_str = truncated and "&lt;Truncated&gt;" or formater(t, size, big)
            tb[#tb+1] = {n .. name_suffix, val_str, desc}
            res[n] = t
            offset = offset + size
        end
    end
    res.name = name
    res.html = r.makeTable(tb)
    return res
end

package.loaded["html"] = r
