-- usb_register_class.lua
local hid = require("usb_class_hid")

local function register(context)
    context:regClass(hid)
end

package.loaded["usb_register_class"] = register
