local M = {}

function M.parse_params(params, action_name)
    params = params or {}
    local server_name = params.server_name
    local tool_name = params.tool_name
    local uri = params.uri
    local arguments = params.tool_input or {}
    local errors = {}
    if not vim.tbl_contains({ "use_mcp_tool", "access_mcp_resource" }, action_name) then
        table.insert(errors, "Action must be one of `use_mcp_tool` or `access_mcp_resource`")
    end
    if not server_name then
        table.insert(errors, "server_name is required")
    end
    if action_name == "use_mcp_tool" and not tool_name then
        table.insert(errors, "tool_name is required")
    end
    if action_name == "use_mcp_tool" and type(arguments) ~= "table" then
        table.insert(errors, "parameters must be an object")
    end

    if action_name == "access_mcp_resource" and not uri then
        table.insert(errors, "uri is required")
    end
    return {
        errors = errors,
        action = action_name or "nil",
        server_name = server_name or "nil",
        tool_name = tool_name or "nil",
        uri = uri or "nil",
        arguments = arguments or {},
    }
end
function M.setup_codecompanion_variables(enabled)
    if not enabled then
        return
    end
    local mcphub = require("mcphub")
    --setup event listners to update variables, tools etc
    mcphub.on({ "servers_updated", "resource_list_changed" }, function(_)
        local hub = mcphub.get_hub_instance()
        if not hub then
            return
        end
        local resources = hub:get_resources()
        local ok, config = pcall(require, "codecompanion.config")
        if not ok then
            return
        end

        local cc_variables = config.strategies.chat.variables
        -- remove existing mcp variables that start with mcp
        for key, value in pairs(cc_variables) do
            local id = value.id or ""
            if id:sub(1, 3) == "mcp" then
                cc_variables[key] = nil
            end
        end
        for _, resource in ipairs(resources) do
            local server_name = resource.server_name
            local uri = resource.uri
            local resource_name = resource.name or uri
            local description = resource.description or ""
            if type(description) == "function" then
                local ok, desc = pcall(description, resource)
                if ok then
                    description = desc or ""
                else
                    description = "Error in description function: " .. (desc or "")
                end
            end
            --remove new lines
            description = description:gsub("\n", " ")

            description = resource_name .. " (" .. description .. ")"
            cc_variables[uri] = {
                id = "mcp" .. server_name .. uri,
                description = description,
                callback = function(self)
                    -- this is sync and will block the UI (can't use async in variables yet)
                    local response = hub:access_resource(server_name, uri, {
                        caller = {
                            type = "codecompanion",
                            codecompanion = self,
                            meta = {
                                is_within_variable = true,
                            },
                        },
                        parse_response = true,
                    })
                    return response and response.text
                end,
            }
        end
    end)
end

function M.setup_codecompanion_slash_commands(enabled)
    if not enabled then
        return
    end

    local mcphub = require("mcphub")
    --setup event listners to update variables, tools etc
    mcphub.on({ "servers_updated", "prompt_list_changed" }, function(_)
        local hub = mcphub.get_hub_instance()
        if not hub then
            return
        end
        local prompts = hub:get_prompts()
        local ok, config = pcall(require, "codecompanion.config")
        if not ok then
            return
        end

        local slash_commands = config.strategies.chat.slash_commands
        -- remove existing mcp slash commands that start with mcp
        for key, value in pairs(slash_commands) do
            local id = value.id or ""
            if id:sub(1, 3) == "mcp" then
                slash_commands[key] = nil
            end
        end
        for _, prompt in ipairs(prompts) do
            local server_name = prompt.server_name
            local prompt_name = prompt.name or ""
            local description = prompt.description or ""
            local arguments = prompt.arguments or {}
            if type(description) == "function" then
                local ok, desc = pcall(description, prompt)
                if ok then
                    description = desc or ""
                else
                    description = "Error in description function: " .. (desc or "")
                end
            end
            if type(arguments) == "function" then
                local ok, args = pcall(arguments, prompt)
                if ok then
                    arguments = args or {}
                else
                    vim.notify("Error in arguments function: " .. (args or ""), vim.log.levels.ERROR)
                    arguments = {}
                end
            end
            --remove new lines
            description = description:gsub("\n", " ")

            description = prompt_name .. " (" .. description .. ")"
            slash_commands["mcp:" .. prompt_name] = {
                id = "mcp" .. server_name .. prompt_name,
                description = description,
                callback = function(self)
                    local values = {}
                    local should_proceed = true
                    for _, arg in ipairs(arguments) do
                        if not should_proceed then
                            break
                        end
                        local arg_name = arg.name or ""
                        -- local arg_description = arg.description or ""
                        local required = arg.required or false
                        vim.ui.input({
                            prompt = arg_name .. (required and " (required): " or ": "),
                            default = arg.default or "",
                        }, function(input)
                            if required and (input == nil or input == "") then
                                vim.notify("Value for " .. arg_name .. " is required", vim.log.levels.ERROR)
                                should_proceed = false
                                return
                            end
                            if input == nil then
                                return
                            end
                            values[arg_name] = input
                        end)
                    end
                    if not should_proceed then
                        vim.notify("Prompt cancelled", vim.log.levels.INFO)
                        return
                    end
                    -- this is sync and will block the UI (can't use async in slash_commands yet)
                    local response, err = hub:get_prompt(server_name, prompt_name, values, {
                        caller = {
                            type = "codecompanion",
                            codecompanion = self,
                            meta = {
                                is_within_slash_command = true,
                            },
                        },
                        parse_response = true,
                    })
                    if not response then
                        if err then
                            vim.notify("Error in slash command: " .. err, vim.log.levels.ERROR)
                            vim.notify("Prompt cancelled", vim.log.levels.INFO)
                        end
                        return
                    end
                    local messages = response.messages or {}
                    local text_messages = 0
                    for i, message in ipairs(messages) do
                        local output = message.output
                        --TODO: Currently codecompanion only supports text messages
                        if output.text and output.text ~= "" then
                            local mapped_role = message.role == "assistant" and config.constants.LLM_ROLE
                                or message.role == "system" and config.constants.SYSTEM_ROLE
                                or config.constants.USER_ROLE
                            text_messages = text_messages + 1
                            -- if last message is from user, add it to the chat buffer
                            if i == #messages and mapped_role == config.constants.USER_ROLE then
                                self:add_buf_message({
                                    role = mapped_role,
                                    content = output.text,
                                })
                            else
                                self:add_message({
                                    role = mapped_role,
                                    content = output.text,
                                })
                            end
                        end
                    end
                    vim.notify(
                        string.format(
                            "%s message%s added successfully",
                            text_messages,
                            text_messages == 1 and "" or "s"
                        ),
                        vim.log.levels.INFO
                    )
                end,
            }
        end
    end)
end

function M.setup_codecompanion_tools(enabled)
    if not enabled then
        return
    end
    --INFO:Individual tools might be an overkill
end

function M.get_mcp_tool_prompt(params)
    local action_name = params.action
    local server_name = params.server_name
    local tool_name = params.tool_name
    local uri = params.uri
    local arguments = params.arguments or {}

    local args = ""
    for k, v in pairs(arguments) do
        args = args .. k .. ":\n "
        if type(v) == "string" then
            local lines = vim.split(v, "\n")
            for _, line in ipairs(lines) do
                args = args .. line .. "\n"
            end
        else
            args = args .. vim.inspect(v) .. "\n"
        end
    end
    local msg = ""
    if action_name == "use_mcp_tool" then
        msg = string.format(
            [[Do you want to run the `%s` tool on the `%s` mcp server with arguments:
%s]],
            tool_name,
            server_name,
            args
        )
    elseif action_name == "access_mcp_resource" then
        msg = string.format("Do you want to access the resource `%s` on the `%s` server?", uri, server_name)
    end
    return msg
end

function M.show_mcp_tool_prompt(params)
    local msg = M.get_mcp_tool_prompt(params)
    local confirm = vim.fn.confirm(msg, "&Yes\n&No", 2)
    return confirm == 1
end

return M
