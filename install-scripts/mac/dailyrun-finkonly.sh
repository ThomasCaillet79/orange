#!/bin/bash
#
# $1 workdir
# $2 force
# $3 local

WORK_DIR=${1:-"/private/tmp"}
FORCE=$2
LOCAL=$3

test -r /sw/bin/init.sh && . /sw/bin/init.sh

export PATH=$HOME/bin:$PATH

if [ $LOCAL ]; then
	PUBLISH_DIR=$WORK_DIR/download
	LOG_DIR=$WORK_DIR/logs
	mkdir -p $PUBLISH_DIR
	mkdir -p $LOG_DIR
else
	PUBLISH_DIR=/Volumes/download
	LOG_DIR=/Volumes/download/buildLogs/osx
fi


if [ ! -e $WORK_DIR ]; then
	mkdir -p $WORK_DIR
fi


if [ ! $LOCAL ]; then
	/Users/ailabc/mount-dirs.sh || { echo "Mounting failed." ; exit 1 ; }
fi

SOURCES_DIR=$PUBLISH_DIR/sources

# Get versions from PKG-INFO files (these are updated by dailyrun-sources.sh)
ORANGE_VERSION=`grep "^Version:" $SOURCES_DIR/Orange.egg-info/PKG-INFO | cut -d " " -f 2`
BIOINFORMATICS_VERSION=`grep "^Version:" $SOURCES_DIR/Orange_Bioinformatics.egg-info/PKG-INFO | cut -d " " -f 2`
TEXT_VERSION=`grep "^Version:" $SOURCES_DIR/Orange_Text_Mining.egg-info/PKG-INFO | cut -d " " -f 2`


# Source filenames
ORANGE_SOURCE="Orange-${ORANGE_VERSION}.tar.gz"
BIOINFORMATICS_SOURCE="Orange-Bioinformatics-${BIOINFORMATICS_VERSION}.tar.gz"
TEXT_SOURCE="Orange-Text-Mining-${TEXT_VERSION}.tar.gz"


# Get source packages md5 checksum
ORANGE_SOURCE_MD5=`md5 -q $SOURCES_DIR/$ORANGE_SOURCE`
BIOINFORMATICS_SOURCE_MD5=`md5 -q $SOURCES_DIR/$BIOINFORMATICS_SOURCE`
TEXT_SOURCE_MD5=`md5 -q $SOURCES_DIR/$TEXT_SOURCE`

MAC_VERSION=`sw_vers -productVersion | cut -d '.' -f 2`
ARCH=`perl -MFink::FinkVersion -e 'print Fink::FinkVersion::get_arch'`


FINK_ROOT=/sw

if [ ! $LOCAL ]; then
	# Compare with the published info files
	BASE="http://orange.biolab.si/fink/dists/10.$MAC_VERSION/main/finkinfo"
else
	# Compare with the local info files
	BASE="file://$FINK_ROOT/fink/dists/local/main/finkinfo"
fi

OLD_ORANGE_VERSION=`curl --silent $BASE/orange-gui-dev-py.info | grep "Version: " | cut -d" " -f 2`
OLD_BIOINFORMATICS_VERSION=`curl --silent $BASE/orange-bioinformatics-gui-dev-py.info | grep "Version: " | cut -d" " -f 2`
OLD_TEXT_VERSION=`curl --silent $BASE/orange-text-gui-dev-py.info | grep "Version: " | cut -d" " -f 2`

if [[ $OLD_ORANGE_VERSION < ORANGE_VERSION ]]; then
	NEW_ORANGE=1
fi

if [[ $OLD_BIOINFORMATICS_VERSION < BIOINFORMATICS_VERSION ]]; then
	NEW_BIOINFORMATICS=1
fi

if [[ $OLD_TEXT_VERSION < TEXT_VERSION ]]; then
	NEW_TEXT=1
fi

# Base url for sources in fink .info files
if [ $LOCAL ]; then
	BASE_URL="file://$PUBLISH_DIR/sources"
else
	BASE_URL="http://orange.biolab.si/download/sources"
fi

# Update the local finkinfo 
# Local info files will be moved to biolab/main/finkinfo in fink-daily-build-packages.sh
FINK_INFO_DIR="$FINK_ROOT/fink/dists/local/main/finkinfo"

if [ ! -e $FINK_INFO_DIR ]; then
	mkdir -p $FINK_INFO_DIR
fi

