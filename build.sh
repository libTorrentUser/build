#!/bin/sh

# finally part of POSIX
set -o pipefail

_scriptPath=$(readlink -f "$0");
_scriptDir=$(dirname "$_scriptPath");


_packages=;
_compilerC=gcc;
_compilerCXX=g++;
_compilerFlagsAdd='native-lto';
_deleteSources=;
_dirConfig="${_scriptDir}/cfg/build";
_dirBin=;
_dirRoot=;
_lazyCheck=;
_linker='ld.bfd';
_linkerFlags='none';
_overrideCompiler=1;
_overrideLinker=1;
_prefix='/usr';
_noBuild=;
_noBuildDependencies=;

_buildDir=;
_destDir=;
_envVarsFile=;
_logDir=;
_npp=;
_packagesAddedToSearchPaths=;
_warningsFile=;


source /usr/local/bin/script.lib.sh






PrintUsage()
{
	local usage='build.sh [options] package

this script will download the latest version of {package} and all its 
dependencies and build them. You can pass more than one package if you wish.

-b
--build-dir
	directory where the source code will be downloaded to and built.

--compiler-c
--compiler-cxx
	select the compiler. Can be anything inside {--dir-config/bin/compiler) 

--compiler-flags-add
	select flags that will be always enforced (or disabled). No matter what
	flags the compiler is being invoked with, these flags will always be 
	appeneded at the end of the invocation. Can 	be anything inside 
	{--dir-config}/bin/compiler/{--compiler-c/)"
	"{--dir-config}/bin/compiler/{--compiler-cxx/)"
	Note? the script with the flags must exist on both dirs, since it will be 
	used by both the C and the C++ compiler.
	
-d
--dest-dir
	directory where binaries will be installed to (make DESTDIR=dir install)

--delete-sources
	delete all source and intermediate files after a successful build. This flag
	automaticaly sets --lazy-check.

--dir-config
	directory where the configuration files are located. The default is
	"cfg/build"

-j
--jobs
	number of concurrent compilation jobs. Defaults to the number of physical
	CPU cores.

--lazy-check
	by default, any package that had one or more files modified after it has
	been last built will be built again. That includes any file inside a 
	directory that belongs to the package, like the directory with the 	sources 
	and also the directory with the files generated by the build. The build 
	script is also considered. If this flag is set, all that is ignored and only
	the "ok" directory 	will be checked. If it is there, the package is assumed
	to have been built and is perfectly fine. This flag is always set if
	--delete-sources is used.

--linker
	select the linker you want to use. Anything inside 
	"{--dir-config}/bin/linker/" is valid.

--linker-flags
	select a script that will force aditional flags to be passed to the linker
	on every invocation. Anuthing inside "{--dir-config}/bin/linker/{--linker}/"
	is valid.

--prefix
	prefix to be passed to the "configure" command. Prefixes containing spaces
	are not supported.

--no-build
	do not build any of these packages.

--no-build-depedencies
	do not build any depedency.
';

	printf '%s\n' "$usage";
}






ParseCommandLine()
{
	for i in "$@"; do
		case $i in			 
			-b=*|--build-dir=*)
				_buildDir="$(MkDirReadLinkF ""${i#*=}"")";
	      	;;			
	      	--compiler-c=*)
				_compilerC="${i#*=}"
			;;
	      	--compiler-cxx=*)
				_compilerCXX="${i#*=}"
			;;
			--compiler-flags-add=*)
				_compilerFlagsAdd="${i#*=}";
			;;
			-d=*|--dest-dir=*)
				_destDir="$(MkDirReadLinkF ""${i#*=}"")";
	      	;;	
	      	--delete-sources)
	      		_deleteSources=1;
	      	;;
	      	--dir-config=*)
	      		_dirConfig="${i#*=}";
	      	;;		
	      	-h|--help)
	      		PrintUsage;
	      		exit 0;
	      	;;
	      	-j=*|--jobs=*)
	      		_npp="${i#*=}"
			;;
	      	--lazy-check)
	      		_lazyCheck=1;
	      	;;
	      	--linker=*)
	      		_linker="${i#*=}"
			;;
			--linker-flags=*)
	      		_linkerFlags="${i#*=}"
			;;
	      	-p=*|--prefix=*)
				_prefix="${i#*=}"
			;;
	      	--no-build=*)
	      		_noBuild="${i#*=}";
	      	;;
	      	--no-build-dependencies)
	      		_noBuildDependencies=1;
	      	;;
			--)
	      		# nothing else to parse
	      		break;  
	      	;;    
	    	-*)
	      		Die "Unknown option \"$i\""
				exit 1;
	      	;;
	      	*)
	      		_packages="${_packages} $i"
	      	;;
		esac
	done
}


