# Andy

Predictive Processing for Lego BrickPi3 robots

Setup:

    https://www.ev3dev.org/downloads/
    https://github.com/resin-io/etcher#debian-and-ubuntu-based-package-repository-gnulinux-x86x64
    http://docs.ev3dev.org/projects/lego-linux-drivers/en/ev3dev-stretch/brickpi3.html#input-ports
    http://docs.ev3dev.org/en/ev3dev-stretch/platforms/brickpi3.html
    Don;t forget to enable sound by editing config.txt in EV3DEV_BOOT on the sd card
    https://www.ev3dev.org/docs/tutorials/setting-up-wifi-using-the-command-line/
    
    Before installing erlang via apt-get install erlang
    > sudo apt-get install -y gnupg
    Install elixir from Precompiled.zip, add bin to PATH
    
    use vi if nano bugs out
    https://ryanstutorials.net/linuxtutorial/cheatsheetvi.php
    
    to update brickpi3 firmware: 
    sudo update-brickpi3-fw

To connect:

    ssh robot@ev3dev.local

ISSUES:


To test on PC: 

    > MIX_TARGET=host iex -S mix phx.server

