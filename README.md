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

#脚本接口说明
``` lua
-- encoding: UTF8
----------------------------------------
---  USB Packet Viewer 脚本接口说明  ---
----------------------------------------
-- 将此说明内容保存为文本文件，并重命名为scripts.lua，替换自带的脚本可以看到此示例的运行效果

--------------------------------
------  文件相关API开始  -------
-- 文件相关操作的API一共有三个
-- valid_filter 获取支持的文件名后缀
-- open_file    读取文件
-- write_file   写入文件
--------------------------------
-- 返回Qt风格的文件Filter
-- 默认支持 USB Packet Viewer File (*.upv)
function valid_filter()
    return "Text File (*.txt);;All Files (*.*)"
end

-- 打开并读取文件，此函数可以阻塞，不会影响UI
-- 参数说明
--           name              文件名
--           packet_handler    数据回调，当读取到文件中的数据后，调用packet_handler
--           context           调用packet_handler时的传入的第一个参数
-- 返回值(1个)
--           读取的数据包数量

-- packet_handler 函数原型  packet_handler(context, ts, nano, pkt, status, pos, total)
-- packet_handler 参数说明 
--                       context   传入open_file的第三个参数
--                       ts        以秒为单位的时间戳
--                       nano      以纳秒为单位的时间戳
--                       pkt       数据包内容，包含前面的PID和后面的CRC
--                       status    状态值
--                       pos       当前已经读取的文件长度
--                       total     文件总长度
-- packet_handler 返回值(1个)
--                        nil 表示读取到的包处理出错
--                        true 表示处理成功
function open_file(name, packet_handler, context)
    for i=1,10 do
        packet_handler(context, i,i, "\x69\x00\x10", 0, i, 10)
    end
    return 10
end

-- 将数据写入文件，此函数可以阻塞，不会影响UI
-- 参数说明
--           name              文件名
--           packet_handler    数据回调，调用packet_handler获取需要写入文件的数据包，当没有更多的数据包时，返回nil
--           context           调用packet_handler时的传入的第一个参数
-- 返回值(1个)
--           写入的数据包数量

-- packet_handler 函数原型  packet_handler(context)
-- packet_handler 参数说明 
--                       context   write_file
-- packet_handler 返回值(4个)
--                       ts        以秒为单位的时间戳
--                       nano      以纳秒为单位的时间戳
--                       pkt       数据包内容，包含前面的PID和后面的CRC
--                       status    状态值

function write_file(name, packet_handler, context)
    local f = io.open(name, "w+")
    local count = 0
    while f do
        local ts,nano,pkt,status = packet_handler(context)
        if not ts then break end
        f:write(string.format("ts %d, nano %d, status %d:", ts, nano, status&0xff))
        for i=1,#pkt do
            f:write(string.format("%02x ", pkt:byte(i)))
        end
        f:write("\n")
        count = count + 1
    end
    f:close()
    return count
end

--------------------------------
------  解码相关API开始  -------
--------------------------------
-- 解码相关操作的API一共有六个
-- upv_register_decoder   向USBPV注册解码器，此函数由USBPV实现，脚本中只能调用
-- upv_reset_parser       重置解码器
-- upv_parse_transaction  解析Transaction
-- upv_add_decoder        添加解码器
-- upv_remove_decoder     移除解码器
-- upv_valid_parser       获取支持的解码器

-- 注册解码器，此函数由USBPV实现，当脚本需要向USBPV注册解码器时，调用此函数
-- 此函数内部会调用 upv_add_decoder， 用来向脚本添加端点对应的解码器
-- 函数原型 upv_register_decoder(name, param)
-- 参数说明
--          name      解码器名称,脚本中通过名称来区分不同的解码器
--          param     端点参数，格式为由地址和端点序列组成的字符串 string.char(addr,endp1,addr,endp2,...)
--
-- 说明：   此函数会将解码器注册到对应的地址和端点上。
--          USBPV会先检测当前数据包的地址端点是否已经注册，如果没有注册且端点号不为0，不会将数据发给脚本进行解码。
--          端点号为0的数据会直接发往脚本进行解码，不需要预先注册。
local upv_register_decoder = upv_register_decoder

-- 模拟一个 decoder_map
local decoder_map = {}

-- 重置解码器，无参数，无返回值。UI上点击清除按钮后会调用此函数
function upv_reset_parser()
    -- 下面的代码，将地址为01的设备中的0x81和0x01端点注册到了名为MSC的解码器上
    upv_register_decoder("MSC", "\x01\x81\x01\x01")
end

-- 解码Transaction数据
-- 参数说明
--           param       transaction 参数，包含了地址，端点，PID，和响应信息
--           data        transaction 数据，(不包含PID和CRC)
--           needDetail  是否需要详细信息
--           forceBegin  是否强制重新解码
--           autoDecoder 是否为脚本自动设置的解码器
-- 返回值(3个)
--           state       解码状态。 0-解码失败         Transaction不能解码
--                                1-数据开始         Xfer数据的第一包
--                                2-数据结束         Xfer数据的最后一包
--                                3-数据开始及结束   Xfer只有一包Transaction数据，例如普通的HID数据
--                                4-还有更多的数据   Xfer中的数据，既不是第一包，也不是最后一包
--           transaction transaction 解码结果
--           transfer    transfer    解码结果
--
-- 解码结果数据格式为以"\x00"分隔的字符串，分别表示 标题、名字、描述、状态、html信息、数据信息
function upv_parse_transaction(param, data, needDetail, forceBegin, autoDecoder)
    -- 从param中分离出地址，端点，PID及响应信息
    local addr, ep, pid, ack = param:byte(1), param:byte(2), param:byte(3), param:byte(4)
    if ep == 0 then
        -- TODO: 端点为0的为控制传输，可以在此将端点0上的Transaction合并成Control Transfer
        -- 然后解码设备的各种描述，根据描述符调用 upv_register_decoder 自动注册相应的解码器
        return 0
    end
    local title = decoder_map[string.char(addr,ep)]
    if title ~= "MSC" then return 0 end
    local state = 4
    -- CBW 数据
    if #data == 31 then state = 1 end
    -- CSW 数据
    if #data == 13 then state = 2 end
    
    if not needDetail then
        -- 不需要详细信息，只返回状态
        return state
    end
    return state,
           title .. "-Xact标题"
           .."\x00".."Xact名字"
           .."\x00".."Xact描述"
           .."\x00".."success"
           .."\x00".."<h>Transaction Html Info</h>"
           .."\x00".."\x01\x02\x00\x03\x00\x04",
           title .."-Xfer标题"
           .."\x00".."Xfer名字"
           .."\x00".."Xfer描述"
           .."\x00".."success"
           .."\x00".."<h>Xfer Html Info</h>"
           .."\x00".."\x11\x12\x00\x13\x00\x14"
end

-- 为端点添加添加解码器
-- 参数说明
--          name   解码器名称,脚本中通过名称来区分不同的解码器
--          eps    端点参数，格式为由地址和端点序列组成的字符串 string.char(addr,endp1,addr,endp2,...)
-- 返回值(1个)
--          true-成功,  false-失败
function upv_add_decoder(name, eps)
    if name == "MSC" then
        for i=1,#eps,2 do
            decoder_map[string.char(eps:byte(i), eps:byte(i+1))] = "MSC"
        end
        return true
    end
    return false
end

-- 为端点移除解码器
-- 参数说明
--          name   解码器名称,脚本中通过名称来区分不同的解码器
--          eps    端点参数，格式为由地址和端点序列组成的字符串 string.char(addr,endp1,addr,endp2,...)
-- 返回值(1个)
--          true成功， nil或false失败
function upv_remove_decoder(name, eps)
    for i=1,#eps,2 do
        decoder_map[string.char(eps:byte(i), eps:byte(i+1))] = nil
    end
    return true
end

-- 获取支持的解码器
-- 返回值(1个)
--        字符串形式的解码器列表，格式为以;号分隔的解码器参数:
--        <解码器参数1>;<解码器参数2>;<解码器参数3>
-- 解码器参数格式如下:
--       <解码器名>:<端点参数1>,<端点参数2>,<端点参数3>,
-- 端点参数格式如下:
--       <端点描述><端点类型>
-- 端点类型为012456这六种类型的一种，0-IN, 1-OUT, 2-INOUT, 4-可选IN, 5-可选OUT, 6-可选INOUT
function upv_valid_parser()
   -- 下面的参数表示三个解码器，名称分别为MSC, CDC和Video
   -- MSC    有两个端点，分别为:Bulk IN，类型为IN；Bulk OUT，类型为OUT
   -- CDC    有三个端点，分别为:Bulk IN，类型为IN；Bulk OUT，类型为OUT。Notify，类型为IN
   -- Video  有两个端点，分别为:Stream，类型为INOUT；StillImage，类型为可选的INOUT
   return "MSC:Bulk IN1,Bulk Out0;CDC:Bulk In1,Bulk Out0,Notify1;Video:Stream2,StillImage6"
end

```
