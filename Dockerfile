FROM wso2/wso2mi:4.3.0

USER root

WORKDIR /home/wso2carbon

# ── Layer 1: Truststore ──────────────────
COPY client-truststore.jks /home/wso2carbon/
RUN chown wso2carbon:root /home/wso2carbon/client-truststore.jks

# ── Layer 2: CApp deployment ────────────────────────────────────────────────
# All .car files in capps/ are copied into the MI deployment directory
COPY capps/*.car /home/wso2carbon/wso2mi-4.3.0/repository/deployment/server/carbonapps/

RUN chown -R wso2carbon:root \
    /home/wso2carbon/wso2mi-4.3.0/repository/deployment/server/carbonapps/

USER wso2carbon

EXPOSE 8290 8253 9164

CMD ["/home/wso2carbon/wso2mi-4.3.0/bin/micro-integrator.sh"]

