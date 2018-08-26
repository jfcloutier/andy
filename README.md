# Andy

Prediction Processing for Lego EV3 robots

    cp rel/vm.args.andy rel/vm.args 
    MIX_TARGET=ev3 mix firmware         # or cp rel/vm.args.marv rel/vm.args; mix firmware
    MIX_TARGET=ev3 mix firmware.burn    # or ./upload.sh 192.168.1.181 # SLOW

Top open a console:

    # Make sure PC connects via WiFi
     ssh 192.168.1.181
    # Type ~. to close it

ISSUES:

* tacho-motors not detected when plugged into port A

To test on PC: 

    > MIX_TARGET=host iex -S mix phx.server

