#!/bin/sh

. ./lib.sh


BuildXOrgLib()
{
	local package="$1";
	local buildDir="$2";
	local prefix="$3";
	local destDir="$4";
	#local npp="$5";
	local dirBin="$6";
	local dirRoot="$7";

	local sourceDir=$(./latest.sh \
		-b="$buildDir" \
		--package="$package" \
		--url='https://www.x.org/releases/individual/lib/'
		);

	if [ $? -ne 0  ] || [ -z "$sourceDir" ]; then
		Die "unable to retrieve the latest version tar";
	fi

	 #apply all patches
	 DieIfFails ./patch.sh "$package" "$sourceDir";
		
	DieIfFails ./make.sh \
		-b="$buildDir" \
		-s="$sourceDir" \
		--configure-options="\
			--prefix=$prefix \
			--disable-devel-docs
		" \
		--dest-dir="$destDir" \
		--install-options="install-strip";

	local pkgconfigDir="$dirBin/pkgconfig";

	# some xorg packages are somewhat sane and generate a pkc-config file with
	# the same name as the package. But some do not like the fact they are named
	# libxxx and remove the "lib" part. Some use an upper-case 'X', some don't.
	# Some use it, but the use a lower-case 'x' in the pkg-config file. Some
	# produces 300 different .pc files. Because of that, we simply tell the 
	# script to search and adjust any "*/pkgconfig/*.pc" file it finds. xorg is
	# a mess...
	DieIfFails ./adjust-pkgconfig.sh \
		-d="$destDir" \
		--prefix="$prefix" \
		-o="${dirBin}/pkgconfig" \
		-r="$dirRoot";

	# although I painfuly made things work with this awesome script, nothing
	# in xorg should need libtool .la files. So we can simply delete them. 
	# Anything an user could do with them he can be done (better) with 
	# pkg-config
	#
	# DieIfFails ./adjust-libtool.sh \
	#	-d="$destDir" \
	#	--prefix="$prefix" \
	#	-o="${dirBin}/lib";
	DieIfFails ./adjust-libtool.sh \
		-d="$destDir" \
		--delete;
}
