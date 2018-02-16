#/bin/bash

echo "SCUBBING DISTRIBUTION PER DAY OF THE WEEK"
for date in `ceph pg dump | grep active | awk '{print $20}'`; do date +%A -d $date; done | sort | uniq -c

echo
echo "SCUBBING DISTRIBUTION PER HOUR"
for date in `ceph pg dump | grep active | awk '{print $21}'`; do date +%H -d $date; done | sort | uniq -c