DirBuild()
{
	printf '%s/p/%s' "$_buildDir" "$1"
}


DirOK()
{
	printf '%s/ok/%s' "$_buildDir" "$1"
}


DirDest()
{
	printf '%s/d/%s' "$_buildDir" "$1"
}


FileConfig()
{
	printf '%s/build.cfg' "$(DirOK ""$1"")"
}


CreateNonFltoCopy()
{
	local nonLtoFile="${1}-no.lto";
	
	DieIfFails cp "$1" "$nonLtoFile";
	DieIfFails sed -i 's;-flto=[^ ]*;;' "$nonLtoFile";
}


CreateFltoPartitionNoneCopy()
{
	local noneFile="${1}-lto.partition.none";
	
	DieIfFails cp "$1" "$noneFile";

	# remove any existing flto-partition falgs
	DieIfFails sed -i 's;-flto-partition=[^ ]*;;' "$noneFile";

	# add -flto-partition=none.
	DieIfFails sed -i 's;\("$@".*\);\1 -flto-partition=none;' "$noneFile";
}


InitializeCompilers()
{
	# clean up garbage from any previous invocation
	local ccFiles=
	ccFiles="cc c++ "$( \
		find "${_dirConfig}/bin/compiler/" -mindepth 1 -maxdepth 1 -type d);
		
	for f in $ccFiles; do		
		f="${f##*/}";
		DieIfFails rm -f "${_dirBin}/${f}";
		DieIfFails rm -f "${_dirBin}/${f}-no.lto";		
		DieIfFails rm -f "${_dirBin}/${f}-lto.partition.none";
	done
	

	# add these to the path in order to have every compiler invocation use our
	# scripts. They will enforce (and remove) certain optimization flags. This
	# seems way better than just exporting CFLAGS and CXXFLAGS and hoping for 
	# the best
	if [ ! -z "$_overrideCompiler" ]; then	
 
			
		DieIfFails cp "${_dirConfig}/bin/compiler/${_compilerC}/${_compilerFlagsAdd}" "${_dirBin}/${_compilerC}";
		DieIfFails cp "${_dirConfig}/bin/compiler/${_compilerCXX}/${_compilerFlagsAdd}" "${_dirBin}/${_compilerCXX}";

		# ugly hack because some projects cannot be built with -flto
		DieIfFails CreateNonFltoCopy "${_dirBin}/${_compilerC}";
		DieIfFails CreateNonFltoCopy "${_dirBin}/${_compilerCXX}";

		# same as above, but for those projects that can handle -flto, as long
		# as we use -flto-partition=none
		DieIfFails CreateFltoPartitionNoneCopy "${_dirBin}/${_compilerC}";
		DieIfFails CreateFltoPartitionNoneCopy "${_dirBin}/${_compilerCXX}";

		# gnu make defaults CC to cc. So we must override that too		
		DieIfFails ln -s "${_dirBin}/${_compilerC}" "${_dirBin}/cc" 
		DieIfFails ln -s "${_dirBin}/${_compilerCXX}" "${_dirBin}/c++"

		# same for the non-lto copies. This way build scripts can just set CC to
		# cc-no.lto.
		DieIfFails ln -s "${_dirBin}/${_compilerC}-no.lto" "${_dirBin}/cc-no.lto";
		DieIfFails ln -s "${_dirBin}/${_compilerCXX}-no.lto" "${_dirBin}/c++-no.lto";
		DieIfFails ln -s "${_dirBin}/${_compilerC}-lto.partition.none" "${_dirBin}/cc-lto.partition.none";
		DieIfFails ln -s "${_dirBin}/${_compilerCXX}-lto.partition.none" "${_dirBin}/c++-lto.partition.none";

		CC="${_dirBin}/cc";
		export CC;

		CXX="${_dirBin}/c++";
		export CXX;

		printf 'dir-config="%s"
cc=%s
c++=%s
compiler-flags-add=%s\n' \
	"$_dirConfig" \
	"$_compilerC"  \
	"$_compilerCXX" \
	"$_compilerFlagsAdd";
	fi
}


