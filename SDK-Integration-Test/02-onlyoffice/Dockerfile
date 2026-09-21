FROM onlyoffice/documentserver:latest
USER root
# Fix missing index_loader.html (renamed in v9.4)
RUN for dir in documenteditor spreadsheeteditor presentationeditor; do \
      cp /var/www/onlyoffice/documentserver/web-apps/apps/${dir}/main/index.html \
         /var/www/onlyoffice/documentserver/web-apps/apps/${dir}/main/index_loader.html; \
    done
# Disable SSRF protection so docservice can reach localhost:8091 (fileUrl) and host.docker.internal (callbackUrl)
RUN sed -i 's/"blockPrivateIP": true/"blockPrivateIP": false/g' /etc/onlyoffice/documentserver/default.json \
 && sed -i 's/"allowPrivateIPAddress": false/"allowPrivateIPAddress": true/g' /etc/onlyoffice/documentserver/default.json
# Serve uploaded files at :8091/uploads/ inside the container (fileUrl points here)
RUN printf 'server {\n    listen 8091;\n    location /uploads/ {\n        alias /var/www/onlyoffice/uploads/;\n    }\n}\n' \
    > /etc/nginx/conf.d/uploads.conf
