--function reload()
--   package.loaded["dap-helper"] = nil
--   require("dap-helper").setup()
--end

local internals = require("dap-helper.internals")

local M = {}

local humpangle_dap_helper = vim.api.nvim_create_augroup("HUMPANGLE_DAP_HELPER", {
  clear = true,
})

local dap = require("dap")

---@class daHelper.PluginOpts
---@field is_invalid_filename function

---@param plugin_opts? daHelper.PluginOpts
function M.setup(plugin_opts)
  plugin_opts = plugin_opts or {}

  vim.api.nvim_create_user_command("DapHelperSetLaunchArgs", function(_arg)
    local entry = internals.load_from_json_file("args")
    local opts = { prompt = "Launch arguments: " }
    -- Check if file exists and data could be loaded
    -- If not, create default entry for this directory
    -- TODO: Always use base directory of current project, not cwd
    -- If entry exists and has args, use them as default for the prompt
    -- concatening them with spaces
    if #entry > 0 then
      opts.default = table.concat(entry, " ")
    end
    -- Ask use to input arguments
    vim.ui.input(opts, function(new_args)
      if not new_args then
        return
      end
      -- Now do the reverse of the above, and split the input into an array
      local arg_array = {}
      for arg in string.gmatch(new_args, "%S+") do
        table.insert(arg_array, arg)
      end
      -- If the entry does not exist, or the arguments have changed, save the
      -- new arguments
      if not entry or not internals.compare_args(arg_array, entry) then
        if not internals.update_json_file("args", arg_array) then
          vim.notify("Saving failed", vim.log.levels.WARN)
        end
        M.set_launch_args(internals.get_filetype(opts.buf), arg_array)
      end
    end)
  end, {})

  vim.api.nvim_create_user_command("DapHelperSetBuildCommand", function(_arg)
    local entry = internals.load_from_json_file("buildCmd")
    local opts = { prompt = "Build command: " }
    if type(entry) == "string" then
      opts.default = entry
    else
      entry = ""
    end
    -- Ask use to input arguments
    vim.ui.input(opts, function(new_cmd)
      if not new_cmd then
        return
      end
      if new_cmd ~= entry then
        if not internals.update_json_file("buildCmd", new_cmd) then
          vim.notify("Saving failed", vim.log.levels.WARN)
        end
      end
    end)
  end, {})

  vim.api.nvim_create_user_command("DapHelperReset", function(_arg)
    local succ, str = os.remove(internals.get_config_file())
    if not succ then
      vim.notify("Error resetting the configuration: " .. str, vim.log.levels.ERROR)
    end
  end, {})

  vim.api.nvim_create_autocmd("BufUnload", {
    pattern = "*",
    callback = function(opts)
      if internals.is_invalid_filename(opts, plugin_opts) then
        return
      end
      internals.save_watches(plugin_opts)
      if vim.api.nvim_get_option_value("modified", { buf = opts.buf }) then
        return
      end
      -- Only save breakpoints if buffer is unmodified to make sure we save no
      -- breakpoints that reference non-existing lines
      internals.save_breakpoints(plugin_opts)
    end,
    group = humpangle_dap_helper,
  })
  vim.api.nvim_create_autocmd("BufReadPost", {
    pattern = "*",
    callback = function(opts)
      if internals.is_invalid_filename(opts, plugin_opts) then
        return
      end
      M.set_launch_args(internals.get_filetype(opts.buf), M.get_launch_args())
      internals.load_breakpoints()
      internals.load_watches()
    end,
    group = humpangle_dap_helper,
  })
end

function M.get_launch_args()
  return internals.load_from_json_file("args")
end

function M.set_launch_args(filetype, args)
  local configs = dap.configurations[filetype]
  if configs then
    configs[1].args = args
  end
end

function M.get_startup_program(filetype)
  if filetype == "rust" then
    local base_dir = internals.get_base_dir(vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()))
    assert(base_dir, "This shouldn't be nil")
    local proj_name = vim.fs.basename(base_dir)
    return vim.fs.joinpath(base_dir, "target/debug", proj_name)
  end
  return nil
end

function M.set_startup_program(filetype, filepath)
  if not filepath then
    return
  end
  dap.configurations[filetype][1].program = filepath
end

function M.get_build_cmd()
  local buildcmd = internals.load_from_json_file("buildCmd")
  if type(buildcmd) == "table" then
    return nil
  end
  return buildcmd
end

return M
