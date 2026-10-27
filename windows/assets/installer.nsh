!macro customInit
  SetRegView 64
  ReadRegStr $R0 HKLM "SOFTWARE\Microsoft\Windows NT\CurrentVersion" "CurrentBuildNumber"
  ${If} $R0 < 19045
    MessageBox MB_ICONSTOP "T-Cube requires Windows 10 22H2 (19045) or Windows 11."
    Abort
  ${EndIf}
!macroend