InitializeLinker()
{
	# clean up garbage from any previous invocation
		# clean up garbage from any previous invocation
	local ldFiles=
	ldFiles="ld "$( \
		find "${_dirConfig}/bin/linker/" -mindepth 1 -maxdepth 1 -type d);
		
	for f in $ldFiles; do		
		f="${f##*/}";
		DieIfFails rm -f "${_dirBin}/${f}";
	done
	

	# add this to the path in order to have every build use our scripts. They 
	# can enforce (and remove) certain flags.
	if [ ! -z "$_overrideLinker" ]; then 
			
		DieIfFails cp "${_dirConfig}/bin/linker/${_linker}/${_linkerFlags}" "${_dirBin}/${_linker}";
		
		# some tools default the linker to "ld", so we have to override that too
		DieIfFails ln -s "${_dirBin}/${_linker}" "${_dirBin}/ld"

		LD="${_dirBin}/ld";
		export LD;

		printf 'ld=%s (flags=%s)\n' "$_linker" "$_linkerFlags";
	fi
}


Initialize()
{
	# we have to perform a lazy check if the sources will be deleted
	if [ ! -z "$_deleteSources" ]; then
		_lazyCheck=1;
	fi;

	# directory every we will download and build stuff
	if [ -z "$_buildDir" ]; then
		Die '--build-dir is needed';
	fi

	# we have to make sure theese variables are exported. We will add more stuff
	# in them later, but there is no need to keep calling export every time we
	# do it. We always assign them to themselves first, just in case they 
	# already existed

	# directories where pkg-config will search for .pc files
	PKG_CONFIG_PATH="$PKG_CONFIG_PATH";
	export PKG_CONFIG_PATH;	

	# additional GCC include directories
	CPATH="$CPATH";
	export CPATH;

	# additional GCC library directories
	LIBRARY_PATH="$LIBRARY_PATH";
	export LIBRARY_PATH;

	# aditional shared library directories
	LD_LIBRARY_PATH="$LD_LIBRARY_PATH";
	export LD_LIBRARY_PATH;

	# these dirs will be used by all packages
	_logDir="${_buildDir}/log";
	
	DieIfFails mkdir -p "$_logDir";

	# number of physical processors
	if [ -z "$_npp" ]; then
		_npp=$(npproc.sh);
		if [ $? -ne 0  ]; then
			Die "unable to retrieve the number of physical processors";
		fi	
	fi

	# some packages create scripts that allow other tools to retrieve 
	# information about them. Many times that means paths to special directories
	# those packages created. The problem is that we don't really install the
	# packages in the system and that means that other packages the depend on
	# them will not build properly. To fix that, we create a copy of those 
	# scripts with paths adjusted to where the packages were actually built and
	# put them all inside this dir here. This directory must always come before
	# any package dest dir in the PATH, otherwise the wrong script might be used
	_dirBin="${_buildDir}/bin";	
	PATH=$(PathPrepend "$PATH" "$_dirBin");
	DieIfFails mkdir -p "$_dirBin";
	export PATH;

	# pkg-config is a somewhat standard tool that does what the scripts 
	# mentioned above do. They also have to have their paths adjusted, and we
	# will put them all here
	local pkgConfigDir="${_dirBin}/pkgconfig";
	DieIfFails mkdir -p "$pkgConfigDir";
	PKG_CONFIG_PATH=$(PathPrepend "$PKG_CONFIG_PATH" "$pkgConfigDir");

	# same as above for libtool files. But this one, unlike pkg-config, does not
	# have a env variable to hold the path. Because of that, we must ensure this
	# dir with the adjusted files comes first in the library search paths
	# LIBRARY_PATH and LD_LIBRARY_PATH
	local libtoolDir="${_dirBin}/lib";
	DieIfFails mkdir -p "$libtoolDir";

	# this file will hold the name of all packages that have already been added
	# to the search paths. This way we can avoid adding duplicated entries. And
	# the only reason we leave an empty file here is because it will be grepped
	# and grep prints error messages when the input file does not exist. An
	# empty file here save us from have to see or redirect those error messages
	_packagesAddedToSearchPaths="$_buildDir/paths.txt";
	DieIfFails rm -f "$_packagesAddedToSearchPaths";
	DieIfFails touch "$_packagesAddedToSearchPaths";

	# this is where packages will store enviroment variables needed to make
	# them work correctly when used as a dependency to other packages
	_envVarsFile="${_buildDir}/env.sh";
	DieIfFails printf '#!/bin/sh\nsource script.lib.sh\n' > "$_envVarsFile";
	DieIfFails chmod +x "$_envVarsFile";

	# this is where the build script warnings will be stored
	_warningsFile="${_buildDir}/warnings.txt";
	DieIfFails rm -f "$_warningsFile";

	# this will be a fake root file system containing symlinks to every file
	# a package would install. This is done so tools like cmake, which seems to
	# ignore PKG_CONFIG_PATH and other commonly used env vars, can locate stuff
	# without us having to pass the directories of every single package to it
	_dirRoot="${_buildDir}/r";
	DieIfFails mkdir -p "$_dirRoot";

	# override cc, c++, gcc, etc with scripts that enforce or disable 
	# optimizations
	InitializeCompilers;

	# override ld ld.fd ld.gold etc with scripts that enforce or disable
	# certain flags
	InitializeLinker;
}


