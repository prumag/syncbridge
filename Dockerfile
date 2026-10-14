# Rebuild and run the app the way it runs locally: Rails on port 3000 and the
# mock client API on port 4567, inside one container.
#
#   docker build -t syncbridge .
#   docker run --rm -p 3000:3000 -p 4567:4567 syncbridge
#
# Then open http://localhost:3000
FROM ruby:3.4.11

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    build-essential \
    libsqlite3-dev \
    libyaml-dev \
    pkg-config \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV RAILS_ENV=development \
    CLIENT_API_URL=http://127.0.0.1:4567 \
    CLIENT_API_TOKEN=test-token

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .
RUN chmod +x bin/docker-entrypoint

EXPOSE 3000 4567

ENTRYPOINT ["bin/docker-entrypoint"]
