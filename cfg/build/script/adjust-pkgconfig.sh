#!/bin/sh


_destDir=;
_outDir=;
_package=;
_prefix=;
_rootDir=;


source script.lib.sh



PrintUsage()
{
	local usage='adjust-pkg-config.sh -d=destDir --prefix=prefix -r=rootDir -o=outDir [-p=package] 

Search for the pkg-config scripts inside {destDir} and copy them to {outDir}, 
adjusting the paths so that they point to {rootDir}. See the comments on 
--root-dir for the reasoning behind needed both --dest-dir and --root-dir

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

-r
--root-dir
	fake system root dir used by the build system. It should contain symlinks
	to all built files. Because of that, if we use this directory instead of the
	--dest-dir directory on the adjusted .pc files, PKG_CONFIG_PATH will not
	need to contain thousands of paths (one for each package), but only the
	paths in the fake system root dir. Technically, because of the fake sys root
	dir, --dest-dir is not really needed. But we still require it because it
	allows this script to adjust only the .pc files found inside --dest-dir, 
	i.e., the ones that have probably just been built/rebuilt. If we only used
	--root-dir, we would not know which files need to be adjust and which were
	already ajusted. At the very least we would need to compare modification
	dates and see if the the "source" .pc file is newer. That would be possible
	but it would still was time. And it would get worse the more packages are
	built. By using --dest-dir we know for sure which files need to be adjust
	and ajust only those.

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
			-r=*|--root-dir=*)
				_rootDir="${i#*=}";
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
	|| [ -z "$_prefix" ] \
	|| [ -z "$_rootDir" ]; then
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
	DieIfFails sed -i "s;\(^prefix=\);\1${_rootDir};" "${_outDir}/${scriptFileName}";	
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
		DieIfFails sed "s;\(^prefix=\);\1${_rootDir};" "$p" > "${_outDir}/${fileName}";	
		
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

