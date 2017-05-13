#!/bin/bash

NEXTDIFF=1
while :;
do
  while :;
  do
    wget --quiet -O rss-last.xml https://robertsspaceindustries.com/comm-link/rss
    if [ $(stat --printf="%s" rss.xml) != $(stat --printf="%s" rss-last.xml) ];
    then
      echo `date` Size differs
      break
    else
      echo `date` Size the same, again
    fi
  done
  DIFFFILE=$(printf "rss-different-%04d.xml" ${NEXTDIFF})
  while [ -f ${DIFFFILE} ];
  do
    NEXTDIFF=$(expr ${NEXTDIFF} + 1)
    DIFFFILE=$(printf "rss-different-%04d.xml" ${NEXTDIFF})
  done
  mv -v rss-last.xml ${DIFFFILE}
done
