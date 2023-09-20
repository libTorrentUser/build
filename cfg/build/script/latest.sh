#!/bin/sh


_baseURL=;
_githubRegex=;
_gnomeIgnore8x=;
_gnomeIgnore9x=;
_host=;
_noDownload=;
_tmpDir=;
_urlTar=;
_versionMajor=;

_tarExtensions="xz gz bz bz2";


. ./lib.sh


PrintUsage()
{
	local usage='latest.sh -b=buildDir -p=package [some host or url] 

-b
--build-dir
	directory where the archive with the source code will be downloaded and 
	extracted.

--github-regex
	the github latest release API
	https://api.github.com/repos/user/project/releases/latest
	usually list more than one file file. By default this script will use the
	first "browser_download_url" containing a tar with one of the extensions
	inside the $_tarExtensions variable. If that is not the archive you want,
	you can provide a regular expression that can filter the API call and return
	the archive you need. The regular expression must return the URL inside a
	pair of double quotes. There is no problem if there is garbage before and
	after the quoted string, as long as there is a quoted string. This option
	must be used in conjunction with --host="github". See the comments on --host
	for more info.

--gnome-ignore8x
	see --gnome-ignore9x
	
--gnome-ignore9x
	useful when dealing with GTK related packages because GTK devs are insane
	and decided that the .9x branches are actualy betas of the next major 
	version.

--host
	lots of source codes are stored in very popular hosts. That (sometimes) 
	makes it easier to retrieve the latest version of a certain package. When
	you use the --host option, you do not have to pass an URL (--url), because
	it will be inferred from the host name. The host name can be any of the
	following values
	
	"github"
	the package is hosted on github and is using its "release" feature. I.e.
	https://api.github.com/repos/{user/project}/releases/latest
	That means we can use github APIs to retrieve the lateted source code. When using
	this flag, the value of --package must be "user/project". For 
	instance, in order to build zstd, --package must be "facebook/zstd". If the
	package is not using the "release" feature, this will fail. Some github
	projects have more than one archive per release. If the script is not 
	selecting the correct one, you can use --github-regex to specify a regular
	expression capable of selected the one you need.

	"github-master"
	retrieve the latest commit on the master branch.

	"github-tag"
	same as "github", but the project is using tags instead of releases

	"gitlab"
	package is hosted on gitlab and the latest source code can be retrieved
	using the "latest release" API, like this
	https://gitlab.freedesktop.org/api/v4/projects/{projectID}/releases/permalink/latest
	When using this flag, the value of --packge must be the gitlab project ID.
	This ID is a number and should be visible right below the project name on
	its gitlab page. For instance, 1205 is the ID of the shared-mime-info project
	and you can confirm it by going to 
	https://gitlab.freedesktop.org/xdg/shared-mime-info

	"gnome"
	package is hosted on gnome servers, i.e., 
	https://download.gnome.org/sources/{package}	
	You can use --version-major to filter out undesired versions. For instance,
	GTK related packages are usually incompatible when the major version 
	changes. In fact, the most recent major is often a beta release. Without
	using --version-major, the script would go for the most recent version. But
	if you want/need to stick to a specific version, like GTK3 and related 
	packages, you can use --version-major=3. This will make the script ignore
	all releases that are not from v3. You will also probably want to use 
	--gnome-ignore9x, becaues GTK devs are insane and decided that .9x branches
	are supposed to be betas of the next major version. Crazy... And, for the
	same reason, you can also use --gnome-ignore8x
	
	"gnu"
	package is hosted on GNU server, i.e,
	ftp.gnu.org/gnu/{package}"

	"pypi"
	package is hosted on pypi.org and can be retrieved using
	https://pypi.org/project/{package}/#files

	"sourceforge"
	package is hosted on Sourforce and the latest released version can be 
	retrieved using
	https://sourceforge.net/projects/{package}/best_release.json

	"sourceforge-snapshot"
	package is hosted on Source forge and either it is not using the "release"
	feature (see above) or you just want the latest source snapshot, which can
	be retrieved using
	https://sourceforge.net/p/{package}/code/HEAD/tarball

--no-download
	just retrieve the latest source code URL, but do not download it

-p
--package
	name of the package you want to get the latest source code version. When
	using the --host option, you may have to provide more than just the package
	name. See --host for more info.

-u
--url
	url to a web page containing links to one or more releases of --package

-v=
--version-major=
	using this with some hosts (like gnome) allows you to filter out any release
	not belonging to a specific major version.

';

	printf '%s\n' "$usage" 1>&2;
}



