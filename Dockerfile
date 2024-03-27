# Dockerfile for the generating pcdm-manifests Rails application Docker image
#
# To build:
#
# docker build -t docker.lib.umd.edu/pcdm-manifests:<VERSION> -f Dockerfile .
#
# where <VERSION> is the Docker image version to create.

FROM ruby:3.0.6-slim

# Install apt based dependencies required to run Rails as
# well as RubyGems. As the Ruby image itself is based on a
# Debian image, we use apt-get ≥to install those.
RUN apt-get update && \
    apt-get install -y build-essential && \
    apt-get clean

# Create a user for the web app.
RUN addgroup --gid 9999 app && \
    adduser --uid 9999 --gid 9999 --disabled-password --gecos "Application" app && \
    usermod -L app

# Configure the main working directory. This is the base
# directory used in any further RUN, COPY, and ENTRYPOINT
# commands.

USER app
WORKDIR /home/app

ENV RAILS_ENV=production

# Copy the Gemfile as well as the Gemfile.lock and install
# the RubyGems. This is a separate step so the dependencies
# will be cached unless changes to one of those two files
# are made.
COPY --chown=app:app Gemfile Gemfile.lock /home/app/webapp/
RUN cd /home/app/webapp && \
    gem install bundler:2.5.7 && \
    bundle install --deployment && \
    cd ..

# Copy the main application.
COPY  --chown=app:app . /home/app/webapp/

# Expose port 3000 to the Docker host, so we can access it
# from the outside.
EXPOSE 3000

WORKDIR /home/app/webapp
CMD ["/home/app/webapp/bin/pcdm-manifests.sh"]