# ModificationDate "file"
#
# return the file's modification date
ModificationDate()
{
	stat -c '%y' "$1";
	
	if [ $? -ne 0 ]; then
		Die "unable to retrieve the modification date of ${1}";
	fi
}


# NewestFileModificationTime "someDirectory"
#"
# returns the the modification time of the newest file in the provided directory
# The reason the date is returned as a string, instead of an "integer since 
# epoch" is because there seems to be no POSIX way to do that without losing
# precision. To make things worse, this complicates dates comparison, as can
# be seen in the function IsNewerDate()
NewestFileModificationTime()
{
	if [ -e "$1" ]; then
		# the reason for running "find" in a subshell is because I wasn't able
		# to figure out how to pipe "find -exec +" directly to "sort". It works
		# if we do not use the "+", but then it will become unberably slow if
		# the directory has lots of files (cmake takes 30 seconds or so!)
		local dates=$(find "$1" -exec stat -c '%y' {} +);		
		printf '%s' "$dates" | sort | tail -n 1;
	else
		printf '9999-12-31 23:59:59.999999999 +0000';
	fi;		
}


# IsNewerDate "date1" "date2"
#
# return 0 if "date1" is newer than "date2"
IsNewerDate()
{
	local d1="$1";
	local d2="$2";
	
	# the time is not an integer, so we cannot use the test command to
	# compare them.		
	local newest=$(printf '%s\n%s' "$d1" "$d2" | sort | tail -n 1);
	
	if [ "$newest" = "$d1" ]; then
		return 0;
	fi

	return 1;
}


# NewestBuildScript "package" "buildDependencies" "runtimeDependencies"
#
# get the modification date of the package build script and then compare it to
# the modification date of all the packages it depends on and return the newest
# one
NewestBuildScript()
{
	local package="$1";
	local buildDependencies="$2";
	local runtimeDependencies="$3";

	local buildScriptDir="${_dirConfig}/package";

	local dates;
	dates=$(ModificationDate "${buildScriptDir}/${package}");

	for p in $buildDependencies; do
		d=$(ModificationDate "${buildScriptDir}/${p}");
		dates=$(printf '%s\n%s' "$dates" "$d");
	done
		
	for p in $runtimeDependencies; do
		d=$(ModificationDate "${buildScriptDir}/${p}");
		dates=$(printf '%s\n%s' "$dates" "$d");
	done

	local newest=$(printf '%s' "$dates" | sort | tail -n 1);

	printf '%s' "$newest";
}


