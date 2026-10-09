FROM node:24-alpine
WORKDIR /app
COPY server server
COPY relay relay
COPY contracts contracts
ENV HOST=0.0.0.0 PORT=8792 DATABASE_PATH=/data/babytrack.sqlite
USER node
EXPOSE 8792
CMD ["node", "server/main.mjs"]
