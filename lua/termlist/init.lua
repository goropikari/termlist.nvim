local M = {}

local toggleterm = require('toggleterm.terminal')

local default_config = {
  shell = 'bash',
  keymaps = {
    toggle = '<c-t>',
    select = '<CR>',
    shutdown = 'D',
    rename = 'r',
    add = '<c-n>',
  },
  height_ratio = 0.35,
}

local config = {}

local state = {
  view_win = nil,
  list_win = nil,
  view_buf = nil,
  list_buf = nil,
  terminals = {},
}

local function get_keymap(key)
  return config.keymaps[key]
end

local function show(term)
  vim.api.nvim_win_set_buf(state.view_win, term.bufnr)
end

local function set_toggle_keymap(term)
  vim.keymap.set('t', get_keymap('toggle'), M.toggle, { buffer = term.buf, noremap = true, silent = true })
end

local function current_view_buf()
  if state.view_win and vim.api.nvim_win_is_valid(state.view_win) then
    return vim.api.nvim_win_get_buf(state.view_win)
  end
  return nil
end

---@return Terminal
local function new_terminal()
  local term = toggleterm.Terminal:new({ cmd = config.shell, hidden = false })
  term:spawn()
  set_toggle_keymap(term)
  return term
end

---@return integer
local function view_buf()
  if state.view_buf and vim.api.nvim_buf_is_valid(state.view_buf) then
    return state.view_buf
  end

  local term = new_terminal()
  state.view_buf = term.bufnr
  return state.view_buf
end

---@return integer
local function view_win()
  local total_height = vim.o.lines
  local height = math.floor(total_height * config.height_ratio)
  if state.view_win and vim.api.nvim_win_is_valid(state.view_win) then
    return state.view_win
  end

  local view_opts = {
    height = height,
    style = 'minimal',
    split = 'below',
    win = 0,
  }
  local winid = vim.api.nvim_open_win(view_buf(), true, view_opts)
  state.view_win = winid
  vim.api.nvim_win_set_config(winid, view_opts)
  vim.cmd('wincmd J')
  vim.api.nvim_win_set_height(winid, height)
  return winid
end

function M.open()
  if state.view_win and vim.api.nvim_win_is_valid(state.view_win) then
    -- すでに view window が開いている場合は何もしない
    return
  end

  -- editor 全体サイズ
  local total_width = vim.o.columns
  local list_width = math.floor(total_width * 0.2)

  if #state.terminals == 0 then
    local term = new_terminal()
    state.view_buf = term.bufnr
  end

  local winid = view_win()
  vim.api.nvim_win_set_buf(winid, view_buf())

  -- terminal 一覧 window
  state.list_buf = vim.api.nvim_create_buf(false, true)
  local list_opts = {
    width = list_width,
    style = 'minimal',
    split = 'right',
    win = view_win(),
  }
  state.list_win = vim.api.nvim_open_win(state.list_buf, false, list_opts)

  vim.api.nvim_set_option_value('buftype', 'nofile', { buf = state.list_buf })
  vim.api.nvim_set_option_value('modifiable', false, { buf = state.list_buf })
  vim.api.nvim_set_option_value('winhl', 'Normal:Normal', { win = state.list_win })

  vim.keymap.set('n', get_keymap('select'), M.select_terminal, { buffer = state.list_buf })
  vim.keymap.set('n', get_keymap('shutdown'), M.shutdown_terminal, { buffer = state.list_buf })
  vim.keymap.set('n', get_keymap('rename'), M.rename_terminal, { buffer = state.list_buf })
  vim.keymap.set('n', get_keymap('add'), function()
    M.add_terminal(false)
  end, { buffer = state.list_buf })

  M.refresh_list()

  -- view window が閉じられたら terminal list window も閉じる
  -- terminal が ctrl-d で閉じられたときのことを想定している
  local group = vim.api.nvim_create_augroup('TerminalCloseGroup', { clear = true })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = group,
    callback = function(args)
      local closed_win = tonumber(args.match)
      if closed_win == state.view_win and vim.api.nvim_win_is_valid(state.list_win) then
        vim.api.nvim_win_close(state.list_win, true)
      elseif closed_win == state.list_win and vim.api.nvim_win_is_valid(state.view_win) then
        vim.api.nvim_win_close(state.view_win, true)
      end
    end,
    once = true,
  })
