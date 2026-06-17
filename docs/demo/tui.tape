# Paramify TUI — a quick walkthrough
# Render from the repo root:  vhs docs/demo/tui.tape
#
# Drives the Textual TUI by keypress: the welcome screen settles, we open a
# manifest, then tour the Catalog (with search), Manifest, and Run tabs.

Output docs/demo/tui.gif

Set Shell "bash"
Set FontSize 16
Set Width 1280
Set Height 760
Set Padding 16
Set Theme "TokyoNight"
Set TypingSpeed 90ms

Hide
Type "source .venv/bin/activate 2>/dev/null; clear"
Enter
Show

# Launch — the welcome screen runs its startup checks, then settles
Type "paramify tui"
Sleep 500ms
Enter
Sleep 4500ms

# Open the highlighted manifest -> workspace (Catalog tab)
Enter
Sleep 2200ms

# Search the catalog
Type "/"
Sleep 600ms
Type "okta"
Sleep 2200ms
Escape
Sleep 800ms

# Manifest tab
Type "2"
Sleep 2400ms

# Run tab
Type "3"
Sleep 2200ms

# Back to Catalog, then quit
Type "1"
Sleep 1500ms
Type "q"
Sleep 1200ms
