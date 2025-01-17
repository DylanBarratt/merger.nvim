---@class Buffers
---@field current number
---@field currentInfo number
---@field incoming number
---@field incomingInfo number
---@field base number
---@field startFile number

---@class Windows
---@field current number
---@field currentInfo number
---@field incoming number
---@field incomingInfo number
---@field base number

---@class Conflict
---@field lineNum number 0 indexed
---@field incoming string[]
---@field current string[]
---@field base string[]

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS

---@return table
local function valuesOnly(tbl)
  local values_only = {}
  for _, value in pairs(tbl) do
    table.insert(values_only, value)
  end
  return values_only
end

--------------------------------------------------------------------------------

---@param buffers Buffers
local function setBuffersFiletype(buffers)
  local baseFileType = vim.bo[buffers.startFile].filetype
  vim.bo[buffers.base].filetype = baseFileType
  vim.bo[buffers.current].filetype = baseFileType
  vim.bo[buffers.incoming].filetype = baseFileType
  vim.bo[buffers.startFile].filetype = baseFileType
end

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
        relativeLineNum = relativeLineNum + 2
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
        -- save conflict section inner parts
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

  local function createFloat(bufnr, enter, top, left, width, height)
    local opts = {
      relative = "editor",
      row = top,
      col = left,
      width = width,
      height = height,
    }

    return vim.api.nvim_open_win(bufnr, enter, opts)
  end

  local function createInfoLine(bufnr, enter, top, left, width, height)
    local opts = {
      relative = "editor",
      row = top,
      col = left,
      width = width,
      height = height,
      focusable = false,
      style = "minimal",
    }

    return vim.api.nvim_open_win(bufnr, enter, opts)
  end

  return {
    incoming = createFloat(
      buffers.incoming,
      false,
      1,
      0,
      math.floor(editor_width / 2),
      math.floor(editor_height / 2)
    ),
    incomingInfo = createInfoLine(
      buffers.incomingInfo,
      false,
      0,
      0,
      math.floor(editor_width / 2),
      1
    ),
    current = createFloat(
      buffers.current,
      false,
      1,
      math.floor(editor_width / 2),
      math.floor(editor_width / 2),
      math.floor(editor_height / 2)
    ),
    currentInfo = createInfoLine(
      buffers.currentInfo,
      false,
      0,
      math.floor(editor_width / 2),
      math.floor(editor_width / 2),
      1
    ),
    base = createFloat(
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

  setBuf(buffers.currentInfo, { " Current" })
  setBuf(buffers.incomingInfo, { " Incoming" })

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
---@param windows Windows
---@param conflicts Conflict[]
local function highlightDiffs(namespace, buffers, windows, conflicts)
  -- highlight whole section
  -- local function highlightLine(buff, line)
  --   vim.api.nvim_buf_add_highlight(buff, namespace, "Visual", line, 0, -1)
  -- end
  --
  -- for x = 1, #conflicts do
  --   for i = 0, #conflicts[x].incoming do
  --     highlightLine(buffers.base, conflicts[x].lineNum + i)
  --     highlightLine(buffers.incoming, conflicts[x].lineNum + i)
  --     highlightLine(buffers.current, conflicts[x].lineNum + i)
  --   end
  -- end

  local function linesAround(buff, line, len, confIndex)
    -- HACK: repeat 1000 so that dashes always fill window
    vim.api.nvim_buf_set_extmark(buff, namespace, line, 0, {
      virt_lines = {
        { { "───" .. confIndex .. string.rep("─", 1000) } },
      },
      virt_lines_above = true,
    })

    vim.api.nvim_buf_set_extmark(buff, namespace, line + len - 1, 0, {
      virt_lines = {
        { { string.rep("─", 1000) } },
      },
      virt_lines_above = false,
    })
  end

  local function highlightChar(buff, line, char)
    vim.api.nvim_buf_add_highlight(
      buff,
      namespace,
      "DiffAdd",
      line - 1, -- match 0 indexing
      char - 1, -- match 0 indexing
      char
    )
  end

  for curConf = 1, #conflicts do
    linesAround(
      buffers.current,
      conflicts[curConf].lineNum,
      #conflicts[curConf].current,
      curConf
    )
    linesAround(
      buffers.incoming,
      conflicts[curConf].lineNum,
      #conflicts[curConf].incoming,
      curConf
    )

    -- HACK: virtual lines on line 0 are hidden without this :/
    if conflicts[curConf].lineNum == 0 then
      vim.api.nvim_set_current_win(windows.current)
      vim.fn.winrestview({ topfill = 1 })
      vim.api.nvim_set_current_win(windows.incoming)
      vim.fn.winrestview({ topfill = 1 })
      vim.api.nvim_set_current_win(windows.base)
    end

    -- highlight character diffs
    for curLineI = 1, math.max(#conflicts[curConf].current, #conflicts[curConf].incoming) do
      local baseLine = conflicts[curConf].base[curLineI] or ""
      local currentLine = conflicts[curConf].current[curLineI] or ""
      local incomingLine = conflicts[curConf].incoming[curLineI] or ""

      -- highlight the differences for this line to base
      for curChar = 1, #baseLine do
        local baseLineChar = baseLine:sub(curChar, curChar)
        local currentLineChar = currentLine:sub(curChar, curChar)
        local incomingLineChar = incomingLine:sub(curChar, curChar)

        if currentLineChar ~= baseLineChar then
          highlightChar(
            buffers.current,
            conflicts[curConf].lineNum + curLineI,
            curChar
          )
        end
        if incomingLineChar ~= baseLineChar then
          highlightChar(
            buffers.incoming,
            conflicts[curConf].lineNum + curLineI,
            curChar
          )
        end
      end

      -- highlight all remaining characters
      if #currentLine > #baseLine then
        for i = #baseLine, #currentLine, 1 do
          highlightChar(
            buffers.current,
            conflicts[curConf].lineNum + curLineI,
            i
          )
        end
      end
      if #incomingLine > #baseLine then
        for i = #baseLine, #incomingLine, 1 do
          highlightChar(
            buffers.incoming,
            conflicts[curConf].lineNum + curLineI,
            i
          )
        end
      end
    end
  end
end

---@param buffers Buffers
---@param conflicts Conflict[]
local function userCommands(buffers, conflicts)
  vim.api.nvim_create_user_command("Merger", function(event)
    if
      event.args ~= "current"
      and event.args ~= "incoming"
      and event.args ~= "base"
    then
      print(
        "incorrect "
          .. event.args
          .. ", please use current, incoming, or parent"
      )
      return
    end

    for i = 1, #conflicts, 1 do
      local curLineNum = vim.api.nvim_win_get_cursor(0)[1]
      if
        curLineNum >= conflicts[i].lineNum
        and curLineNum <= conflicts[i].lineNum + #conflicts[i][event.args]
      then
        vim.api.nvim_buf_set_lines(
          buffers.base,
          conflicts[i].lineNum,
          conflicts[i].lineNum + #conflicts[i][event.args],
          false,
          conflicts[i][event.args]
        )
        break
      end
    end
  end, {
    complete = function()
      return { "current", "incoming", "base" }
    end,
    nargs = 1,
  })
end

---@param conflicts Conflict[]
---@param windows Windows
local function navigation(conflicts, windows)
  ---@return Conflict
  local function find_next_conflict()
    ---@type Conflict
    local next_conflict = nil

    for i = 1, #conflicts, 1 do
      if
        conflicts[i].lineNum > vim.api.nvim_win_get_cursor(0)[1] - 1
        and (not next_conflict or conflicts[i].lineNum < next_conflict.lineNum)
      then
        next_conflict = conflicts[i]
      end
    end

    return next_conflict == nil and conflicts[1] or next_conflict
  end

  ---@return Conflict
  local function find_prev_conflict()
    ---@type Conflict
    local prev_conflict = nil

    for i = 1, #conflicts, 1 do
      if
        conflicts[i].lineNum < vim.api.nvim_win_get_cursor(0)[1] - 1
        and (not prev_conflict or conflicts[i].lineNum > prev_conflict.lineNum)
      then
        prev_conflict = conflicts[i]
      end
    end

    return prev_conflict == nil and conflicts[#conflicts] or prev_conflict
  end

  vim.keymap.set("n", "]c", function()
    vim.api.nvim_win_set_cursor(
      windows.base,
      { find_next_conflict().lineNum + 1, 0 }
    )
  end, { desc = "next conflict" })
  vim.keymap.set("n", "[c", function()
    vim.api.nvim_win_set_cursor(
      windows.base,
      { find_prev_conflict().lineNum + 1, 0 }
    )
  end, { desc = "previous conflict" })
end

---@param buffers Buffers
local function saveBase(buffers)
  vim.api.nvim_buf_set_lines(
    buffers.startFile,
    0,
    -1,
    false,
    vim.api.nvim_buf_get_lines(buffers.base, 0, -1, false)
  )
end

---@param windows Windows
---@param cursorAutoCmd number
---@param buffers Buffers
local function cleanup(windows, cursorAutoCmd, buffers)
  -- cleanup all when one win closes
  vim.api.nvim_create_autocmd("WinClosed", {
    callback = function(event)
      local wins = valuesOnly(windows)
      if vim.tbl_contains(wins, tonumber(event.match)) then
        saveBase(buffers)
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
  local namespace = vim.api.nvim_create_namespace("Merger")

  local startFileName = vim.fn.expand("%:t")
  local gitDir = vim.fn
    .system("git -C " .. vim.fn.expand("%:p:h") .. " rev-parse --show-toplevel")
    :gsub("\n", "")

  if gitDir == "" then
    print("Merger.nvim error: git repo not found")
    return
  end

  ---@type Buffers
  local buffers = {
    currentInfo = vim.api.nvim_create_buf(false, true),
    current = vim.api.nvim_create_buf(false, true),
    incomingInfo = vim.api.nvim_create_buf(false, true),
    incoming = vim.api.nvim_create_buf(false, true),
    base = vim.api.nvim_create_buf(false, true),
    startFile = vim.api.nvim_get_current_buf(),
  }

  setBuffersFiletype(buffers)

  populateBuffers(startFileName, gitDir, buffers)

  local conflicts = searchBuffer(buffers.startFile)

  local windows = createWindows(buffers)

  -- set the cursor to the first conflict
  vim.api.nvim_win_set_cursor(windows.base, { conflicts[1].lineNum + 1, 0 })
  vim.api.nvim_win_set_cursor(windows.incoming, { conflicts[1].lineNum + 1, 0 })
  vim.api.nvim_win_set_cursor(windows.current, { conflicts[1].lineNum + 1, 0 })

  local cursorAutoCmd = syncCursors(windows)

  highlightDiffs(namespace, buffers, windows, conflicts)

  userCommands(buffers, conflicts)

  navigation(conflicts, windows)

  cleanup(windows, cursorAutoCmd, buffers)
end

--------------------------------------------------------------------------------

local M = {}

M.setup = function()
  vim.api.nvim_create_user_command("Merger", Main, { desc = "Git Mergetool" })
end

return M
