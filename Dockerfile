FROM ruby:3.2

WORKDIR /site
COPY docs/Gemfile* ./

RUN : \
    && gem install bundler \
    && bundle install \
    && :

EXPOSE 4000
VOLUME /site

RUN : \
    && { \
        echo '#!/bin/sh'; \
        echo 'cd /site'; \
        echo 'bundle exec jekyll serve --host ${HOST-0.0.0.0} ${OPTS---drafts}'; \
    } > /entrypoint.sh \
    && chmod +x /entrypoint.sh \
    && :

CMD ["/entrypoint.sh"]
