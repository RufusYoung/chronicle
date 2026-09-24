FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts && npm cache clean --force
COPY auth.mjs server.mjs catalog.mjs tools.mjs snapshot.json ./
USER node
EXPOSE 8792
CMD ["node", "server.mjs"]
