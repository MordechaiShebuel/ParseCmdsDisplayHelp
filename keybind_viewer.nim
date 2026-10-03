import std/[os, strutils, re, tables, options]
import gintro/[gtk, glib]

type
  KeyBinding = object
    shortcut: string
    action: string

proc readLuaVariables(source: string): Table[string, string] =
  result = initTable[string, string]()

  let pattern = re"""local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"]*)""""

  for match in source.findAll(pattern):
    result[match.captures[1]] = match.captures[2]

proc expandPart(part: string,
                variables: Table[string, string]): string =
  result = part.strip()

  if result in variables:
    return variables[result]

  if result.len >= 2 and
     result[0] == '"' and
     result[^1] == '"':
    return result[1 .. ^2]

  result = result.strip(chars = {'"', '\''})

proc commonKeyName(key: string): string =
  let value = key.strip()

  case value.toUpperAscii()
  of "SUPER":
    "Super"
  of "ALT", "OPTION":
    "Alt"
  of "CTRL", "CONTROL":
    "Ctrl"
  of "SHIFT":
    "Shift"
  of "RETURN", "ENTER":
    "Enter"
  of "ESC", "ESCAPE":
    "Esc"
  of "TAB":
    "Tab"
  of "SPACE":
    "Space"
  of "BACKSPACE":
    "Backspace"
  of "DELETE", "DEL":
    "Delete"
  of "UP":
    "Up"
  of "DOWN":
    "Down"
  of "LEFT":
    "Left"
  of "RIGHT":
    "Right"
  else:
    value

proc normalizeShortcut(shortcut: string): string =
  var keys: seq[string]

  for part in shortcut.split('+'):
    let key = commonKeyName(part)
    if key.len > 0:
      keys.add(key)

  keys.join(" + ")

proc parseShortcut(expression: string,
                   variables: Table[string, string]): string =
  var parts: seq[string]

  for part in expression.split(".."):
    parts.add(expandPart(part, variables))

  normalizeShortcut(parts.join(" + "))

proc extractKeyBindings(source: string): seq[KeyBinding] =
  let variables = readLuaVariables(source)

  # The shortcut is captured up to the comma before hl.dsp.
  let bindingPattern = re"""
    hl\.bind\s*\(\s*(.*?)\s*,\s*hl\.dsp\.([A-Za-z_][A-Za-z0-9_]*)
  """

  for line in source.splitLines():
    let match = line.find(bindingPattern)

    if match.isSome:
      let shortcutExpression = match.get.captures[1]
      let actionName = match.get.captures[2]

      result.add(KeyBinding(
        shortcut: parseShortcut(shortcutExpression, variables),
        action: actionName
      ))

proc bindingsAsText(bindings: seq[KeyBinding]): string =
  if bindings.len == 0:
    return "No keybindings found."

  for binding in bindings:
    result.add(binding.shortcut & "    →    " & binding.action & "\n")

proc activate(app: Application, text: string) =
  let window = newApplicationWindow(app)
  window.title = "Lua Keybindings"
  window.defaultWidth = 650
  window.defaultHeight = 400

  let textView = newTextView()
  textView.editable = false
  textView.cursorVisible = false
  textView.monospace = true
  textView.wrapMode = WrapMode.none

  let buffer = textView.buffer
  buffer.text = text

  let scrolledWindow = newScrolledWindow()
  scrolledWindow.setPolicy(
    PolicyType.automatic,
    PolicyType.automatic
  )
  scrolledWindow.add(textView)

  window.add(scrolledWindow)
  window.showAll()

proc main() =
  if paramCount() < 1:
    echo "Usage: keybind_viewer <keybinds.lua>"
    quit(1)

  let luaFile = paramStr(1)

  if not fileExists(luaFile):
    quit("File not found: " & luaFile)

  let source = readFile(luaFile)
  let bindings = extractKeyBindings(source)
  let displayText = bindingsAsText(bindings)

  let app = newApplication(
    "com.example.LuaKeybindViewer",
    ApplicationFlags.flagsNone
  )

  discard app.connect("activate", activate, displayText)
  discard app.run()

when isMainModule:
  main()
