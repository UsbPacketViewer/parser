
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

r.make_table = function(t)
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

r.expand_bit_field = function(value, bf, noMask)
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
		local desc = v[bv]
		if not desc then desc = v.convertor and v.convertor(bv) end
		if not desc then desc = v.comment or "" end
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

local function signedFmt(v, len, isBig)
	isBig = isBig and ">" or "<"
	if type(v) == "string" then
		v = unpack(isBig .. "i" .. len, v)
	end
	return fmt("%d", v)
end

local function dataFmt(v, len)
	return util.toHex(v, " ", 8, "<br>")
end

local function strFmt(v, len)
	return tostring(v)
end
local function unicodeFmt(v, len)
	local r = ""
    for i=1, #v, 2 do
        local l,h = unpack("I1I1", v, i)
        if h == 0 then
            r = r .. string.char(l)
        else
            r = r .. "."
        end
    end
    return r
end

local function ipFmt(v, len)
    local res = ""
    local del = ""
    for i=1,#v do
        res = res .. del .. tonumber(v:byte(i))
        del = "."
    end
    return res
end

local fmt2str = {
	[hexFmt] = "hex",
	[decFmt] = "dec",
	[dataFmt] = "data",
	[strFmt] = "str",
    [ipFmt] = "ip"
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

local function parse_comment(c)
    local res = load("return " .. c .. "\n\n")
	if type(res) == "function" then
		local r1, r2 = pcall(res)
        if r1 then return r2 end
    end
    return nil
end

local function format_name(r1)
	r1 = string.gsub(r1, "^%s*","")
	r1 = string.gsub(r1, "^[//%*]+","")
	r1 = string.gsub(r1, "[//%*%s]+$","")
	r1 = string.gsub(r1, "^struct","")
	r1 = string.gsub(r1, "^union","")
	r1 = string.gsub(r1, "^%s*","")
	r1 = string.gsub(r1, "[%s{}]*$","")
return r1
end

local function push_rep(stack, r)
	local rep = {
		start = #r + 1;
	}
	stack[#stack + 1] = rep
end

local function dynamic_get_size(n, type_size)
	return function(res, data, offset)
		if #n < 1 then return 1 end
		res.math = math
		local func, t = load("return (" .. n .. ")\n", "calc size: \"" .. n .. "\"", "tb", res)
		if type(func) == "function" then
			local err, r = pcall(func)
			if err and type(r) == "number" then
				return math.floor(r) * (type_size or 1)
			end
			print("dynamic_get_size error exec",r)
		else
			print("dynamic_get_size error parse",t)
		end
		return 1
	end
end

local function pop_rep(stack, r, n)
	local rep = stack[#stack]
	stack[#stack] = nil
	assert(rep, "{} pair mismatch")
	rep.stop = #r
	if not n then
		return
	end
	if tonumber(n) then
		rep.size = function(res, data, offset)
			return tonumber(n)
		end
	else
		rep.size = dynamic_get_size(n)
	end
	for i=rep.start, rep.stop do
		r[i].rep = rep
	end
end

local function build_struct(info, data, name)
	local tb = {}
	local res = {}
    local offset = 1
	tb.title = name or info.name
	res.name = name or info.name
    tb.header = {"Filed", "Value", "Description"}
	local rep_info = {}
	local isBig = info.isBig
	local i = 0
	while i < #info do
		i = i + 1
		local v = info[i]
        if v.name then
			local bits = math.floor((v.bits or 8)/8)
			local unpack_fmt = "I"..bits
			if isBig then unpack_fmt = ">" .. unpack_fmt end
			local t = 0
			local truncated = #data + 1 < offset + bits
			if not truncated then
				t = unpack(unpack_fmt, data, offset)
			end
			tb[#tb+1] = r.expand_bit_field(t, v)
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
			local n_suffix = ""
			if v.rep then
				if v.rep.start == i then
					rep_info[v.rep] = rep_info[v.rep] or {
						count = 1
					}
				end
				n_suffix = tostring(rep_info[v.rep].count)
			end
			local n, formater, size, big, fields = v[1], v[2], v[3], v[4], v[5]
			local name_suffix = ""
			if type(size) == 'function' then
				size = size(res, data, offset)
				name_suffix = "[" .. tostring(size) .. "]"
			end
			name_suffix = name_suffix .. n_suffix
			local t =  data:sub(offset, offset+size-1)--  unpack(unpack_fmt, data, offset)
			local prefix = big and ">" or "<"
			local truncated = #data + 1 < offset + size
			local desc = ""
			local oldTV = t
			t = 0
			if not truncated then
				if formater == hexFmt or formater == decFmt then
					t = unpack(prefix .."I"..size, data, offset)
				elseif formater == signedFmt then
					t = unpack(prefix .."i"..size, data, offset)
				end
			end
            if type(fields) == "table" then
				desc = fields[t] or fields.comment or "<Unknown>"
			elseif type(fields) == "string" then
				desc = fields
			elseif type(fields) == "function" then
				desc = fields(t)
			end
			local val_str = truncated and "&lt;Truncated&gt;" or formater(oldTV, size, big)
			tb[#tb+1] = {n .. name_suffix, val_str, desc}
            res[n] = t
			offset = offset + size
			if v.rep and v.rep.stop == i then
				if rep_info[v.rep].count >= v.rep.size(res, data, offset) then
					rep_info[v.rep] = nil
				else
					if not truncated then
						rep_info[v.rep].count = rep_info[v.rep].count + 1
						i = v.rep.start - 1
					else
						rep_info[v.rep] = nil
					end
				end
			end
        end
    end
    res.html = r.make_table(tb)
    return res
end

local function create_struct(desc, field, isBig)
	assert(desc, debug.traceback())
	local r = {}
	r.isBig = isBig
	local stk = {}
	field = field or {}
	local bf = nil
	local fieldNames = {}
	local lastBfName = nil
	string.gsub(desc, "([^\n]*)\n", function(l)
		local mayName = format_name(l)
		local bfName = nil
		if l:find("{") then
			push_rep(stk,r)
		end
		if l:find("}") then
			local rep_name = nil
			string.gsub(l, "}%[([^%[]*)%]",function(tn)
				rep_name = tn
			end)
			pop_rep(stk, r, rep_name)
		end
		local st_name = l:find("struct") or l:find("union")
		if st_name then
			if mayName and #mayName > 1 then
				r.name = mayName
			end
		else
			if mayName and #mayName > 1 then
				bfName = mayName
			end
		end
		string.gsub(l, "^%s*([%w_]+)%s+([%w_]+)([^;]*);(.*)", function(t, n, q, comment)
			bfName = nil
			comment = format_comment(comment)
			local table_comment = parse_comment(comment)
			local p1 = q:find(":")
			local p2, p3 = q:find("%[[^%[]*%]")
			local bitfield = nil
			local array = nil
			if p1 then
				bitfield = tonumber(q:sub(p1+1))
			elseif p2 then
				array = tonumber(q:sub(p2+1, p3-1))
				if p2+1 == p3 then
					array = 0
				end
				if not array then
					array = q:sub(p2+1, p3-1)
				end
			end
			assert(type2size[t], "unkown type " .. t)
			fieldNames[n] = 1
			if bitfield then
				if not bf then
				bf = {
					bits = type2size[t]*8,
					bit_pos = 0,
					name = lastBfName,
				}
				lastBfName = nil
				end
				local f = {
					name = n,
					mask = ((1<<bitfield)-1)<<bf.bit_pos,
					comment = comment,
					pos = bf.bit_pos,
				}
				local field_data = field[n] or table_comment
				if field_data and type(field_data) == "table" then
					for k,v in pairs(field_data) do
						f[k] = v
					end
					if field_data.name then
						bf.name = bf.name or field_data.name
					end
				elseif field_data and type(field_data) == "function" then
					f.convertor = field_data
				end
				bf[#bf+1] = f
				bf.bit_pos = bf.bit_pos + bitfield
				if bf.bit_pos >= bf.bits then
					bf.name = bf.name or ""
					r[#r+1] = bf
					bf = nil
				end
			else
				local f = field[n] or table_comment
				local formater = dataFmt
				local size = 0
				if array then
					local type_size = type2size[t]
					if type(array) == "string" then
						size = dynamic_get_size(array)
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
							formater = t:sub(1,1) == 'i' and signedFmt or decFmt
                        elseif f.format == "ip" then
							formater = ipFmt
						elseif f.format == "uni" or f.format == "unicode" then
							formater = unicodeFmt
						end
					end
				else
					formater = hexFmt
					array = 1
					size = type2size[t]*array
					if f and type(f) == "table" and f.format then
						if f.format == "string" or f.format == "str" then
							formater = strFmt
						elseif f.format == "data" then
							formater = hexFmt
						elseif f.format == "hex" then
							formater = hexFmt
						elseif f.format == "dec" then
							formater = t:sub(1,1) == 'i' and signedFmt or decFmt
                        elseif f.format == "ip" then
							formater = ipFmt
						elseif f.format == "uni" or f.format == "unicode" then
							formater = unicodeFmt
						end
					end
				end
				local fieldBig = isBig
				if f and type(f) == "table" and f.endian then fieldBig = f.endian == ">" end
				r[#r+1] = {n, formater, size,  fieldBig, f or comment }
			end
		end)
		lastBfName = bfName or lastBfName
	end)
	r.build = build_struct
	return r
end

r.create_struct = create_struct
r.create_field = function(desc, field, isBig)
	local res = create_struct(desc, field, isBig)[1]
	assert(res and res.name, "wrong field description")
	return res
end

package.loaded["html"] = r
