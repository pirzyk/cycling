#!/bin/sh

BASE_DIR=$(pwd)
DB_DIR="${BASE_DIR}/db"
BIN_DIR="${BASE_DIR}/bin"
INIT_DIR="${BASE_DIR}/init"
CACHE_DIR="${BASE_DIR}/cache"
API_KEY=.google-api.key                 # Generated at https://console.cloud.google.com/apis/credentials

usage() {
    echo "Usage: [-hx ] $0 WHO OP [ ... ]";
    echo "WHO is the name of the group/database, required"
    echo "Where OP is either:"
    echo "    clear                 Clears certain templ files in the system"
    echo "         cache [URL ...]  Clears the cache (loaded by fetch) or single results"
    echo "    fetch URL             Fetch the race results in the google sheet represented by URL"
    echo "    process URL           Process the race results in URL"
    echo "    report                Generate a report from the database"
    echo "         age              Generate a report of year born of all the racers"
    echo "         cache            Generate a report of the cache files we have downloaded"
    echo "         event            Generate a report of all the events"
    echo "         race EVENT_ID    Generate a report of the race results from a given event"
    echo "         team             Generate a list of known teams"
    echo "         team_roster      Generate a current team roster"
    echo "    reset                 Reset the WHO database"
    echo "         All              Don't save the team[_alias] and racer[_alias] tables when doing the reset\n"
    echo ""
    echo "URL can be the Google sheet URL or just the SHEETID"
    exit 0;
}

# Normal google sheet URLs look like this:
#   https://docs.google.com/spreadsheets/d/1goSmm4f2fw8AtDwvBBAv7Al9cZi2MJVUfvkBPfP8ByQ/edit <maybe with some extra arguments here>
#
# NOTE: This routine should be a no-op if the argument passed in is just a google sheet id
get_sheet_id() {
    id=$(echo $1 | sed -e 's,^https://docs.google.com/spreadsheets/d/,,' -e 's,/edit.*$,,')

    echo $id
}

get_api_key() {
    if [ -f "${BASE_DIR}/${API_KEY}" ]; then
        file="${BASE_DIR}/${API_KEY}"
    elif [ -f "${HOME}/${API_KEY}" ]; then
        file="${HOME}/${API_KEY}"
    else
        echo "Could not find Google API key (${API_KEY})"
        exit 1
    fi

    cat $file
}

# Internal routine we use to fetch both json files
_fetch_file() {
    wget -q -O "$2" "$1"
    err=$?
    if [ $err -ne 0 ]; then
        echo "Failed to fetch file ($2) from ($1) ($err)"
        exit $err
    fi
}

# Fetch sheet metadata via:
#   https://sheets.googleapis.com/v4/spreadsheets/{SPREADSHEET_ID}?alt=json&key={API_KEY}
# Fetch the results via (per tab):
#   https://sheets.googleapis.com/v4/spreadsheets/{SPREADSHEET_ID}/values/{TAB}!A1:Z?alt=json&key={API_KEY}
#
# See https://developers.google.com/workspace/sheets/api/reference/rest
fetch() {
    if [ $# -eq 0 ]; then
        usage
    fi

    IDS=''
    for URL in $*; do
        API_KEY=$(get_api_key)
        SHEETID=$(get_sheet_id $URL)
        IDS="${IDS} ${SHEETID}"

        # If we already have the results in the cache, just skip
        if [ ! -f "${CACHE_DIR}/${SHEETID}.json" ]; then
            _fetch_file "https://sheets.googleapis.com/v4/spreadsheets/${SHEETID}?alt=json&key=${API_KEY}" "${CACHE_DIR}/${SHEETID}.json"
        fi

        # Now fetch each tab in the spreadsheet (without quotes)
        jq -r '.sheets.[].properties.title' "${CACHE_DIR}/${SHEETID}.json" | while read tab; do
            if [ ! -f "${CACHE_DIR}/${SHEETID}-${tab}-values.json" ]; then
               _fetch_file "https://sheets.googleapis.com/v4/spreadsheets/${SHEETID}/values/${tab}!A1:Z?alt=json&key=${API_KEY}" "${CACHE_DIR}/${SHEETID}-${tab}-values.json"
            fi
        done
    done

    echo $IDS
}

while getopts hx arg; do
    case $arg in
        h|\?) usage ;;
        x) set -x ;;
    esac
done
shift $(( $OPTIND - 1 ))

