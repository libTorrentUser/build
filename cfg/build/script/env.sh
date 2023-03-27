#!/bin/sh

# EnvExists "$envVarsFile" "$package"
#
# return success if a section for "$package" is already present in 
# "$envVarsFile"
EnvExists()
{
	local envVarsFile="$1";
	local package="$2";
	
	if grep -q "^# $package" "$envVarsFile"; then
		return 0;
	fi

	return 1;
}

# EnvAddPackage "$envVarsFile" "$package"
#
# Creates a "section" for the "$package" inside "$envVarsFile". That "section"
# can then be checked with EnvExists(), thus allowing the user to avoid having
# duplicated vars in "$envVarsFile"
#
# Return success (0) if the "section" did not exist.
EnvAddPackage()
{
	local envVarsFile="$1";
	local package="$2";

	if ! EnvExists "$envVarsFile" "$package"; then
		DieIfFails printf '# %s\n' "$package" >> "$envVarsFile";
		return 0;
	fi

	return 1;
}


# EnvPathPrepend "$envVarsFile" "$variable" "$value"
#
# Writes "$variable" to "$envVarsFile" as
#
# variable=$( PathPrepend "$variable" 'contentsOfValue' )
#
# PathPrepend is a function from script.lib.sh that assumes the content of 
# $variable is a standard linux path and will pre-prend the provided value to it
# in case it isn't already there.
#
# ex:
# calling
#
# EnvPathPrepend "myVars.sh" "v1" "someValue"
#
# writes the following inside the file "myVars.sh"
#
# v1=$(PathPrepend "$v1" 'someValue');
# export v1;
#
EnvPathPrepend()
{
	local envVarsFile="$1";
	local variable="$2";
	local value="$3";

	DieIfFails printf '%s=$(PathPrepend "$%s" '"'%s'"'); \nexport %s;\n' \
		"$variable" \
		"$variable" \
		"$value" \
		"$variable" >> "$envVarsFile"
}