ParseCommandLine()
{
	for i in "$@"; do
		case $i in
			-b=*|--build-dir=*)
				_buildDir="$(MkDirReadLinkF ""${i#*=}"")";
			;;
			--github-regex=*)
				_githubRegex="${i#*=}";
	      	;;
	      	--gnome-ignore8x)
				_gnomeIgnore8x=1;
	      	;;
	      	--gnome-ignore9x)
				_gnomeIgnore9x=1;
	      	;;
	      	-h|--help)
	      		PrintUsage;
	      	;;
	      	--host=*)
	      		_host="${i#*=}";
	      	;;
	      	--no-download)
	      		_noDownload=1;
	      	;;
	     	-p=*|--package=*)
				_package="${i#*=}"
			;;
			-u=*|--url=*)
				_baseURL="${i#*=}";
				_baseURL="${_baseURL%/}";
			;;
			-v=*|--version-major=*)
				_versionMajor="${i#*=}";
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
	local hasURL="${_baseURL}${_host}"
	
	if [ -z "$_buildDir" ] || [ -z "$hasURL" ] || [ -z "$_package" ]; then
		PrintUsage;
		exit 1;
	fi	

	if [ -z "$_tmpDir" ]; then
		_tmpDir="${_buildDir}/tmp";
	fi
}



Scan()
{		
	local downloadAttempts=3;
	local content=;
	while true; do
		content=$(Download "${_baseURL}/");
		downloadAttempts=$((downloadAttempts - 1));

	  	if [ -n "$content" ] || [ "$downloadAttempts" -eq 0 ]; then
	  		break;
	  	fi;
	done
	
	# get the latest tar
	local latestVersion;
	local latestVersionExt;	
	for ext in $_tarExtensions; do
		#printf 'ext=%s\nlatestVersion=%s\nlatestVersionExt=%s\n' "$ext" "$latestVersion" "$latestVersionExt" 1>&2;
	
		# search for a tar with the current extension. The first grep here has
		# a double quote char (") in the end in order to not mistakenly match
		# similar extensions, like bz and bz2. 		
		local tarName;		
		tarName=$( \
			printf '%s' "$content" | \
			grep -o "${_package}"'[^"]*\.'"$ext"'"' | \
			grep -v 'rc' | \
			sed 's;\([^"]*\)";\1;');

		# now we will have one or more package-#.#.#.#.tar.ext values. Remove 
		# the extension
		local tarNameNoExt=;
		tarNameNoExt=$(printf '%s' "$tarName" | sed 's;\(.*\)\.'"$ext"'$;\1;');

		# now we have package-#.#.#.#.tar (probably.) So remove the ".tar" if it
		# it exists
		local tarNameNoTarNoExt;
		tarNameNoTarNoExt=$(printf '%s' "$tarNameNoExt" | sed 's;\(.*\)\.tar$;\1;');

		# and now we should have only packge-#.#.#.# and that is something that
		# can be properly sorted with "sort -V"
		tarNameNoTarNoExt=$(printf '%s' "$tarNameNoTarNoExt" | sort -V | tail -n 1);

		# now restore the .tar.ext part
		tarName=$(printf '%s' "$tarName" | grep "$tarNameNoTarNoExt");

		# if one was found, remove the extension and compare the version and
		# keep the latest one stored in {latestVersion} and its extension in
		# {latestVersionExt}
		if [ ! -z "$tarName" ]; then
			if [ ! -z "$latestVersion" ]; then
				# remove the extension
				local version="$tarNameNoTarNoExt";
				local versionExt="${tarName#$version}";
				#printf 'version=%s\nversionExt=%s\n' "$version" "$versionExt" 1>&2;
				

				# use sort in a very hacky way to compare the two versions and
				# store the latest in {version}
				version=$( \
					printf '%s\n%s' "$version" "$latestVersion" | \
					sort -V | \
					tail -n 1);

				# if the {version} is different thant {latestVersion}, it means
				# it is newer
				if [ "$version" != "$latestVersion" ]; then
					latestVersion="$version";
					latestVersionExt="$versionExt";
				fi
			else
				# first iteration. Just initialize
				latestVersion="$tarNameNoTarNoExt";
				latestVersionExt="${tarName#$latestVersion}";				
			fi
		fi;
	done

	if [ -z "$latestVersion" ]; then
		Die 'unable to retrieve the latest source code version';
	fi

	_tarName="${latestVersion}${latestVersionExt}";

	_urlTar="${_baseURL}/$_tarName";
}


