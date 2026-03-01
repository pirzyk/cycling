#!/bin/ksh
#
# Withings API Reference
#   https://developer.withings.com/api-reference/
#
PROGNAME=$(basename $0)
TMP_FILE=$HOME/tmp/tmp-$PROGNAME.json
SECRETS_FILE=$HOME/git/pywithings/secrets.env
DAY='today'
START_DATE=$(date -j $(date +%m%d0000) +%s)
END_DATE=$(date -j $(date -v+1d +%m%d0000) +%s)

for arg in $*; do
    case $arg in
	-h)
            print -u2 "Usage: $PROGNAME [-h] [-insert] [-keep] [-yesterday] [-x]"
            exit 0;
            ;;
        -insert) INSERT=1 ;;
        -keep) KEEP=1 ;;
        -yesterday)
            END_DATE=$START_DATE
            START_DATE=$(date -j $(date -v-1d +%m%d0000) +%s)
            DAY=yesterday
            ;;
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

# TODO: Handle case where we might not have updated in a few days
#       like on vacation or so
curl -o $TMP_FILE --silent --header "Authorization: Bearer ${ACCESS_TOKEN}" --data "action=getmeas&meastype=1&startdate=${START_DATE}&enddate=${END_DATE}" 'https://wbsapi.withings.net/measure'

value=$(cat $TMP_FILE | jq -r .body.measuregrps[0].measures[0].value)
unit=$(cat $TMP_FILE | jq -r .body.measuregrps[0].measures[0].unit)
# Verify we got a weight value, should be 1 per the API:
#   https://developer.withings.com/api-reference/#tag/measure/operation/measure-getmeas
tpe=$(cat $TMP_FILE | jq -r .body.measuregrps[0].measures[0].type)
if [ ${tpe:-null} -eq 1 -a ${value:-null} != null -a "${unit:-null}" != null ]; then
    # Seems that withings store weight values as grams, so the unit says to covert to kgs
    # There is no info in the result saying this is metric vs imperial
    unit=$(( 10 ** ($unit * -1) ))

    # Since we are using integer division, we need to get the fractional as a seperate step
    weight=$(( $value / $unit ))
    frac=$(( $value % $unit ))

    # TODO: Write to the db directly...
    #       but verify we didn't already record this value
    echo "bin/bikelog-cmd.pl insert weight $DAY ${weight}.${frac} kg"
    if [ ${INSERT:=0} -eq 1 ]; then
        ( cd $HOME/ownCloud/bikelog; bin/bikelog-cmd.pl insert weight $DAY ${weight}.${frac} kg )
    fi
else
    echo "Could not retrieve weight data: "
    cat $TMP_FILE
fi
