FROM python:3.10.7-alpine3.16

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
RUN addgroup --system --gid ${CISA_GID} ${CISA_GROUP} \
  && adduser --system --uid ${CISA_UID} --ingroup ${CISA_GROUP} ${CISA_USER}

##
# Make sure pip, setuptools, and wheel are the latest versions
##
RUN pip install --no-cache-dir --upgrade pip setuptools wheel

##
# Install client-cert-update python requirements
##
COPY src/requirements.txt /tmp
RUN pip install --no-cache-dir --requirement /tmp/requirements.txt

# Put this just before we change users because the copy (and every
# step after it) will often be rerun by docker, but we need to be root
# for the chown command.
COPY src/email-update.py src/body.txt src/body.html $CISA_HOME/
RUN chown --recursive ${CISA_USER}:${CISA_USER} $CISA_HOME

###
# Prepare to Run
###
# USER $USER
WORKDIR $CISA_HOME
ENTRYPOINT ["python3", "email-update.py"]
