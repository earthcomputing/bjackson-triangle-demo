#!/bin/csh -f
#---------------------------------------------------------------------------------------------
 #  Copyright © 2016-present Earth Computing Corporation. All rights reserved.
 #  Licensed under the MIT License. See LICENSE.txt in the project root for license information.
#---------------------------------------------------------------------------------------------

set frames = frames-triamgle-1539644788248291.json.gz

if ( $#argv > 0 ) then
    set frames = $1:q
else
    echo "usage: $0 : ${frames}"
    exit 1
endif

set wdir = `pwd`

set dir = /tmp/virtual-replay
mkdir -p ${dir}

cat > ${dir}/simulated-triangle-demo.html << 'EOF'
<frameset cols="33%, 33%, 33%">
  <frame src="http://localhost:3000/?machineName=Alice&color=yellow" name="alice">
  <frame src="http://localhost:3001/?machineName=Bob&color=cyan" name="bob">
  <frame src="http://localhost:3002/?machineName=Carol&color=magenta" name="carol">
  <noframes> no frame support ?</noframes>
</frameset>
'EOF'

# set position and logical size
echo "printf '\e[3;0;0t' ; printf '\e[8;15;95t'" > ${dir}/alice-eccf.command
echo "printf '\e[3;0;250t' ; printf '\e[8;15;95t'" > ${dir}/bob-eccf.command
echo "printf '\e[3;0;500t' ; printf '\e[8;15;95t'" > ${dir}/carol-eccf.command

echo "printf '\e[3;700;0t' ; printf '\e[8;15;95t'" > ${dir}/alice-adapt.command
echo "printf '\e[3;700;250t' ; printf '\e[8;15;95t'" > ${dir}/bob-adapt.command
echo "printf '\e[3;700;500t' ; printf '\e[8;15;95t'" > ${dir}/carol-adapt.command

echo 'nodejs '${wdir}/'eccf-server.js Alice 3000 1337' >> ${dir}/alice-eccf.command
echo 'nodejs '${wdir}/'eccf-server.js Bob   3001 1338' >> ${dir}/bob-eccf.command
echo 'nodejs '${wdir}/'eccf-server.js Carol 3002 1339' >> ${dir}/carol-eccf.command

echo 'cd '${wdir}'; ./virtual-adapter.pl -config=blueprint-sim.json -machine=Alice localhost:1337' >> ${dir}/alice-adapt.command
echo 'cd '${wdir}'; ./virtual-adapter.pl -config=blueprint-sim.json -machine=Bob localhost:1338' >> ${dir}/bob-adapt.command
echo 'cd '${wdir}'; ./virtual-adapter.pl -config=blueprint-sim.json -machine=Carol localhost:1339' >> ${dir}/carol-adapt.command

echo "printf '\e[3;0;700t' ; printf '\e[8;9;175t'" > ${dir}/poster.command
echo 'cd '${wdir}'; ./post-frame.pl -config=blueprint-sim.json -delay=1 ' ${frames} >> ${dir}/poster.command

chmod +x ${dir}/*.command

open ${dir}/alice-eccf.command
open ${dir}/bob-eccf.command
open ${dir}/carol-eccf.command

sleep 3

open ${dir}/alice-adapt.command
open ${dir}/bob-adapt.command
open ${dir}/carol-adapt.command

open ${dir}/simulated-triangle-demo.html

# need a delay here for browser network connections
sleep 3

open ${dir}/poster.command
