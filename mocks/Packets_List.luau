--!strict
--
-- REQUIRES
--
-- (none - pure mock, no dependencies)
--
-- LOCAL FUNCTIONS
--

--
-- make_packet_stub
--
-- Creates a stub packet table with Fire, FireClient, and event
-- Connect methods that record calls for test assertions.
--
local function make_packet_stub(name: string)
    local calls: {any} = {}

    return {
        Name = name,
        Type = "Packet",
        Id   = 0,

        Fire = function(_self: any, ...: any)
            table.insert(calls, { method = "Fire", args = table.pack(...) })
        end,

        FireClient = function(_self: any, _player: any, ...: any)
            table.insert(calls, { method = "FireClient", args = table.pack(...) })
        end,

        OnServerEvent = {
            Connect = function(_self: any, _fn: any)
                return { Disconnect = function() end }
            end,
        },
        OnClientEvent = {
            Connect = function(_self: any, _fn: any)
                return { Disconnect = function() end }
            end,
        },

        --
        -- Test helper: retrieve and clear recorded calls
        --
        _get_calls = function(): {any}
            local snapshot = calls
            return snapshot
        end,
        _clear_calls = function()
            calls = {}
        end,
    }
end

--
-- VARIABLES
--
local packets: {[string]: any} = {}

-- Client-to-server
packets["Return_To_Lobby"]          = make_packet_stub("Return_To_Lobby")
packets["Build_Planned"]            = make_packet_stub("Build_Planned")
packets["Enqueue_Unit"]             = make_packet_stub("Enqueue_Unit")
packets["Cancel_Unit_In_Queue"]     = make_packet_stub("Cancel_Unit_In_Queue")
packets["Movement_Order_Requested"] = make_packet_stub("Movement_Order_Requested")
packets["Cancel_Movement_Order"]    = make_packet_stub("Cancel_Movement_Order")

-- Admin (client-to-server)
packets["Send_Admin_List_Matches"]       = make_packet_stub("Send_Admin_List_Matches")
packets["Send_Admin_List_Empires"]       = make_packet_stub("Send_Admin_List_Empires")
packets["Send_Admin_Add_Fake_Players"]   = make_packet_stub("Send_Admin_Add_Fake_Players")
packets["Send_Admin_Create_Debug_Match"] = make_packet_stub("Send_Admin_Create_Debug_Match")
packets["Send_Admin_Teleport_To_Match"]  = make_packet_stub("Send_Admin_Teleport_To_Match")
packets["Send_Admin_Kick_Player"]        = make_packet_stub("Send_Admin_Kick_Player")

-- Server-to-client
packets["Countdown_Started"]            = make_packet_stub("Countdown_Started")
packets["Game_Started"]                 = make_packet_stub("Game_Started")
packets["Admin_Gui_Changed"]            = make_packet_stub("Admin_Gui_Changed")
packets["Draw_Spline"]                  = make_packet_stub("Draw_Spline")
packets["Create_Unit_Model"]            = make_packet_stub("Create_Unit_Model")
packets["Create_Build_Model"]           = make_packet_stub("Create_Build_Model")
packets["Build_State_Changed"]          = make_packet_stub("Build_State_Changed")
packets["Construction_Halted"]          = make_packet_stub("Construction_Halted")
packets["Construction_Resumed"]         = make_packet_stub("Construction_Resumed")
packets["Empire_Income_Changed"]        = make_packet_stub("Empire_Income_Changed")
packets["Empire_Resources_Changed"]     = make_packet_stub("Empire_Resources_Changed")
packets["Sync_Empire_Income"]           = make_packet_stub("Sync_Empire_Income")
packets["Sync_Empire_Resource_Counts"]  = make_packet_stub("Sync_Empire_Resource_Counts")
packets["Unit_Positions_Updated"]       = make_packet_stub("Unit_Positions_Updated")
packets["Movement_Order_Started"]       = make_packet_stub("Movement_Order_Started")
packets["Movement_Order_Cancelled"]     = make_packet_stub("Movement_Order_Cancelled")

-- Admin (server-to-client)
packets["Receive_Admin_Panel"]           = make_packet_stub("Receive_Admin_Panel")
packets["Receive_Admin_Matches_List"]    = make_packet_stub("Receive_Admin_Matches_List")
packets["Receive_Admin_Empires_List"]    = make_packet_stub("Receive_Admin_Empires_List")
packets["Receive_Admin_Action_Result"]   = make_packet_stub("Receive_Admin_Action_Result")

-- Pairs
packets["Alliance_Request"]                          = make_packet_stub("Alliance_Request")
packets["Alliance_Responce"]                         = make_packet_stub("Alliance_Responce")
packets["Player_Loaded"]                             = make_packet_stub("Player_Loaded")
packets["Player_Loaded_Server_Confirmation"]          = make_packet_stub("Player_Loaded_Server_Confirmation")
packets["Player_Device_Type"]                        = make_packet_stub("Player_Device_Type")
packets["Player_Device_Type_Server_Confirmation"]     = make_packet_stub("Player_Device_Type_Server_Confirmation")
packets["Movement_Order_Points_List_Request"]         = make_packet_stub("Movement_Order_Points_List_Request")
packets["Movement_Order_Points_List_Responce"]        = make_packet_stub("Movement_Order_Points_List_Responce")
packets["Clock_Sync_Request"]                        = make_packet_stub("Clock_Sync_Request")
packets["Clock_Sync_Responce"]                       = make_packet_stub("Clock_Sync_Responce")

-- Destruction
packets["Destroy_Build"]       = make_packet_stub("Destroy_Build")
packets["Destroy_Build_Model"] = make_packet_stub("Destroy_Build_Model")
packets["Destroy_Unit"]        = make_packet_stub("Destroy_Unit")
packets["Destroy_Unit_Model"]  = make_packet_stub("Destroy_Unit_Model")

-- Health
packets["Unit_Health_Changed"]  = make_packet_stub("Unit_Health_Changed")
packets["Build_Health_Changed"] = make_packet_stub("Build_Health_Changed")

-- Attack
packets["Attack_Preparation"] = make_packet_stub("Attack_Preparation")
packets["Attack_Firing"]      = make_packet_stub("Attack_Firing")
--
-- MODULE DEFINITION
--

--
-- Return a proxy that auto-creates unknown packet names on first access.
--
local Packets_List = setmetatable({}, {
    __index = function(_, key: string)
        if (packets[key] == nil) then
            packets[key] = make_packet_stub(key)
        end
        return packets[key]
    end,
    __newindex = function(_, key: string, value: any)
        packets[key] = value
    end,
})
--
-- RETURN VALUE
--
return Packets_List
