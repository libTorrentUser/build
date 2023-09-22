

#!/bin/sh



_buildDir=;
_buildOptions=;
_cmdBuild='make';
_cmdDir=;
_cmdConfigure='configure';
_cmdInstall='make';
_configureOptions=;
_destDir=;
_installOptions='install';
_inSourceTreeBuild=;
_meson=;
_noBuild=
_noConfirm=;
_noConfigure=;
_noDelete=;
_noInstall=;
_objDir=

_npp=;
_tarName=;
_sourceDir=;




. ./lib.sh


PrintUsage()
{
	local usage='make.sh -b=buildDir -s=sourceDir [options] 

basicly... 

cd sourceDir || exit 1
./configure || exit 1
make || exit 1
make install DESTDIR="dest/Dir" || exit 1


-b
--build-dir
	directory where the source code will be downloaded to and built.

--build-options
	options to be passed to --build-command. Useful when you want to build only
	a specific target.

-c
--configure-options
	values to be passed to the build system configure call. You can pass more 
	than one value, but you will have to quote them, like this 
	"--enable-lto --enable-shared".

--cmd-configure
	for those projects that insist on using something other than "configure" as
	the configure command (eg. perl). There are special code paths for some 
	(unfortunately) commonly used commands:

	cmake
		the following options are always appended to the configuration options
		-S "sourceDir" -O "objDir" -G "Unix Makefiles"

	meson
		out of tree building with the classic "configure" script works by going
		into the "obj" directory and calling "sourceDir/configure" form there.
		But with meson you should do the opposite, that is, you go to the source
		code directory, call meson from there and point it to the "obj" dir. And
		so this is what this script will do.

	Default: "configure"

--cmd-build
	command to use when building the sources.

	Default: "make"

--cmd-install
	command to use when installing

	Default: "make"

-d
--dest-dir
	directory where binaries will be installed to (make DESTDIR=dir install)

-i
--install-options
	what to pass to make (--cmd-install)  when installing. The default is 
	"install", but some packages might accepts something else, like 
	"install-strip"

	Default: "install"

--in-source
	perform an "in source tree" build. By default the script will perform an
	out of source tree build, that is, it will compile the code in a directory
	outside of the directory where the source files are. Out of source is the
	default because, not only it is cleaner because it leaves the source dir
	untouched, but also because some projects (like GCC) require you to do so.
	Then again, some projects work the other way around and will fail to compile
	if you attempt an out of source build. Using this flag the script will 
	configure and compile from inside the source code directory.

-j
	number of parallel tasks. Defaults to the number of physical CPU cores.

--no-cbi
	same as --no-configure --no-build --no-install.

--no-build
	do not execute the build step (i.e, "make")

--no-configure
	do not execute the configuration step (i.e., "configure")

--no-delete
	do not delete the dest dir before installing

--no-install
	do not install the package (i.e., 
	make  DESTDIR={--dest-dir} {--install-command} )

--pre-configure
	script file containing a function named CustomPreConfigure that will be
	called before the "configure" step. The function will receive the source
	and obj directories as arguments, and also the number of physical processors
	in the machine. This script file will be "sourced" when	right before the
	"configure" step is called. Since it will be "sourced", avoid having 
	anything you do not want to be executed in there, because, as it happens 
	with any other "sourced" script, the script will be, effectively,
	executed.

-s
--source
	directory with the source files

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
			--build-options=*)
				_buildOptions="${i#*=}";
	      	;;
			-c=*|--configure-options=*)
				_configureOptions="${i#*=}"
			;;
			--cmd-build=*)
				_cmdBuild="${i#*=}"
			;;
			--cmd-configure=*)
				_cmdConfigure="${i#*=}"
			;;
			--cmd-install=*)
				_cmdInstall="${i#*=}"
			;;
			-d=*|--dest-dir=*)
				_destDir="$(MkDirReadLinkF ""${i#*=}"")";
	      	;;
	      	-h|--help)
	      		PrintUsage;
	      	;;
			-i=*|--install-options=*)
				_installOptions="${i#*=}"
			;;
			--in-source)
				_inSourceTreeBuild="1";
	      	;;
	      	-j=*)
				_npp="${i#*=}"
			;;
	      	--no-cbi)
	      		_noConfigure="1";
	      		_noBuild="1";
	      		_noInstall="1";
	      	;;
	      	--no-configure)
				_noConfigure="1";
	      	;;
	      	--no-delete)
				_noDelete="1";
	      	;;
	      	--no-build)
				_noBuild="1";
	      	;;
	      	--no-install)
				_noInstall="1";
	      	;;
			-s=*|--source=*)
				_sourceDir="${i#*=}";
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
	if [ -z "$_buildDir" ] || [ -z "$_sourceDir" ] ; then
		PrintUsage;
		exit 1;
	fi

	if [ -z "$_objDir" ]; then
		_objDir="${_buildDir}/obj";
	fi

	if [ -z "$_cmdDir" ]; then
		_cmdDir="${_buildDir}/cmd";
	fi

	# ensure the cmd dir is empty
	DieIfFails DeleteAllFiles "$_cmdDir";

	if [ -z "$_npp" ]; then
		_npp=$(npproc.sh);
		if [ $? -ne 0  ]; then
			Die "unable to retrieve the number of physical processors";
		fi	
	fi

	if [ -z "$_inSourceTreeBuild" ]; then
		DieIfFails mkdir -p "$_objDir";
	else
		_objDir="$_sourceDir";
	fi

	Log 'Getting ready to build...'
	printf '
