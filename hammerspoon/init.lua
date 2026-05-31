-- Unified launch-or-focus helper.
--
-- For proper .app bundles (single-arg form): defers to
-- hs.application.launchOrFocus — Launch Services handles "launch if not
-- running, focus if running" correctly for .app bundles.
--
-- For shell-launched apps (multi-arg form): .app-bundle APIs don't see them
-- because the running app on macOS is "Python" (or whatever the interpreter
-- is), not the app's own name. Detect via pgrep on the command-line pattern,
-- then bring the host app forward; only launch when pgrep says it's not running.
local function launchOrFocus(name, shellCmd, opts)
  if not shellCmd then
    hs.application.launchOrFocus(name)
    return
  end

  opts = opts or {}
  local pgrepPattern = opts.pgrep  -- e.g., "my-tool.*app.main"
  local hostApp = opts.host or "Python"  -- macOS-visible app name hosting the process

  if pgrepPattern then
    local _, ok = hs.execute("pgrep -f " .. ("%q"):format(pgrepPattern))
    if ok then
      -- Running. Try the host app (Python.app) first — most reliable for Tk.
      local app = hs.application.get(hostApp)
      if app then
        app:activate(true)  -- true = bring all windows forward
        return
      end
      -- Fallback: window-title substring match.
      local win = hs.window.find(name)
      if win then
        win:focus()
        return
      end
      -- Process exists but neither path could focus — alert instead of relaunching.
      hs.alert.show(name .. " is running but couldn't focus")
      return
    end
  else
    -- No pgrep pattern given — use window-title match only.
    local win = hs.window.find(name)
    if win then
      win:focus()
      return
    end
  end

  hs.execute(shellCmd, true)  -- with_user_env: login shell, sources ~/.zshrc / PATH
end

-- ----------------------------------------------------------------------------
-- App bindings (cmd + alt + letter)
-- ----------------------------------------------------------------------------

-- Productivity / chat
hs.hotkey.bind({"cmd", "alt"}, "M", function() launchOrFocus("ChatGPT") end)
hs.hotkey.bind({"cmd", "alt"}, "K", function() launchOrFocus("Claude") end)
hs.hotkey.bind({"cmd", "alt"}, "C", function() launchOrFocus("Slack") end)
hs.hotkey.bind({"cmd", "alt"}, "P", function() launchOrFocus("Spotify") end)

-- Dev tools
hs.hotkey.bind({"cmd", "alt"}, "V", function() launchOrFocus("Visual Studio Code") end)
hs.hotkey.bind({"cmd", "alt"}, "B", function() launchOrFocus("Google Chrome") end)
hs.hotkey.bind({"cmd", "alt"}, "X", function() launchOrFocus("Terminal") end)
hs.hotkey.bind({"cmd", "alt"}, "G", function() launchOrFocus("Github Desktop") end)

-- System
hs.hotkey.bind({"cmd", "alt"}, "Z", function() launchOrFocus("Finder") end)
hs.hotkey.bind({"cmd", "alt"}, "S", function() launchOrFocus("Settings") end)
hs.hotkey.bind({"cmd", "alt"}, "A", function() launchOrFocus("Activity Monitor") end)

-- Notes / reminders
hs.hotkey.bind({"cmd", "alt"}, "T", function() launchOrFocus("Notes") end)
hs.hotkey.bind({"cmd", "alt"}, "R", function() launchOrFocus("Reminders") end)

-- ----------------------------------------------------------------------------
-- Shell-launched apps (non-.app bundles — pgrep-detected, host-app activated)
-- ----------------------------------------------------------------------------
--
-- Example: a Tk/Python app launched from the shell rather than as a .app bundle.
-- Uncomment and adapt the path + pgrep pattern to your own tool.
--
-- hs.hotkey.bind({"cmd", "alt"}, "W", function()
--   launchOrFocus(
--     "My Tool",
--     'cd ~/path/to/my-tool && ' ..
--     'nohup uv run python -m app.main >/dev/null 2>&1 &',
--     { pgrep = "my-tool.*app.main", host = "Python" }
--   )
-- end)

-- ----------------------------------------------------------------------------
-- Hammerspoon meta
-- ----------------------------------------------------------------------------

hs.hotkey.bind({"cmd", "alt", "ctrl"}, "R", function()
  hs.reload()
end)
