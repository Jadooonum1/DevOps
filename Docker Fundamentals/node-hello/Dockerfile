FROM node:20-alpine
WORKDIR /usr/src/app
# copy the manifest first so the dependency layer is cached between code edits
COPY package.json ./
RUN npm install --omit=dev
COPY server.js ./
ENV PORT=3000
EXPOSE 3000
# the official image ships an unprivileged "node" user
USER node
CMD ["node", "server.js"]
