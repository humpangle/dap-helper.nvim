local M = {}

local function get_config_path()
  return vim.fn.stdpath("data")
end

local function get_dir_key(filename)
  -- None found? Use current directory as key
  local git_dir = M.get_git_dir(filename)
  if not git_dir then
    return vim.loop.cwd()
  end
  -- Return base path (with the .git stripped off)
  return vim.fs.dirname(git_dir)
end

function M.get_config_file()
  return vim.fs.joinpath(get_config_path(), "dap-helper.json")
end

-- Saves data to json file
--
-- @param filename: string (path to file)
-- @param args: table (data to be stored in the json)
-- @return boolean
local function save_to_json(filename, args)
  local f = io.open(filename, "w")
  if not f then
    return false
  end
  local json = vim.json.encode(args)
  f:write(json)
  f:close()
  return true
end

local function load_json_file(filename)
  local f = io.open(filename, "r")
  local data = {}
  if f then
    local content = f:read("*a")
    f:close()
    _, data = pcall(vim.json.decode, content, { object = true, array = true })
    assert(data, "Could not decode json")
  end
  return data
end

-- Loads data from json file and executes action on it
--
-- @param filename: string (path to file)
-- @param sub_key: string (name of the data entry to be stored in the json)
-- @param action: function (function to be executed on the data entry)
-- @return boolean, table (boolean: whether the data was modified; table: the modified data)
-- @param key: string (main key to store this data under; default: .git dir location
-- /current directory)
-- @return table
local function load_entry_from_file_and(filename, sub_key, action, main_key)
  local data = load_json_file(filename)

  main_key = main_key or get_dir_key(filename)

  local entry = data[main_key]
  if not entry then
    data[main_key] = {}
    entry = data[main_key]
  end
  entry[sub_key] = entry[sub_key] or {}

  local modified, modified_entry = action(entry[sub_key])
  if modified then
    entry[sub_key] = modified_entry
    return save_to_json(filename, data)
  end
  return entry[sub_key]
end

-- Updates data in json file
--
-- @param sub_key: string (name of the data entry to be stored in the json)
-- @param data: table (data to be stored under the entry)
-- @param key: string (main key to store this data under; default: .git dir location
-- /current directory)
-- @return boolean
function M.update_json_file(sub_key, data, main_key)
  return load_entry_from_file_and(M.get_config_file(), sub_key, function(entry)
    return true, data
  end, main_key)
end

-- Loads data from json file
--
-- @param sub_key: string (name of the data entry stored in the json)
-- @param key: string (main key to store this data under; default: .git dir location
-- /current directory)
-- @return table
function M.load_from_json_file(sub_key, main_key)
  return load_entry_from_file_and(M.get_config_file(), sub_key, function(entry)
    return false
  end, main_key)
end

function M.save_watches(plugin_opts)
  local curbuf = vim.api.nvim_get_current_buf()
  local filename = vim.api.nvim_buf_get_name(curbuf)
  if M.is_invalid_filename({ file = filename }, plugin_opts) then
    return
  end

  local dapui = require("dapui")

  M.update_json_file("watches", dapui.elements.watches.get(), filename)
end

function M.load_watches()
  local dapui = require("dapui")

  local curbuf = vim.api.nvim_get_current_buf()
  local filename = vim.api.nvim_buf_get_name(curbuf)
  local entry = M.load_from_json_file("watches", filename)

  -- remove present watches -> we want only watches pertinent to the file
  local watches = dapui.elements.watches.get()
  while #watches > 0 do
    table.remove(watches, 1)
  end
  for _, watch in ipairs(entry) do
    dapui.elements.watches.add(watch.expression)
  end
end

function M.save_breakpoints(plugin_opts)
  local curbuf = vim.api.nvim_get_current_buf()
  local filename = vim.api.nvim_buf_get_name(curbuf)
  if M.is_invalid_filename({ file = filename }, plugin_opts) then
    return
  end

  local bps = require("dap.breakpoints")

  local bufbps = bps.get(curbuf)
  --local _,bpsextracted = pairs(bufbps)(bufbps)
  local bpsextracted = bufbps[curbuf]

  M.update_json_file("breakpoints", bpsextracted, filename)
end

function M.load_breakpoints()
  local bps = require("dap.breakpoints")

  local curbuf = vim.api.nvim_get_current_buf()

  local entry = M.load_from_json_file("breakpoints", vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()))
  if entry then
    for _, bp in ipairs(entry) do
      bps.set(bp, curbuf, bp.line)
    end
  end
end

-- Compares two arrays of arguments
--
-- @param args1: table (array of arguments)
-- @param args2: table (array of arguments)
-- @return boolean
function M.compare_args(args1, args2)
  if not args1 or not args2 then
    return false
  end
  if #args1 ~= #args2 then
    return false
  end
  for i = 1, #args1 do
    if args1[i] ~= args2[i] then
      return false
    end
  end
  return true
end

---@param opts table
---@param plugin_opts table
---@return boolean
function M.is_invalid_filename(opts, plugin_opts)
  if opts.file == "" then
    return true
  end

  local cb = plugin_opts.is_invalid_filename
  if cb then
    return cb(opts.file)
  end

  return false
end

function M.get_filetype(bufnr)
  return vim.api.nvim_get_option_value("filetype", { buf = bufnr })
end

function M.get_git_dir(filename)
  -- Try to find base folder that contains the .git files
  local path = vim.fs.find(".git", {
    upward = true,
    stop = vim.uv.os_homedir(),
    path = vim.fs.dirname(filename),
  })
  return path[1]
end

-- Parent dir of the .git dir
function M.get_base_dir(filename)
  return vim.fs.dirname(M.get_git_dir(filename))
end

function M.enumerate_project_file_data(filename)
  local git_dir = M.get_git_dir(filename)
  if not git_dir then
    return {}
  end
  local project_dir = M.get_base_dir(git_dir)
  local json_data = load_json_file(M.get_config_file())
  local ret = {}
  for path, data in pairs(json_data) do
    if string.contains(path, project_dir) and not vim.fn.isdirectory(path) and vim.loop.fs_stat(path) then
      if #data.breakpoints > 0 then
        table.insert(ret, path)
      end
    end
  end
  return ret
end

return M
