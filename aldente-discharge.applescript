-- Presses AlDente's Discharge button. Built as its own applet so the
-- Accessibility grant goes to this app, not to zsh or osascript.
-- Errors must not raise a modal dialog: under launchd that would hang every later tick.
try
	tell application "System Events"
		tell process "AlDente"
			if (count of windows) = 0 then
				perform action "AXPress" of menu bar item 1 of menu bar 2
				delay 2
			end if
			repeat with b in (buttons of UI element 1 of window 1)
				try
					if (value of attribute "AXHelp" of b) starts with "Discharges" then
						perform action "AXPress" of b
						exit repeat
					end if
				end try
			end repeat
			key code 53
		end tell
	end tell
on error errText
	do shell script "logger -t battery-home " & quoted form of errText
end try
