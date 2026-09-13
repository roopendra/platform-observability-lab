import logging
import os

import requests
from flask import Flask, jsonify, request
from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor
from opentelemetry.instrumentation.logging.handler import LoggingHandler
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler as SDKLoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter

OTEL_ENDPOINT = os.getenv(
    "OTEL_EXPORTER_OTLP_ENDPOINT",
    "http://opentelemetry-collector.opentelemetry.svc.cluster.local:4318",
)

resource = Resource.create({
    "service.name": "otel-demo",
    "service.version": "1.2",
})

# Tracing
trace_provider = TracerProvider(resource=resource)
trace_provider.add_span_processor(
    BatchSpanProcessor(
        OTLPSpanExporter(endpoint=f"{OTEL_ENDPOINT}/v1/traces")
    )
)
trace.set_tracer_provider(trace_provider)
tracer = trace.get_tracer("otel-demo")

# Logging
logger_provider = LoggerProvider(resource=resource)
logger_provider.add_log_record_processor(
    BatchLogRecordProcessor(
        OTLPLogExporter(endpoint=f"{OTEL_ENDPOINT}/v1/logs")
    )
)

otel_log_handler = SDKLoggingHandler(
    level=logging.INFO,
    logger_provider=logger_provider,
)

logger = logging.getLogger("otel-demo")
logger.setLevel(logging.INFO)
logger.handlers.clear()
logger.addHandler(otel_log_handler)
logger.propagate = False

app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)
RequestsInstrumentor().instrument()

USER_SERVICE_URL = os.getenv(
    "USER_SERVICE_URL",
    "http://user-service.opentelemetry.svc.cluster.local:8081",
)
INVENTORY_SERVICE_URL = os.getenv(
    "INVENTORY_SERVICE_URL",
    "http://inventory-service.opentelemetry.svc.cluster.local:8082",
)


@app.route("/")
def index():
    logger.info("Root endpoint called")
    return jsonify({
        "service": "otel-demo",
        "version": "1.2",
        "status": "ok",
    })


@app.route("/api")
def api():
    fail_inventory = request.args.get("fail_inventory", "false").lower() == "true"

    with tracer.start_as_current_span("process-api-request") as span:
        span.set_attribute("request.fail_inventory", fail_inventory)

        logger.info("Processing API request")

        try:
            user_response = requests.get(
                f"{USER_SERVICE_URL}/users/123",
                timeout=3,
            )
            user_response.raise_for_status()

            inventory_response = requests.get(
                f"{INVENTORY_SERVICE_URL}/inventory/item-001",
                params={"fail": str(fail_inventory).lower()},
                timeout=3,
            )
            inventory_response.raise_for_status()

            logger.info("API request completed")

            return jsonify({
                "status": "ok",
                "user": user_response.json(),
                "inventory": inventory_response.json(),
            })

        except requests.RequestException as exc:
            span.record_exception(exc)
            span.set_status(trace.Status(trace.StatusCode.ERROR, str(exc)))

            logger.exception("API request failed")

            return jsonify({
                "status": "error",
                "error": str(exc),
            }), 502


@app.route("/error")
def error():
    with tracer.start_as_current_span("process-error-request") as span:
        logger.warning("Processing request that will return an error")

        span.set_status(
            trace.Status(trace.StatusCode.ERROR, "intentional demo error")
        )

        logger.error(
            "API request failed",
            extra={"error_type": "intentional_demo_error"},
        )

        return jsonify({
            "status": "error",
            "message": "intentional demo error",
        }), 500


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
