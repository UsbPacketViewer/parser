

local r = {}
r.makeTable = function(t)
	local tw = nil
	if t.width then
		tw = 0
		for i,v in ipairs(t.width) do
			tw = tw + v
		end
	end
	local r = "<p><h1>"..tostring(t.title) .. "</h1></p>"
	r = r .. '<p><table border="0" ' .. (tw and "width = "..tw or "").. '>'
	r = r .. '<tr style="background-color:#66B3FF">'
	for i,v in ipairs(t.header) do
		r = r .. '<td><font size="5"><b>' .. tostring(v) .. "</b></font></td>"
	end
	r = r .. "</tr>"
	for i,v in ipairs(t) do
		r = r .. '<tr style="background-color: ' .. ( (i&1)==1 and "white" or "lightgray") .. '">'
		for j=1, #t.header do
			local w = ""
			if t.width and t.width[j] then
				w = " width=" .. t.width[j]
			end
			r = r .. '<td'..w..'><font size="5">' .. tostring(v[j]) .. "</font></td>"
		end
		r = r .. "</tr>"
	end
	return r .. "</table></p>"
end

package.loaded["html"] = r
