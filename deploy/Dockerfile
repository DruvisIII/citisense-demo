# Static hosting for the Flutter web demo on Railway.
# Build the app LOCALLY first (see deploy.md); this image only serves
# the files in deploy/web. No Flutter install happens here.
FROM nginx:alpine

# nginx:alpine renders /etc/nginx/templates/*.template into
# /etc/nginx/conf.d/ at startup, filling in ${PORT} from Railway.
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
COPY web/ /usr/share/nginx/html/

# Railway sets PORT; 8080 is only the local default.
ENV PORT=8080
EXPOSE 8080
