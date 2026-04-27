#Requires AutoHotkey v2.0
#SingleInstance Force
SetTitleMatchMode 2
CoordMode "Pixel", "Screen"
CoordMode "ToolTip", "Screen"  ; ToolTip dùng tọa độ màn hình thật

; ===== AUTO BOSS HUNTER - DÒ KHU + DETECT BOSS =====
; F1 = Bắt đầu auto hunt
; F2 = Tạm dừng / Tiếp tục
; F3 = Dừng hoàn toàn
; F5 = Quét boss thử 1 lần
; F6 = Test gửi lệnh đổi khu
; F7 = Test toggle TS
; ESC = Thoát

GAME_CLASS := "ahk_class UnityWndClass"
BOSS_FOLDER := "C:\Users\dotri\NRO_Tools\boss"

; ===== CẤU HÌNH =====
KHU_MIN := 0
KHU_MAX := 29
THOI_GIAN_DOI_KHU := 8000
THOI_GIAN_QUET_BOSS := 1000
THOI_GIAN_XAC_NHAN_CHET := 5000
TOLERANCE := 50

SCAN_X1 := 0
SCAN_Y1 := 0
SCAN_X2 := A_ScreenWidth
SCAN_Y2 := A_ScreenHeight

; ===== VỊ TRÍ HIỂN THỊ TOOLTIP =====
; Mặc định ở giữa màn hình theo chiều ngang, gần đáy
; Tránh xa vùng banner boss (thường ở đỉnh giữa)
TOOLTIP_X := A_ScreenWidth // 2 - 200
TOOLTIP_Y := A_ScreenHeight - 120

; ===== TIMING GỬI PHÍM =====
KEY_HOLD_TIME := 50
DELAY_BETWEEN_KEYS := 100
DELAY_AFTER_R := 150

; Delay sau khi tắt TS, trước khi bấm skill 1
DELAY_BEFORE_SKILL1 := 300

; ===== WINDOWS MESSAGE =====
WM_KEYDOWN := 0x0100
WM_KEYUP := 0x0101

; ===== BẢNG VK + SCAN CODE =====
global keyMap := Map(
    "0", { vk: 0x30, sc: 0x0B },
    "1", { vk: 0x31, sc: 0x02 },
    "2", { vk: 0x32, sc: 0x03 },
    "3", { vk: 0x33, sc: 0x04 },
    "4", { vk: 0x34, sc: 0x05 },
    "5", { vk: 0x35, sc: 0x06 },
    "6", { vk: 0x36, sc: 0x07 },
    "7", { vk: 0x37, sc: 0x08 },
    "8", { vk: 0x38, sc: 0x09 },
    "9", { vk: 0x39, sc: 0x0A },
    "R",     { vk: 0x52, sc: 0x13 },
    "T",     { vk: 0x54, sc: 0x14 },
    "S",     { vk: 0x53, sc: 0x1F },
    "K",     { vk: 0x4B, sc: 0x25 },
    "Space", { vk: 0x20, sc: 0x39 },
    "Enter", { vk: 0x0D, sc: 0x1C },
    "Slash", { vk: 0xBF, sc: 0x35 }
)

; ===== TRẠNG THÁI =====
global hunting := false
global paused := false
global tsActive := false
global currentKhu := KHU_MIN
global bossList := []
global bossFoundName := ""
global lastChangeKhuTime := 0
global state := "idle"
global deathConfirmStartTime := 0

F1:: StartHunt()
F2:: TogglePause()
F3:: StopHunt()
F5:: TestScan()
F6:: TestChangeKhu()
F7:: TestToggleTS()
Esc:: ExitApp()

LoadBossList()

LoadBossList() {
    global BOSS_FOLDER, bossList
    bossList := []

    if (!DirExist(BOSS_FOLDER)) {
        MsgBox("❌ Không tìm thấy folder:`n" . BOSS_FOLDER, "Lỗi")
        ExitApp()
    }

    Loop Files, BOSS_FOLDER . "\*.png" {
        bossName := SubStr(A_LoopFileName, 1, StrLen(A_LoopFileName) - 4)
        bossList.Push({ name: bossName, path: A_LoopFileFullPath })
    }
    Loop Files, BOSS_FOLDER . "\*.jpg" {
        bossName := SubStr(A_LoopFileName, 1, StrLen(A_LoopFileName) - 4)
        bossList.Push({ name: bossName, path: A_LoopFileFullPath })
    }

    if (bossList.Length = 0) {
        MsgBox("❌ Không có ảnh boss nào trong folder.", "Lỗi")
        ExitApp()
    }
}

