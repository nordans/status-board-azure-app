FROM grafana/grafana@sha256:dbbc38ea21103cefb50396340cd88afec779c7e070b0a7bf5a75b4ce46651d3f AS plugins
FROM grafana/grafana@sha256:3838fe4d1cb7fef51a91b9a72011a7a68736b6052785594d437ec65d441acd8b
COPY --from=plugins /usr/share/grafana/data/plugins-bundled/prometheus /usr/share/grafana/data/plugins-bundled/prometheus
USER 472:0
