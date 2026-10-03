# ParseCmdsDisplayHelp

# NIM VERSION

## You will need wNim to compile

`nimble install gintro`

## You'll need the library for GTK
`sudo xbps-install -S gtk+3-devel gobject-introspection`

## Compile application:
`nim c -d:release keybind_viewer.nim`

## Run it against your lua
`./keybind_viewer ~/.config/hypr/hyprland.lua`

(COULD NOT GET THE ABOVE TO COMPILE)

# ZIG VERSION

## compile
`zig build-exe main.zig \
  $(pkg-config --cflags --libs gtk+-3.0) \
  -lc`

## run
`./main ~/.config/hypr/hyprland.lua`

# Compile of this is also not working

# LLMs cannot generate code that runs the first time, I don't know Zig or Nim all that well, so it is difficult for me to diagnose what it got wrong.z

# Grok code again saved this, got a functional bit of code, some cleanup still needed, but looks much better than the shell version I was using