source dir:       "%s"
obj dir:          "%s"
configure-options "%s"
dest dir          "%s"
jobs (-j)         "%i"

environment variables
%s\n' \
	"$_sourceDir" \
	"$_objDir" \
	"$_configureOptions" \
	"$_destDir" \
	"$_npp" \
	"$(printenv | sort)";
}


SaveCommandScript()
{
	local fileName="${_cmdDir}/$1";
	shift;

	DieIfFails mkdir -p "$_cmdDir";

	DieIfFails rm -f "$fileName";

	# we cannot use a for loop here, at least not like this, because it would
	# break $e on each space in the variable value
	#for e in $(printenv | sort); do
	#	DieIfFails printf 'export %s\n' "$e" >> "$fileName";
	#done
	printenv | sort | while IFS= read -r line; do
	  DieIfFails printf 'export %s\n' "$line" >> "$fileName";
	done
	
	printf '\n' >> "$fileName";
	DieIfFails printf '%s ' "$@" >> "$fileName";
}


Configure()
{
	Log "Configuring...";

	if [ ! -z "$_noConfigure" ]; then	
		printf 'Skippiing configure step\n';
		return 0;
	fi

	# ensure obj dir is empty
	if [ "$_objDir" != "$_sourceDir" ]; then
		DieIfFails DeleteAllFiles "$_objDir";
	fi;

	case "$_cmdConfigure" in
		cmake)
			SaveCommandScript 'configure.sh' \
				cmake \
				-S="$_sourceDir" \
				-B="$_objDir" \
				-G="Unix Makefiles" \
				$_configureOptions;
		
			DieIfFails cmake \
				-S="$_sourceDir" \
				-B="$_objDir" \
				-G="Unix Makefiles" \
				$_configureOptions;
		;;
		meson)
			_configureOptions="-D b_colorout=auto $_configureOptions";
			
			SaveCommandScript 'configure.sh' "cd $_sourceDir;" meson setup "${_objDir}" $_configureOptions;
		
			DieIfFails cd "$_sourceDir";
			DieIfFails meson setup "${_objDir}" $_configureOptions;
			
		;;
		*)	
			SaveCommandScript 'configure.sh' "cd $_objDir;" "${_sourceDir}/${_cmdConfigure}" $_configureOptions;
			
			DieIfFails cd "$_objDir";
			DieIfFails "${_sourceDir}/${_cmdConfigure}" $_configureOptions;
			
		;;
	esac
}


Build()
{
	Log "Building...";

	local startTime=$(date '+%s');
	
	if [ ! -z "$_noBuild" ]; then
		printf 'Skippiing build step\n';
		return 0;
	fi
	
	SaveCommandScript 'build.sh' \
		$_cmdBuild \
		-C "$_objDir" \
		-j "$_npp" \
		$_buildOptions

	DieIfFails $_cmdBuild \
		-C "$_objDir" \
		-j "$_npp" \
		$_buildOptions

	local endTime=$(date '+%s');

	local totalTime=$((endTime - startTime));

	printf '\nbuild time: %02i:%02i:%02i\n' \
		"$((totalTime / 3600))" \
		"$((totalTime % 3600 / 60))" \
		"$((totalTime % 60))"
}


InstallToDestDir()
{
	Log 'Installing...';

	if [ ! -z "$_noInstall" ]; then
		printf 'Skippiing install step\n';
		return 0;
	fi

	local destDir=;
	if [ ! -z "$_destDir" ]; then
		printf 'installing to "%s"\n' "$_destDir";
		destDir="DESTDIR=$_destDir";

		# ensure the dir is empty
		if [ -z "$_noDelete" ]; then
			DieIfFails DeleteAllFiles "$_destDir";
		fi
	fi

	case "$_cmdInstall" in		
		meson)
			SaveCommandScript 'install.sh' \
				$_installOptions \
				${_destDir:+--destdir "$_destDir"} \
				--no-rebuild \
				--strip \
				-C "$_objDir";
		
			 DieIfFails meson \
				$_installOptions \
				${_destDir:+--destdir "$_destDir"} \
				--no-rebuild \
				--strip \
				-C "$_objDir" \
				;				
		;;
		*)	
			SaveCommandScript 'install.sh' \
				-C "$_objDir" \
				$destDir \
				$_installOptions;
			
			DieIfFails "$_cmdInstall" \
				-C "$_objDir" \
				$destDir \
				$_installOptions;
		;;
	esac
}




Done()
{
	Log "Done!";
}




ParseCommandLine "$@";
ValidateCommandLine;
Configure;
Build;
InstallToDestDir;
Done;
