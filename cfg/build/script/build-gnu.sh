#!/bin/sh

. ./lib.sh



BuildGNU()
{
	local package="$1";
	local buildDir="$2";
	local prefix="$3";
	local destDir="$4";
	local installOptions="${5:-install-strip}";

	local sourceDir=$(./latest.sh --host='gnu' --package="$package" -b="$buildDir");

	if [ $? -ne 0  ] || [ -z "$sourceDir" ]; then
		Die "unable to retrieve the latest version tar";
	fi
	
	DieIfFails ./make.sh \
		-b="$buildDir" \
		-s="$sourceDir" \
		--configure-options="\
			--prefix=$prefix \
			--disable-nls \
			--disable-rpath" \
		--dest-dir="$destDir" \
		--install-options="$installOptions";
}
