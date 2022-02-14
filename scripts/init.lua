-- init.lua
-- encoding: utf-8
local _, LuaDebuggee = pcall(require, 'LuaDebuggee')
if LuaDebuggee and LuaDebuggee.StartDebug then
	if LuaDebuggee.StartDebug('127.0.0.1', 9826) then
		print('LuaPerfect: Successfully connected to debugger!')
	else
		print('LuaPerfect: Failed to connect debugger!')
	end
else
	print('LuaPerfect: Check documents at: https://luaperfect.net')
end

require("file_base")
require("file_pcap")
require("file_iti1480a")

require("usb_class_hid")
require("usb_class_msc_bot")
require("usb_class_cdc_acm")
require("usb_class_hub")
require("usb_class_audio")
require("usb_class_video")
require("usb_class_dfu")

require("usb_device_ftdi")
require("usb_device_aw_efex")


require("upv_parser")
