FROM wso2/wso2mi:4.3.0

USER root

WORKDIR /home/wso2carbon

COPY client-truststore.jks /home/wso2carbon/

RUN chown wso2carbon:root /home/wso2carbon/client-truststore.jks

USER wso2carbon

EXPOSE 8290 8253

CMD ["/home/wso2carbon/wso2mi-4.3.0/bin/micro-integrator.sh"]
