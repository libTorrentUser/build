#!/bin/sh

source script.lib.sh


Execute()
{
	Log 'applying patches...';
	
	local package="$1";
	local sourceDir="$2";

	local patchDir="../patch/${package}";
	
	# apply all patches	
	if [ $(CountItems "$patchDir") -gt 0 ]; then
		for p in "$patchDir/"*; do
			p=$(readlink -f "$p");
			printf 'applying patch %s\n' "$p";
			DieIfFails patch -p1 -i "$p" -d "$sourceDir";
		done;
	fi
}


Execute "$@";
