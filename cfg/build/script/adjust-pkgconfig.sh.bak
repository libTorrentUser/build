#!/bin/sh


_destDir=;
_outDir=;
_package=;
_prefix=;


source script.lib.sh



PrintUsage()
{
	local usage='adjust-pkg-config.sh -d=destDir --prefix=prefix  -o=outDir [-p=package] 

Search for the pkg-config scripts inside {destDir} and copy them to {outDir}, 
adjusting the paths so that they point to {destDir}.

The idea here is to allow build scripts to call pkg-config to retrieve 
information about packages without having to insteall the package in the system.

In order to avoid poluting the system, build.sh "installs" all packages to a
temporary directory. But things like the chosen prefix are kept intacts, as if
the package would have been installed the real system. This way it gets every 
easy to package the package for the final install. The problem is that tools
like pkg-config will break, because its script will contain the wrong paths
because they will be using the "prefix", without accounting for the directory 
where they were temporarily put. Enter adjust-pkg-config.sh!

All you have to do is to add the directory where the adjusted script will be
put to PKG_CONFIG_PATH. Then, calls to pkg-config will use the adjusted scripted
which in turn contains the correct paths and everything should work.


-d
--dest-dir
	directory where binaries weree installed by the build script

-o
--out-dir
	directory where the adjusted package config script will be created

-p
--package
	package name. The package config script we will be looking forshould be 
	named "{package}.pc". When not provided, we will search for all *.pc files
	inside {destDir}
	

--prefix
	prefix used when the package was built.
';

	printf '%s\n' "$usage";
}



ParseCommandLine()
{
	for i in "$@"; do
		case $i in			
			-d=*|--dest-dir=*)
				_destDir="${i#*=}";
	      	;;
	      	-h|--help)
	      		PrintUsage;
	      	;;			
			-o=*|--out-dir=*)
				_outDir="${i#*=}";
			;;
			-p=*|--package=*)
				_package="${i#*=}";
			;;
			--prefix=*)
				_prefix="${i#*=}";
			;;
			--)
	      		# nothing else to parse
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
	if [ -z "$_destDir" ] \
	|| [ -z "$_outDir" ] \
	|| [ -z "$_prefix" ]; then
		PrintUsage;
		exit 1;
	fi	
}


AdjustSpecific()
{
	Log 'Adjusting the pkgconfig script...';

	local directories="lib/pkgconfig share/pkgconfig";

	local scriptFileName="${_package}.pc";

	local prefixedDestDir="${_destDir}${_prefix}";

	# search for the original pkg-config script
	local sourcePath=;
	for d in $directories; do
		local p="${prefixedDestDir}/${d}/${scriptFileName}"
		printf 'searching as "%s"\n' "$p";
		
		if [ -f "$p" ]; then
			sourcePath="$p";
			break;
		fi;
	done

	# exit if we did not find it
	if [ -z "$sourcePath" ]; then
		printf 'unable to locate the file %s\n' "$scriptFileName";
		exit 1;
	fi

	# copy the script to the output dir and adjust the path
	DieIfFails cp "${sourcePath}" "${_outDir}/";
	DieIfFails sed -i "s;\(^prefix=\);\1${_destDir};" "${_outDir}/${scriptFileName}";	
}


AdjustAny()
{
	Log 'Adjusting the pkgconfig script...';

	local directories="lib/pkgconfig share/pkgconfig";

	#local scriptFileName="${_package}.pc";

	local prefixedDestDir="${_destDir}${_prefix}";

	# search for the pkg-config scripts
	local found=;
	for p in $(find "${prefixedDestDir}" -wholename '*/pkgconfig/*.pc' -type f); do
		printf 'adjusting "%s"\n' "$p";

		# get the file name
		local fileName="$(basename ""$p"")";

		# copy the script to the output dir and adjust the path
		DieIfFails sed "s;\(^prefix=\);\1${_destDir};" "$p" > "${_outDir}/${fileName}";	
		
		# set this flag to indicate that at least one pc file was found
		found=1;		
	done

	# exit if we did not find it
	if [ -z "$found" ]; then
		Die 'unable to locate any pkg-config file';
	fi
}


Execute()
{
	if [ -z "$_package" ]; then
		AdjustAny;
	else
		AdjustSpecific;
	fi
}


ParseCommandLine "$@";
ValidateCommandLine;
Execute;

