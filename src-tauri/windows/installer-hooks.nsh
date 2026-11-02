; SPDX-License-Identifier: GPL-3.0-or-later
; SPDX-FileCopyrightText: 2026 zahidzta
; During an in-app update Tauri starts the installer as the app exits. Wait
; briefly for Windows to release the executable before Tauri checks it.
!macro NSIS_HOOK_PREINSTALL
  ${If} $UpdateMode = 1
    Push $R8
    Push $R9
    StrCpy $R9 0
    zownload_wait_for_exit:
      IfFileExists "$INSTDIR\${MAINBINARYNAME}.exe" 0 zownload_wait_done
      ClearErrors
      ; Opening in append mode does not write to the executable. Windows will
      ; reject the open while the installed app still has the image in use.
      FileOpen $R8 "$INSTDIR\${MAINBINARYNAME}.exe" a
      IfErrors 0 zownload_exe_released
      IntOp $R9 $R9 + 1
      IntCmp $R9 20 zownload_wait_done
      Sleep 250
      Goto zownload_wait_for_exit
    zownload_exe_released:
      FileClose $R8
    zownload_wait_done:
    Pop $R9
    Pop $R8
  ${EndIf}
!macroend
