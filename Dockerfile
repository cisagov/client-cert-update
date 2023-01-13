FROM python:3.11.1-alpine3.17 as compile-stage

###
# For a list of pre-defined annotation keys and value types see:
# https://github.com/opencontainers/image-spec/blob/master/annotations.md
#
# Note: Additional labels are added by the build workflow.
###
LABEL org.opencontainers.image.authors="vm-fusion-dev-group@trio.dhs.gov"
LABEL org.opencontainers.image.vendor="Cybersecurity and Infrastructure Security Agency"

###
# Unprivileged user information necessary for the Python virtual environment
###
ARG CISA_USER="cisa"
ENV CISA_HOME="/home/${CISA_USER}"
ENV VIRTUAL_ENV="${CISA_HOME}/.venv"

# Install base Python requirements and then install pipenv to manage installing
# the Python dependencies into a created Python virtual environment. This is
# done separately from the virtual environment so that pipenv and its
# dependencies are not installed in the Python virtual environment used in the
# final image.
#
# Please note that we only install the base Python requirements (pip,
# setuptools, and wheel) pre-venv because this Docker image is using Python
# built from source and not a system Python package.
RUN python3 -m pip install --no-cache-dir --upgrade \
    pip==22.3.1 \
    setuptools==65.7.0 \
    wheel==0.38.4 \
  && python3 -m pip install --no-cache-dir --upgrade pipenv==2022.12.19 \
  # Manually create Python virtual environment for the final image
  && python3 -m venv ${VIRTUAL_ENV} \
  # Ensure the core Python packages are installed in the virtual environment
  && ${VIRTUAL_ENV}/bin/python3 -m pip install --no-cache-dir --upgrade \
    pip==22.3.1 \
    setuptools==65.7.0 \
    wheel==0.38.4

# Install client-cert-update Python requirements
WORKDIR /tmp
COPY src/Pipfile src/Pipfile.lock ./
# pipenv will install packages into the virtual environment specified in the
# VIRTUAL_ENV environment variable if it is set.
RUN pipenv sync --clear --verbose

FROM python:3.11.1-alpine3.17 as build-stage

###
# Unprivileged user setup variables
###
ARG CISA_UID=1005
ARG CISA_GID=${CISA_UID}
ARG CISA_USER="cisa"
ENV CISA_GROUP=${CISA_USER}
ENV CISA_HOME="/home/${CISA_USER}"
ENV VIRTUAL_ENV="${CISA_HOME}/.venv"

###
# Create unprivileged user
###
RUN addgroup --system --gid ${CISA_GID} ${CISA_GROUP} \
  && adduser --system --uid ${CISA_UID} --ingroup ${CISA_GROUP} ${CISA_USER}

# Copy in the Python virtual environment we created in the compile stage
COPY --from=compile-stage --chown=${CISA_USER}:${CISA_GROUP} ${VIRTUAL_ENV} ${VIRTUAL_ENV}
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"

# Put this just before we change users because the copy (and every
# step after it) will often be rerun by Docker.
COPY --chown=${CISA_USER}:${CISA_GROUP} src/email-update.py src/body.txt src/body.html ${CISA_HOME}/

###
# Prepare to run
###
WORKDIR ${CISA_HOME}
USER ${CISA_USER}
ENTRYPOINT ["python3", "email-update.py"]
