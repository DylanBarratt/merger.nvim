---@class Buffers
---@field current number
---@field incoming number
---@field base number

local CONFLICT_MARKER_START = "<<<<<<<"
local CONFLICT_MARKER_END = ">>>>>>>"
local PARENT_MARKER = "|||||||"
local CONFLICT_MIDDLE = "======="

---@param buffers Buffers
---@return number[]
local function createWindows(buffers)
  local editor_width = vim.o.columns
  local editor_height = vim.o.lines

  local function create_float(bufnr, enter, top, left, width, height)
    local opts = {
      relative = "editor",
      row = top,
      col = left,
      width = width,
      height = height,
    }

    return vim.api.nvim_open_win(bufnr, enter, opts)
  end

  local wins = {
    create_float(buffers.incoming, false, 0, 0, math.floor(editor_width / 2), math.floor(editor_height / 2)),
    create_float(
      buffers.current,
      false,
      0,
      math.floor(editor_width / 2),
      math.floor(editor_width / 2),
      math.floor(editor_height / 2)
    ),
    create_float(
      buffers.base,
      true,
      math.floor(editor_height / 2),
      0,
      editor_width,
      math.floor(editor_height / 2)
    ),
  }

  return wins
end

---@param buffers Buffers
local function populateBuffers(buffers)
  local function setBuf(bufNr, content)
    vim.api.nvim_buf_set_lines(bufNr, 0, -1, false, content)
  end

  setBuf(buffers.base, vim.split(vim.fn.system("git show :1:file1.txt"), "\n"))
  setBuf(buffers.current, vim.split(vim.fn.system("git show :2:file1.txt"), "\n"))
  setBuf(buffers.incoming, vim.split(vim.fn.system("git show :3:file1.txt"), "\n"))
end

---@param windows number[]
local function cleanup(windows)
  -- close other windows when one closes
  vim.api.nvim_create_autocmd("WinClosed", {
    callback = function(event)
      if vim.tbl_contains(windows, tonumber(event.match)) then
        for _, win_id in ipairs(windows) do
          if vim.api.nvim_win_is_valid(win_id) then
            vim.api.nvim_win_close(win_id, true)
          end
        end
      end
    end,
  })
end

function Main()
  ---@type Buffers
  local buffers = {
    current = vim.api.nvim_create_buf(false, true),
    incoming = vim.api.nvim_create_buf(false, true),
    base = vim.api.nvim_create_buf(false, true),
  }

  populateBuffers(buffers)

  local windows = createWindows(buffers)

  cleanup(windows)
end

local M = {}

M.setup = function()
  vim.api.nvim_create_user_command("Merger", Main, { desc = "Git Mergetool" })
end

return M