end

function M.refresh_list()
  -- toggleterm の terminal 一覧を取得
  local terminals = toggleterm.get_all()
  state.terminals = terminals

  local lines = {}
  for _, term in ipairs(terminals) do
    local active_mark = term.bufnr == current_view_buf() and '>' or ' '
    local name = term.display_name or ('Terminal #' .. term.id)
    table.insert(lines, string.format('%s termid=%d: %s', active_mark, term.id, name))
  end

  vim.api.nvim_set_option_value('modifiable', true, { buf = state.list_buf })
  vim.api.nvim_buf_set_lines(state.list_buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = state.list_buf })
end

function M.select_terminal()
  local row = unpack(vim.api.nvim_win_get_cursor(state.list_win))
  local term = state.terminals[row]
  if term then
    -- 右の terminal ウィンドウにそのターミナルのバッファを表示
    vim.api.nvim_win_set_buf(view_win(), term.bufnr)
  end
  vim.api.nvim_set_current_win(view_win())
  vim.cmd('stopinsert')
  M.refresh_list()
end

function M.rename_terminal()
  local row = unpack(vim.api.nvim_win_get_cursor(state.list_win))
  local term = state.terminals[row]
  if not term then
    return
  end

  vim.ui.input({ prompt = 'New name for terminal: ', default = term.display_name }, function(input)
    if input ~= nil then
      term.display_name = input
    end
  end)
  M.refresh_list()
end

function M.shutdown_terminal()
  local row = unpack(vim.api.nvim_win_get_cursor(state.list_win))
  local term = state.terminals[row]
  local next_term
  -- 最低一つは terminal を残す
  if #state.terminals == 1 then
    next_term = new_terminal()
  else
    for i, _ in ipairs(state.terminals) do
      if i ~= row then
        next_term = state.terminals[i]
        break
      end
    end
  end
  show(next_term)

  term:shutdown()
  M.refresh_list()
end

---@param forcus boolean
function M.add_terminal(forcus)
  local term = new_terminal()
  show(term)
  vim.schedule(function()
    M.refresh_list()
  end)
  if forcus then
    vim.api.nvim_set_current_win(view_win())
    return
  end
  vim.api.nvim_set_current_win(state.list_win)
  vim.schedule(function()
    vim.cmd('stopinsert')
  end)
end

function M.close()
  if state.view_win and vim.api.nvim_win_is_valid(state.view_win) then
    vim.api.nvim_win_close(state.view_win, true)
    state.view_win = nil
  end
  if state.list_win and vim.api.nvim_win_is_valid(state.list_win) then
    vim.api.nvim_win_close(state.list_win, true)
    state.list_win = nil
  end
end

function M.toggle()
  if state.view_win and vim.api.nvim_win_is_valid(state.view_win) then
    M.close()
  else
    M.open()
  end
end

---@return Terminal
local function get_current_term()
  local lines = vim.api.nvim_buf_get_lines(state.list_buf, 0, -1, false)
  for i, line in ipairs(lines) do
    if line:sub(1, 1) == '>' then
      return state.terminals[i]
    end
  end
end

local function get_visual_lines(opts)
  if vim.fn.mode() == 'n' then -- command から使う用
    return vim.fn.getline(opts.line1, opts.line2)
  else -- <leader> key を使った keymap 用
    local lines = vim.fn.getregion(vim.fn.getpos('v'), vim.fn.getpos('.'), { type = vim.fn.mode() })
    -- https://github.com/neovim/neovim/discussions/26092
    vim.cmd([[ execute "normal! \<ESC>" ]])
    return lines
  end
end

local function get_visual_text(opts)
  local texts = get_visual_lines(opts or {})
  vim.print(texts)
  return vim.fn.join(texts, '\n')
end

function M.send_current_line()
  M.open()
  local term = get_current_term()

  local line = vim.api.nvim_get_current_line()
  if line ~= '' then
    term:send(line, true)
  end
end

function M.send_visual_text(opts)
  M.open()
  local term = get_current_term()

  term:send(get_visual_text(opts), true)
end

function M.setup(opts)
  config = vim.tbl_deep_extend('force', default_config, opts or {})
end

return M