; ===== HÀM TIỆN ÍCH: HIỆN TOOLTIP Ở VỊ TRÍ TÙY CHỈNH =====
ShowStatus(text) {
    global TOOLTIP_X, TOOLTIP_Y
    ToolTip(text, TOOLTIP_X, TOOLTIP_Y)
}

ShowTip(text, duration := 1500) {
    global TOOLTIP_X, TOOLTIP_Y
    ToolTip(text, TOOLTIP_X, TOOLTIP_Y)
    SetTimer(() => ToolTip(), -duration)
}

StartHunt(*) {
    global hunting, paused, tsActive, currentKhu, KHU_MIN, GAME_CLASS, state, lastChangeKhuTime

    if (!WinExist(GAME_CLASS)) {
        ShowTip("❌ Không tìm thấy cửa sổ CBNR", 3000)
        return
    }

    hunting := true
    paused := false
    tsActive := false
    currentKhu := KHU_MIN
    state := "scanning"
    lastChangeKhuTime := 0

    ShowTip("🚀 START - Bật TS rồi bắt đầu dò khu", 2000)
    Sleep(500)
    SendChatCommand("ts")
    tsActive := true
    Sleep(1000)

    SetTimer(MainLoop, 200)
}

TogglePause(*) {
    global paused, hunting
    if (!hunting) {
        ShowTip("⚠ Chưa start. Bấm F1.", 1500)
        return
    }
    paused := !paused
    ShowTip(paused ? "⏸ TẠM DỪNG" : "▶ TIẾP TỤC", 1500)
}

StopHunt(*) {
    global hunting, paused, state
    hunting := false
    paused := false
    state := "idle"
    SetTimer(MainLoop, 0)
    ToolTip()
    ShowTip("🛑 ĐÃ DỪNG", 2000)
}

; ===== VÒNG LẶP CHÍNH =====
MainLoop() {
    global hunting, paused, state, tsActive, bossFoundName
    global lastChangeKhuTime, THOI_GIAN_DOI_KHU, currentKhu
    global KHU_MIN, KHU_MAX, GAME_CLASS
    global deathConfirmStartTime, THOI_GIAN_XAC_NHAN_CHET
    global DELAY_BEFORE_SKILL1

    if (!hunting || paused)
        return

    if (!WinExist(GAME_CLASS)) {
        StopHunt()
        ShowTip("⚠ Cửa sổ CBNR đã đóng", 3000)
        return
    }

    ; ===== STATE: SCANNING =====
    if (state = "scanning") {
        found := ScanBoss()
        if (found != "") {
            bossFoundName := found
            ShowStatus("🎯 PHÁT HIỆN BOSS: " . found . "`n→ Tắt TS, về skill 1, treo afk")

            Sleep(300)
            SendChatCommand("ts")  ; tắt TS
            tsActive := false

            ; Đợi 1 chút rồi bấm phím 1 để chuyển về skill 1
            Sleep(DELAY_BEFORE_SKILL1)
            PressKey("1")

            state := "fighting"
            return
        }

        if (A_TickCount - lastChangeKhuTime >= THOI_GIAN_DOI_KHU) {
            ChangeKhu()
            lastChangeKhuTime := A_TickCount
        } else {
            timeLeft := Round((THOI_GIAN_DOI_KHU - (A_TickCount - lastChangeKhuTime)) / 1000, 1)
            ShowStatus("🔍 Quét khu " . currentKhu . " | Đổi khu sau " . timeLeft . "s")
        }
        return
    }

    ; ===== STATE: FIGHTING =====
    if (state = "fighting") {
        found := ScanBoss()
        if (found != "") {
            ShowStatus("⚔ Đang đánh: " . found . " (treo afk)")
        } else {
            state := "confirming_death"
            deathConfirmStartTime := A_TickCount
            ShowStatus("❓ Không thấy boss... đang xác nhận trong " . (THOI_GIAN_XAC_NHAN_CHET / 1000) . "s")
        }
        return
    }

    ; ===== STATE: CONFIRMING_DEATH =====
    if (state = "confirming_death") {
        found := ScanBoss()

        if (found != "") {
            bossFoundName := found
            state := "fighting"
            ShowStatus("✅ Boss xuất hiện lại: " . found . " (false alarm)")
            return
        }

        elapsed := A_TickCount - deathConfirmStartTime

        if (elapsed >= THOI_GIAN_XAC_NHAN_CHET) {
            ShowStatus("💀 Boss đã chết → Bật TS, dò khu tiếp")
            Sleep(500)
            SendChatCommand("ts")
            tsActive := true
            Sleep(800)

            bossFoundName := ""
            state := "scanning"
            lastChangeKhuTime := 0
        } else {
            timeLeft := Round((THOI_GIAN_XAC_NHAN_CHET - elapsed) / 1000, 1)
            ShowStatus("❓ Đang xác nhận boss chết... còn " . timeLeft . "s")
        }
        return
    }
}

