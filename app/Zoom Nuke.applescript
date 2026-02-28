on run
  set cleanMode to choose_clean_mode()
  if cleanMode is false then return

  set shouldStart to confirm_start(cleanMode)
  if shouldStart is false then return

  launch_in_terminal(cleanMode)
end run

on choose_clean_mode()
  try
    display dialog "Choose cleanup mode:" buttons {"Cancel", "Deep Clean", "Standard Clean"} default button "Standard Clean" cancel button "Cancel" with title "Zoom Nuke"
    set selectedButton to button returned of result
    if selectedButton is "Deep Clean" then
      return "deep"
    end if
    return "standard"
  on error number -128
    return false
  end try
end choose_clean_mode

on confirm_start(cleanMode)
  if cleanMode is "deep" then
    set modeLabel to "Deep Clean"
  else
    set modeLabel to "Standard Clean"
  end if

  try
    display dialog "Mode: " & modeLabel & return & return & "Press Start to open Terminal and run Zoom Nuke." buttons {"Cancel", "Start"} default button "Start" cancel button "Cancel" with title "Zoom Nuke"
    return true
  on error number -128
    return false
  end try
end confirm_start

on launch_in_terminal(cleanMode)
  set appPath to POSIX path of (path to me)
  set scriptPath to appPath & "/Contents/Resources/Screw1132_Overkill.sh"
  set quotedScriptPath to quoted form of scriptPath

  do shell script "if [ ! -f " & quotedScriptPath & " ]; then exit 22; fi"

  set modeLabel to "Standard Clean"
  set runArgs to ""
  if cleanMode is "deep" then
    set modeLabel to "Deep Clean"
    set runArgs to " --deep-clean"
  end if

  set shellCommand to "clear; echo 'Zoom Nuke.app'; echo 'Mode: " & modeLabel & "'; echo; chmod +x " & quotedScriptPath & "; /usr/bin/env bash " & quotedScriptPath & runArgs & "; EXIT_CODE=$?; echo; echo \"Log file: $HOME/zoom_fix.log\"; echo \"Exit code: $EXIT_CODE\";"

  tell application "Terminal"
    activate
    do script shellCommand
  end tell
end launch_in_terminal
