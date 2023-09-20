# get the directory where this script is
#_scriptPath=$(readlink -f "$0")

#_scriptDir=$(dirname "$_scriptPath")


# print something and exit the script
Die()
{
	printf >&2 -- '%s\n' "$*";
	exit 1;
}


# check the result of a command and exit the script if it failed
DieIfFails()
{
	"$@" || Die "cannot $*"; 
}


# print what we are doing
Log()
{
	local NORMAL=;
	local GREEN=;

	if [ -t 1 ]; then
		# only enable color codes if stdout is connected to a terminal
		NORMAL="\e[0m"
		GREEN="\e[0;32m";
	fi
	
	printf "\n$GREEN--------------------------------------------------------------------------------\n%s\n--------------------------------------------------------------------------------\n$NORMAL" "$*";
}


# print what we are doing to stderr
LogErr()
{
	Log "$@" 1>&2;
}



# CommandIsAvailable command
#
# return 0 (success) if the command is available on the system
CommandIsAvailable()
{
	if command -v "$1" > /dev/null; then
		return 0;
	fi;

	return 1;
}


# DistroName
#
# return the name of the distro
DistroName()
{
	local name=;
	if [ -e '/etc/alpine-release' ]; then
		name='alpine';
	elif [ -e '/etc/arch-release' ]; then
		name='arch';
	fi

	printf '%s' "$name";
	
	if [ -z "$name" ]; then
		return 1;
	fi

	return 0;	
}

# DistroIsAlpine
#
# success if distro is alpine linux
DistroIsAlpine()
{
	if [ $(DistroName) = 'alpine' ]; then
		return 0;
	fi

	return 1;
}


# DistroIsArch
#
# success if distro is arch linux
DistroIsArch()
{
	if [ $(DistroName) = 'arch' ]; then
		return 0;
	fi

	return 1;
}



# see the comments of Download()
Download_curl()
{
	local url="$1";
	local dir="$2";
	local destFile="$3";
	
	if [ $# -eq 2 ]; then	
		curl -L --output-dir "$dir" --create-dirs -O -J "$url";
	elif [ $# -eq 3 ]; then
		curl -L --output "${dir}/${destFile}" --create-dirs "$url" ;
	else
		curl "$url" -L;
	fi
}


# see the comments of Download()
Download_wget()
{
	local url="$1";
	local dir="$2";
	local destFile="$3";

	if [ ! -z "$dir" ]; then
		mkdir -p "$dir" || exit 1;
	fi
	
	if [ $# -eq 2 ]; then		
		wget $flags  --directory-prefix "$dir" "$url";
	elif [ $# -eq 3 ]; then
		wget $flags --output-document "${dir}/${destFile}" "$url";
	else
		# if you do not redirect stderr to /dev/null you may see some unwanted
		# stuff being printed like "SSL_INIT"
		wget -qO - "$url" 2> /dev/null
	fi
}


# download a file to dir or to stdout, if the "dir" argument is empty. If 
# "destFile" is provided, the data is written to "dir/destFile", otherwise the
# remote file name is used.
#
# usage:
# Download url dir destFile;
# Download url dir;
# Download url;
Download()
{	
	if CommandIsAvailable wget; then
		Download_wget "$@";
	else
		Download_curl "$@";
	fi
}


# ask a yes/no question, return 0 if the user answered "yes"
#
# usage:
# if Confirm "wanna be my friend?"; then
#     printf 'he said yes!\n";
# fi
#
# https://stackoverflow.com/questions/226703/how-do-i-prompt-for-yes-no-cancel-input-in-a-linux-shell-script/27875395#27875395
Confirm()
{
	printf '%s (y/N) ' "$1"
	read _answer;
	if [ "$_answer" != "${_answer#[Yy]}" ] ; then
		return 0;
	else
		return 1;
	fi
}


# same as $(readlink -f $1)" but ensure the directory exists by creating it. 
# This is done in order to avoid readlink returning an empty string, which it
# might do in case some component of the specified path does not exist.
MkDirReadLinkF()
{
	local path="$1";

	DieIfFails mkdir -p "$path";

	DieIfFails readlink -f "$path";
}


#DeleteAllFiles "directory"
#
# delete all files inside the directory, including hidden files. And if you 
# think 'rm -rf dir/*' should have been enough, that means you are normal.
#
# https://unix.stackexchange.com/questions/77127/rm-rf-all-files-and-all-hidden-files-without-error
# https://unix.stackexchange.com/a/77313
DeleteAllFiles()
{	
	if [ -z "$1" ]; then
		Die 'DeleteAllFiles expects a valid directory';
	fi
	
	DieIfFails rm -rf "$1/"..?* "$1/".[!.]* "$1/"*
}


# PathContains allPaths somePath
#
# return 0 if {allPaths} contains {somePath}.
#
# Expects that paths are separated by a ':' char
#
# The ':' chars are appended in order to ensure a match no matter the position
# inside the path. 
PathContains()
{
	case :$1: in
		*:$2:*)
			return 0;
		;;
	esac

	return 1;
}


# PathAppend allPaths newPath
#
# Append "$newPath" to "$allPaths" when not already in. Special care is taken
# to leave no empty ':' char at the end, in case $allPAths" is empty. That can
# break stuff (like making it impossible to build perl)
#
# Copied from Arch Linux
PathAppend()
{
	local allPaths="$1";
	local newPath="$2";
	
	case ":$allPaths:" in
		*:"$newPath":*)
			;;
		*)
			allPaths="${allPaths:+$allPaths:}$newPath"
			;;		
	esac

	printf '%s' "$allPaths";
}


# PathPreprend allPaths newPath
#
# Preprends "$newPath" to "$allPaths" when not already in. Special care is taken
# to leave no empty ':' char at the end, in case $allPAths" is empty. That can
# break stuff (like making it impossible to build perl)
PathPrepend()
{
	local allPaths="$1";
	local newPath="$2";
	
	case ":$allPaths:" in
		*:"$newPath":*)
			;;
		*)
			allPaths="$newPath${allPaths:+:$allPaths}"
			;;		
	esac

	printf '%s' "$allPaths";
}


# CountItems dir
#
# return how many files and directories are inside {dir}. Includes hidden files.
CountItems()
{
	local dir="$1";
	
	set -- "$dir"/*

	local n=$#;

	set -- "$dir"/.*

	# -2 because of . and ..
	n=$((n + $# -2));

	printf '%i' $n;
}