if [ $# -lt 2 ]; then
    usage
fi

# Who's results are we processing
WHO=$1
OP=$2
shift 2;

# The Database is defined by the $WHO
DB=${DB_DIR}/${WHO}.sqlite

case $OP in
    reset)
        # Dump certain tables to restore after schema update. Order is important (for restoriation WRT to foriegn keys)
        #   Team needs to be before racer and *_alias needs to be after the base table.
        TABLES='team team_alias racer racer_alias'
        if [ "$1" != 'All' ]; then
            SQL='.mode insert'
            for table in $TABLES; do
                SQL="$SQL
                    .output db/${table}.dump
                    select * from ${table};
                "
            done
            echo $SQL | sqlite3 $DB
        fi

        rm -f $DB

        # setup the initial DB schema and some initialization data.
        sqlite3 $DB < ${INIT_DIR}/schema.sql
        err=$?
        if [ $err -ne 0 ]; then
            echo "Error in loading initialization data into the DB ($err)"
            exit $err;
        fi

        # Do we have a custom script to generate more initialization data?
        script="${INIT_DIR}/${WHO}-generate-data"
        if [ -x $script ]; then
            $script
            err=$?
            if [ $err -ne 0 ]; then
                echo "Error in generating additional initialization data ($err)"
                exit $err;
            fi
        else
            for ext in sh pl py; do
                if [ -x "${script}.${ext}" ]; then
                    "${script}.${ext}"
                    err=$?
                    if [ $err -ne 0 ]; then
                        echo "Error in generating additional initialization data ($err)"
                        exit $err;
                    fi
                fi
            done
        fi

        # Load WHO specific initialization data.
        for file in ${INIT_DIR}/${WHO}*.sql; do
            if [ -f $file ]; then
                sqlite3 $DB < $file
                err=$?
                if [ $err -ne 0 ]; then
                    echo "Error in loading additional initialization data into the DB ($err)"
                    exit $err;
                fi
            fi
        done

        # TODO: Figure out what .sql files to clean up (generated  above)

        # Restore the dumped data
        if [ "$1" != 'All' ]; then
            for table in $TABLES; do
                sqlite3 $DB < db/${table}.dump
                # rm -f db/${table}.dump
            done
        fi
        ;;

    fetch)
        # Ignore the converted URL to spreadsheetId values we send back
        fetch $* > /dev/null
        ;;

    process)
        # The fetch process will convert all URLs to spreadsheetId values
        IDS=$(fetch $*)

        # TODO: process the cache files (probably a .pl file under bin/)
        for id in $IDS; do
            bin/process-spreadsheet.pl --sheet ${id} --db $WHO
        done
        ;;

    report)
        if [ "$1" = '' ]; then
            usage
        elif [ $1 = 'age' ]; then
            sqlite3 -box $DB "SELECT first_name, last_name, year_born FROM racer ORDER BY year_born;"
        elif [ $1 = 'cache' ]; then
            for f in cache/*.json; do
                case $f in
                    *-values.json ) ;;
                    *)
                        jq  '.spreadsheetId, .properties.title' $f | xargs
                        ;;
                esac
            done
        elif [ $1 = 'event' ]; then
            sqlite3 -box $DB "SELECT id, name, event_date, google_spreadsheet_id FROM event ORDER BY event_date;"
        elif [ $1 = 'race' ]; then
            sed -e "s/%%event_id%%/${2}/" < bin/report_results.sql | sqlite3 $DB
        elif [ $1 = 'team' ]; then
            sqlite3 -box $DB "SELECT distinct name, abreviation FROM team ORDER BY name;"
        elif [ $1 = 'team_roster' ]; then
            sqlite3 -box $DB "
                SELECT team.name as 'Team Name',
                       racer.first_name,
                       racer.last_name,
                       racer.team_start_date AS Since
                FROM team,
                     racer
                WHERE team.id = racer.fk_team_id
                ORDER BY team.name, Since, last_name, first_name"
        fi
        ;;

    clear)
        if [ "$1" = '' ]; then
            usage
        elif [ $1 = 'cache' ]; then
            shift 1;

            # The clean the entire cache case
            if [ $# -eq 0 ]; then
                rm -f ${CACHE_DIR}/*.json
            else
                for sheet_id in $*; do
                    rm -f ${CACHE_DIR}/${sheet_id}*.json
                done
            fi
        fi
        ;;

    *)
        echo "Don't know what to do with ($OP)"
        exit 1
        ;;
esac

exit 0
