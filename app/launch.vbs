' Starts the Daily Board (hidden) with its bundled Node.js engine and opens it in the default browser.
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
node = fso.BuildPath(fso.GetParentFolderName(dir), "runtime\node.exe")
If Not fso.FileExists(node) Then
  MsgBox "The Daily Board engine is missing. Please run the Daily Board setup again.", vbExclamation, "Daily Board"
  WScript.Quit 1
End If
' Run the engine from the board's own folder, so it never locks the folder it was started from (for example the setup's temp folder).
sh.CurrentDirectory = dir
' "/quiet" (used by the "Start the board" button through the dailyboard:// link) starts the engine without opening a new tab,
' because the board page that asked for it is already open.
extra = ""
If WScript.Arguments.Count > 0 Then
  If LCase(WScript.Arguments(0)) = "/quiet" Then extra = " --no-open"
End If
sh.Run """" & node & """ """ & dir & "\server.js""" & extra, 0, False