Github()
{
	local url="https://api.github.com/repos/${_package}/releases/latest";
	
	local content="$(Download "$url")";

	local url=;
	if [ ! -z "$_githubRegex" ] ; then
		url=$( \
			printf '%s' "$content" | \
			grep -o "${_githubRegex}" );
	else
		for ext in $_tarExtensions; do
			url=$( \
				printf '%s' "$content" | \
				grep -o 'browser_download_url.*\.tar\.'"$ext"'"' );

			if [ ! -z "$url" ]; then
				break;
			fi;
		done

		# if everything fails, try the tarball_url variable
		if [ -z "$url" ]; then
			url=$( \
				printf '%s' "$content" | \
				grep -o 'tarball_url.*' );
		fi
	fi
	
	_urlTar=$(\
		printf '%s' "$url" | \
		sed 's;.*":[^"]*"\([^"]*\).*;\1;');

	if [ $? -ne 0 ] || [ -z "$_urlTar" ]; then
		Die 'unable to retrieve the latest version tarball URL

content:
'"$content";
	fi	
}


GithubMaster()
{
	_urlTar="https://github.com/${_package}/archive/master.zip";
}


GithubTag()
{
	local url="https://api.github.com/repos/${_package}/tags";
	
	local content="$(Download "$url")";

	local regex="${_githubRegex:-tarball_url.*}";

	local url=;	
	url=$( \
		printf '%s' "$content" | \
		grep -o "${regex}" );
	
	_urlTar=$(\
		printf '%s' "$url" | \
		sed 's;.*":[^"]*"\([^"]*\).*;\1;' | \
		sort -V | \
		tail -n 1);

	if [ $? -ne 0 ] || [ -z "$_urlTar" ]; then
		Die "unable to retrieve the latest version tarball URL";
	fi	
}


Pypi()
{
	local content=$(Download "https://pypi.org/project/${_package}/#files");

	for ext in $_tarExtensions; do
		_urlTar=$(\
			printf '%s' "$content" | \
			grep -o 'href=".*'"$package"'-[^"]*'"$ext"'"' | \
			sed 's;.*"\([^"]*\)";\1;');

		if [ ! -z "$_urlTar" ]; then
			break;
		fi
	done

	if [ $? -ne 0 ] || [ -z "$_urlTar" ]; then
		Die "unable to retrieve the latest version tarball URL";
	fi
}


Sourceforge()
{	
	local url="https://sourceforge.net/projects/$_package/best_release.json";
		
	local content="$(Download "$url")";

	# get all available urls and sort by version number. We must first isolate
	# the package though, because some projects have completely different urls
	# and it we were to sort by the full url we would get wrong results
	local latestVersion=$( \
		printf '%s' "$content" | \
		grep -o 'http[^"]*"' | \
		grep -o "$_package"'-.*\.tar' | \
		sort -V | \
		tail -n 1						
		);

	# now get the url that corresponds to that version. The head -n 1 is needed
	# because projects return duplicated urls
	_urlTar=$( \
		printf '%s' "$content" | \
		grep -o 'http[^"]*"' | \
		grep "$latestVersion" | \
		sed 's;"$;;' | \
		head -n 1
		);
	
	if [ $? -ne 0 ] || [ -z "$_urlTar" ]; then
		Die "unable to retrieve the latest version tarball URL";
	fi	
}


SourceforgeSnapshot()
{
	local url="https://sourceforge.net/p/${_package}/code/HEAD/tarball";

	local content="$(Download "$url")";

	_urlTar=$( \
		printf '%s' "$content" | \
		grep -o 'https://.*code-snapshots[^"]*"' | \
		sed 's;\([^"]*\).*;\1;'
		);

	if [ $? -ne 0 ] || [ -z "$_urlTar" ]; then
		Die "unable to retrieve the latest version snapshot URL";
	fi
}


