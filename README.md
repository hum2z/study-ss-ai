# StudySnap

A tiny Mac menu bar app: press **⌥⇧S**, drag over a question, and it opens in
ChatGPT, Gemini or Claude with the screenshot already pasted in.

## Setup

```bash
./build.sh
open build/StudySnap.app
```

On first launch:
1. Pick ChatGPT, Gemini or Claude (untick "Remember my choice" to be asked every time).
2. Allow **Accessibility** (System Settings → Privacy & Security) so it can paste for you.
3. The first snap will ask for **Screen Recording** permission — allow it.

Change the site, auto-Enter, or paste delay any time from the menu bar icon.

## Notes
- Be logged in to the site in your default browser.
- If the paste happens before the page loads, raise "Wait before pasting".
- Rebuilding resets the Accessibility permission (remove and re-add the app).
