---@class Buffers
---@field current number
---@field incoming number
---@field base number
---@field startFile number

---@class Windows
---@field current number
---@field incoming number
---@field base number

---@class Conflict
---@field lineNum number
---@field incoming string[]
---@field current string[]
---@field base string[]

--------------------------------------------------------------------------------

local function valuesOnly(tbl)
  local values_only = {}
  for _, value in pairs(tbl) do
    table.insert(values_only, value)
  end
  return values_only
end

--------------------------------------------------------------------------------

---@param buffNum number
---@return Conflict[]
local function searchBuffer(buffNum)
  local CONFLICT_MARKER_START = "<<<<<<<"
  local CONFLICT_MARKER_END = ">>>>>>>"
  local PARENT_MARKER = "|||||||"
  local CONFLICT_MIDDLE = "======="

  ---@type Conflict[]
  local conflicts = {}

  local lineNum = 0
  local relativeLineNum = 0 -- line num without conflict markers
  ---@type "none" | "current" | "base" | "incoming"
  local curPart = "none"
  while lineNum <= vim.api.nvim_buf_line_count(buffNum) - 1 do
    local curLine =
      vim.api.nvim_buf_get_lines(buffNum, lineNum, lineNum + 1, false)[1]

    if curLine:match(CONFLICT_MARKER_START) then
      -- New conflict found
      if curPart == "none" then
        table.insert(conflicts, { lineNum = relativeLineNum })
        relativeLineNum = relativeLineNum + 1
      end

      curPart = "current"
    elseif curLine:match(PARENT_MARKER) then
      curPart = "base"
    elseif curLine:match(CONFLICT_MIDDLE) then
      curPart = "incoming"
    elseif curLine:match(CONFLICT_MARKER_END) then
      curPart = "none"
    else
      if curPart ~= "none" then
        if conflicts[#conflicts][curPart] == nil then
          conflicts[#conflicts][curPart] = { curLine }
        else
          table.insert(conflicts[#conflicts][curPart], curLine)
        end
      else
        relativeLineNum = relativeLineNum + 1 -- only increment when not in conflict
      end
    end

    lineNum = lineNum + 1
  end

  return conflicts
end
---@param buffers Buffers
---@return Windows
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

  return {
    incoming = create_float(
      buffers.incoming,
      false,
      0,
      0,
      math.floor(editor_width / 2),
      math.floor(editor_height / 2)
    ),
    current = create_float(
      buffers.current,
      false,
      0,
      math.floor(editor_width / 2),
      math.floor(editor_width / 2),
      math.floor(editor_height / 2)
    ),
    base = create_float(
      buffers.base,
      true,
      math.floor(editor_height / 2),
      0,
      editor_width,
      math.floor(editor_height / 2)
    ),
  }
end

---@param fileName string
---@param gitDir string
---@param buffers Buffers
local function populateBuffers(fileName, gitDir, buffers)
  local function setBuf(bufNr, content)
    vim.api.nvim_buf_set_lines(bufNr, 0, -1, false, content)
  end

  setBuf(
    buffers.base,
    vim.split(
      vim.fn.system("git -C " .. gitDir .. " show :1:" .. fileName),
      "\n"
    )
  )
  setBuf(
    buffers.current,
    vim.split(
      vim.fn.system("git -C " .. gitDir .. " show :2:" .. fileName),
      "\n"
    )
  )
  setBuf(
    buffers.incoming,
    vim.split(
      vim.fn.system("git -C " .. gitDir .. " show :3:" .. fileName),
      "\n"
    )
  )
end

---@param windows Windows
---@return number
local function syncCursors(windows)
  return vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    callback = function()
      local cursor_pos = vim.api.nvim_win_get_cursor(windows.base)

      vim.api.nvim_win_set_cursor(windows.current, cursor_pos)
      vim.api.nvim_win_set_cursor(windows.incoming, cursor_pos)
    end,
  })
end

---@param namespace number
---@param buffers Buffers
---@param conflicts Conflict[]
local function highlightDiffs(namespace, buffers, conflicts)
  local function highlightLine(buff, line)
    vim.api.nvim_buf_add_highlight(buff, namespace, "Visual", line, 0, -1)
  end

  for x = 1, #conflicts do
    for i = 0, #conflicts[x].incoming do
      highlightLine(buffers.base, conflicts[x].lineNum + i)
      highlightLine(buffers.incoming, conflicts[x].lineNum + i)
      highlightLine(buffers.current, conflicts[x].lineNum + i)
    end
  end
end

---@param windows Windows
---@param cursorAutoCmd number
local function cleanup(windows, cursorAutoCmd)
  -- cleanup when one win closes
  vim.api.nvim_create_autocmd("WinClosed", {
    callback = function(event)
      local wins = valuesOnly(windows)
      if vim.tbl_contains(wins, tonumber(event.match)) then
        vim.api.nvim_del_autocmd(cursorAutoCmd)

        for _, win_id in ipairs(wins) do
          if vim.api.nvim_win_is_valid(win_id) then
            vim.api.nvim_win_close(win_id, true)
          end
        end
      end
    end,
  })
end

--------------------------------------------------------------------------------

function Main()
  ---@type Buffers
  local buffers = {
    current = vim.api.nvim_create_buf(false, true),
    incoming = vim.api.nvim_create_buf(false, true),
    base = vim.api.nvim_create_buf(false, true),
    startFile = vim.api.nvim_get_current_buf(),
  }

  local namespace = vim.api.nvim_create_namespace("Merger")

  local startFileName = vim.fn.expand("%:t")
  local gitDir = vim.fn
    .system("git -C " .. vim.fn.expand("%:p:h") .. " rev-parse --show-toplevel")
    :gsub("\n", "")

  if gitDir == "" then
    print("Merger.nvim error: git repo not found")
    return
  end

  populateBuffers(startFileName, gitDir, buffers)

  local conflicts = searchBuffer(buffers.startFile)

  local windows = createWindows(buffers)

  local cursorAutoCmd = syncCursors(windows)

  highlightDiffs(namespace, buffers, conflicts)

  cleanup(windows, cursorAutoCmd)
end

--------------------------------------------------------------------------------

local M = {}

M.setup = function()
  vim.api.nvim_create_user_command("Merger", Main, { desc = "Git Mergetool" })
end

return M
