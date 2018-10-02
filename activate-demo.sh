#!/bin/csh -f

set alice = 172.16.1.67
set bob = 172.16.1.40
set carol = 172.16.1.105

cat > /tmp/triangle-demo.html << _eos_
<frameset cols="33%, 33%, 33%">
  <frame src="http://${alice}:3000/?machineName=Alice&color=yellow" name="alice">
  <frame src="http://${bob}:3000/?machineName=Bob&color=cyan" name="bob">
  <frame src="http://${carol}:3000/?machineName=Carol&color=magenta" name="carol">
  <noframes> no frame support ?</noframes>
</frameset>
_eos_

echo 'ssh demouser@'$alice' "cd /home/demouser/earthcomputing/NALDD/entl_test; ./do_demo"' > /tmp/alice.command
echo 'ssh demouser@'$bob' "cd /home/demouser/earthcomputing/NALDD/entl_test; ./do_demo"' > /tmp/bob.command
echo 'ssh demouser@'$carol' "cd /home/demouser/earthcomputing/NALDD/entl_test; ./do_demo"' > /tmp/carol.command

foreach one ( alice bob carol )
    echo $one
    chmod +x /tmp/${one}.command
    open /tmp/${one}.command
end

sleep 5
open /tmp/triangle-demo.html