ScanBoss() {
    global bossList, TOLERANCE, SCAN_X1, SCAN_Y1, SCAN_X2, SCAN_Y2

    for boss in bossList {
        try {
            if (ImageSearch(&fx, &fy, SCAN_X1, SCAN_Y1, SCAN_X2, SCAN_Y2, "*" . TOLERANCE . " " . boss.path)) {
                return boss.name
            }
        } catch {
        }
    }
    return ""
}

ChangeKhu() {
    global currentKhu, KHU_MIN, KHU_MAX

    currentKhu++
    if (currentKhu > KHU_MAX)
        currentKhu := KHU_MIN

    SendKhuCommand(currentKhu)
    ShowStatus("🚪 Đổi sang khu " . currentKhu)
}

SendKhuCommand(khuNumber) {
    global DELAY_BETWEEN_KEYS, DELAY_AFTER_R

    PressKey("R")
    Sleep(DELAY_AFTER_R)
    PressKey("K")
    Sleep(DELAY_BETWEEN_KEYS)
    PressKey("Space")
    Sleep(DELAY_BETWEEN_KEYS)

    numStr := String(khuNumber)
    Loop Parse, numStr {
        PressKey(A_LoopField)
        Sleep(DELAY_BETWEEN_KEYS)
    }

    PressKey("Enter")
}

SendChatCommand(text) {
    global DELAY_BETWEEN_KEYS, DELAY_AFTER_R

    PressKey("R")
    Sleep(DELAY_AFTER_R)

    Loop Parse, text {
        ch := StrUpper(A_LoopField)
        PressKey(ch)
        Sleep(DELAY_BETWEEN_KEYS)
    }

    PressKey("Enter")
}

PressKey(key) {
    global GAME_CLASS, keyMap, WM_KEYDOWN, WM_KEYUP, KEY_HOLD_TIME

    if (!keyMap.Has(key))
        return

    if (!WinExist(GAME_CLASS))
        return

    hwnd := WinGetID(GAME_CLASS)
    info := keyMap[key]
    vk := info.vk
    sc := info.sc

    lParamDown := (sc << 16) | 1
    lParamUp := (sc << 16) | 1 | (1 << 30) | (1 << 31)

    PostMessage(WM_KEYDOWN, vk, lParamDown, , "ahk_id " . hwnd)
    Sleep(KEY_HOLD_TIME)
    PostMessage(WM_KEYUP, vk, lParamUp, , "ahk_id " . hwnd)
}

TestScan(*) {
    found := ScanBoss()
    if (found != "")
        MsgBox("✅ Tìm thấy: " . found, "Test scan")
    else
        MsgBox("❌ Không thấy boss nào", "Test scan")
}

TestChangeKhu(*) {
    input := InputBox("Nhập số khu để test (0-29):", "Test đổi khu", "w300", "0")
    if (input.Result != "OK")
        return
    khu := Integer(input.Value)
    ShowTip("Gửi lệnh đổi sang khu " . khu, 1500)
    Sleep(1000)
    SendKhuCommand(khu)
    ShowTip("Done", 1500)
}

TestToggleTS(*) {
    ShowTip("Gửi lệnh ts (R+T+S+Enter)...", 1500)
    Sleep(1000)
    SendChatCommand("ts")
    ShowTip("Done", 1500)
}