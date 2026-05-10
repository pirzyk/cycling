#!/usr/bin/env python3

# WORK IN PROGRESS!
#
# This script is designed to compare race envents between different sources
#   WI / IL Cycling association webste (using WPevents)
#   Strava
#   BikeReg
#
# and display and discrepencies when values are set
#   does not yet display missing fields
#
# and eventually update the sources to be in sync
#   TBD: How to determine who is autoratative for each piece of data?

import datetime as dt
import json
import os
import pprint
import re
import requests
import time

# TODO:
#   Fetch events from:
#       Strava
#       Zwift?
#
#   Create/Update events on:
#       WI/IL site
#       Strava
#       Zwift?

# NOTES:

# Strava:
#       Club APIs: https://developers.strava.com/docs/reference/#api-Clubs
#       Though looks like no API to fetch events

# BikeReg:
#   Search API: https://www.bikereg.com/api/EventSearchDoc.aspx
#
# Currently this URL doesn't get all events as the eventtype search seems to be broken
#   Cross check with the web site search: https://www.bikereg.com/events?types=103
#bikereg_url = 'https://www.BikeReg.com/api/search?eventtype=MATTS'
bikereg_url = 'https://www.BikeReg.com/api/search?states=IL,WI&name=MATTS'

# WI/IL Site (WordPress)
#
# https://theeventscalendar.com/knowledgebase/event-tickets-rest-api/
wiilcycle_url = 'https://www.wiilcycle.org/wp-json/tribe/events/v1/events?per_page=30'

# Where we have a 1:1 field mapping
map_fields = {
    'Name':         { 'BikeReg': 'EventName', 'wiilcycle': 'title' },
    'Date':         { 'BikeReg': 'EventDate', 'wiilcycle': 'start_date' },
    'Registration': { 'BikeReg': 'EventUrl', 'wiilcycle': 'website' }
}

# Store all our events with different fields.
race_date_name_ndx = {}
race_date_loc_ndx = {}
race_date_reg_ndx = {}
race_start_list_ndx = {}
race_events = list()

coming_soon_re = re.compile('\\[Coming Soon\\]\\s*', re.I)

# Retrieve the reqeusted JSON data
#   url  - The URL to get the REST API data from
#   msg  - The customizeable part of and messages printed telling the viewer what data was being fetched
#   file - The cached copy of the JSON data from url
#   Returns a python variable with the JSON data loaded
def get_json_data(url, msg, file):
    if os.path.exists(file):
        with open(file) as f:
            print(f"using cached {msg} data")
            data = json.load(f)
            f.close()
            return data
    else:
        print(f"Fetching {msg} data")
        r = requests.get(url)
        if r.status_code == 200:
            data = r.json()
            # Once we get all the JSON data, cache a copy of it
            with open(file, "w") as f:
                f.write(json.dumps(data))
                f.close()
                return data
        else:
            print(f"Error: Failed to retrieve {msg} data. Status Code: {r.status_code}")

def merge_records(ndx, record):
    for k in record.keys():
        if k not in race_events[ndx]:
            race_events[ndx][k] = record[k]

        elif record[k] != race_events[ndx][k]:
            print(f"Need to merge {k} ({record[k]}:{race_events[ndx][k]})")

# Insert or update the race event record
#   record - the current data to be added
# Returns nothing side effect is the race_events variable updated
# TODO:
#   Matching criteria
#       Date & Name
#       Date & Location
#       Date & Registration
#       Start List
#   Create indexes to search in O(1) time
#   Process to update matched events
def add_or_insert(record):
    date = str(dt.datetime.timestamp(record['Date']))
    date_name_str = date + '|' + re.sub(coming_soon_re, '', record['Name'])
    if 'Location' in record:
        date_loc_str = date + '|' + record['Location']
    if 'Registration' in record:
        date_reg_str = date + '|' + record['Registration']
    
    # Do we have this event already?
    if 'Start List' in record and record['Start List'] in race_start_list_ndx:
        ndx = race_start_list_ndx[record['Start List']]
        merge_records(ndx, record)

    elif 'Location' in record and date_loc_str in race_date_loc_ndx: 
        ndx = race_date_loc_ndx[date_loc_str]
        merge_records(ndx, record)

    elif date_name_str in race_date_name_ndx: 
        ndx = race_date_name_ndx[date_name_str]
        merge_records(ndx, record)

    elif 'Registration' in record and date_reg_str in race_date_reg_ndx: 
        ndx = race_date_reg_ndx[date_reg_str]
        merge_records(ndx, record)

    # If all else fails, add the record to the list of events
    #   and update the search indicies
    else:
        ndx = len(race_events)
        race_events.append(record)
        race_date_name_ndx[date_name_str] = ndx
        if 'Location' in record:
            race_date_loc_ndx[date_loc_str] = ndx
        if 'Registration' in record:
            race_date_reg_ndx[date_reg_str] = ndx
        if 'Start List' in record:
            race_start_list_ndx[record['Start List']] = ndx

