# inspired by https://sourcery.ai/blog/python-docker/
FROM nvidia/cuda:11.5.0-base-ubuntu20.04 as base

ENV LC_ALL C.UTF-8

# no .pyc files
ENV PYTHONDONTWRITEBYTECODE 1

# traceback on segfau8t
ENV PYTHONFAULTHANDLER 1

# use ipdb for breakpoints
ENV PYTHONBREAKPOINT=ipdb.set_trace

# common dependencies
RUN apt-get update -q \
  && DEBIAN_FRONTEND="noninteractive" \
  apt-get install -yq \
  # git-state
  git \
  # primary interpreter
  python3.8 \
  # redis-python
  redis \
  && apt-get clean

FROM base AS deps
# TODO: This is probably where most of the logic from your current Dockerfile goes
# build dependencies
RUN apt-get update -q \
  && DEBIAN_FRONTEND="noninteractive" \
  apt-get install -yq python3-pip \
  && apt-get clean
WORKDIR "/deps"
COPY pyproject.toml poetry.lock /deps/
RUN pip3 install poetry && poetry install
ENV PYTHON_ENV=/root/.cache/pypoetry/virtualenvs/hazelnut-K3BlsyQa-py3.8/

FROM base AS runtime
COPY --from=deps $PYTHON_ENV $PYTHON_ENV
WORKDIR "/RL_env"
RUN apt-get update -q \
  && DEBIAN_FRONTEND="noninteractive" \
  apt-get install -yq \
  opam \
  gcc \
  cmake \
  && apt-get clean
COPY opam.export .
RUN opam init --yes --disable-sandboxing \
  && opam update \
  && opam switch create . ocaml-base-compiler.4.13.1 \
  && opam switch import opam.export --yes
ENV PATH="$PYTHON_ENV/bin:$PATH"
COPY . .

ENTRYPOINT /RL_env/entrypoint.sh
