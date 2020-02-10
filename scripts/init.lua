-- init.lua
-- encoding: utf-8
require("file_base")
require("parser")
require("pcap_file")
require("iti1480a")



local captureList = {
    "demoCap",
    "openvizsla"
}

function valid_capture()
    return table.concat(captureList, ",")
end

