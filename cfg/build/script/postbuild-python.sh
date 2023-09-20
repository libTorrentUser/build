. ./env.sh

PostBuildPython()
{
	Log 'Post build...';

	local prefix="$1";
	local rootDir="$2";
	local envVarsFile="$3";

	if EnvAddPackage "$envVarsFile" 'python'; then
		local path=$(find "${rootDir}${prefix}/lib/" -maxdepth 1 -mindepth 1 -name 'python*' -type d );

		local v='PYTHONPATH';
		EnvPathPrepend "$envVarsFile" "$v" "$path";
		EnvPathPrepend "$envVarsFile" "$v" "${path}/site-packages";
	fi	
}
