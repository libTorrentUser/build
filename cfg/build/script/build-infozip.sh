#!/bin/sh

source script.lib.sh



BuildInfozip()
{
	local package="$1";
	local pageVersion="$2";
	shift 2;
	
	local buildDir="$1";
	local prefix="$2";
	local destDir="$3";
	local npp="$4";		

	Log 'Retrieving the latest version value...';	
	# the way zip source code archies are named makes sorting them a disaster
	# waiting to happen. In order to deal with that we will first try to  
	# retrieve the latest version number from their website and then convert 
	# that value to something that matches the versioning used in the source
	# code archives
	local version=;
	version=$(Download "https://infozip.sourceforge.net/${pageVersion}.html" | \
		grep 'New features' | \
		sed 's;.*Zip \([^<]*\).*;\1;');

	if [ $? -ne 0 ] || [ -z "$version" ]; then
		Die 'unable to retrieve the latest version value';
	fi

	printf 'latest version is %s\n' "$version";

	# now we remove all dots
	local dotlessVersion=;
	dotlessVersion=$(printf '%s' "$version" | sed 's;\.;;');

	if [ $? -ne 0 ] || [ -z "$dotlessVersion" ]; then
		Die 'unable to convert the latest version value';
	fi
	
	
	# and finally we have a value that should correspond to the latest source
	local sourceDir;
	sourceDir=$(./download.sh \
		--url="ftp://ftp.info-zip.org/pub/infozip/src/${package}${dotlessVersion}.tgz" \
		-b="$buildDir"
		);

	if [ $? -ne 0 ] || [ -z "$sourceDir" ]; then
		Die 'unable to download the latest source code';
	fi
	
	DieIfFails ./make.sh \
		-b="$buildDir" \
		-s="$sourceDir" \
		-j="$npp" \
		--in-source \
		--no-configure \
		--build-options="--file=unix/Makefile generic prefix=$prefix" \
		--dest-dir="$destDir" \
		--install-options="--file=unix/Makefile install prefix=${destDir}/${prefix}";
}
