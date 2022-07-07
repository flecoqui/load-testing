import asyncio
import multiprocessing
import pytest
from datetime import datetime, timedelta
from azure.eventhub.aio import EventHubConsumerClient
from typing import List, Dict
from conftest import (
    csv_to_json,
    send_to_eventhub,
    get_eventhub_consumer,
    get_events_with_delta,
    get_events_max_ts,
)
from junit import create_test_suites


@pytest.fixture(scope="session")
def eventhubs_connection_string(pytestconfig):
    return pytestconfig.getoption("--eventhubs-connection-string")


@pytest.fixture(scope="session")
def input_csv_logs(pytestconfig):
    return pytestconfig.getoption("--input-csv-input-1")


@pytest.fixture(scope="session")
def eventhub_logs_name(pytestconfig):
    return pytestconfig.getoption("--eventhub-input-1-name")


@pytest.fixture(scope="session")
def input_csv_metrics(pytestconfig):
    return pytestconfig.getoption("--input-csv-input-2")


@pytest.fixture(scope="session")
def eventhub_metrics_name(pytestconfig):
    return pytestconfig.getoption("--eventhub-input-2-name")


@pytest.fixture(scope="session")
def eventhub_events_name(pytestconfig):
    return pytestconfig.getoption("--eventhub-output-1-name")


@pytest.fixture(scope="session")
def eventhub_events_consumer_group(pytestconfig):
    return pytestconfig.getoption("--eventhub-output-1-consumer-group")


@pytest.fixture(scope="session")
def receiving_duration(pytestconfig):
    return pytestconfig.getoption("--receiving-duration-max-seconds")


@pytest.fixture(scope="session")
def no_transmission_duration(pytestconfig):
    return pytestconfig.getoption("--no-transmission-duration-seconds")


@pytest.fixture(scope="session")
def junit_result_file(pytestconfig):
    return pytestconfig.getoption("--junit-result-file")


# returns the elapsed milliseconds since the start of the program
def delta(start: datetime, end: datetime):
    dt = end - start
    ms = (dt.days * 24 * 60 * 60 + dt.seconds) * 1000 + dt.microseconds / 1000.0
    return ms


def deltamicro(start: datetime, end: datetime):
    dt = end - start
    ms = (dt.days * 24 * 60 * 60 + dt.seconds) * 1000000 + dt.microseconds
    return ms


global readyToReceive
global anomaly_data

readyToReceive = 0
anomaly_data: List[Dict] = []


async def on_event(partition_context, event):
    b = event.body_as_json(encoding="UTF-8")
    print(
        # f"{datetime.utcnow()} start time: {b['winstarttime']} end time: {b['winendtime']} Event received: {b}"
        f"{datetime.utcnow()} EVENT RECEIVED: {b}"
    )
    anomaly_data.append(b)
    await partition_context.update_checkpoint(event)


def send(
    logs_data: List[Dict],
    eventhub_logs_name: str,
    metrics_data: List[Dict],
    eventhub_metrics_name: str,
    eventhubs_connection_string: str,
):
    asyncio.run(
        send_logs_async(logs_data, eventhub_logs_name, eventhubs_connection_string)
    )
    asyncio.run(
        send_metrics_async(
            metrics_data, eventhub_metrics_name, eventhubs_connection_string
        )
    )


def send_logs(
    logs_data: List[Dict], eventhub_logs_name: str, eventhubs_connection_string: str
):
    asyncio.run(
        send_logs_async(logs_data, eventhub_logs_name, eventhubs_connection_string)
    )


async def send_logs_async(
    logs_data: List[Dict], eventhub_logs_name: str, eventhubs_connection_string: str
):
    if len(logs_data) > 0:
        await send_to_eventhub(
            logs_data, eventhub_logs_name, eventhubs_connection_string
        )


def send_metrics(
    metrics_data: List[Dict],
    eventhub_metrics_name: str,
    eventhubs_connection_string: str,
):
    asyncio.run(
        send_metrics_async(
            metrics_data, eventhub_metrics_name, eventhubs_connection_string
        )
    )


async def send_metrics_async(
    metrics_data: List[Dict],
    eventhub_metrics_name: str,
    eventhubs_connection_string: str,
):
    if len(metrics_data) > 0:
        await send_to_eventhub(
            metrics_data, eventhub_metrics_name, eventhubs_connection_string
        )


