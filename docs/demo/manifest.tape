# Paramify CLI — build a run manifest, guided
# Render from the repo root:  vhs docs/demo/manifest.tape
#
# The manifest commands need a cwd inside the repo (they walk up for the
# sibling fetchers/ + framework/ dirs), so we record from a throwaway
# docs/demo/.scratch/ and wrap `paramify` to trim the absolute path it prints.
# render.sh removes the scratch dir afterward; it is also gitignored.

Output docs/demo/manifest.gif

Set Shell "bash"
Set FontSize 18
Set Width 1240
Set Height 720
Set Padding 24
Set Theme "TokyoNight"
Set TypingSpeed 55ms

# --- hidden setup: venv, scratch dir, clean prompt, path-trimming wrapper ---
Hide
Type "source .venv/bin/activate 2>/dev/null"
Enter
Type "rm -rf docs/demo/.scratch && mkdir -p docs/demo/.scratch && cd docs/demo/.scratch"
Enter
Type `export PS1='$ '; D="$PWD"; paramify() { command paramify "$@" 2>&1 | sed "s#$D/##g"; }`
Enter
Type "clear"
Enter
Show

# Start an empty manifest
Sleep 600ms
Type "paramify manifest init --output-dir ./evidence"
Sleep 300ms
Enter
Sleep 1400ms

# Add a fetcher — the builder tells you what's still missing
Type "paramify manifest add okta_phishing_resistant_mfa"
Sleep 300ms
Enter
Sleep 2600ms

# Wire its secrets to env vars; the warnings shrink as you go
Type "paramify manifest set-secret okta_phishing_resistant_mfa api_token OKTA_API_TOKEN"
Sleep 300ms
Enter
Sleep 2200ms

Type "paramify manifest set-secret okta_phishing_resistant_mfa org_url OKTA_ORG_URL"
Sleep 300ms
Enter
Sleep 2000ms

# Now it's runnable
Type "paramify manifest show"
Sleep 300ms
Enter
Sleep 3800ms
