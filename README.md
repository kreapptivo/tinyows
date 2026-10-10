# TinyOWS Docker Image (WFS-T)

[TinyOWS](https://mapserver.org/tinyows/) as a small **distroless** FastCGI
image, providing **WFS-T** (transactional WFS) on PostGIS tables. MapServer
only serves read-only WFS; TinyOWS from the MapServer family adds
insert/update/delete.

TinyOWS cannot speak HTTP itself — it runs as a FastCGI process (started by
`spawn-fcgi` in the foreground, listening on **:9000**) and expects an
HTTP-to-FastCGI frontend such as **nginx** with `fastcgi_pass`. In Kubernetes
the intended shape is a two-container pod: this image plus a stock
`nginx` sidecar; the container runtime handles supervision/restarts.

## Configuration

The image ships no TinyOWS configuration. `spawn-fcgi` passes its
environment directly to the FCGI process, so `TINYOWS_CONFIG_FILE` works and defaults to `/etc/tinyows/tinyows.xml` — mount
the rendered config there (e.g. a Kubernetes ConfigMap mounted at
`/etc/tinyows`).

In the TinyOWS config, `check_schema="0"` is required — the strict OGC
schema validation otherwise rejects requests from common clients. The XSD
schemas are nevertheless included at `/usr/share/tinyows/schema/` (the `schema_dir` attribute points there).

## Build

```sh
docker build -t ghcr.io/kreapptivo/tinyows:<tag> .
```

The Debian release (`ARG DEBIAN_VERSION`) and the image version label
(`ARG IMAGE_VERSION`) are pinned in the `Dockerfile`. The tag scheme is
`<tinyows version>-<image revision>` (e.g. `1.2-1` for TinyOWS 1.2.0).
TinyOWS comes from Debian **non-free**.

Smoke test (runs TinyOWS once in CGI mode; the expected output is an XML
`ExceptionReport` with `ConnectionFailed` — binary, libraries and config
parsing all work, only the database is missing):

```sh
docker run --rm --entrypoint /usr/lib/cgi-bin/tinyows \
  -v ./tinyows.xml:/etc/tinyows/tinyows.xml:ro \
  -e REQUEST_METHOD=GET \
  -e "QUERY_STRING=service=WFS&version=1.1.0&request=GetCapabilities" \
  ghcr.io/kreapptivo/tinyows:<tag>
```

## Release

The GitHub Actions workflow [`release.yml`](.github/workflows/release.yml) is
triggered manually (*Actions → Release → Run workflow*). It builds the image
and publishes it to `ghcr.io/kreapptivo/tinyows` tagged with the version and
`latest`. The version input is optional — left empty, the `IMAGE_VERSION`
default from the `Dockerfile` is used.
