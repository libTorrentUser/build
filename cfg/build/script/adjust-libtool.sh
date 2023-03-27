#!/bin/sh


_destDir=;
_delete=;
_outDir=;
_prefix=;


source script.lib.sh



PrintUsage()
{
	local usage="$0"' -d=destDir --prefix=prefix  -o=outDir

Search for the all .la files inside ${destDir} and copy them to ${outDir}, 
adjusting the paths so that they point to ${destDir}. 

The idea here is to allow build scripts to call libtool to retrieve information 
about packages without having to insteall the package in the system.

In order to avoid poluting the system, build.sh "installs" all packages to a
temporary directory. But things like the chosen prefix are kept intact, as if
the package would have been installed the real system. This way it gets very 
easy to package the package for the final install. The problem is that tools
like libtool will break, because the .la files will contain the wrong paths
because they will be using the "prefix", without accounting for the directory 
where they were temporarily put.

This script will create a copy of the original files, adjust the path and put
that copy inside ${outdir}. All you have to do then is to add ${outdir} before
any other path in the LD_LIBRARY_PATH and LIBRARY_PATH env variables, so those
files are searched there first and the correct value is used


-d
--dest-dir
	directory where binaries weree installed by the build script

--delete
	instead of adjusting the .la files, simply delete them. This is usually the
	best choice if the project also produces pkg-config files (*.pc) because
	pkg-config is more decoupled and does a better job.

	The biggest problem with .la files is that they might cause overlinking. The
	second biggest problem 	with .la files is that libtool likes to put full 
	file paths in there AND HARDCODE THE PREFIX AT THE SAME TIME! The result of
	this mess is that it is likely to break build systems like ours, which build
	each package in a separate dir. The moment libtool starts making use of .la
	files from other projects it will probably complain it is unable to find 
	them because it ignores LD_LIBRARY_PATH and LIBRARY_PATH and searches only
	at that hardcoded prefix. Stupid libtool

	Note: it seems some projects do require .la files to work correctly during
	run-time. Those are usually projects that use plugins and use libtool to
	load them. And then there is also the case of projects that generat .la 
	files that having nothing to do with libtool.

-o
--out-dir
	directory where the adjusted files will be created

--prefix
	prefix used when the package was built.

Examples:
	# call it like this to adjust the .la files
	'$0' -d="$destDir" --prefix="$prefix" -o="${dirBin}/lib";

	# call it like this to simply delete the darn things
	'$0' -d="$destDir" --delete;
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
	      	--delete)
	      		_delete=1;
	      	;;
	      	-h|--help)
	      		PrintUsage;
	      	;;			
			-o=*|--out-dir=*)
				_outDir="${i#*=}";
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
	if [ -z "$_delete" ]; then
		if [ -z "$_destDir" ] \
		|| [ -z "$_outDir" ] \
		|| [ -z "$_prefix" ]; then
			PrintUsage;
			exit 1;
		fi	
	else
		if [ -z "$_destDir" ]; then
			PrintUsage;
			exit 1;
		fi	
	fi
}


AdjustFile()
{
	local f="$1";

	printf 'adjusting %s\n' "$f";

	# generate the dest file name
	local destFile="${_outDir}/$(basename ""$f"")";

	# replace the wrong hardecoded paths by the correct... hardcoded paths 
	DieIfFails sed "s;^libdir='${_prefix};libdir='${_destDir}${_prefix};" "$f" > "$destFile";

	# when a .la depends on a library that depends on another library, that
	# "dependency of the dependency" will be added with the wrong path
	# ({pefix}) so we must change it too. Without this, using libx11 as an
	# example, you'd see something like this inside libX11.la
	#
	# dependency_libs=' /correct/path/usr/lib/lbxcb.la /usr/lib/libXau.la'
	#
	# And now if anything depends on libX11.la. it won't find libXau.la 
	# because libtool used {prefix} as the path, instead of the correct
	# location which it should have gotten from "libxcb.la". libxcb.la 
	# should contain the correct path to libXau.la, so this is jst libtool
	# being dumb.
	DieIfFails sed -i "s; ${_prefix}; ${_destDir}${_prefix};g" "$destFile"

	# and last, but not least, due to all these hacks to allow packages using
	# libtool to be built in our build system, the paths in the original .la
	# files will be "wrong" too, that is, they will be pointing to the directory
	# where we installed the dependency. And, as you remember, our build system
	# installs each package in its own directory. But that original .la file is
	# supposed to be ready to be packed and installed on a real system. That 
	# means that the paths should be set to {prefix} (which is what libtool 
	# would have done if we were building this package in a system where 
	# everything gets installed in the same dir ({prefix})
	DieIfFails sed -i "s; [^ ]*${_prefix}; ${_prefix};g" "$f";
}


Execute()
{
	Log 'Adjusting the libtool .la files...';

	# search for a .la files
	for f in $(find "$_destDir" -name '*.la' -type f); do
		# now delete or adjust them
		if [ -n "$_delete" ]; then
			printf 'deleting %s\n' "$f";
			DieIfFails rm -f "$f";
		else		
			AdjustFile "$f";
		fi		
	done
}


ParseCommandLine "$@";
ValidateCommandLine;
Execute;

