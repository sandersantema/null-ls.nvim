local stub = require("luassert.stub")

local c = require("null-ls.config")
local u = require("null-ls.utils")
local s = require("null-ls.state")
local methods = require("null-ls.methods")
local handlers = require("null-ls.handlers")

local lsp = vim.lsp

describe("client", function()
    stub(vim.fn, "buflisted")
    stub(vim, "uri_from_bufnr")
    stub(vim.api, "nvim_buf_is_loaded")
    stub(vim.api, "nvim_buf_get_option")
    stub(vim.api, "nvim_get_current_buf")
    stub(lsp, "start_client")
    stub(lsp, "buf_attach_client")
    stub(handlers, "setup_client")
    stub(s, "attach")
    stub(s, "get_rtp")
    stub(s, "initialize")
    stub(u, "filetype_matches")

    local client = require("null-ls.client")

    local mock_client_id = 1234
    local mock_uri = "file:///mock-file.lua"
    local mock_rtp = "/my/rtp/null-ls.nvim"
    local mock_bufnr = 5
    before_each(function()
        vim.fn.buflisted.returns(1)
        vim.api.nvim_buf_get_option.returns("lua")
        vim.api.nvim_buf_is_loaded.returns(true)
        lsp.start_client.returns(mock_client_id)
        vim.uri_from_bufnr.returns(mock_uri)
        vim.api.nvim_get_current_buf.returns(mock_bufnr)

        s.get_rtp.returns(mock_rtp)
        u.filetype_matches.returns(true)
    end)

    after_each(function()
        vim.fn.buflisted:clear()
        vim.api.nvim_buf_get_option:clear()
        vim.api.nvim_get_current_buf:clear()
        vim.uri_from_bufnr:clear()
        lsp.start_client:clear()
        lsp.buf_attach_client:clear()
        s.attach:clear()
        s.initialize:clear()
        s.get_rtp:clear()
        u.filetype_matches:clear()
        handlers.setup_client:clear()

        c.reset()
        s.reset()
    end)

    describe("try_attach", function()
        it("should return when buffer is not loaded", function()
            vim.api.nvim_buf_is_loaded.returns(false)

            client.try_attach()
            vim.wait(0)

            assert.stub(lsp.start_client).was_not_called()
        end)

        it("should return when buffer is not listed", function()
            vim.fn.buflisted.returns(0)

            client.try_attach()
            vim.wait(0)

            assert.stub(lsp.start_client).was_not_called()
        end)

        it("should return when no filetype", function()
            vim.api.nvim_buf_get_option.returns("")

            client.try_attach()
            vim.wait(0)

            assert.stub(lsp.start_client).was_not_called()
        end)

        it("should return when filetype doesn't match", function()
            u.filetype_matches.returns(false)

            client.try_attach()
            vim.wait(0)

            assert.stub(lsp.start_client).was_not_called()
        end)

        it("should start client with config when client_id is nil", function()
            client.try_attach()
            vim.wait(0)

            assert.stub(lsp.start_client).was_called()
            local config = lsp.start_client.calls[1].refs[1]

            assert.same(config.cmd, {
                "nvim",
                "--headless",
                "-u",
                "NONE",
                "-c",
                "set rtp+=" .. mock_rtp,
                "-c",
                "lua require'null-ls'.start_server()",
            })
            assert.equals(config.root_dir, vim.fn.getcwd())
            assert.equals(config.name, "null-ls")
            assert.same(config.flags, { debounce_text_changes = c.get().debounce })
        end)

        it("should not start client when client_id is already set", function()
            s.set({ client_id = mock_client_id })
            vim.api.nvim_get_current_buf.returns(mock_bufnr)

            client.try_attach()
            vim.wait(0)

            assert.stub(lsp.start_client).was_not_called()
        end)

        it("should set client_id after start", function()
            client.try_attach()
            vim.wait(0)

            assert.equals(s.get().client_id, mock_client_id)
        end)

        it("should pass bufnr to attach", function()
            client.try_attach()
            vim.wait(0)

            assert.stub(s.attach).was_called_with(mock_bufnr)
        end)
    end)

    describe("attach_or_refresh", function()
        stub(s, "notify_client")

        after_each(function()
            s.notify_client:clear()
        end)

        it("should call notify_client if attached and return", function()
            s.set({ attached = { [mock_uri] = true } })

            client.attach_or_refresh()
            vim.wait(0)

            assert.stub(s.notify_client).was_called_with(methods.lsp.DID_CHANGE, {
                textDocument = { uri = mock_uri },
            })
            assert.stub(s.attach).was_not_called()
        end)

        it("should call try_attach if not attached", function()
            client.attach_or_refresh()
            vim.wait(0)

            assert.stub(s.notify_client).was_not_called()
            assert.stub(s.attach).was_called()
        end)
    end)

    describe("callbacks", function()
        local mock_client
        before_each(function()
            mock_client = { id = 99 }
        end)

        describe("on_init", function()
            local on_init
            before_each(function()
                client.try_attach()
                vim.wait(0)

                on_init = lsp.start_client.calls[1].refs[1].on_init
            end)

            it("should call setup_client with client", function()
                on_init(mock_client)

                assert.stub(handlers.setup_client).was_called_with(mock_client)
            end)

            it("should call state initialize with client", function()
                on_init(mock_client)

                assert.stub(s.initialize).was_called_with(mock_client)
            end)
        end)

        describe("on_exit", function()
            local on_exit
            before_each(function()
                client.try_attach()
                vim.wait(0)

                on_exit = lsp.start_client.calls[1].refs[1].on_exit
            end)

            it("should reset state", function()
                s.set({ client = "client" })

                on_exit(mock_client)

                assert.equals(s.get().client, nil)
            end)
        end)

        describe("on_attach", function()
            local on_attach, mock_on_attach
            before_each(function()
                mock_on_attach = stub.new()
                local _on_attach = function()
                    mock_on_attach()
                end
                c.setup({ on_attach = _on_attach })

                client.try_attach()
                vim.wait(0)

                on_attach = lsp.start_client.calls[1].refs[1].on_attach
            end)

            it("should equal config on_attach function", function()
                on_attach()

                assert.stub(mock_on_attach).was_called()
            end)
        end)
    end)
end)
