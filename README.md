# Andy

Prediction Processing for Lego EV3 robots

cp rel/vm.args.andy rel/vm.args; mix firmware # or cp rel/vm.args.marv rel/vm.args; mix firmware
mix firmware.burn 
or ./upload.sh 192.168.1.181 # SLOW

Top open a console:

Get on WiFi
ssh 192.168.1.181
Type ~. to close it

ISSUES:

UART sensors detectors but not "mounted" under /sys/class/lego-sensor
tacho-motors not detected when plugged into port A

