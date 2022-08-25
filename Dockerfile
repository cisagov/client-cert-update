FROM python:3.7.3-slim-stretch

# For a list of pre-defined annotation keys and value types see:
# https://github.com/opencontainers/image-spec/blob/master/annotations.md
# Note: Additional labels are added by the build workflow.
LABEL org.opencontainers.image.authors="jeremy.frasier@trio.dhs.gov"
LABEL org.opencontainers.image.vendor="Cybersecurity and Infrastructure Security Agency"

ARG CISA_GID=421
ARG CISA_UID=${CISA_GID}
ENV CISA_USER="cisa"
ENV CISA_GROUP=${CISA_USER}
ENV CISA_HOME="/home/cisa"

###
# Create unprivileged user
###
RUN groupadd --system --gid ${CISA_GID} ${CISA_GROUP}
RUN useradd --system --uid ${CISA_UID} --gid ${CISA_GROUP} --comment "${CISA_USER} user" ${CISA_USER}

##
# Make sure pip and setuptools are the latest versions
##
RUN pip install --upgrade pip setuptools

##
# Install client-cert-update python requirements
##
COPY src/requirements.txt /tmp
RUN pip install -r /tmp/requirements.txt

# Clean up aptitude cruft
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# Put this just before we change users because the copy (and every
# step after it) will often be rerun by docker, but we need to be root
# for the chown command.
COPY src/email-update.py src/body.txt src/body.html $CISA_HOME/
RUN chown -R ${CISA_USER}:${CISA_USER} $CISA_HOME

###
# Prepare to Run
###
# USER $USER
WORKDIR $CISA_HOME
ENTRYPOINT ["./email-update.py"]
