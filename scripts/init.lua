-- init.lua
-- encoding: utf-8
require("file_base")
require("parser")
require("file_pcap")
require("file_iti1480a")



local captureList = {
    "demoCap",
    "openvizsla"
}

function valid_capture()
    return table.concat(captureList, ",")
end

