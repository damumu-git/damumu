FROM ghcr.io/cirruslabs/flutter:3.44.0@sha256:0a9de3b70b5b7b921a346eb2793e363dc22280849a4fd690d9dde99ce1c2b1b8 AS build
WORKDIR /src

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .

ARG API_BASE_URL
ARG FIREBASE_API_KEY=
ARG FIREBASE_APP_ID=
ARG FIREBASE_MESSAGING_SENDER_ID=
ARG FIREBASE_PROJECT_ID=
ARG FIREBASE_AUTH_DOMAIN=
ARG FIREBASE_STORAGE_BUCKET=
ARG FIREBASE_WEB_VAPID_KEY=

RUN test -n "$API_BASE_URL" && flutter build web --release \
    --dart-define=API_BASE_URL="$API_BASE_URL" \
    --dart-define=DEV_AUTO_LOGIN=false \
    --dart-define=FIREBASE_API_KEY="$FIREBASE_API_KEY" \
    --dart-define=FIREBASE_APP_ID="$FIREBASE_APP_ID" \
    --dart-define=FIREBASE_MESSAGING_SENDER_ID="$FIREBASE_MESSAGING_SENDER_ID" \
    --dart-define=FIREBASE_PROJECT_ID="$FIREBASE_PROJECT_ID" \
    --dart-define=FIREBASE_AUTH_DOMAIN="$FIREBASE_AUTH_DOMAIN" \
    --dart-define=FIREBASE_STORAGE_BUCKET="$FIREBASE_STORAGE_BUCKET" \
    --dart-define=FIREBASE_WEB_VAPID_KEY="$FIREBASE_WEB_VAPID_KEY"

FROM nginx:1.29-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/build/web /usr/share/nginx/html
EXPOSE 80
