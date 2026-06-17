# Paramify CLI — discovery & breadth
# Render from the repo root:  vhs docs/demo/catalog.tape
# (or run docs/demo/render.sh to build every demo)

Output docs/demo/catalog.gif

Set Shell "bash"
Set FontSize 18
Set Width 1180
Set Height 640
Set Padding 24
Set Theme "TokyoNight"
Set TypingSpeed 55ms

# --- hidden setup: activate venv, clean prompt ---
Hide
Type "source .venv/bin/activate 2>/dev/null; export PS1='$ '; clear"
Enter
Show

# The 8 source systems we collect from
Sleep 600ms
Type `paramify catalog | grep -v '^[[:space:]]' | grep . | sed 's/ —.*//'`
Sleep 400ms
Enter
Sleep 2800ms

Hide
Type "clear"
Enter
Show
Sleep 300ms

# 107 fetchers across them
Type "paramify list | head -n 14"
Sleep 400ms
Enter
Sleep 3200ms

Hide
Type "clear"
Enter
Show
Sleep 300ms

# Inspect any one of them
Type "paramify describe okta_phishing_resistant_mfa"
Sleep 400ms
Enter
Sleep 3500ms
