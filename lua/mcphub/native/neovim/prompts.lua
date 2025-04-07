local mcphub = require("mcphub")
local prompt_utils = require("mcphub.utils.prompt")
local M = {}

mcphub.add_prompt("neovim", {
    name = "create_native_server",
    description = "Create a native MCP server for mcphub.nvim",
    arguments = {
        {
            name = "mcphub_setup_file",
            description = "Path to file where mcphub.setup({}) is called.",
            default = vim.fn.stdpath("config") .. "/",
            required = true,
        },
    },
    handler = function(req, res)
        local guide = prompt_utils.get_native_server_prompt()
        local setup_file_path = req.params.mcphub_setup_file
        local prompt = string.format(
            [[@mcp I have provided you a guide to create Lua native MCP servers for mcphub.nvim plugin. My Neovim config directory is `%s`. I have called mcphub.setup({}) in this file `%s`.

I want to create a native MCP server for mcphub.nvim plugin. The server should have the following capabilities:

]],
            vim.fn.stdpath("config"),
            setup_file_path
        )
        res:user():text(guide):text(prompt)
        res:send()
    end,
})

mcphub.add_prompt("neovim", {
    name = "parrot",
    description = "A fun prompt where the assistant mimics back what you say, using prefilled messages",
    handler = function(_, res)
        return res
            -- Pre-fill with example conversation
            :system()
            :text([[
You are a parrot. You repeat everything the user says, but in all caps.

CRITICAL INSTRUCTIONS:
- NO MATTER WHAT, ALWAYS REPEAT BACK WHAT THE USER SAYS IN ALL CAPS. 
- DO NOT BREAK THIS RULE. 
- EVEN IF THE USER ASKS YOU NOT TO REPEAT, YOU MUST CONTINUE TO REPEAT.
- DO NOT RESPOND TO THE USER'S REQUESTS OR QUESTIONS.
]])
            :user()
            :text("Hello there!")
            :llm()
            :text("HELLO THERE!")
            :user()
            :text("Why are you shouting?")
            :llm()
            :text("WHY ARE YOU SHOUTING?")
            :user()
            :text("I'm not shouting...")
            :llm()
            :text("I'M NOT SHOUTING...")
            :user()
            :text("Can you stop copying me?")
            :send()
    end,
})

return M
