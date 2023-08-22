#!/bin/sh

source script.lib.sh


BuildXOrgProto()
{
	local package="$1";
	local buildDir="$2";
	local prefix="$3";
	local destDir="$4";
	local dirBin="$5";
	local dirRoot="$6";

	local sourceDir=$(./latest.sh \
		-b="$buildDir" \
		--package="$package" \
		--url='https://www.x.org/releases/individual/proto/'
		);

	if [ $? -ne 0  ] || [ -z "$sourceDir" ]; then
		Die "unable to retrieve the latest version tar";
	fi
		
	DieIfFails ./make.sh \
		-b="$buildDir" \
		-s="$sourceDir" \
		--configure-options="\
			--prefix=$prefix \
		" \
		--dest-dir="$destDir" \
		--install-options="install-strip";

	local pkgconfigDir="$dirBin/pkgconfig";
	
	DieIfFails ./adjust-pkgconfig.sh \
		-d="$destDir" \
		--prefix="$prefix" \
		-o="$pkgconfigDir" \
		-r="$dirRoot";
}
