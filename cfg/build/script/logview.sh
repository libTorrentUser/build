#!/bin/sh



# LogView \
#     "$style" \
#     "$logFile" \
#     "$lineCount" \
#     "$keepGoingCallback" \
#     "$keepGoingCallbackInterval"
#
# $style:
#     'clip' long lines are clippedso they do not go beyond the TTY window.
#	  'wrap' long lines wrap to the next line
#
# $logFile:
#     file from where the data will be read.
#
# $lineCount:
#     we will show the last $lineCount lines of $logFile
#
# $updateInterval:
#     how many seconds between each log update. Check $keepGoingCallbackInterval
#     for more info.
#
# $keepGoingCallback:
#     function that should return 0 to keep the log view running, any other 
#     value to stop it. This function will be called once every 
#     $keepGoingCallbackInterval seconds
#
# $keepGoingCallbackInterval:
#     how many seconds between each call to $keepGoingCallback. Should be less
#     thank because this value effectively controls how much time we sleep 
#     between updates.
LogView()
{
	local style="$1";
	shift;
	
	#local logFile="$1"
	#local lineCount="$2"
	#local updateInterval="$3"
	#local keepGoingCallback="$4"
	#local keepGoingCallbackInterval="$5"
	if [ "$#" -ne 5 ]; then
		printf 'Invalid LogView() call. Check the docs!\n' 1>&2;
		exit 1;
	fi;
	

	TTYClearLastLines()
	{
		local count="$1";
	
		# \r 
		# go to first column
		#
		# \033[xxxA
		# move up xxx lines
		#
		# \033[J 
		# clear everything starting from the current cursor position
		printf '\r\033[%iA\033[J' "$count";
	}
	
	
	TTYClearFromCursor()
	{
		printf '\033[J' 1>&2;
	}
	
	
	TTYSize()
	{
		local settings="$(stty -a)";
	
		TTYSize_Result_Rows=$(
			printf '%s' "$settings" | sed -n 's;.*rows \([0-9]\+\).*;\1;p');
			
		TTYSize_Result_Columns=$(
			printf '%s' "$settings" | sed -n 's;.*columns \([0-9]\+\).*;\1;p');
	}
	
	
	# TTYSetCursorPosition $x $y
	#
	# put the cursor in the specified position. The positions are 1-based
	TTYSetCursorPosition()
	{
		local x="$1";
		local y="$2";
	
		printf '\033[%i;%iH' "$y" "$x";
	}
	
		
	TTYScrollUp()
	{
		local count="$1";
		printf '\033[%iS' "$count";
	}
	
	
	# CursorPos
	#
	# return the current cursor position in the variables
	# CursorPos_Result_x
	# CursorPos_Result_y
	TTYCursorPos()
	{
		TTYCursorPos_Result_x=-1;		
		TTYCursorPos_Result_y=-1;
		
		# execute in a subshell in order to not mess with any existing "trap"s. 
		# POSIX specific says that Traps are not inherited in subshells. Unless 
		# it is being ignored
		local pos=;
		pos=$(		
			local oldSettings="$(stty -g)" || exit 1
			trap 'stty "$(oldSettings)"' INT TERM QUIT ALRM
	
			stty -icanon -echo min 0 time 1 || exit	1;
			printf '\033[6n' 1>&2		
			
			local pos=$(dd count=1 2> /dev/null)
			stty "$oldSettings"
			
			pos=${pos%R*}
			pos=${pos##*\[}
			
			printf '%s' "$pos";
		)

		if [ $? -eq 0 ] && [ -n "$pos" ]; then	
			TTYCursorPos_Result_x=${pos##*;}
			TTYCursorPos_Result_y=${pos%%;*}
			return 0;
		fi

		return 1;
	}
	
	
	# WrappedLineCount "$text" "$maxLength" 
	#
	# returns how many lines would take to print "$text" if lines that are 
	# longer than "$maxLength" get wrapped (i.e., printed on the next line
	WrappedLineCount()
	{
		local text="$1";
		local maxLen="$2";
	
		# first count the number of lines. The \n in the printf command is
		# extremely important because the POSIX definition of a line 
		# https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap03.html#tag_03_206
		# states that an empty last line is not a line. But we want it to be
		local count=$(printf '%s\n' "$text" | wc -l);
		
		# now iterate over every non-empty line and increment the count every 
		# time a line is too big (do it in a subshell to avoid having to reset 
		# IFS
		 count=$(
			# set the separator to \n
IFS='
'
			# disable pathname expansion
			set -f
			for line in $text
			do
				local len="${#line}";
				if [ $len -gt $maxLen ]; then
					local q=$((len / maxLen));
					local r=$((len % maxLen));			
				    count=$((count + q - 1));
				    
				    if [ $r -gt 0 ]; then
				    	count=$((count + 1));
				    fi
				fi
			done
	
			printf '%s' "$count";
		)
	
		printf '%s' "$count";
	}
	
	
	# Sleep $interval $callbackInterval $callback
	#
	# Sleeps (at least) $interval seconds. "At least" because the function 
	# actualy sleeps $callbackInterval seconds, calls $callback to see if we are
	# supposed to return and only then checks if $interval seconds has already 
	# elapsed
	Sleep()
	{
		local interval="$1";
		local keepGoingCallbackInterval="$2";	
		local keepGoingCallback="$3";
	
		while [ "$interval" -gt 0 ]; do
			sleep "$keepGoingCallbackInterval";
	
			if ! $keepGoingCallback; then
				return 1;
			fi
	
			interval=$((interval - keepGoingCallbackInterval));
		done;
	
		return 0;
	}
	
		
	ShowLog()
	{
		local logFile="$1"
		local lineCount="$2";
		local logUpdateInterval="$3";
		local keepGoingCallback="$4";
		local keepGoingCallbackInterval="$5";
		local expandedTextCallback="$6"
		local neededLinesCallback="$7";
	
		
		while true; do
			# we need to get the TTY size and cursor position on every 
			# because the TTY size might change at any moment. This call is
			# very filmy though, depending on the terminal we are running, and
			# sometimes it simply fails. We handle that by pretending we are at
			# the bottom of the screen.
			TTYSize;	
			local rows="$TTYSize_Result_Rows";
			local cols="$TTYSize_Result_Columns";		
			local colsMinus1=$((cols - 1))				
			
			local posY=-1;
			if TTYCursorPos; then
				posY="$TTYCursorPos_Result_y";
			else
				posY=rows;
			fi
	
			# the text that will be printed on the screen, exactly how it would 
			# be printed on the screen (i.e., tabs expanded)
			local text=;			
			text="$($expandedTextCallback "$logFile" "$lineCount" "$cols")";
	
			# count how many lines we would need to print all that
			local neededLines=$($neededLinesCallback "$text" "$cols");
			neededLines=$((neededLines+2))
			#printf 'neededLines: "%i"\n' "$neededLines";
	
			# if we are too close to the bottom of the TTY, calculate how many
			# lines we will need to scroll up so everything fits
			local endPosY=$((posY + neededLines));
			local scrollBy=$((endPosY - rows))
			#printf 'scrollBy: "%i" (rows: %i; posY: %i)\n' "$scrollBy" "$rows" "$posY";
							
			if [ "$scrollBy" -gt '0' ]; then
				# we had to scroll up. Update our Y position
				TTYScrollUp "$scrollBy";
				posY=$((posY - scrollBy))
				TTYSetCursorPosition 1 "$posY";
			fi
	
			# print the last few lines of the log
			# \e[1m:    bold
			# c\e[ndb:  repeat char 'c' 'n' times
			# \e0m:     reset
			TTYClearFromCursor;			
			printf '\e[1mv\e[%db\n\e[0m' "$colsMinus1";
			printf '%s' "$text";			
			printf '\n\e[1m^\e[%db\n\e[0m' "$colsMinus1";
	
			# wait a little bit until the next update. If this function fails
			# it means $keepGoingCallback told us the user wants to stop seeing
			# the log
			if ! Sleep \
				"$logUpdateInterval" \
				"$keepGoingCallbackInterval" \
				$keepGoingCallback; then
				
				break;
			fi
	
			# move back to the first line of the log and start over
			TTYSetCursorPosition 1 "$posY";
		done;

		# move back to the first line of the log and clear it before exiting
		TTYSetCursorPosition 1 "$posY";
		TTYClearFromCursor
	}
		

	ExpandedLogLines()
	{
		local logFile="$1"
		local lineCount="$2";
		tail -n "$lineCount" "$logFile" | tr -cd "\t\n -~" | expand;
	}


	ExpandedLogLinesClipped()
	{
		local logFile="$1"
		local lineCount="$2";
		local maxLength="$3";
		ExpandedLogLines "$logFile" "$lineCount" | cut -b -"$maxLength";		
	}


	LineCount()
	{
		local text="$1";
		#local maxLength="$2";
		printf '%s\n' "$text" | wc -l;
	}

	case "$style" in
		'clip')
			ShowLog \
				"$@" \
				ExpandedLogLinesClipped \
				LineCount;
		;;
		*)
			ShowLog \
				"$@" \
				ExpandedLogLines \
				WrappedLineCount;
		;;
	esac
}



