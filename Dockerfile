FROM ruby

WORKDIR /site
COPY docs/ .

RUN : \
    && gem install bundler \
    && bundle install \
    && :

EXPOSE 4000

CMD [ "/bin/sh", "-c", "bundle exec jekyll serve --host 0.0.0.0" ]
