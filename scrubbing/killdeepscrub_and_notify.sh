#!/bin/bash -l

PK=$(type -p pkill)
CURL=$(type -p curl)

${PK} -9 -f deep-scrubber.sh
if [ "$?" -eq 0 ];
then
  SLACK_WEBHOOK_URL="https://hooks.slack.com/services/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"
  SLACK_CHANNEL=""#ceph-deep-scrubbing""
  SLACK_BOTNAME="nubeliu-scrubber"

  message=":radioactive_sign: I HAD TO KILL deep-scrubber.sh BEFORE PRODUCTION HOURS"
  PAYLOAD="payload={\"channel\": \"${SLACK_CHANNEL}\", \"username\": \"${SLACK_BOTNAME}\", \"text\": \"${message}\"}"
  $CURL --connect-timeout 30 --max-time 60 -s -S -X POST --data-urlencode "${PAYLOAD}" "${SLACK_WEBHOOK_URL}"
fi
