# USB Packet Viewer parser

[USB Packet Viewer](http://pv.tusb.org)的插件项目，使用lua 5.3.4开发。包含文件读写，USB协议解析功能。

An add-on project for [USB Packet viewer](http://pv.tusb.org), writen in lua 5.3.4.


用scripts目录替换USB Packet Viewer中的scripts.lua文件，以使用最新的解析器。

Replace scripts.lua in USB Packet Viewer with scripts folder here to use the latest parser.

确保目录结构如下 Ensure the directory structure as below:

``` batch
\---usbpv
    |   usbpv.exe
    |
    \---scripts
            build.bat
            decoder_ethernet.lua
            decoder_rndis.lua
            decoder_scsi.lua
            file_base.lua
            file_iti1480a.lua
            file_pcap.lua
            html.lua
            init.lua
            macro_defs.lua
            upv_parser.lua
            usb_class_cdc_acm.lua
            usb_class_hid.lua
            usb_class_hub.lua
            usb_class_msc_bot.lua
            usb_control_transfer.lua
            usb_descriptor_parser.lua
            usb_device_ftdi.lua
            usb_register_class.lua
            usb_setup_parser.lua
            util.lua
```


