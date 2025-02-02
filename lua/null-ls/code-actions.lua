local s = require("null-ls.state")
local u = require("null-ls.utils")
local methods = require("null-ls.methods")
local generators = require("null-ls.generators")

local schedule = vim.schedule_wrap

local M = {}

local postprocess = function(action)
    s.register_action(action)

    action.command = methods.internal.CODE_ACTION
    action.action = nil
end

M.handler = function(method, original_params, handler, bufnr)
    local a = require("plenary.async_lib")

    local inject_actions = a.async_void(function(params, callback)
        s.clear_actions()

        local runner = generators.make_runner(u.make_params(params, methods.internal.CODE_ACTION), postprocess)
        local actions = a.await(runner())
        callback(actions)
    end)

    if method == methods.lsp.CODE_ACTION then
        if original_params._null_ls_ignore then
            return
        end

        original_params.bufnr = bufnr
        inject_actions(
            u.make_params(original_params, methods.internal.CODE_ACTION),
            schedule(function(actions)
                handler(nil, method, actions, s.get().client_id, bufnr)
            end)
        )

        original_params._null_ls_handled = true
    end

    if method == methods.lsp.EXECUTE_COMMAND and original_params.command == methods.internal.CODE_ACTION then
        s.run_action(original_params.title)

        original_params._null_ls_handled = true
    end
end

return M
