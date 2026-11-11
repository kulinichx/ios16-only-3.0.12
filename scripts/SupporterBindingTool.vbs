Option Explicit
Dim fso, shell, scriptPath, command, status
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
scriptPath = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "SupporterBindingTool.ps1")
command = "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File """ & scriptPath & """"
status = shell.Run(command, 0, True)
If status <> 0 Then
  MsgBox "The binding tool could not start. Check that Node.js is installed, or run SupporterBindingTool.ps1 to see the error.", vbExclamation, "Supporter Binding Tool"
End If
