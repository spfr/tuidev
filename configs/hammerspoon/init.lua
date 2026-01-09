-- ============================================================================
-- Hammerspoon Configuration
-- macOS automation powerhouse
-- ============================================================================

-- Reload configuration on save
hs.hotkey.bind({'cmd', 'alt', 'ctrl'}, 'R', function()
  hs.reload()
  hs.alert.show('Config reloaded')
end)

-- ============================================================================
-- Window Management (Keyboard-Driven)
-- ============================================================================

-- Grid layout (create a 3x2 grid for better control)
hs.grid.setGrid('30x30')
hs.grid.setMargins('5x5')
hs.alert.defaultStyle.strokeColor = {white = 1, alpha = 0}
hs.alert.defaultStyle.fillColor = {white = 0, alpha = 0.75}
hs.alert.defaultStyle.radius = 2
hs.alert.defaultStyle.textSize = 20

-- Window movement hotkeys (Ctrl + Alt + Arrow)
hs.hotkey.bind({'ctrl', 'alt'}, 'Left', function()
  local win = hs.window.focusedWindow()
  if win then
    win:moveToUnit(hs.layout.left50)
  end
end)

hs.hotkey.bind({'ctrl', 'alt'}, 'Right', function()
  local win = hs.window.focusedWindow()
  if win then
    win:moveToUnit(hs.layout.right50)
  end
end)

hs.hotkey.bind({'ctrl', 'alt'}, 'Up', function()
  local win = hs.window.focusedWindow()
  if win then
    win:moveToUnit(hs.layout.top50)
  end
end)

hs.hotkey.bind({'ctrl', 'alt'}, 'Down', function()
  local win = hs.window.focusedWindow()
  if win then
    win:moveToUnit(hs.layout.bottom50)
  end
end)

-- Maximize window (Ctrl + Alt + M)
hs.hotkey.bind({'ctrl', 'alt'}, 'M', function()
  local win = hs.window.focusedWindow()
  if win then
    win: maximize()
  end
end)

-- Center window (Ctrl + Alt + C)
hs.hotkey.bind({'ctrl', 'alt'}, 'C', function()
  local win = hs.window.focusedWindow()
  if win then
    win: centerOnScreen()
  end
end)

-- Resize window (Ctrl + Alt + Shift + Arrow)
hs.hotkey.bind({'ctrl', 'alt', 'shift'}, 'Left', function()
  local win = hs.window.focusedWindow()
  if win then
    win:moveOneScreenWest()
  end
end)

hs.hotkey.bind({'ctrl', 'alt', 'shift'}, 'Right', function()
  local win = hs.window.focusedWindow()
  if win then
    win:moveOneScreenEast()
  end
end)

-- Full screen (Ctrl + Alt + F)
hs.hotkey.bind({'ctrl', 'alt'}, 'F', function()
  local win = hs.window.focusedWindow()
  if win then
    win:toggleFullScreen()
  end
end)

-- ============================================================================
-- Application Launcher (Cmd + Space style)
-- ============================================================================

-- Quick launcher (Ctrl + Alt + P)
hs.hotkey.bind({'ctrl', 'alt'}, 'P', function()
  hs.application.launchOrFocus('Ghostty')
end)

hs.hotkey.bind({'ctrl', 'alt'}, 'E', function()
  hs.application.launchOrFocus('Neovim')
end)

hs.hotkey.bind({'ctrl', 'alt'}, 'B', function()
  hs.application.launchOrFocus('Brave Browser')
end)

-- ============================================================================
-- Clipboard History Enhancement (works with Maccy)
-- ============================================================================

-- Open Maccy with Cmd + Shift + V (alternative to Maccy's default)
hs.hotkey.bind({'cmd', 'shift'}, 'V', function()
  hs.application.launchOrFocus('Maccy')
end)

-- ============================================================================
-- Focus Switching
-- ============================================================================

-- Focus next window (Ctrl + Alt + Tab)
hs.hotkey.bind({'ctrl', 'alt'}, 'Tab', function()
  hs.window.focusedWindow():focusCycle(1)
end)

-- Focus previous window (Ctrl + Alt + Shift + Tab)
hs.hotkey.bind({'ctrl', 'alt', 'shift'}, 'Tab', function()
  hs.window.focusedWindow():focusCycle(-1)
end)

-- ============================================================================
-- Screen Management (for multi-monitor setups)
-- ============================================================================

-- Move window to next screen (Ctrl + Alt + S)
hs.hotkey.bind({'ctrl', 'alt'}, 'S', function()
  local win = hs.window.focusedWindow()
  if win then
    win:moveToScreen(win:screen():next())
  end
end)

-- ============================================================================
-- Volume Control (Media keys might not work on some keyboards)
-- ============================================================================

hs.hotkey.bind({'ctrl', 'alt'}, '=', function()
  hs.audiodevice.defaultOutputDevice():setVolume(
    hs.audiodevice.defaultOutputDevice():volume() + 5
  )
end)

hs.hotkey.bind({'ctrl', 'alt'}, '-', function()
  hs.audiodevice.defaultOutputDevice():setVolume(
    hs.audiodevice.defaultOutputDevice():volume() - 5
  )
end)

-- ============================================================================
-- Notifications and Alerts
-- ============================================================================

-- Show startup alert
hs.alert.show('Hammerspoon loaded! Use Ctrl+Alt+Arrow keys to move windows')

-- Watch for new windows and notify
hs.window.filter.default:subscribe(hs.window.filter.windowCreated, function(window)
  hs.alert.show('New window: ' .. window:title(), 2)
end)

-- ============================================================================
-- Utility Functions
-- ============================================================================

-- Show window info (for debugging) - Ctrl + Alt + I
hs.hotkey.bind({'ctrl', 'alt'}, 'I', function()
  local win = hs.window.focusedWindow()
  if win then
    hs.alert.show(string.format(
      'App: %s\nTitle: %s\nID: %s',
      win:application():name(),
      win:title(),
      win:id()
    ), 3)
  end
end)

-- Hide all windows except current (Ctrl + Alt + H)
hs.hotkey.bind({'ctrl', 'alt'}, 'H', function()
  local current = hs.window.focusedWindow()
  hs.fnutils.each(hs.window.visibleWindows(), function(win)
    if win ~= current then
      win:application():hide()
    end
  end)
end)

-- ============================================================================
-- Mouse Focus (follow mouse when moving)
-- ============================================================================

-- Uncomment to enable mouse-follows-focus
-- hs.mousefollowsfocus = true

-- ============================================================================
-- Auto Layout for Specific Apps
-- ============================================================================

-- Layout for terminal apps (Ghostty)
local terminalApps = {'Ghostty', 'Terminal', 'iTerm2'}
hs.window.filter.new(terminalApps):subscribe(hs.window.filter.windowCreated, function(win)
  win:moveToUnit(hs.layout.left50)
end)

-- Layout for browsers
local browserApps = {'Brave Browser', 'Google Chrome', 'Safari'}
hs.window.filter.new(browserApps):subscribe(hs.window.filter.windowCreated, function(win)
  win:moveToUnit(hs.layout.right50)
end)

-- ============================================================================
-- End of Configuration
-- ============================================================================