Gnome()
{
	local baseUrl="https://download.gnome.org/sources/${_package}";
		
	local content=$(Download "${baseUrl}/");

	local latestVersionDir=$(\
		printf '%s' "$content" | \
		grep -o 'href="[0-9]*[^/]*/"' | \
		sed 's;.*"\([^"]*\)/";\1;');

	if [ -n "$_versionMajor" ]; then
		# remove anything not starting if the desired major version.
		latestVersionDir=$(\
			printf '%s' "$latestVersionDir" | \
			grep -o "^${_versionMajor}.*");
	fi

	if [ -n "$_gnomeIgnore9x" ]; then
		# due to what can only be called insanity, GTK devs decided that the .9x
		# branches are supposed to be betas of their next major release. I kid 
		# you not :{ 	
		latestVersionDir=$(\
			printf '%s' "$latestVersionDir" | \
			grep -v '.*\.9[0-9]');
	fi

	if [ -n "$_gnomeIgnore8x" ]; then
		# and you thought the stupidity ended with the .9x issue. Tsc... It 
		# seems that, at least the GTK+3, has also a .8x branch that should be
		# ignored
		latestVersionDir=$(\
			printf '%s' "$latestVersionDir" | \
			grep -v '.*\.8[0-9]');
	fi

	local latestVersionDir=$(\
			printf '%s' "$latestVersionDir" | \
			sort -V | \
			tail -n 1);
		

	if [ -z "$latestVersionDir" ]; then
		Die 'Unable to locate '"$_package"' latest version directory';
	fi;

	local latestVersionDirUrl="${baseUrl}/${latestVersionDir}";	

	local content="$(Download "${latestVersionDirUrl}/")";

	local tarName=;	
	for ext in $_tarExtensions; do
		tarName=$( \
			printf '%s' "$content" | \
			grep -o "${_package}"'[^"]*\.'"$ext" | \
			sort -V | \
			tail -n 1
			);

		if [ ! -z "$tarName" ]; then
			break;
		fi;
	done
	
	if [ $? -ne 0 ] || [ -z "$tarName" ]; then
		Die "unable to retrieve the latest version tarball file name";
	fi	

	_urlTar="${latestVersionDirUrl}/${tarName}";
}


Gnu()
{
	# force http mode, otherwise the server might return a linux like directory
	# listing (curl can do it when dealing with ftp), and that will break the
	# call to Scan()
	#_baseURL="ftp.gnu.org/gnu/$_package";
	_baseURL="https://ftp.gnu.org/gnu/$_package";

	Scan;
}


Gitlab()
{
	# $package should be the project numeric ID. For instance, 
	# "xdg/shared-mimeinfo" ID is 1205. You can discover the project ID by
	# navigating to its gitlab page. It should be there, right after the name.
	local url="https://gitlab.freedesktop.org/api/v4/projects/${_package}/releases/permalink/latest";
	
	local content="$(Download "$url")";

	local url=;	
	for ext in $_tarExtensions; do
		url=$( \
			printf '%s' "$content" | \
			grep -o 'http[^"]*\.tar\.'"$ext" );

		if [ ! -z "$url" ]; then
			break;
		fi;
	done

	if [ $? -ne 0 ] || [ -z "$url" ]; then
		Die "unable to retrieve the latest version tarball URL";
	fi	

	_urlTar="$url";
}


LatestVersion()
{	
	LogErr 'retrieving the latest source code version...';
	
	case "$_host" in
		github)
			Github;
		;;
		github-master)
			GithubMaster;
		;;
		github-tag)
			GithubTag;
		;;
		gitlab)
			Gitlab;
		;;
		gnome)
			Gnome;
		;;
		gnu)
			Gnu;
		;;
		pypi)
			Pypi;
		;;
		sourceforge)
			Sourceforge;
		;;
		sourceforge-snapshot)
			SourceforgeSnapshot;
		;;
		*)
			Scan;
		;;
	esac	

	if [ $? -ne 0  ] || [ -z "$_urlTar" ]; then
		Die "unable to retrieve the latest version url";
	fi	
}


DownloadAndExtract()
{
	if [ ! -z "$_noDownload" ]; then	          
		printf '%s' "$_urlTar";
		exit 0;
	fi

	./download.sh -b="$_buildDir" -u="$_urlTar";
}


ParseCommandLine "$@"
ValidateCommandLine;
LatestVersion;
DownloadAndExtract;

