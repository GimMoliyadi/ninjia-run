Set shell = CreateObject("WScript.Shell")
shell.Run "cmd.exe /c npm.cmd run preview -- --host 127.0.0.1 --open", 0, False
