# Andy

Predictive Processing for Lego BrickPi3 robots

Setup:

    https://www.ev3dev.org/downloads/
    https://github.com/resin-io/etcher#debian-and-ubuntu-based-package-repository-gnulinux-x86x64
    http://docs.ev3dev.org/projects/lego-linux-drivers/en/ev3dev-stretch/brickpi3.html#input-ports

    http://docs.ev3dev.org/en/ev3dev-stretch/andy.platforms/brickpi3.html

        Enable BrickPi
        Uncomment: dtoverlay=brickpi3

        Enable sound by editing config.txt in EV3DEV_BOOT on the sd card
        Uncomment: dtparam=audio=on

    https://www.ev3dev.org/docs/tutorials/connecting-to-ev3dev-with-ssh/
    https://www.ev3dev.org/docs/tutorials/setting-up-wifi-using-the-command-line/

To connect:

    > ssh robot@ev3dev.local
    > ssh robot@andy.local (latest)
    
    password: maker

Before doing `use apt-get`:

    > sudo apt-get update

To update the brickpi3 firmware:

    > sudo update-brickpi3-fw


If you use asdf to install erlang and elixir, first do:

    > sudo apt-get install build-essentials
    > sudo apt-get install autoconf
    > sudo apt-get install libncurses5-dev
    > sudo apt-get install libssl-dev

To install Erlang and Elixir via asdf:

    Install asdf -- See https://asdf-vm.com/#/core-manage-asdf-vm

    > echo -e '\n. $HOME/.asdf/asdf.sh' >> ~/.bashrc
    > echo -e '\n. $HOME/.asdf/completions/asdf.bash' >>  ~/.bashrc # optional
    > source ~/.bashrc

    Then:

    > asdf plugin-add erlang
    > asdf plugin-add elixir
    > asdf install erlang 21.2.2 # Any OTP 21 version should work
    > asdf install elixir 1.8.1-otp-21
    > asdf global erlang 21.2.2
    > asdf global elixir 1.8.1-otp-21

To get the source code for Andy on the Raspberry Pi:

    > git clone https://github.com/jfcloutier/andy.git
    > cd andy
    > mix deps.get
    > mix compile
    
To update the source code:

    > git checkout master
    > git pull
    
To reset the robot (erase its accumulated experience)

    > rm memory.dets

To launch on the robot:

    > ANDY_SYSTEM=brickpi ANDY_PLATFORM=rover ANDY_NAME=andy; iex -S mix
    
To stop the robot and retain newly acquired experience:

    > Andy.shutdown


To test on PC with mock rover named karl, do: 

    > export ANDY_PLAYGROUND='playground@ukemi';iex --sname karl --cookie 'predictive processing' -S mix


