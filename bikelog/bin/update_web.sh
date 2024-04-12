#!/bin/sh

FILE=$HOME/Public/mileage.js
FILE2=$HOME/Public/time.js
REMOTE_DIRS="amigo.home.pirzyk.org:/usr/local/www/wordpress/static/mileage
    stitch.vpn.pirzyk.org:/usr/local/www/html-www.pirzyk.org/static/mileage"
YEAR=`date "+%Y"`
FILES="$FILE $FILE2"

d=`dirname $0`

# FIXME the location of bikelog-cmd.pl and format_mileage_js.pl
if [ $# -eq 0 ]; then
	MILES=`$d/bikelog-cmd.pl report ride mileage this year`
	TIME=`$d/bikelog-cmd.pl report trainer time this year`
	$d/format_mileage_js.pl ${MILES:='0.00'} > $FILE
	if [ ${MILES} != '0.00' ]; then
		$d/bikelog-cmd.pl graph ride this year groupby month
		mv bikelog.ride.png bikelog.ride.$YEAR.png
		FILES="$FILES bikelog.ride.$YEAR.png"
	fi
	$d/format_time_js.pl ${TIME:='0:00:00'} > $FILE2
	if [ ${TIME} != '0:00:00' ]; then
		$d/bikelog-cmd.pl graph trainer time this year groupby month 
		mv bikelog.trainer.png bikelog.trainer.$YEAR.png
		FILES="$FILES bikelog.trainer.$YEAR.png"
	fi
	if [ ${MILES} != '0.00' -a ${TIME} != '0:00:00' ]; then
		$d/bikelog-cmd.pl graph time this year groupby month 
		mv bikelog.time.png bikelog.time.$YEAR.png
		FILES="$FILES bikelog.time.$YEAR.png"
	fi
else 
	$d/format_mileage_js.pl $1 > $FILE
	$d/format_time_js.pl $2 > $FILE2
fi
for location in ${REMOTE_DIRS}; do
    scp $FILES $location
done

exit $?
