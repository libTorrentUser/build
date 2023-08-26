#!/bin/sh


# calling this ensures that no package build script leaves garbages in case it
# is missing some optional function. Using this we do not have to update every 
# single build script when a new function is created. 


PackageBuildDependencies()
{
	return 0;
}


PackageRuntimeDependencies()
{
	return 0;
}


PackageWarnings()
{
	return 0;
}


PackageBuild()
{
	printf 'you forgot to override PackageBuild()!!!\n';
	exit 1;
}


PackagePostBuild()
{
	return 0;
}