# Remove any old remaining local .info files
rm -f $FINK_INFO_DIR/orange-*.info

# Directory where fink .info templates are stored
FINK_TEMPLATES=$WORK_DIR/fink

if [ ! -e $FINK_TEMPLATES ]; then
	mkdir -p $FINK_TEMPLATES
fi

FINK_LOG=$WORK_DIR/fink-daily-build.log

echo "" > $FINK_LOG

if [[ $NEW_ORANGE || $FORCE ]]; then
	FINK_ORANGE_SOURCE_TEMPLATE="Orange-%v.tar.gz"
	curl --silent -o $FINK_TEMPLATES/orange-gui-dev-py.info https://bitbucket.org/biolab/orange/raw/tip/install-scripts/mac/fink/orange-gui-dev-py.info
	./fink-register-info.sh "$FINK_TEMPLATES/orange-gui-dev-py.info" $BASE_URL/$FINK_ORANGE_SOURCE_TEMPLATE $ORANGE_SOURCE_MD5 $ORANGE_VERSION $FINK_INFO_DIR/orange-gui-dev-py.info >> $FINK_LOG 2>&1
	FINK_ORANGE_INFO_EXIT_VALUE=$?
fi

if [[ $NEW_BIOINFORMATICS || $FORCE ]]; then
	FINK_BIOINFORMATICS_SOURCE_TEMPLATE="Orange-Bioinformatics-%v.tar.gz"
	curl --silent -o $FINK_TEMPLATES/orange-bioinformatics-gui-dev-py.info https://bitbucket.org/biolab/orange/raw/tip/install-scripts/mac/fink/orange-bioinformatics-gui-dev-py.info
	./fink-register-info.sh "$FINK_TEMPLATES/orange-bioinformatics-gui-dev-py.info" $BASE_URL/$FINK_BIOINFORMATICS_SOURCE_TEMPLATE $BIOINFORMATICS_SOURCE_MD5 $BIOINFORMATICS_VERSION $FINK_INFO_DIR/orange-bioinformatics-gui-dev-py.info >> $FINK_LOG 2>&1
	FINK_BIOINFORMATICS_INFO_EXIT_VALUE=$?
fi

if [[ $NEW_TEXT || $FORCE ]]; then
	FINK_TEXT_SOURCE_TEMPLATE="Orange-Text-Mining-%v.tar.gz"
	curl --silent -o $FINK_TEMPLATES/orange-text-gui-dev-py.info https://bitbucket.org/biolab/orange/raw/tip/install-scripts/mac/fink/orange-text-gui-dev-py.info
	./fink-register-info.sh "$FINK_TEMPLATES/orange-text-gui-dev-py.info" $BASE_URL/$FINK_TEXT_SOURCE_TEMPLATE $TEXT_SOURCE_MD5 $TEXT_VERSION $FINK_INFO_DIR/orange-text-gui-dev-py.info >> $FINK_LOG 2>&1
	FINK_TEXT_INFO_EXIT_VALUE=$?
fi

if [ ! $LOCAL ]; then
	/Users/ailabc/mount-dirs.sh || { echo "Mounting failed." ; exit 1 ; }
fi

EXIT_VALUE=$(($FINK_ORANGE_INFO_EXIT_VALUE + $FINK_BIOINFORMATICS_INFO_EXIT_VALUE + $FINK_TEXT_INFO_EXIT_VALUE))
if (($EXIT_VALUE)); then
	echo "Running fink-register-info.sh failed"
	rm -f $FINK_INFO_DIR/orange-*.info
fi

## daily fink build
if [ ! $LOCAL ]; then
	./fink-daily-build-packages.sh &> $WORK_DIR/fink-daily-build-packages.log
	EXIT_VALUE=$?
fi

if [ ! $LOCAL ]; then
	/Users/ailabc/mount-dirs.sh || { echo "Mounting failed." ; exit 1 ; }
fi

echo "Orange (fink $MAC_VERSION $ARCH) [$EXIT_VALUE]" > "$LOG_DIR/fink-$MAC_VERSION-$ARCH-daily-build.log"
date >> "$LOG_DIR/fink-$MAC_VERSION-$ARCH-daily-build.log"
cat $WORK_DIR/fink-daily-build-packages.log >> "$LOG_DIR/fink-$MAC_VERSION-$ARCH-daily-build.log"
(($EXIT_VALUE)) && echo "Running fink-daily-build-packages.sh failed"

# Zero exit value
true