CurrentConfig()
{
	printf -- '--prefix=%s' "$_prefix"
}


PackageOK()
{	
	local package="$1";
	local buildDependencies="$2";
	local runtimeDependencies="$3";
		
	local buildDir="$(DirBuild ""$package"")";
	local destDir="$(DirDest ""$package"")";
	local okDir="$(DirOK ""$package"")";
	local configFile="$(FileConfig ""$package"")";

	# if we are performing a lazy check, then the exitence of the OK dir is
	# considered enough
	if [ ! -z "$_lazyCheck" ]; then
		test -e "$okDir";
		return $?;
	fi

	local currentConfig="$(	CurrentConfig )";
	local oldConfig=;
	if [ -f "$configFile" ]; then
		oldConfig="$( cat "$configFile" )";
	fi

	local dateScript=$(NewestBuildScript \
		"$package" \
		"$buildDependencies" \
		"$runtimeDependencies");
	local dateBuildDir=$(NewestFileModificationTime "$buildDir");
	local dateDestDir=$(NewestFileModificationTime "$destDir");
	local dateOkDir=$(NewestFileModificationTime "$okDir");
	
	if [ "$currentConfig" = "$oldConfig" ] &&
		IsNewerDate "$dateBuildDir" "$dateScript" &&
		IsNewerDate "$dateDestDir" "$dateBuildDir" && 
		IsNewerDate "$dateOkDir" "$dateDestDir"; then

		return 0;
	fi

	return 1;

	# DEBUG DEBUG DEBUG (comment the "return 1;" above to execute)
	if [ "$currentConfig" != "$oldConfig" ]; then 
		printf 'config different\n' 
	fi
	if ! IsNewerDate "$dateBuildDir" "$dateScript"; then 
		printf 'dateBuildDir not newer than dateScrip\n' 
	fi
	if ! IsNewerDate "$dateDestDir" "$dateBuildDir"; then 
		printf 'dateDestDir not newer than dateBuildDir\n' 
	fi
	if ! IsNewerDate "$dateOkDir" "$dateDestDir"; then 
		printf 'dateOkDir not newer than dateDestDir\n'
	fi
	exit 1;
	return 1;
}


SetPackageOK()
{
	local okDir="$(DirOK ""$1"")";
	local configFile="$(FileConfig ""$package"")";
	
	DieIfFails mkdir -p "$okDir";
	DieIfFails printf '%s' "$(CurrentConfig)" > "$configFile";
}


UpdateSearchPaths()
{
	local package="$1";

	# if the package has already been added once, do not do it again
	if grep -q "^${package}\$" "$_packagesAddedToSearchPaths"; then
		return 0;
	fi;
		
	local packageDestDir="$2";
	local warnings="$3";

	# add the dest dir to the path, so packages that depend on this one can be
	# built without issues
	local destDirPrefixed="${packageDestDir}$_prefix";

	# binaries search path. Remember that {_dirBin} must always be the first.
	# We ensure that by first deleting it and then adding it again
	PATH="${PATH##${_dirBin}:}";
	PATH=$(PathPrepend "$PATH" "${destDirPrefixed}/bin");
	PATH=$(PathPrepend "$PATH" "${_dirBin}");

	# gcc include file search path 
	CPATH=$(PathPrepend "$CPATH" "${destDirPrefixed}/include");

	# gcc library file search path
	local dirLib="${destDirPrefixed}/lib";
	if [ -e "$dirLib" ]; then
		# the lib inside our temporary bin directory must always comes first in
		# the path so our "adjusted" files are picked, instead of the regular
		# ones. 
		local libInBin="${_dirBin}/lib";
		LIBRARY_PATH="${LIBRARY_PATH##${libInBin}:}"
		LIBRARY_PATH=$(PathPrepend "$LIBRARY_PATH" "$dirLib");
		LIBRARY_PATH=$(PathPrepend "$LIBRARY_PATH" "$libInBin");

		LD_LIBRARY_PATH="${LD_LIBRARY_PATH##${libInBin}:}"
		LD_LIBRARY_PATH=$(PathPrepend "$LD_LIBRARY_PATH" "$dirLib");
		LD_LIBRARY_PATH=$(PathPrepend "$LD_LIBRARY_PATH" "$libInBin");
	fi

	# flag this package as one of those that are in our paths
	DieIfFails printf '%s\n' "$package" >> "$_packagesAddedToSearchPaths";

	# print any warnings the build script may have. We do this here in order to
	# avoid printing the warnings every time a package is mentioned. Doing it
	# here ensures the warnings, if any, will be printed only once for each 
	# package
	if [ ! -z "$warnings" ]; then
		printf 'WARNING: %s\n' "$warnings";

		printf '%s\n%s\n--------------------------------------------------------------------------------\n' \
			"$package" \
			"$warnings" >> "$_warningsFile";
	fi
}

