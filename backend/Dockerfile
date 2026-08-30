FROM node:18-alpine
RUN apk upgrade --no-cache
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
EXPOSE 4000
CMD ["node", "index.js"]

