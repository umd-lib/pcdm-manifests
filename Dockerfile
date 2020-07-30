FROM ruby:2.6.3
WORKDIR /opt/pcdm-manifests

COPY ./Gemfile ./Gemfile.lock /opt/pcdm-manifests/
RUN bundle install --deployment
COPY . /opt/pcdm-manifests
EXPOSE 3000
CMD ["bin/pcdm-manifests.sh"]
