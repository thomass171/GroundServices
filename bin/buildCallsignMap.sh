#!/bin/sh
#
# Build a map of AI callsign to aircraft model. Needed to find aircraft dimensions.
# 

DESTINATIONFILE=Models/GroundServices/callsignmap.txt

checkrc() {
	if [ $1 != 0 ]
	then
		echo "exit due to exit code != 0"
		exit $1
	fi
}

error() {
	echo $*
    exit 1	
}

if [ -z "$FG_ROOT" ]
then
    error "FG_ROOT not set"
fi

find $FG_ROOT/AI/Traffic.orig -follow -type f -name "*.xml" | xargs egrep "callsign|required-aircraft|model" | awk -F '[<>]' '
{
    #print $2;
    #print $3;
    if ($2 == "model") {
        modelfile = $3;
    }
    if ($2 == "required-aircraft") {
        if (callsign != "") {
            pos = index(model[$3],"/");
            m = substr(model[$3],pos+1);
            pos = index(m,"/");                        
            type = substr(m,0,pos-1);
            print callsign " " type;
            callsign = "";
        }
        else
        {
            model[$3] = modelfile;
        }
    }
    if ($2 == "callsign") {
        callsign = $3;
    }
}' > $DESTINATIONFILE
checkrc $?

exit 0