# StringContainsWholeWord bigString word
#
# Return 0 if the {word} is inside {bigString} as a whole word, i.e., 
# StringContainsWholeWord "zaz make pow" "make" # returns 0
# StringContainsWholeWord "zazmake pow makezaz" "make" # returns 1
StringContainsWholeWord()
{
	printf '%s' "$1" | grep -q "\b$2\b";
	return $?;
}


# DoNotBuild package
#
# returns 0 if the package is in the "do not build list"
DoNotBuild()
{
	StringContainsWholeWord "$_noBuild" "$1";		
	return $?;
}


DependencySetContains()
{
	local package="$1";
	local dependencies="$2";

	# note: grep -w (whole word) considers dashes (-) a word separator char.
	# Because of that we cannot simply do
	#
	# grep -q -w "$package"
	#
	# Because that would match both "python" and "python-setuptools"
	#
	# The solution then is to do it ourselves, by searching for all possible
	# combinations. 
	# 'package '
	# ' package '
	# ' packge'
	#
	# This works because our dependency chain string always contains a space
	# after the package name, unless it is the last one. And we also must search
	# for lines starting with the package, since those won't have a space char
	# before the package name
	if printf '%s' "$dependencies" | grep -q '^'${package}' \| '${package}'$\| ${package} '; then
		return 0;
	fi

	return 1;
}


