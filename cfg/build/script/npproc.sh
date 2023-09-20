#!/bin/sh

# returns the number of physical cores in the system. Handles machines with more than one CPU.

# this one you can use in case lscpu is available
# lscpu -b -p=Core,Socket | grep -v '^#' | sort -u | wc -l


# this is the one I came up all by my own. I'm so proud of myself
# cat /proc/cpuinfo | grep -B2 'core id' | sed 's/siblings.*/'/ | tr -d '[:space:]' | sed 's/--/\n/'g | sort -u | wc -l

# and this pretty much like mine, but better. I discovered it just after I finished mine...
cat /proc/cpuinfo | grep -E "core id|physical id" | tr -d "\n" | sed s/physical/\\nphysical/g | grep -v ^$ | sort -u | wc -l
