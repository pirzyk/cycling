#!/bin/sh

cd $HOME/Library/NetAthlon2
for i in *.RAW; do
	file=`basename "$i" .RAW`
	if [ ! -f "${file}.png" ]; then
		na2png "$i"
	fi
done
