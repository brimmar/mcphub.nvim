local M = {}

function M.mcp_tool()
    local function get_hub()
        return require("mcphub").get_hub_instance()
    end

    return {
        id = "mcp",
        name = "MCP Tool",
        description = "Enables communication with MCP servers through the Model Context Protocol",
        source = "mcphub",

        execute = function(params, callback)
            local hub = get_hub()
            if not hub then
                return nil, "MCPHub not initialized"
            end

            if not params.action then
                return nil, "action is required: use_mcp_tool or access_mcp_resource"
            end

            if params.action == "use_mcp_tool" then
                if not params.server_name then
                    return nil, "server_name is required"
                end
                if not params.tool_name then
                    return nil, "tool_name is required"
                end

                hub:call_tool(params.server_name, params.tool_name, params.arguments or {}, {
                    parse_response = true,
                    callback = function(result, err)
                        if err then
                            callback(nil, err)
                        else
                            callback(result)
                        end
                    end,
                })
            elseif params.action == "access_mcp_resource" then
                if not params.server_name then
                    return nil, "server_name is required"
                end
                if not params.uri then
                    return nil, "uri is required"
                end

                hub:access_resource(params.server_name, params.uri, {
                    parse_response = true,
                    callback = function(result, err)
                        if err then
                            callback(nil, err)
                        else
                            callback(result)
                        end
                    end,
                })
            else
                return nil, "Invalid action: " .. params.action
            end
        end,
    }
end

function M.get_system_prompts()
    local hub = require("mcphub").get_hub_instance()
    if not hub then
        return {
            active_servers = "",
            use_mcp_tool = "",
            access_mcp_resource = "",
        }
    end

    return hub:get_prompts()
end

return M
