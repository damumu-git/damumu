FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
ARG VITE_API_BASE=/api/v1
ARG VITE_BASE=/admin/
ARG VITE_ADMIN_KEY
ENV VITE_API_BASE=$VITE_API_BASE
ENV VITE_BASE=$VITE_BASE
ENV VITE_ADMIN_KEY=$VITE_ADMIN_KEY
RUN test -n "$VITE_ADMIN_KEY"
RUN npm run lint && npm run build

FROM nginx:1.29-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
