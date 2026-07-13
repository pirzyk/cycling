#!/bin/ksh
#
# Withings API Reference
#   https://developer.withings.com/api-reference/
#
PROGNAME=$(basename $0)
TMP_FILE=$HOME/tmp/tmp-$PROGNAME.json
SECRETS_FILE=$HOME/ownCloud/bikelog/secrets.env

# Find the last entry we have in our BikeLog DB
DB_DATE=$(sqlite3 --list $HOME/ownCloud/bikelog/db/BikeLog-pirzyk.sqlite "select max(date) from weight")
LASTDATE=$(date -j -f '%Y-%m-%d %H:%M:%S' "${DB_DATE} 00:00:00" +%s)

for arg in $*; do
    case $arg in
	-h)
            print -u2 "Usage: $PROGNAME [-h] [-insert] [-keep] [-yesterday] [-x]"
            exit 0;
            ;;
        -insert) INSERT=1 ;;
        -keep) KEEP=1 ;;
	-x) set -x ;;
        *) print -u2 "Unknown arg ($arg)" ;;
    esac
done

if [ ${KEEP:=0} -eq 0 ]; then
    trap "rm -f $TMP_FILE; exit 0" EXIT
fi

# Get the ACCESS_TOKEN or REFRESH_TOKEN values
. $SECRETS_FILE

# Now update the values
curl -o $TMP_FILE --silent --data "action=requesttoken&grant_type=authorization_code&client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}&refresh_token=${REFRESH_TOKEN}" 'https://wbsapi.withings.net/v2/oauth2'

ACCESS_TOKEN=$(cat $TMP_FILE | jq -r .body.access_token)
REFRESH_TOKEN=$(cat $TMP_FILE | jq -r .body.refresh_token)
# NOTE: The refresh token doesn't seem to get updated,
#       but is always returned in the results
#       so future proof if it does get updated,
#       we record the new value
if [ ${ACCESS_TOKEN:-null} != null -a "${REFRESH_TOKEN:-null}" != null ]; then
    cat > $SECRETS_FILE << EOF
ACCESS_TOKEN=${ACCESS_TOKEN}
REFRESH_TOKEN=${REFRESH_TOKEN}
CLIENT_ID=${CLIENT_ID}
CLIENT_SECRET=${CLIENT_SECRET}
EOF
else
    echo "Could not refresh the access token, exiting"
    cat $TMP_FILE
    exit 1
fi

# Ask for all data since the last date we stored in the BikeLog DB, we will get that last entry (overlapping range).
curl -o $TMP_FILE --silent --header "Authorization: Bearer ${ACCESS_TOKEN}" --data "action=getmeas&meastypes=1,6&lastupdate=${LASTDATE}" 'https://wbsapi.withings.net/measure'

# Find how many days we got returned
days=$(cat $TMP_FILE | jq '.body.measuregrps | length')

# We should always get at least 1 day (the day we have in the DB by chance)
if [ ${days:=0} -lt 1 ]; then
    echo "Could not retrieve weight data (0 days): "
    cat $TMP_FILE
    exit 1
fi

day=0
while [ $day -lt $days ]; do

    # Weight value, type should be 1 per the API (and 6 for the fat percentage):
    #   https://developer.withings.com/api-reference/#tag/measure/operation/measure-getmeas
    w_value=$(cat $TMP_FILE | jq -r ".body.measuregrps[${day}].measures[] | select(.type==1) | .value")
    w_unit=$(cat $TMP_FILE | jq -r ".body.measuregrps[${day}].measures[] | select(.type==1) | .unit")
    f_value=$(cat $TMP_FILE | jq -r ".body.measuregrps[${day}].measures[] | select(.type==6) | .value")
    f_unit=$(cat $TMP_FILE | jq -r ".body.measuregrps[${day}].measures[] | select(.type==6) | .unit")
    d_date=$(cat $TMP_FILE | jq -r ".body.measuregrps[${day}].date")

    if [ ${w_value:-null} != null -a "${w_unit:-null}" != null -a ${f_value:-null} != null -a "${f_unit:-null}" != null ]; then
        # Seems that withings store weight values as grams, so the unit says to covert to kgs
        # There is no info in the result saying this is metric vs imperial
        w_unit=$(( 10 ** ($w_unit * -1) ))
        f_unit=$(( 10 ** ($f_unit * -1) ))

        # Since we are using integer division, we need to get the fractional as a seperate step
        wint=$(( $w_value / $w_unit ))
        wfrac=$(( $w_value % $w_unit ))
        fint=$(( $f_value / $f_unit ))
        ffrac=$(( $f_value % $f_unit ))

        # BUG: doing fractional units, we loose
        #       the leading zeros, so handle that case.
        weight=$(printf "%d.%3.3d" $wint $wfrac)
        fatp=$(printf "%d.%3.3d" $fint $ffrac)

        # Format the d_date so the SQLite DB understands it.
        DAY=$(date -j -r ${d_date} +%Y-%m-%d)

        # TODO: Write to the db directly...
        #       but verify we didn't already record this value
        echo "bin/bikelog-cmd.pl insert weight $DAY ${weight} kg ${fatp}"
        if [ ${INSERT:=0} -eq 1 ]; then
            ( cd $HOME/ownCloud/bikelog; bin/bikelog-cmd.pl insert weight $DAY ${weight} kg ${fatp} )
        fi
    else
        echo "Could not retrieve weight data: "
        cat $TMP_FILE
    fi

    day=$(($day + 1))
done
