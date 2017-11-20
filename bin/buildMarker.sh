#!/bin/sh
#
# Build a list of helper models for marking taxiways. Only needed once.
# A more dynamic solution is preferrable, but not yet known.
# 
#

checkrc() {
	if [ $1 != 0 ]
	then
		echo "exit due to exit code != 0"
		exit $1
	fi
}

if [ ! -r README.md ]
then
    error "not in base directory"
fi

buildMarker() {
    for i in 0 1 2 3 4 5 6 7 8 9
    do
        for j in 0 1 2 3 4 5 6 7 8 9
        do
            for k in 0 1 2 3 4 5 6 7 8 9
            do
            typeset -i meter
            meter=$i*100+$j*10+k
            echo "AC3Db
MATERIAL \"yellow\" rgb 1 1 0 amb 1 0 0 emis 1 0 0 spec 0 0 0 shi 0 trans 0.1
OBJECT world
kids 1
OBJECT poly
name \"x\"
numvert 2
-$meter 0 0
0 0 0
numsurf 1
SURF 0x02
mat 0
refs 2
0 0 0
1 0 0
kids 0" > GroundServices/markerpool/segment$meter.ac
            done
        done
    done
}

buildMarker

exit 0
