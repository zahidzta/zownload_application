; SPDX-License-Identifier: GPL-3.0-or-later
; SPDX-FileCopyrightText: 2026 zahidzta
; The updater starts the NSIS installer as the app is exiting. Give Windows a
; short bounded period to release the executable before Tauri checks it
; (tauri-apps/tauri#16277).
!define /ifndef ERROR_MORE_DATA 234

!macro NSIS_HOOK_PREINSTALL
  ${If} $UpdateMode = 1
    Push $0
    Push $1
    Push $2
    Push $3
    Push $R4
    Push $R5
    StrCpy $R5 0
    ${Do}
      !insertmacro RestartManager_StartSession $R4
      ${If} $R4 == ""
        ${Break}
      ${EndIf}
      !insertmacro RestartManager_RegisterFile $R4 "$INSTDIR\${MAINBINARYNAME}.exe"
      ${If} $0 = 0
        System::Call 'RSTRTMGR::RmGetList(i R4, *i .r1, *i .r2, p 0, *i .r3) i .r0'
      ${EndIf}
      !insertmacro RestartManager_EndSession $R4
      ${If} $0 <> ${ERROR_MORE_DATA}
      ${OrIf} $R5 >= 120
        ${Break}
      ${EndIf}
      ${If} $R5 = 0
        DetailPrint "Waiting for Zownload to close before updating..."
      ${EndIf}
      IntOp $R5 $R5 + 1
      Sleep 250
    ${Loop}
    Pop $R5
    Pop $R4
    Pop $3
    Pop $2
    Pop $1
    Pop $0
  ${EndIf}
!macroend
