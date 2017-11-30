#!/bin/sh
#
# Build release package. Now builds package from git.
# 
#
RELEASE=0.3.0
#`date "+%Y%m%d%H%M"`
DESTFILE=GroundServices-$RELEASE

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

if [ ! -r README.md ]
then
    error "not in base directory"
fi

echo "Building package from HEAD. Be sure to commit last changes. Hit <CR>"
read

rm -f $DESTFILE.zip

# zip from above for including "GroundServices" path
# use git
#cd ..
#zip -q -r GroundServices/$DESTFILE.zip GroundServices/gui/dialogs/groundservices.xml \
#    GroundServices/Nasal/canvasmap Nasal/groundservices/G* \
#    GroundServices/Nasal/groundservices/main.nas \
#    GroundServices/Nasal/groundservices/mathutil.nas \
#    GroundServices/Nasal/groundservices/util.nas \
#    GroundServices/Nasal/groundservices/logger.nas \
#    GroundServices/AI/groundservices.xml \
#    GroundServices/Models/GroundServices -x *.DS_Store*
#checkrc $?

#cd GroundServices
git archive HEAD --prefix=GroundServices/ --format=zip -o $DESTFILE.zip

unzip -l $DESTFILE.zip|sed '1,4d'|awk '{if (length($4)>0) print $4}' |sort > $DESTFILE.content