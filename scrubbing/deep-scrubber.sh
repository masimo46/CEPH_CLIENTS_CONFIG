#!/bin/bash

set -o nounset 
set -o errexit

CEPH=/usr/bin/ceph
AWK=/usr/bin/awk
SORT=/usr/bin/sort
HEAD=/usr/bin/head
DATE=/bin/date
SED=/bin/sed
GREP=/bin/grep
PYTHON=/usr/bin/python
CURL=$(type -p curl)
BC=$(type -p bc)

SLACK_WEBHOOK_URL="https://hooks.slack.com/services/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"
SLACK_CHANNEL=""#ceph-deep-scrubbing""
SLACK_BOTNAME="nubeliu-scrubber"

SLACK_WEBHOOK_URL1="https://hooks.slack.com/services/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"
SLACK_CHANNEL1=""#infra-alerts""

#What string does match a deep scrubing state in ceph pg's output?
DEEPMARK="scrubbing+deep"
#Max concurrent deep scrubs operations
MAXSCRUBS=2

#Set work ratio from first arg; fall back to '7'.
workratio=$1
[ "x$workratio" == x ] && workratio=7
# Set the pool id to scrub PGs, if nothing, defaults to 1
whatpool=$2
[ "x$whatpool" == x ] && whatpool=1

function isNewerThan() {
    # Args: [PG] [TIMESTAMP]
    # Output: None
    # Returns: 0 if changed; 1 otherwise
    # Desc: Check if a placement group "PG" deep scrub stamp has changed 
    # (i.e != "TIMESTAMP")
    pg=$1
    ots=$2
    ndate=$($CEPH pg $pg query -f json-pretty | \
        $PYTHON -c 'import json;import sys; print json.loads(sys.stdin.read())["info"]["stats"]["last_deep_scrub_stamp"]')
    nts=$($DATE -d "$ndate" +%s)
    [ $ots -ne $nts ] && return 0
    return 1
}

function scrubbingCount() {
    # Args: None
    # Output: int
    # Returns: 0
    # Desc: Outputs concurent deep scrubbing tasks.
    cnt=$($CEPH -s | $GREP $DEEPMARK | $AWK '{ print $1; }')
    [ "x$cnt" == x ] && cnt=0
    logger -t ceph_scrub "PGS SCRUBBING NOW --> $cnt"
    echo $cnt
    return 0
}

function waitForScrubSlot() {
    # Args: None
    # Output: Informative text
    # Returns: true
    # Desc: Idle loop waiting for a free deepscrub slot.
    while [ $(scrubbingCount) -ge $MAXSCRUBS ]; do
        sleep 1
    done
    return 0
}

function deepScrubPg() {
    # Args: [PG]
    # Output: Informative text
    # Return: 0 when PG is effectively deep scrubing
    # Desc: Start a PG "PG" deep-scrub
    $CEPH pg deep-scrub $1 >& /dev/null
    #Must sleep as ceph does not immediately start scrubbing
    #So we wait until wanted PG effectively goes into deep scrubbing state...
    local emergencyCounter=0
    while ! $CEPH pg $1 query | $GREP state | $GREP -q $DEEPMARK; do
        isNewerThan $1 $2 && break
        test $emergencyCounter -gt 150 && break
        sleep 1
        emergencyCounter=$[ $emergencyCounter +1 ]
    done
    sleep 2
    return 0
}


function getOldestScrubs() {
    # Args: [num_res] [poolID]
    # Output: [num_res] PG ids
    # Return: 0
    # Desc: Get the "num_res" oldest deep-scrubbed PGs for a specific poolID
    numres=$1
    poolID=$2
    [ x$numres == x ] && numres=20
    $CEPH pg dump pgs 2>/dev/null | \
        $AWK '/^'${poolID}'\.[0-9a-z]+/ { if($10 == "active+clean") {  print $1,$23,$24 ; }; }' | \
        while read line; do set $line; echo $1 $($DATE -d "$2 $3" +%s); done | \
        $SORT -n -k2  | \
        $HEAD -n $numres
    return 0
}

function getPgCount() {
    # Args: [poolID
    # Output: number of total PGs
    # Desc: Output the total number of "active+clean" PGs for a pool id
    poolID=$1
    $CEPH pg dump pgs 2>/dev/null | \
        $AWK '/^'${poolID}'\.[0-9a-z]+/ { if($10 == "active+clean") {  print $1,$23,$24 ; }; }' |
        wc -l
}


#Get PG count
pgcnt=$(getPgCount ${whatpool})
#Get the number of PGs we'll be working on
pgwork=$(echo "${pgcnt}/${workratio}" | bc -l)
pgwork=$(printf "%.0f" ${pgwork})

#Actual work starts here, quite self-explanatory.

message="About to scrub 1/${workratio} of $pgcnt PGs = $pgwork PGs to scrub from Pool ID ${whatpool}"
logger -t ceph_scrub ${message}
PAYLOAD="payload={\"channel\": \"${SLACK_CHANNEL}\", \"username\": \"${SLACK_BOTNAME}\", \"text\": \":wrench: *QUALIFACTS* ${message}\"}"
$CURL --connect-timeout 30 --max-time 60 -s -S -X POST --data-urlencode "${PAYLOAD}" "${SLACK_WEBHOOK_URL}"
PAYLOAD="payload={\"channel\": \"${SLACK_CHANNEL1}\", \"username\": \"${SLACK_BOTNAME}\", \"text\": \":wrench: *QUALIFACTS* ${message}\"}"
$CURL --connect-timeout 30 --max-time 60 -s -S -X POST --data-urlencode "${PAYLOAD}" "${SLACK_WEBHOOK_URL1}"

getOldestScrubs $pgwork $whatpool | while read line; do
    set $line
    waitForScrubSlot
    deepScrubPg $1 $2
done

message=":ok: *QUALIFACTS* Finished deep-scrubbing for Pool ID ${whatpool}"
logger -t ceph_scrub ${message}
PAYLOAD="payload={\"channel\": \"${SLACK_CHANNEL}\", \"username\": \"${SLACK_BOTNAME}\", \"text\": \"${message}\"}"
$CURL --connect-timeout 30 --max-time 60 -s -S -X POST --data-urlencode "${PAYLOAD}" "${SLACK_WEBHOOK_URL}"
PAYLOAD="payload={\"channel\": \"${SLACK_CHANNEL1}\", \"username\": \"${SLACK_BOTNAME}\", \"text\": \":wrench: *QUALIFACTS* ${message}\"}"
$CURL --connect-timeout 30 --max-time 60 -s -S -X POST --data-urlencode "${PAYLOAD}" "${SLACK_WEBHOOK_URL1}"
