on run argv
	set actionName to item 1 of argv
	tell application "Xcode"
		-- Xcode may still be opening the project: wait for the document, then for it to load.
		repeat 120 times
			if exists workspace document "mood.xcodeproj" then exit repeat
			delay 1
		end repeat
		set ws to workspace document "mood.xcodeproj"
		repeat 120 times
			if loaded of ws then exit repeat
			delay 1
		end repeat
		if actionName is "run" then
			set r to run ws
		else
			set r to build ws
		end if
		repeat 900 times
			if completed of r then exit repeat
			delay 2
		end repeat
		set msg to ""
		try
			set msg to error message of r
		end try
		return (status of r as text) & " | " & msg
	end tell
end run
