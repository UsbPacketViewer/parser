-- usb_control_transfer.lua
-- control transfer parser

local html = require("html")
local gb = require("graph_builder")
local fmt = string.format
local unpack = string.unpack


local function makeControlXferGraph(xfer, ts)
    local addr,ep = gb.str2addr(xfer.addrStr)
    local header = gb.req(xfer.reqName or "Unknown")
                .. gb.addr(addr)
                .. gb.endp(ep)
    if xfer.state ~= "success" then
        return gb.ts("Control transfer", ts, gb.C.XFER)
         .. header .. gb.incomp() .. gb.F_XFER .. gb.F_INCOMPLETE .. xfer.addrStr
    end
    local res
    if (xfer.setup.bmRequest & 0x80) == 0x80 then
        res = gb.ts("Control In", ts, gb.C.XFER)
    else
        res = gb.ts("Control Out", ts, gb.C.XFER)
    end
    res = res .. header .. gb.data(xfer.data or "")
    res = res .. gb.block(xfer.state, "", gb.C.ACK)
    return res .. gb.F_XFER .. gb.F_ACK .. xfer.addrStr
end


local function controlXferHandler(xfer, trans, ts, updateGraph, context)
    xfer.fsm = xfer.fsm or 0
    xfer.name = "Control transfer"
    if      xfer.fsm == 0 then
        if trans.id == xfer.id and trans.pkts[1].name == "SETUP" then
            if trans.state == "ACK" then
                trans.desc = "Setup"
                local setup = context:parseSetupRequest(trans.pkts[2].data)
                trans.infoHtml = setup.html
                trans.infoData = setup.data
                xfer.setup = setup
                xfer.infoHtml = setup.html
                xfer.reqName = setup.name
                if (xfer.setup.bmRequest & 0x80) == 0x80 then
                    if xfer.setup.wLength > 0 then
                        xfer.fsm = 1
                    else
                        error("should never reach status out here")
                        xfer.fsm = 2
                    end
                else
                    if xfer.setup.wLength > 0 then
                        xfer.fsm = 3
                    else
                        xfer.fsm = 4
                    end
                end
            end
        else
            return nil
        end
    elseif  xfer.fsm == 1 then
        -- data IN
        if trans.pkts[1].name == "IN" then
            if trans.state == "ACK" then
                trans.desc = "Data In"
                xfer.data = xfer.data or ""
                xfer.data = xfer.data .. trans.pkts[2].data
                if context:isShortPacket(xfer.addrStr, trans.pkts[2].data) then
                    xfer.fsm = 2
                elseif #xfer.data >= xfer.setup.wLength then
                    xfer.fsm = 2
                end
                if xfer.fsm == 2 then
                    trans.infoHtml = "<h1>Control transfer (last) data</h1>"
                    xfer.infoHtml = xfer.infoHtml .. 
                    context:parseSetupData(xfer.setup, xfer.data)
                else
                    trans.infoHtml = "<h1>Control transfer partial data</h1>"
                end
            else
                trans.desc = "Data Nak"
                trans.parent = xfer
            end
        else
            return nil
        end
    elseif  xfer.fsm == 2 then
        -- status out
        if trans.pkts[1].name == "OUT" then
            if trans.state == "ACK" then
                trans.desc = "Status Out"
                trans.infoHtml = "<h1>Control transfer status OUT</h1>"
                xfer.state = "success"
                xfer.fsm = 0
                xfer.infoData = xfer.data
            end
        else
            return nil
        end
    elseif  xfer.fsm == 3 then
        -- data out
        if trans.pkts[1].name == "OUT" then
            if trans.state == "ACK" then
                trans.desc = "Data Out"
                xfer.data = xfer.data or ""
                xfer.data = xfer.data .. trans.pkts[2].data
                if context:isShortPacket(xfer.addrStr, trans.pkts[2].data) then
                    xfer.fsm = 4
                elseif #xfer.data >= xfer.setup.wLength then
                    xfer.fsm = 4
                end
                if xfer.fsm == 4 then
                    trans.infoHtml = "<h1>Control transfer (last) data</h1>"
                    xfer.infoHtml = xfer.infoHtml .. 
                    context:parseSetupData(xfer.setup, xfer.data)
                else
                    trans.infoHtml = "<h1>Control transfer partial data</h1>"
                end
            else
                trans.desc = "Data Nak"
                trans.parent = xfer
            end
        else
            return nil
        end
    elseif  xfer.fsm == 4 then
        -- status in
        if trans.pkts[1].name == "IN" then
            if trans.state == "ACK" then
                trans.desc = "Status In"
                trans.infoHtml = "<h1>Control transfer status IN</h1>"
                xfer.state = "success"
                xfer.fsm = 0
                xfer.infoData = xfer.data
            end
        else
            return nil
        end
    end
    updateGraph( makeControlXferGraph(xfer, ts), xfer.id, xfer)
    if xfer.state and xfer.state == "success" then
        return "done"
    end
    return true
end



package.loaded["usb_control_transfer"] = controlXferHandler
