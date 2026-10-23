# StudySnap

Press a shortcut, drag over a question, and it opens in ChatGPT, Gemini or Claude
with the screenshot already pasted in.

## Mac (⌥⇧S)

```bash
xcode-select --install   # once, if you don't have Xcode
./build.sh
open build/StudySnap.app
```

On first launch:
1. Pick ChatGPT, Gemini or Claude (untick "Remember my choice" to be asked every time).
2. Allow **Accessibility** (System Settings → Privacy & Security) so it can paste for you.
3. The first snap will ask for **Screen Recording** permission — allow it.

Rebuilding resets the permissions (remove and re-add the app). To keep them across
rebuilds, make a signing certificate once: Keychain Access → Certificate Assistant →
Create a Certificate… → Name `StudySnap Dev`, Certificate Type **Code Signing** → Create.
`build.sh` uses it automatically from then on.

## Windows (Alt+Shift+S)

1. Install **AutoHotkey v2** from https://www.autohotkey.com
2. Double-click `windows/StudySnap.ahk`.
3. Pick ChatGPT, Gemini or Claude.

To start it with Windows: press Win+R, type `shell:startup`, and put a shortcut to
`StudySnap.ahk` in that folder.

## Settings

Change the site, auto-Enter, or paste delay any time from the menu bar / tray icon.

- Be logged in to the site in your default browser.
- If the paste happens before the page loads, raise "Wait before pasting".
