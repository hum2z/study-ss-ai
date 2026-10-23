; StudySnap for Windows — press Alt+Shift+S, drag over a question, and it opens in
; ChatGPT, Gemini or Claude with the screenshot pasted in.
; Needs AutoHotkey v2: https://www.autohotkey.com

#Requires AutoHotkey v2.0
#SingleInstance Force

Sites := Map("ChatGPT", "https://chatgpt.com/", "Gemini", "https://gemini.google.com/app", "Claude", "https://claude.ai/new")
SiteNames := ["ChatGPT", "Gemini", "Claude"]
Delays := [2, 3, 5, 8]

ConfigDir := A_AppData "\StudySnap"
DirCreate ConfigDir
Ini := ConfigDir "\settings.ini"
firstLaunch := !FileExist(Ini)

GetSetting(key, default) => IniRead(Ini, "Settings", key, default)
SetSetting(key, value) => IniWrite(value, Ini, "Settings", key)

A_IconTip := "StudySnap (Alt+Shift+S)"
BuildMenu()

if firstLaunch {
    SetSetting("hasLaunched", 1)
    AskForSite()
}
TrayTip "Press Alt+Shift+S to snap a question.", "StudySnap is running"

!+s::Snap()

; --- Snap flow ---

Snap(*) {
    A_Clipboard := ""
    Send "#+s"                  ; built-in Windows region picker, copies to clipboard
    if !ClipWait(30, 1)         ; nothing copied = user pressed Esc
        return

    site := GetSetting("site", "")
    if (site = "")
        site := AskForSite()
    if (site = "")
        return

    Run Sites[site]
    Sleep GetSetting("pasteDelay", 3) * 1000
    Send "^v"
    if (GetSetting("autoSend", 0) = 1) {
        Sleep 2000              ; give the image a moment to upload
        Send "{Enter}"
    }
}

; --- Site picker ---

; Shows the "where should screenshots go?" window. Returns "" if closed.
AskForSite() {
    state := {choice: ""}
    g := Gui("+AlwaysOnTop -MinimizeBox", "StudySnap")
    g.SetFont("s10")
    g.Add("Text", , "Where should your screenshots go?")
    for name in SiteNames {
        btn := g.Add("Button", (A_Index = 1 ? "xm" : "x+8") " w90", name)
        btn.OnEvent("Click", Choose.Bind(name))
    }
    remember := g.Add("Checkbox", "xm Checked", "Remember my choice")
    g.Add("Text", "xm cGray", "You can change this any time from the tray icon.")
    g.OnEvent("Escape", (*) => g.Destroy())
    g.Show()
    WinWaitClose "ahk_id " g.Hwnd
    return state.choice

    Choose(name, *) {
        state.choice := name
        if remember.Value {
            SetSetting("site", name)
            BuildMenu()
        }
        g.Destroy()
    }
}

; --- Tray menu ---

BuildMenu() {
    tray := A_TrayMenu
    tray.Delete()
    snapLabel := "Snap a question  (Alt+Shift+S)"
    tray.Add(snapLabel, Snap)
    tray.Default := snapLabel
    tray.Add()

    tray.Add("Send screenshots to:", (*) => 0)
    tray.Disable("Send screenshots to:")
    current := GetSetting("site", "")
    for name in SiteNames {
        tray.Add("    " name, PickSite.Bind(name))
        if (name = current)
            tray.Check("    " name)
    }
    tray.Add("    Ask every time", PickSite.Bind(""))
    if (current = "")
        tray.Check("    Ask every time")
    tray.Add()

    tray.Add("Press Enter automatically", ToggleAutoSend)
    if (GetSetting("autoSend", 0) = 1)
        tray.Check("Press Enter automatically")

    delayMenu := Menu()
    for seconds in Delays {
        delayMenu.Add(seconds " seconds", PickDelay.Bind(seconds))
        if (seconds = GetSetting("pasteDelay", 3))
            delayMenu.Check(seconds " seconds")
    }
    tray.Add("Wait before pasting", delayMenu)
    tray.Add()
    tray.Add("Quit StudySnap", (*) => ExitApp())
}

PickSite(site, *) {
    SetSetting("site", site)
    BuildMenu()
}

ToggleAutoSend(*) {
    SetSetting("autoSend", GetSetting("autoSend", 0) = 1 ? 0 : 1)
    BuildMenu()
}

PickDelay(seconds, *) {
    SetSetting("pasteDelay", seconds)
    BuildMenu()
}
