#!/bin/bash

DATESTAMP=`date "+%Y-%m-%d-%H-%M-%S"`
MOPIDY_CONFIG="/etc/mopidy/mopidy.conf"
ICECAST_CONFIG="/etc/icecast2/icecast.xml"
MOPIDY_SUDOERS="/etc/sudoers.d/010_mopidy-nopasswd"
EXISTING_CONFIG=false
PYTHON_MAJOR_VERSION=3
PIP_BIN=pip3

function add_to_config_text {
    CONFIG_LINE="$1"
    CONFIG="$2"
    sed -i "s/^#$CONFIG_LINE/$CONFIG_LINE/" $CONFIG
    if ! grep -q "$CONFIG_LINE" $CONFIG; then
		printf "$CONFIG_LINE\n" >> $CONFIG
    fi
}

success() {
	echo -e "$(tput setaf 2)$1$(tput sgr0)"
}

inform() {
	echo -e "$(tput setaf 6)$1$(tput sgr0)"
}

warning() {
	echo -e "$(tput setaf 1)$1$(tput sgr0)"
}


# Update apt and install dependencies
inform "Updating apt and installing dependencies"
apt update
apt install -y  python-pip python-pil python-numpy  python-dev python3-dev libevent-dev libelf-dev libmnl-dev build-essential linux-source gcc make binutils libpq-dev libssl-dev openssl libffi-dev zlib1g-dev python3-pip python3-dev
echo

# Verify python version via pip
inform "Verifying python $PYTHON_MAJOR_VERSION.x version"
PIP_CHECK="$PIP_BIN --version"
VERSION=`$PIP_CHECK | sed s/^.*\(python[\ ]*// | sed s/.$//`
RESULT=$?
if [ "$RESULT" == "0" ]; then
  MAJOR_VERSION=`echo $VERSION | awk -F. {'print $1'}`
  if [ "$MAJOR_VERSION" -eq "$PYTHON_MAJOR_VERSION" ]; then
    success "Found Python $VERSION"
  else
    warning "error: installation requires pip for Python $PYTHON_MAJOR_VERSION.x, Python $VERSION found."
    echo
    exit 1
  fi
else
  warning "error: \`$PIP_CHECK\` failed to execute successfully"
  echo
  exit 1
fi
echo

# Stop mopidy if running
systemctl status mopidy > /dev/null 2>&1
RESULT=$?
if [ "$RESULT" == "0" ]; then
  inform "Stopping Mopidy service..."
  systemctl stop mopidy
  echo
fi


# Add necessary lines to config.txt (if they don't exist)
add_to_config_text "gpio=25=op,dh" /boot/config.txt
add_to_config_text "dtoverlay=hifiberry-dac" /boot/config.txt

if [ -f "$MOPIDY_CONFIG" ]; then
  inform "Backing up mopidy config to: $MOPIDY_CONFIG.backup-$DATESTAMP"
  cp "$MOPIDY_CONFIG" "$MOPIDY_CONFIG.backup-$DATESTAMP"
  EXISTING_CONFIG=true
  echo
fi

# Install apt list for Mopidy, see: https://docs.mopidy.com/en/latest/installation/debian/.
if [ ! -f "/etc/apt/sources.list.d/mopidy.list" ]; then
  inform "Adding Mopidy apt source"
  wget -q -O - https://apt.mopidy.com/mopidy.gpg | apt-key add -
  wget -q -O /etc/apt/sources.list.d/mopidy.list https://apt.mopidy.com/buster.list
  apt update && apt upgrade -y
  echo
fi

# Install Mopidy and core plugins for Spotify
inform "Installing mopidy packages"
apt-mark unhold mopidy mopidy-spotify
apt install -y mopidy mopidy-spotify
echo

# Install Mopidy and core plugins for Spotify
inform "Installing mopidy MPD"
apt install mopidy-mpd
echo

# Install Mopidy Iris web UI
inform "Installing Iris web UI for Mopidy"
$PIP_BIN install Mopidy-Iris
echo

# Install Mopidy-Mopidy
inform "Installing Mopidy-Mopidy"
$PIP_BIN install Mopidy-Mopify
echo

# Install Mopidy Spotify Tunigo
inform "Installing Mopidy-Spotify-Tunigo"
$PIP_BIN install mopidy-spotify-tunigo
echo

# Install Mopidy-MPD
inform "Installing Mopidy-MPD"
$PIP_BIN install Mopidy-MPD
echo

