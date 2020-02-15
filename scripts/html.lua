

local r = {}
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
	r = r .. '<tr style="background-color:#66B3FF">'
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
		local trColor = (i&1)==1 and "white" or "lightgray"
		local trRowCount = 1
		local trRow = 1
		for j=1, colCount do
			if type(v[j]) == "table" then
				trRowCount = #v[j]
			end
		end
		while trRow <= trRowCount do
			r = r .. '<tr style="background-color: ' .. trColor .. '">'
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

r.makeBitField = function(bf)
	local value = bf.value or 0
	local bits = bf.bits or 8
	local name = bf.name or ""
	local tw = nil
	local w1 = ""
	local w2 = ""
	if bf.width then
		tw = bf.width[1] + bf.width[2]
		w1 = " width="..bf.width[1]
		w2 = " width="..bf.width[2]
	end

	local r = ""
	r = r .. '<p><table border="0" ' .. (tw and "width = "..tw or "").. '>'
	assert(bits == 8 or bits == 16 or bits == 24 or bits == 32)
	r = r .. '<tr style="background-color:lightgray">'
	local n = bfvalue(value, bits)
	r = r .. '<td '..w1..'><font size="4"><code>' .. n .. "</code></font></td>"
	r = r .. '<td '..w2..'><font size="4"><code>' .. name .. "</code></font></td>"
	r = r .. "</tr>"

	for i,v in ipairs(bf) do
		local desc, bv = bfvalue(value, bits, v.mask)
		local n = ""
		n = v[bv] or n
		r = r .. '<tr style="background-color:white">'
		r = r .. '<td><font size="4"><code>' .. desc .. "</code></font></td>"
		r = r .. '<td><font size="4"><code>' .. n .. "</code></font></td>"
		r = r .. "</tr>"
	end
	r = r .. "</table></p>"
	return r
end

local function fix(v)
	return "<font size=4><code>" .. v .. "</code></font>"
end

r.expandBitFiled = function(value, bf, noMask)
	value = value or 0
	local bits = bf.bits or 8
	local name = bf.name or ""
	local nameCol = { name }
	local bs, bv = bfvalue(value,bf.bits, nil, noMask)
	local valueCol = { fix(bs) }
	local descCol =  {  "" }

	for i,v in ipairs(bf) do
		local bs, bv = bfvalue(value, bits, v.mask, noMask)
		local desc = v[bv] or ""
		if v.name then
			nameCol[#nameCol+1] = "&nbsp;" .. (v.name or "")
		end
		valueCol[#valueCol+1] = fix(bs)
		descCol[#descCol+1] = desc
	end
	if #nameCol == 1 then nameCol = nameCol[1] end
	return {nameCol, valueCol, descCol}
end

package.loaded["html"] = r
