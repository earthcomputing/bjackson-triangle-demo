#!/bin/csh -f

set frames = frames-triamgle-1539644788248291.json.gz

if ( $#argv > 0 ) then
    set frames = $1:q
endif

set alice = 172.16.1.67
set bob = 172.16.1.40
set carol = 172.16.1.105

set demo_dir = /home/demouser/earthcomputing/NALDD/entl_test
set demo_dir = /home/demouser/earthcomputing/triangle-demo

set wdir = ${demo_dir}

set dir = /tmp/validator
mkdir -p ${dir}

cat > ${dir}/triangle-demo.html << _eos_
<frameset cols="33%, 33%, 33%">
  <frame src="http://${alice}:3000/?machineName=Alice&color=yellow" name="alice">
  <frame src="http://${bob}:3000/?machineName=Bob&color=cyan" name="bob">
  <frame src="http://${carol}:3000/?machineName=Carol&color=magenta" name="carol">
  <noframes> no frame support ?</noframes>
</frameset>
_eos_

echo 'ssh demouser@'${alice}' "nodejs '${wdir}'/eccf-server.js Alice 3000 1337"' > ${dir}/alice-eccf.command
echo 'ssh demouser@'${bob}'   "nodejs '${wdir}'/eccf-server.js Bob   3000 1337"' > ${dir}/bob-eccf.command
echo 'ssh demouser@'${carol}' "nodejs '${wdir}'/eccf-server.js Carol 3000 1337"' > ${dir}/carol-eccf.command

echo 'ssh demouser@'${alice}' "cd '${demo_dir}'; ./adapter Alice"' > ${dir}/alice-adapt.command
echo 'ssh demouser@'${bob}'   "cd '${demo_dir}'; ./adapter Bob"' > ${dir}/bob-adapt.command
echo 'ssh demouser@'${carol}' "cd '${demo_dir}'; ./adapter Carol"' > ${dir}/carol-adapt.command

# Danger : different wdir:
set wdir = `pwd`

echo 'cd '${wdir}'; ./post-frame.pl -config=blueprint-triangle.json -delay=1 ' ${frames} > ${dir}/poster.command

chmod +x ${dir}/*.command

open ${dir}/alice-eccf.command
open ${dir}/bob-eccf.command
open ${dir}/carol-eccf.command

sleep 5

open ${dir}/alice-adapt.command
open ${dir}/bob-adapt.command
open ${dir}/carol-adapt.command

open ${dir}/triangle-demo.html

