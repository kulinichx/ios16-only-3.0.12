Option Explicit
Dim fso, shell, scriptPath, command, status, smokeTest, launchError
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
scriptPath = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "SupporterBindingTool.ps1")
smokeTest = False
If WScript.Arguments.Count = 1 Then smokeTest = (WScript.Arguments(0) = "--smoke-test")
command = "powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & scriptPath & """"
If smokeTest Then command = command & " -SmokeTest -VerifyVisible"
' Hide the console in PowerShell, not via inherited SW_HIDE on the first form.
On Error Resume Next
status = shell.Run(command, 1, True)
launchError = Err.Number
On Error GoTo 0
If launchError <> 0 Then status = 1
If status <> 0 And Not smokeTest Then
  MsgBox "The binding tool could not start. Check that Node.js is installed, or run SupporterBindingTool.ps1 to see the error.", vbExclamation, "Supporter Binding Tool"
End If
WScript.Quit status