# Install Icecast for streaming
inform "Installing Icecast2"
apt-get install icecast2
Echo

# Allow Iris to run its system.sh script for https://github.com/pimoroni/pirate-audio/issues/3
# This script backs Iris UI buttons for local scan and server restart.

# Get location of Iris's system.sh
MOPIDY_SYSTEM_SH=`python$PYTHON_MAJOR_VERSION - <<EOF
import pkg_resources
distribution = pkg_resources.get_distribution('mopidy_iris')
print(f"{distribution.location}/mopidy_iris/system.sh")
EOF`

# Add it to sudoers
inform "Adding $MOPIDY_SYSTEM_SH to $MOPIDY_SUDOERS"
echo "mopidy ALL=NOPASSWD: $MOPIDY_SYSTEM_SH" > $MOPIDY_SUDOERS
echo

# Install support plugins for Pirate Audio
inform "Installing Pirate Audio plugins..."
python3.7 -m pip  install --upgrade Mopidy-PiDi pidi-display-pil pidi-display-st7789 
echo

# Reset mopidy.conf to its default state
if [ $EXISTING_CONFIG ]; then
  warning "Resetting $MOPIDY_CONFIG to package defaults."
  inform "Any custom settings have been backed up to $MOPIDY_CONFIG.backup-$DATESTAMP"
  apt install --reinstall -o Dpkg::Options::="--force-confask,confnew,confmiss" mopidy=$MOPIDY_VERSION > /dev/null 2>&1
  echo
fi

# Append Pirate Audio specific defaults to mopidy.conf
# Updated to only change necessary values, as per: https://github.com/pimoroni/pirate-audio/issues/1
# Updated to *append* config values to mopidy.conf, as per: https://github.com/pimoroni/pirate-audio/issues/1#issuecomment-557556802
inform "Configuring Mopidy"
cat <<EOF >> $MOPIDY_CONFIG

[pidi]
enabled = true
display = st7789

[mpd]
enabled = true
hostname = 0.0.0.0
port = 6600
password =
max_connections = 20
connection_timeout = 60
zeroconf = Mopidy MPD server on $hostname
command_blacklist =
  listall
  listallinfo
default_playlist_scheme = m3u

[http]
enabled = true
hostname = 0.0.0.0
port = 6680
static_dir =
zeroconf = Mopidy HTTP server on $hostname
allowed_origins =
csrf_protection = true


[audio]
mixer_volume = 40
output = tee name=t ! queue ! audioresample ! autoaudiosink t. ! queue ! lamemp3enc ! shout2send async=false mount=mopidy ip=127.0.0.1 port=8000 password=xxxxxxxx
#;output = alsasink device=hw:sndrpihifiberry

[spotify]
enabled = true
username = xxxxxxx
password = xxxxxxxxxx
client_id = xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
client_secret = xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
bitrate = 160
volume_normalization = true
private_session = false
timeout = 10
allow_cache = true
allow_network = true
allow_playlists = true
search_album_count = 20
search_artist_count = 10
search_track_count = 5

[spotify_tunigo]
enabled = true

[mopify]
enabled = true
debug = false

[softwaremixer]
enabled = true

[stream]
enabled = true
protocols =
  http
  https
  mms
  rtmp
  rtmps
  rtsp
metadata_blacklist =
timeout = 5000

EOF
echo

cp /dev/nul  $ICECAST_CONFIG
inform "Configuring IceCast"
cat <<EOF >> $ICECAST_CONFIG