@pytest.mark.asyncio
async def test_validate_event_are_generated(
    eventhubs_connection_string,
    input_csv_logs,
    eventhub_logs_name,
    input_csv_metrics,
    eventhub_metrics_name,
    eventhub_events_name,
    eventhub_events_consumer_group,
    receiving_duration,
    no_transmission_duration,
    junit_result_file,
):
    global anomaly_data
    latencyMeasured = False
    logs_data: List[Dict] = []
    metrics_data: List[Dict] = []
    result_data: List[Dict] = []

    print(
        f"Listening from eventhub {eventhub_events_name} and consumer group  {eventhub_events_consumer_group}"
    )
    consumer: EventHubConsumerClient = get_eventhub_consumer(
        eventhub_events_name,
        eventhub_events_consumer_group,
        eventhubs_connection_string,
    )
    consumer_task = asyncio.ensure_future(
        consumer.receive(
            on_event=on_event,
            track_last_enqueued_event_properties=True,
            starting_position=datetime.utcnow(),
        )
    )

    logs = csv_to_json(input_csv_logs)
    print(f"Found {len(logs)} logs to send to the eventhub {eventhub_logs_name}.")

    metrics = csv_to_json(input_csv_metrics)
    print(
        f"Found {len(metrics)} metrics to send to the eventhub {eventhub_metrics_name}."
    )

    test_start_time = datetime.utcnow()
    print(
        f"Starting test at {test_start_time}  during  {int(receiving_duration)*1000} ms."
    )

    index = 0
    oldindex = 0
    readyToSend = True
    tempo = int(no_transmission_duration)
    saved_appid = ""
    saved_hostname = ""
    send_time = datetime.utcnow()
    while True:
        if readyToSend is True and datetime.utcnow() > send_time:
            max_ts = get_events_max_ts(logs, metrics, index)
            delta_time = datetime.utcnow() - max_ts
            logs_data = get_events_with_delta(logs, index, delta_time)
            metrics_data = get_events_with_delta(metrics, index, delta_time)

            if len(logs_data) == 0 and len(metrics_data) == 0:
                index = 0
            else:
                print(
                    f"{datetime.utcnow()} GETTING BUFFERS for logs: {len(logs_data)} and metrics: {len(metrics_data)} Index: {index}"
                )
                if len(logs_data) > 0:
                    saved_appid = logs_data[0]["appid"]
                    saved_hostname = logs_data[0]["hostname"]
                else:
                    if len(metrics_data) > 0:
                        saved_appid = metrics_data[0]["appid"]
                        saved_hostname = metrics_data[0]["hostname"]

                send_process = multiprocessing.Process(
                    target=send,
                    args=(
                        logs_data,
                        eventhub_logs_name,
                        metrics_data,
                        eventhub_metrics_name,
                        eventhubs_connection_string,
                    ),
                )
                print(
                    f"{datetime.utcnow()} SENDING Logs and/or Metrics for index: {index}"
                )
                send_time = datetime.utcnow()
                latencyMeasured = False
                readyToSend = False
                oldindex = index
                index = index + 1
                anomaly_data = []
                send_process.start()

        if len(anomaly_data) > 0:
            for b in anomaly_data:
                if b["appid"] == saved_appid and b["hostname"] == saved_hostname:
                    # Received anomaly event from the right appid and hostname
                    if latencyMeasured is False:
                        receive_time = datetime.utcnow()
                        print(
                            f"{datetime.utcnow()} LATENCY MEASURED: {delta(send_time,receive_time)} ms"
                        )
                        result_data.append(
                            dict(
                                TIMESTAMP=datetime.timestamp(send_time),
                                INDEX=oldindex,
                                LATENCY=delta(send_time, receive_time) / 1000,
                                APMID=b["appid"],
                                PIVOT_FIELD=b["hostname"],
                            )
                        )
                        latencyMeasured = True

                    # if send process is completed and the latency has been measured
                    # trasnmit the next events
                    if send_process.is_alive() is False and latencyMeasured is True:
                        anomaly_data = []
                        readyToSend = True
                        print(
                            f"{datetime.utcnow()} RECEPTION COMPLETED, waiting {tempo} seconds before sending the next events"
                        )
                        # Sleep 2 seconds before sending events
                        # time.sleep(2)
                        # await asyncio.sleep(2)
                        if datetime.utcnow() > send_time:
                            send_time = datetime.utcnow() + timedelta(seconds=tempo)
                        break

        if delta(test_start_time, datetime.utcnow()) > int(receiving_duration) * 1000:
            test_end_time = datetime.utcnow()
            print(f"Ending test at {test_end_time}")
            break

        await asyncio.sleep(0.1)

    # Clean up
    consumer_task.cancel()
    await consumer.close()
    average_latency = 0.0
    count = 0
    for i in result_data:
        print(
            f"LATENCY MEASURED: Timestamp: {i['TIMESTAMP']} - Index: {i['INDEX']} - latency: {i['LATENCY']} s"
        )
        count = count + 1
        average_latency = average_latency + i["LATENCY"]

    if count > 0:
        print(
            f"AVERAGE LATENCY MEASURED: {average_latency/count} seconds for {count} measures"
        )
    else:
        print(
            "AVERAGE LATENCY MEASURED: Unknown for 0 measure, check your configuration."
        )
        assert False

    with open(junit_result_file, "w") as output_file:
        test_suites = create_test_suites(result_data, "latency")
        output_file.write(test_suites)