def process_event(events):
    strava_re = re.compile('https://www.strava.com/segments/[0-9]*', re.I)
    start_list_re = re.compile('"(https://docs.google.com/spreadsheets/[^"]*)"', re.I)
    start_time_re = re.compile('Date.([0-9]*)(-[0-9]*).')
    protocol_re = re.compile('http:', re.I)

    for e in events:
        #pprint.pprint(e)
        # The record we are going to insert/update
        r = {}

        # A BikeReg event record
        if 'EventId' in e:
            t = 'BikeReg'
            r['BikeReg ID'] = e['EventId']
            r['Location'] = e['EventAddress'] + " " + e['EventCity'] + ", " + e['EventState'] + " " + e['EventZip']
            d = re.search(start_time_re, e['EventDate'])

            # NOTE: Looks like this BikeReg timestamp is in UTC
            # group(1) is the unix timestamp in micro seconds
            # group(2) is the timezone designation in (-)HHMM format where MM is effectively 00 (sans special India and some pacific island timezones)
            os.environ['TZ'] = 'UTC'
            time.tzset()
            tz = int(int(d.group(2)) / 100) * 3600 * -1
            r['Date'] = dt.datetime.fromtimestamp(dt.datetime.timestamp(dt.datetime.fromtimestamp(int(int(d.group(1)) / 1000) + tz)))
            m = re.search(strava_re, e['EventNotes'])
            if m:
                r['Segment'] = m.group(0)
            s = re.search(start_list_re, e['EventNotes'])
            if s:
                r['Start List'] = s.group(1)

        # A WP Events Calendar event record
        else:
            t = 'wiilcycle'
            r['WI/IL Cycle ID'] = e['id']
            r['Location'] = e['venue']['address'] + " " + e['venue']['city'] + ", " + e['venue']['state'] + " " + e['venue']['zip']
            # Date is in local (current) timezone
            os.environ['TZ'] = 'US/Chicago'
            time.tzset()
            r['Date'] = dt.datetime.fromisoformat(e['start_date'])
            if 'custom_fields' in e:
                if '_ecp_custom_2' in e['custom_fields']:
                    r['Segment'] = re.sub(protocol_re, 'https:', e['custom_fields']['_ecp_custom_2']['value'])
                if '_ecp_custom_3' in e['custom_fields']:
                    r['Start List'] = re.sub(protocol_re, 'https:', e['custom_fields']['_ecp_custom_3']['value'])

        # Fields that have 1:1 mapping
        r['Name'] = e[map_fields['Name'][t]]
        if map_fields['Registration'][t] in e and len(e[map_fields['Registration'][t]]):
            # Force all Registration URLs to be https
            r['Registration'] = re.sub(protocol_re, 'https:', e[map_fields['Registration'][t]])

        add_or_insert(r)


bikereg_data = get_json_data(bikereg_url, 'BikeReg', 'bikereg.json')
process_event(bikereg_data['MatchingEvents'])

wiilcycle_data = get_json_data(wiilcycle_url, 'WI/IL Cycle', 'wiilcycle.json')
process_event(wiilcycle_data['events'])

#pprint.pprint(race_events)
#pprint.pprint(race_date_name_ndx)
#pprint.pprint(race_date_loc_ndx)
#pprint.pprint(race_date_reg_ndx)
#pprint.pprint(race_start_list_ndx)