<icecast>
    <!-- location and admin are two arbitrary strings that are e.g. visible
         on the server info page of the icecast web interface
         (server_version.xsl). -->
    <location>PlanetEarth</location>
    <admin>icecast@googl.com</admin>

    <!-- IMPORTANT!
         Especially for inexperienced users:
         Start out by ONLY changing all passwords and restarting Icecast.
         For detailed setup instructions please refer to the documentation.
         It's also available here: http://icecast.org/docs/
    -->

    <limits>
        <clients>100</clients>
        <sources>2</sources>
        <queue-size>524288</queue-size>
        <client-timeout>30</client-timeout>
        <header-timeout>15</header-timeout>
        <source-timeout>10</source-timeout>
        <!-- If enabled, this will provide a burst of data when a client
             first connects, thereby significantly reducing the startup
             time for listeners that do substantial buffering. However,
             it also significantly increases latency between the source
             client and listening client.  For low-latency setups, you
             might want to disable this. -->
        <burst-on-connect>1</burst-on-connect>
        <!-- same as burst-on-connect, but this allows for being more
             specific on how much to burst. Most people won't need to
             change from the default 64k. Applies to all mountpoints  -->
        <burst-size>65535</burst-size>
    </limits>

    <authentication>
        <!-- Sources log in with username 'source' -->
        <source-password>xxxxxxxxxxx</source-password>
        <!-- Relays log in with username 'relay' -->
        <relay-password>xxxxxxxxxx</relay-password>

        <!-- Admin logs in with the username given below -->
        <admin-user>admin</admin-user>
        <admin-password>xxxxxxxxxxxx</admin-password>
    </authentication>

    <!-- set the mountpoint for a shoutcast source to use, the default if not
         specified is /stream but you can change it here if an alternative is
         wanted or an extension is required
    <shoutcast-mount>/live.nsv</shoutcast-mount>
    -->

    <!-- Uncomment this if you want directory listings -->
    <!--
    <directory>
        <yp-url-timeout>15</yp-url-timeout>
        <yp-url>http://dir.xiph.org/cgi-bin/yp-cgi</yp-url>
    </directory>
    -->

    <!-- This is the hostname other people will use to connect to your server.
         It affects mainly the urls generated by Icecast for playlists and yp
         listings. You MUST configure it properly for YP listings to work!
    -->
    <hostname>localhost</hostname>

    <!-- You may have multiple <listen-socket> elements -->
    <listen-socket>
        <port>8000</port>
        <!-- <bind-address>127.0.0.1</bind-address> -->
        <!-- <shoutcast-mount>/stream</shoutcast-mount> -->
    </listen-socket>
    <!--
    <listen-socket>
        <port>8080</port>
    </listen-socket>
    -->
    <!--
    <listen-socket>
        <port>8443</port>
        <ssl>1</ssl>
    </listen-socket>
    -->


    <!-- Global header settings
         Headers defined here will be returned for every HTTP request to Icecast.

         The ACAO header makes Icecast public content/API by default
         This will make streams easier embeddable (some HTML5 functionality needs it).
         Also it allows direct access to e.g. /status-json.xsl from other sites.
         If you don't want this, comment out the following line or read up on CORS.
    -->
    <http-headers>
        <header name="Access-Control-Allow-Origin" value="*" />
    </http-headers>


    <!-- Relaying
         You don't need this if you only have one server.
         Please refer to the documentation for a detailed explanation.
    -->
    <!--<master-server>127.0.0.1</master-server>-->
    <!--<master-server-port>8001</master-server-port>-->
    <!--<master-update-interval>120</master-update-interval>-->
    <!--<master-password>hackme</master-password>-->

    <!-- setting this makes all relays on-demand unless overridden, this is
         useful for master relays which do not have <relay> definitions here.
         The default is 0 -->
    <!--<relays-on-demand>1</relays-on-demand>-->

    <!--
    <relay>
        <server>127.0.0.1</server>
        <port>8080</port>
        <mount>/example.ogg</mount>
        <local-mount>/different.ogg</local-mount>
        <on-demand>0</on-demand>

        <relay-shoutcast-metadata>0</relay-shoutcast-metadata>
    </relay>
    -->


    <!-- Mountpoints
         Only define <mount> sections if you want to use advanced options,
         like alternative usernames or passwords
    -->

    <!-- Default settings for all mounts that don't have a specific <mount type="normal">.
    -->
    <!--
    <mount type="default">
        <public>0</public>
        <intro>/server-wide-intro.ogg</intro>
        <max-listener-duration>3600</max-listener-duration>
        <authentication type="url">
                <option name="mount_add" value="http://auth.example.org/stream_start.php"/>
        </authentication>
        <http-headers>
                <header name="foo" value="bar" />
        </http-headers>
    </mount>
    -->

<mount>
  <mount-name>/mopidy</mount-name>
  <fallback-mount>/silence.mp3</fallback-mount>
  <fallback-override>1</fallback-override>
