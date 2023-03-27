source ./env.sh

PostBuildPython()
{
	Log 'Post build...';

	local package="$1";
	local prefix="$2";
	local destDir="$3";
	#local binDir="$4";
	local envVarsFile="$5";

	if EnvAddPackage "$envVarsFile" "$package"; then
		local path=$(find "${destDir}${prefix}/lib/" -maxdepth 1 -mindepth 1 -name 'python*' -type d );

		local v='PYTHONPATH';
		EnvPathPrepend "$envVarsFile" "$v" "$path";
		EnvPathPrepend "$envVarsFile" "$v" "${path}/site-packages";
	fi	
}
