# /etc/pkgusr/skel-u_xdg/.bash_profile
#
# The login profile for SHARED package users -- the ones in the group on your
# XDG runtime directory.  It is what lets a program running as its own account
# reach your display, session bus and audio.
#
# Linked into a shared user's home by:
#     packagemanager user create <name> --shared
#     packagemanager user setup  <name> --shared
#
# XDG_RUNTIME_DIR below is written when the file is first installed, from the
# configured main user.  Edit it if your session lives somewhere else.

# The wrappers directory must be the first entry in the PATH.
# The /tools/bin directory must be the last entry in the PATH and can be
#   removed at the end of Chapter 6.
export PATH=/usr/lib/pkgusr:/bin:/usr/bin:/sbin:/usr/sbin:/tools/bin

# Make prompt reflect that we are a package user.
export PROMPT_COMMAND='PS1="package \u:"`pwd`"> "'

# The session this account is allowed to reach.
export WAYLAND_DISPLAY=wayland-1
#export DISPLAY=:0
#export DBUS_SESSION_BUS_ADDRESS=/dev/null # fake dbus so we dont start one...
export XDG_RUNTIME_DIR=@XDG_RUNTIME_DIR@

# Go to the home directory whenever we su to a package user.
cd

if [ -d "$HOME/bin" ] ; then
  pathprepend $HOME/bin
fi
if [ -d "$HOME/.local/bin" ] ; then
  pathprepend $HOME/.local/bin
fi

for script in /etc/profile.d/*.sh ; do
    if [ -r $script ] ; then
        . $script
    fi
done