</mount>

    <!-- Normal mounts -->
    <!--
    <mount type="normal">
        <mount-name>/example-complex.ogg</mount-name>

        <username>othersource</username>
        <password>hackmemore</password>

        <max-listeners>1</max-listeners>
        <dump-file>/tmp/dump-example1.ogg</dump-file>
        <burst-size>65536</burst-size>
        <fallback-mount>/example2.ogg</fallback-mount>
        <fallback-override>1</fallback-override>
        <fallback-when-full>1</fallback-when-full>
        <intro>/example_intro.ogg</intro>
        <hidden>1</hidden>
        <public>1</public>
        <authentication type="htpasswd">
                <option name="filename" value="myauth"/>
                <option name="allow_duplicate_users" value="0"/>
        </authentication>
        <http-headers>
                <header name="Access-Control-Allow-Origin" value="http://webplayer.example.org" />
                <header name="baz" value="quux" />
        </http-headers>
        <on-connect>/home/icecast/bin/stream-start</on-connect>
        <on-disconnect>/home/icecast/bin/stream-stop</on-disconnect>
    </mount>
    -->

    <!--
    <mount type="normal">
        <mount-name>/auth_example.ogg</mount-name>
        <authentication type="url">
            <option name="mount_add"       value="http://myauthserver.net/notify_mount.php"/>
            <option name="mount_remove"    value="http://myauthserver.net/notify_mount.php"/>
            <option name="listener_add"    value="http://myauthserver.net/notify_listener.php"/>
            <option name="listener_remove" value="http://myauthserver.net/notify_listener.php"/>
            <option name="headers"         value="x-pragma,x-token"/>
            <option name="header_prefix"   value="ClientHeader."/>
        </authentication>
    </mount>
    -->

    <fileserve>1</fileserve>

    <paths>
        <!-- basedir is only used if chroot is enabled -->
        <basedir>/usr/share/icecast2</basedir>

        <!-- Note that if <chroot> is turned on below, these paths must both
             be relative to the new root, not the original root -->
        <logdir>/var/log/icecast2</logdir>
        <webroot>/usr/share/icecast2/web</webroot>
        <adminroot>/usr/share/icecast2/admin</adminroot>
        <!-- <pidfile>/usr/share/icecast2/icecast.pid</pidfile> -->

        <!-- Aliases: treat requests for 'source' path as being for 'dest' path
             May be made specific to a port or bound address using the "port"
             and "bind-address" attributes.
          -->
        <!--
        <alias source="/foo" destination="/bar"/>
        -->
        <!-- Aliases: can also be used for simple redirections as well,
             this example will redirect all requests for http://server:port/ to
             the status page
        -->
        <alias source="/" destination="/status.xsl"/>
        <!-- The certificate file needs to contain both public and private part.
             Both should be PEM encoded.
        <ssl-certificate>/usr/share/icecast2/icecast.pem</ssl-certificate>
        -->
    </paths>

    <logging>
        <accesslog>access.log</accesslog>
        <errorlog>error.log</errorlog>
        <!-- <playlistlog>playlist.log</playlistlog> -->
        <loglevel>3</loglevel> <!-- 4 Debug, 3 Info, 2 Warn, 1 Error -->
        <logsize>10000</logsize> <!-- Max size of a logfile -->
        <!-- If logarchive is enabled (1), then when logsize is reached
             the logfile will be moved to [error|access|playlist].log.DATESTAMP,
             otherwise it will be moved to [error|access|playlist].log.old.
             Default is non-archive mode (i.e. overwrite)
        -->
        <!-- <logarchive>1</logarchive> -->
    </logging>

    <security>
        <chroot>0</chroot>
        <!--
        <changeowner>
            <user>nobody</user>
            <group>nogroup</group>
        </changeowner>
        -->
    </security>
</icecast>




EOF
ECHO

# MAYBE?: Remove the sources.list to avoid any future issues with apt.mopidy.com failing
# rm -f /etc/apt/sources.list.d/mopidy.list

usermod -a -G video mopidy

inform "Enabling and starting Mopidy"
systemctl enable mopidy
systemctl restart mopidy

echo
success "All done!"
if [ $EXISTING_CONFIG ]; then
  diff $MOPIDY_CONFIG $MOPIDY_CONFIG.backup-$DATESTAMP > /dev/null 2>&1
  RESULT=$?
  if [ ! $RESULT == "0" ]; then
    warning "Mopidy configuration has changed, see summary below and make sure to update $MOPIDY_CONFIG!"
    inform "Your previous configuration was backed up to $MOPIDY_CONFIG.backup-$DATESTAMP"
    diff $MOPIDY_CONFIG $MOPIDY_CONFIG.backup-$DATESTAMP
  else
    echo "Don't forget to edit $MOPIDY_CONFIG with your preferences and/or Spotify config."
  fi
else
  echo "Don't forget to edit $MOPIDY_CONFIG with you preferences and/or Spotify config."
fi
