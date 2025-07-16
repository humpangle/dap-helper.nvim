local M = {}

local dap = require("dap")
local internals = require("dap-helper.internals")

-- --- Breakpoints for a given buffer (or current).
function M.get_breakpoints(bufnr)
  local bps_by_buf = require("dap.breakpoints").get() -- table[bufnr] = { {line=..,condition=..,logMessage=..,hitCondition=..}, ... }
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return bps_by_buf[bufnr] or {}
end

-- --- Watch expressions from nvim-dap-ui - if available.
function M.get_watches()
  local ok, dapui = pcall(require, "dapui")
  if not ok or not dapui.elements or not dapui.elements.watches or not dapui.elements.watches.get then
    return {}
  end
  return dapui.elements.watches.get() -- returns { {expression=string, expanded=boolean}, ... }
end

function M.on_dap_event(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filename = vim.api.nvim_buf_get_name(bufnr)
  vim.schedule(function()
    internals.save_breakpoints(filename, M.get_breakpoints(bufnr), vim.g.___dap___helper___)
    internals.save_watches(filename, M.get_watches(), vim.g.___dap___helper___)
  end)
end

-- ---------------------------------------------------------------------------
-- Patch DAP functions we are interested in / Hook BREAKPOINT changes
-- ---------------------------------------------------------------------------
local orig_toggle = dap.toggle_breakpoint
dap.toggle_breakpoint = function(...)
  local ret = orig_toggle(...)
  M.on_dap_event()
  return ret
end

local orig_set = dap.set_breakpoint
dap.set_breakpoint = function(...)
  local ret = orig_set(...)
  M.on_dap_event()
  return ret
end

local orig_clear = dap.clear_breakpoints
if orig_clear then
  dap.clear_breakpoints = function(...)
    local ret = orig_clear(...)
    M.on_dap_event()
    return ret
  end
end

-- React to adapter-side breakpoint events (e.g. verified/unverified updates).
dap.listeners.after.event_breakpoint["dap_helper_state_report"] = M.on_dap_event

-- ---------------------------------------------------------------------------
-- Hook WATCHES changes (dap-ui)
-- ---------------------------------------------------------------------------
do
  local ok, dapui = pcall(require, "dapui")
  if ok and dapui.elements and dapui.elements.watches then
    local w = dapui.elements.watches

    local w_add = w.add
    w.add = function(...)
      local r = w_add(...)
      M.on_dap_event()
      return r
    end

    local w_edit = w.edit
    w.edit = function(...)
      local r = w_edit(...)
      M.on_dap_event()
      return r
    end

    local w_remove = w.remove
    w.remove = function(...)
      local r = w_remove(...)
      M.on_dap_event()
      return r
    end
  end
end

return M
