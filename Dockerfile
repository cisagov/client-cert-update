FROM python:slim-stretch
MAINTAINER Shane Frasier <jeremy.frasier@trio.dhs.gov>

# Create unprivileged user
ENV USER=updater \
    USER_HOME=/home/updater
RUN adduser --system --gecos "Client certificate updater user" --group $USER

##
# Make sure pip and setuptools are the latest versions
##
RUN pip install --upgrade pip setuptools

##
# Install client-cert-update python requirements
##
COPY requirements.txt /tmp
RUN pip install -r /tmp/requirements.txt

# Clean up aptitude cruft
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# Put this just before we change users because the copy (and every
# step after it) will often be rerun by docker, but we need to be root
# for the chown command.
COPY email-update.py body.txt body.html $USER_HOME/
RUN chown -R ${USER}:${USER} $USER_HOME

###
# Prepare to Run
###
# USER $USER
WORKDIR $USER_HOME
ENTRYPOINT ["./update.sh"]
