import logging
import os
import time

from flask import Flask, jsonify, request
from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.logging.handler import LoggingHandler
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler as SDKLoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter

OTEL_ENDPOINT = os.getenv(
    "OTEL_EXPORTER_OTLP_ENDPOINT",
    "http://opentelemetry-collector.opentelemetry.svc.cluster.local:4318",
)

resource = Resource.create({
    "service.name": "inventory-service",
    "service.version": "1.0",
})

trace_provider = TracerProvider(resource=resource)
trace_provider.add_span_processor(
    BatchSpanProcessor(
        OTLPSpanExporter(endpoint=f"{OTEL_ENDPOINT}/v1/traces")
    )
)
trace.set_tracer_provider(trace_provider)
tracer = trace.get_tracer("inventory-service")

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

logger = logging.getLogger("inventory-service")
logger.setLevel(logging.INFO)
logger.handlers.clear()
logger.addHandler(otel_log_handler)
logger.propagate = False

app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)


@app.route("/inventory/<item_id>")
def get_inventory(item_id):
    should_fail = request.args.get("fail", "false").lower() == "true"

    with tracer.start_as_current_span("check-inventory") as span:
        span.set_attribute("inventory.item_id", item_id)
        span.set_attribute("inventory.fail_requested", should_fail)

        logger.info("Checking inventory")

        # Deliberate latency so the distributed trace is easy to see.
        time.sleep(0.10)

        if should_fail:
            message = "intentional inventory failure"
            span.set_status(trace.Status(trace.StatusCode.ERROR, message))
            logger.error("Inventory lookup failed")
            return jsonify({
                "status": "error",
                "message": message,
                "item_id": item_id,
            }), 500

        logger.info("Inventory lookup completed")

        return jsonify({
            "item_id": item_id,
            "available": True,
            "quantity": 42,
        })


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8082)