# LinkPackgeToRoot "$packageDestDir" 
#
# creates symlinks for the package files into our root dir
LinkPackageToRoot()
{
	local packageDestDir="$1";

	# do this inside a sub-shell in order to avoid having to worry about 
	# returning to the directory we were in
	$(
		DieIfFails cd "$_dirRoot";
		
		DieIfFails find "$packageDestDir" \( -type f -o -type l \) -print0 | \
			xargs -0 -n 1 -I {} sh -c '
				packageDestDir="$1";
				packageFilePath="$2";

				# remove $packageDestDir from $packageFilePath so
				# build/d/make/usr/bin/make 
				# becomes 
				# usr/bin/make
				linkFilePath="${packageFilePath#$packageDestDir}";

				# ensure no leading slash remains, otherwise the commands below
				# would try to create stuff in the real system root
				linkFilePath="$(printf "%s" "$linkFilePath" | sed "s;^/*;;")"

				mkdir -p "$(dirname "$linkFilePath")" || exit 1;			

				# create a link named 
				# build/r/usr/bin/make
				# pointing to
				# build/d/make/usr/bin/make 
				ln -sf "$packageFilePath" "$linkFilePath" || exit 1;
				
				' dummy "$packageDestDir" {};

		# note: this check is to detect errors in the xargs call. It requires 
		# "set -o pipefail" to work
		if [ $? -ne 0 ]; then
			Die 'something went wrong in the call to xargs';
		fi
	);

	if [ $? -ne 0 ]; then
		Die 'unable to link package to root dir';
	fi
}


Build()
{
	local package="$1";	
	local dependencyChainWithoutPackage="$2";
	local dependencyChain="${2:+$2 -> }$1";

	# check if we should build it
	if DoNotBuild "$package"; then
		printf 'skipping %s\n' "$dependencyChain";
		return 0;
	fi	

	# check if the package is already inside the dependency set. If it is, it
	# means we have a cyclic dependency chain in our hands and one of these
	# packages will be manually installed and added to --no-build
	if DependencySetContains "$package" "$dependencyChainWithoutPackage"; then
		Die "$dependencyChain"'
ERROR: cyclic dependency detected on package "'"$package"'"';
	fi	

	# set a couple of package dependent paths
	local packageBuildDir="$(DirBuild ""$package"")";	
	local logFile="${_logDir}/$package.txt";
	local packageDestDir="$(DirDest ""$package"")";
	local buildScript="${_dirConfig}/package/${package}";

	# clear any build script function that might not be present in the package
	# build script we are about to load
	source "${_dirConfig}/script/clear.sh";

	# load the package script
	source $buildScript;

	# get all the dependencies and build them	
	local warnings="$( PackageWarnings )";

	local buildDependencies=;
	local runtimeDependencies=;
	if [ -z "$_noBuildDependencies" ]; then
		buildDependencies=$( PackageBuildDependencies );
		runtimeDependencies=$( PackageRuntimeDependencies );
	fi
	
	for d in $buildDependencies; do
		Build "$d" "$dependencyChain";
	done
		
	for d in $runtimeDependencies; do
		Build "$d" "$dependencyChain";
	done

	# now we can finally build the package. 
	printf 'building %s ...\n' "$dependencyChain";

	# load the package script again, since the dependencies will have 
	# sourced their own scripts and the PackageBuild function will be the 
	# wrong one
	if [ ! -z "$buildDependencies" ] || [ ! -z "$runtimeDependencies" ]; then
		source "${_dirConfig}/script/clear.sh";
		source $buildScript;
	fi

	# but first check if we haven't already done so	
	if ! PackageOK "$package" "$buildDependencies" "$runtimeDependencies"; then	
		# before doing anything, delete the OK dir. Otherwise some future 
		# --lazy-check call may think this package is OK
		DieIfFails rm -rf "$(DirOK ""$package"")";

		# and we do not want garbage inside the dir where the package will be
		#  installed
		DieIfFails rm -rf "$packageDestDir";

		DieIfFails mkdir -p "$packageBuildDir";		

		# if this is not done inside a subshell, the script will just exit in 
		# case  of an error. Which is what it is supposed to do. But we want to 
		# tell the user where the log file is before it does so.
		$( PackageBuild \
			"$packageBuildDir" \
			"$_prefix" \
			"$packageDestDir" \
			"$_npp" \
			"$_dirBin" \
			"$_dirRoot" > "$logFile" 2>&1 )
			
		if [ $? -ne 0 ]; then
			Die 'build failed! Check the log file "'"$logFile"'"';
		fi

		# create symlinks for the generated files into our root dir
		DieIfFails LinkPackageToRoot "$packageDestDir";		

		# flag the package as OK
		DieIfFails SetPackageOK "$package"

		# delete the source files
		if [ ! -z "$_deleteSources" ]; then
			DieIfFails rm -rf "$packageBuildDir";
		fi
	fi

	# execute the package's post build script. This is always executed in order
	# to ensure any environment vars the package creates will be set	
	$( PackagePostBuild \
		"$_prefix" \
		"$packageDestDir" \
		"$_dirBin" \
		"$_envVarsFile" >> "$logFile" 2>&1 );
	if [ $? -ne 0 ]; then
		Die 'post build failed! Check the log file "'"$logFile"'"';
	fi

	# and here we set all those env vars. The reason we do it here instead of
	# forcing packages to do it inside their PackagePostBuild() functions is:
	#
	# 1. it allows to call PackagePostBuild in a sub-shell, which simplifies
	# error handling. 
	#
	# 2. having all vars in a separate file makes it easier to manualy reproduce
	# a build.
	DieIfFails source "$_envVarsFile";
	
	# add the dest dir to the path, so packages that depend on this one can be
	# built without issues
	UpdateSearchPaths "$package" "$packageDestDir" "$warnings";
}



BuildPackages()
{
	DieIfFails cd "$_dirConfig/script";

	for p in $_packages; do
		Build "$p"		
	done

	printf 'done!\n';
}



ParseCommandLine "$@"
Initialize;
BuildPackages;

