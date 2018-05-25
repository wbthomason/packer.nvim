local luamodule = {}

luamodule.showstuff = function ()
    print "hello from nvim-example-lua-plugin.luamodule.showstuff"
end

function comment()
    eolComment = "%-%-"
    buf = vim.api.nvim_get_current_buf()
    print("this is the thing")
    --vim.api.echo(buf)
    --a, b = string.find(line, "^%s" .. eolComment)
    --if a == nil then
    --    -- Add a leading comment.
    --else
    --    -- Remove the leading comment.
    --end
end

return luamodule
