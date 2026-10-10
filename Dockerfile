# TinyOWS (WFS-T) als FastCGI-Dienst — distroless Runtime-Image.
# TinyOWS kann kein HTTP selbst: ein FastCGI-fähiger Webserver (z. B. nginx
# mit fastcgi_pass) muss davor stehen. spawn-fcgi startet den Prozess im
# Vordergrund (-n), die Prozess-Supervision übernimmt der Container-Runtime
# bzw. Kubernetes. MapServer ist NICHT mehr enthalten — das WMS läuft separat
# mit dem unveränderten Upstream-Image camptocamp/mapserver.
ARG CONTAINER_REGISTRY=docker.io
ARG DEBIAN_VERSION=12

# Build-Stage: Debian-Pakete installieren und die Shared-Library-
# Abhängigkeiten beider Binaries mit Pfadstruktur einsammeln.
FROM ${CONTAINER_REGISTRY}/debian:${DEBIAN_VERSION}-slim AS build
# tinyows liegt in Debian in "non-free" (OGC-Schema-Lizenzen), das Slim-Image
# aktiviert nur "main".
RUN sed -i 's/Components: main/Components: main non-free/' /etc/apt/sources.list.d/debian.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends tinyows spawn-fcgi \
    && rm -rf /var/lib/apt/lists/*
# ldd-Zeilen ohne "=>" (linux-vdso, ld.so) fallen raus; -L dereferenziert
# Symlinks, damit echte Bibliotheken statt Links kopiert werden.
RUN mkdir /deps \
    && for bin in /usr/lib/cgi-bin/tinyows /usr/bin/spawn-fcgi; do \
         ldd "$bin" | awk '$2 == "=>" && $3 ~ /^\// { print $3 }'; \
       done | sort -u | xargs -r -I{} cp --parents -L {} /deps

# Runtime: distroless (glibc + OpenSSL + CA-Zertifikate, keine Shell),
# läuft als nonroot (uid 65532).
FROM gcr.io/distroless/base-debian${DEBIAN_VERSION}:nonroot
ARG IMAGE_VERSION=1.2-1

LABEL org.opencontainers.image.title="TinyOWS (WFS-T)" \
      org.opencontainers.image.description="TinyOWS as FastCGI service on :9000 (spawn-fcgi, distroless); put an nginx with fastcgi_pass in front" \
      org.opencontainers.image.source="https://github.com/kreapptivo/tinyows" \
      org.opencontainers.image.version="${IMAGE_VERSION}"

COPY --from=build /deps/ /
COPY --from=build /usr/lib/cgi-bin/tinyows /usr/lib/cgi-bin/tinyows
COPY --from=build /usr/bin/spawn-fcgi /usr/bin/spawn-fcgi
# Von tinyows.xml (schema_dir) referenziert; nur bei check_schema="1" wirklich
# gelesen, aber klein genug, um es nicht zur Laufzeit-Überraschung zu machen.
COPY --from=build /usr/share/tinyows /usr/share/tinyows

# spawn-fcgi reicht sein Environment direkt an den FCGI-Prozess durch — der
# mod_fcgid-Workaround (Mount auf den einkompilierten Pfad /etc/tinyows.xml)
# entfällt, die Konfiguration wird als Verzeichnis nach /etc/tinyows gemountet.
ENV TINYOWS_CONFIG_FILE=/etc/tinyows/tinyows.xml

EXPOSE 9000
ENTRYPOINT ["/usr/bin/spawn-fcgi", "-n", "-p", "9000", "--", "/usr/lib/cgi-bin/tinyows"]
