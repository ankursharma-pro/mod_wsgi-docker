#!/usr/bin/env bash

# The master for this script exists in the Python '2.7' directory. Do
# not edit the version of this script found in other directories. When
# the version of the script in the Python '2.7' directory is modified,
# it must then be be copied into other directories. This is necessary as
# Docker when building an image cannot copy in a file from outside of
# the directory where the Dockerfile resides.

# This script will run an interactive bash shell.

# Mark what runtime this is.

WHISKEY_RUNTIME=docker
export WHISKEY_RUNTIME

# Set up the home directory for the application.

WHISKEY_HOMEDIR=/app
export WHISKEY_HOMEDIR

# Set up the data directory for the application.

WHISKEY_DATADIR=/data
export WHISKEY_DATADIR

# Set up the system directory where we keep runtime files.

WHISKEY_TEMPDIR=/.whiskey
export WHISKEY_TEMPDIR

# Set up the user_vars directory where environment variable updates
# can be done.

WHISKEY_ENVDIR=/.whiskey/user_vars
export WHISKEY_ENVDIR

# Override the HOME directory for the user in case it isn't set to
# sensible value.

HOME=/var/www
export HOME

# Make sure we are in the correct working directory for the application.

cd $WHISKEY_HOMEDIR

# Override uid and gid lookup to cope with being randomly assigned IDs
# using the -u option to 'docker run'.

WHISKEY_USER_ID=$(id -u)
WHISKEY_GROUP_ID=$(id -g)

NSS_WRAPPER_PASSWD=$WHISKEY_TEMPDIR/passwd
NSS_WRAPPER_GROUP=$WHISKEY_TEMPDIR/group

cat /etc/passwd > $NSS_WRAPPER_PASSWD
cat /etc/group > $NSS_WRAPPER_GROUP

echo "www-user:x:$WHISKEY_USER_ID:$WHISKEY_GROUP_ID:www-user:/var/www:/sbin/nologin" >> $NSS_WRAPPER_PASSWD
echo "www-user:x:$WHISKEY_GROUP_ID:" >> $NSS_WRAPPER_GROUP

if [ x"$WHISKEY_USER_ID" != x"0" ]; then
    export NSS_WRAPPER_PASSWD
    export NSS_WRAPPER_GROUP

    LD_PRELOAD=/usr/local/nss_wrapper/lib64/libnss_wrapper.so
    export LD_PRELOAD
fi

# Activate the Python virtual environment if one exists. There will only
# be one if the build phase was run. The build phase may not be run if
# some one was using the base image directly to host static files or run
# a minimal WSGI application that was mounted as a volume rather than
# build their own image.

if [ -f $WHISKEY_TEMPDIR/virtualenv/bin/activate ]; then
    source $WHISKEY_TEMPDIR/virtualenv/bin/activate
fi

# Copy environment variable configuration to the system directory used
# for runtime files. This is done so that the '.whiskey/deploy-env' can
# safely add or remove files without modifying the original source code
# directory. This is necessary as the original source code directory
# may not be writable, or could be a mounted directory and we do not
# want to modify any original outside of Docker.

mkdir -p $WHISKEY_ENVDIR

if [ -d .whiskey/user_vars ]; then
    for name in `ls .whiskey/user_vars/*`; do
        cp $name $WHISKEY_ENVDIR
    done
fi

# Docker will have set any environment variables defined in the image or
# on the command line when the container has been run. Here we are going
# to look for any statically defined environment variables provided by
# the user as part of the actual application. These will have been
# placed in the '.whiskey/user_vars' directory. The name of the file
# corresponds to the name of the environment variable and the contents
# of the file the value to set the environment variable to. Each of the
# environment variables is set and exported.

envvars=

for name in `ls $WHISKEY_ENVDIR`; do
    export $name=`cat $WHISKEY_ENVDIR/$name`
    envvars="$envvars $name"
done

# Run any user supplied script to be run to set, modify or delete the
# environment variables.

if [ -x .whiskey/action_hooks/deploy-env ]; then
    echo " -----> Running .whiskey/action_hooks/deploy-env"
    .whiskey/action_hooks/deploy-env
fi

# Go back and reset all the environment variables based on additions or
# changes. Unset any for which the environment variable file no longer
# exists, albeit in practice that is probably unlikely.

for name in `ls $WHISKEY_ENVDIR`; do
    export $name=`cat $WHISKEY_ENVDIR/$name`
done

for name in $envvars; do
    if test ! -f $WHISKEY_ENVDIR/$name; then
        unset $name
    fi
done

# Now finally run bash.

exec bash
