FROM ruby

WORKDIR /site
COPY docs/Gemfile* ./

RUN : \
    && gem install bundler \
    && bundle install \
    && :

EXPOSE 4000
VOLUME /site

CMD [ "/bin/sh", "-c", "bundle exec jekyll serve --host 0.0.0.0 --drafts" ]
