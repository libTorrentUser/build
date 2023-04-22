#!/bin/sh


_buildDir=;
_tarName=;
_tmpDir=;
_urlTar=;


source /usr/local/bin/script.lib.sh


PrintUsage()
{
	local usage='download.sh -b=buildDir -u=url

downloads a tar from {url}, extracts it and return the path to the directory
where the files were extracted.

-b
--build-dir
	directory where the archive with the source code will be downloaded and 
	extracted.

-u
--url
	url to a web page containing links to one or more releases of --package
';

	printf '%s\n' "$usage" 1>&2;
}



ParseCommandLine()
{
	for i in "$@"; do
		case $i in
			-b=*|--build-dir=*)
				_buildDir="$(MkDirReadLinkF ""${i#*=}"")";
				shift;
			;;
	      	-h|--help)
	      		PrintUsage;
	      	;;
			-u=*|--url=*)
				_urlTar="${i#*=}";
				shift;
			;;
			--)
	      		# nothing else to parse
	      		shift;
	      		break;  
	      	;;    
	    	*)
	      		Die "Unknown option \"$i\""
				exit 1;
	      	;;
		esac
	done
}


ValidateCommandLine()
{	
	if [ -z "$_buildDir" ] || [ -z "$_urlTar" ]; then
		PrintUsage;
		exit 1;
	fi	

	if [ -z "$_tmpDir" ]; then
		_tmpDir="${_buildDir}/tmp";
	fi
}




DownloadSource()
{
	LogErr 'downloading source code files...';
	
	printf 'URL: %s\n' "$_urlTar" 1>&2;
	
	# always make sure the tmp dir is empty before downloading. This is useful
	# for later being able to detect the downloaded file name (without have to
	# resource to specific features of curl or wget or parsing headers)
	DieIfFails rm -rf "$_tmpDir";
	DieIfFails mkdir -p "$_tmpDir";

	local i=3;
	while true; do
		if Download "$_urlTar" "$_tmpDir"; then
			break;
		else			
			i=$(( i - 1));
			if [ $i -gt 0 ]; then
				printf '\ndownload failed. Trying again...\n' 1>&2;
			else
				Die 'unable to download';
			fi
		fi;
	done;

	# now that we have a directory with only one file, retrieving the name gets
	# much easier	
	_tarName=$(find "$_tmpDir" -type f);

	if [ $? -ne 0  ] || [ -z "$_tarName" ]; then
		Die "unable to retrieve the latest tarball filename";
	fi	

	# and now that we know its name, we can move it out of there
	local newTarName="${_tarName#${_tmpDir}/}";
	DieIfFails mv "$_tarName" "${_buildDir}/${newTarName}";
	_tarName="$newTarName";
}


ExtractSource()
{
	LogErr 'extracting source code files...';
	# if you think the default directory where the tarball will be extracted is
	# simple the same as the tar archive minues the .tar.something extension,
	# think again...
	#
	# So, in order to find out what it really is, we either have to list the
	# contents with "tar -t" or extract it. Since we are going to extract it 
	# anyway...
	if ! tar -C "$_tmpDir" -xf "${_buildDir}/${_tarName}"; then
		case "$_tarName" in
			*.zip)
				DieIfFails unzip -q -d "$_tmpDir" "${_buildDir}/${_tarName}";
			;;
			*)
				# try extracting with 7z. 7z will output a bunch of stuff
				# so we must redirect the output to /dev/null
				DieIfFails 7z x "${_buildDir}/${_tarName}" -o"${_tmpDir}/" > /dev/null
			;;
		esac
	fi

	local version=$(find "$_tmpDir" -maxdepth 1 -mindepth 1);
	version="${version#${_tmpDir}/}";
		
	if [ $? -ne 0  ] || [ -z "$version" ]; then
		Die "unable to retrieve the latest version name";
	fi	

	# and now we can finaly move it out of there	
	DieIfFails rm -rf "${_buildDir}/${version}";
	DieIfFails mv "${_tmpDir}/${version}" "${_buildDir}/"

	#local sourceDir="${_buildDir}/"$(printf '%s' "$version" | sed 's;\(.*\).tar.*$;\1;');
	local sourceDir="${_buildDir}/${version}";	
	
	printf '%s' "$sourceDir";
}




ParseCommandLine "$@"
ValidateCommandLine;
DownloadSource;
ExtractSource;

