# Andy

Predictive Processing for Lego BrickPi3 robots

Setup:

    https://www.ev3dev.org/downloads/
    https://github.com/resin-io/etcher#debian-and-ubuntu-based-package-repository-gnulinux-x86x64
    http://docs.ev3dev.org/projects/lego-linux-drivers/en/ev3dev-stretch/brickpi3.html#input-ports
    http://docs.ev3dev.org/en/ev3dev-stretch/platforms/brickpi3.html
    Enable sound by editing config.txt in EV3DEV_BOOT on the sd card
    https://www.ev3dev.org/docs/tutorials/setting-up-wifi-using-the-command-line/
    
    Before installing erlang via apt-get install erlang
    > sudo apt-get install -y gnupg
    
    Download and install elixir from https://elixir-lang.org/install.html, add bin to PATH
    
    use vi if nano bugs out
    https://ryanstutorials.net/linuxtutorial/cheatsheetvi.php
    
    to update the brickpi3 firmware: 
    > sudo update-brickpi3-fw

To connect:

    > ssh robot@ev3dev.local
    
To get the source code:

    > git clone https://github.com/jfcloutier/andy.git
    
To update the source code:

    > git checkout master
    > git pull
    
To reset the robot (erase its accumulated experience)

    > rm experience/*

To launch on the robot:

    > ANDY_SYSTEM=brickpi ANDY_PLATFORM=rover iex -S mix
    
To stop the robot and retain newly acquired experience:

    > Andy.shutdown


To test on PC with mock rover: 

    > iex -S mix

