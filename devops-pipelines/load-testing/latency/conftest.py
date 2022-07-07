import csv
import json
from datetime import datetime, timedelta
from typing import List, Dict

from azure.eventhub.aio import EventHubProducerClient, EventHubConsumerClient
from azure.eventhub import EventData


def pytest_addoption(parser):
    parser.addoption("--eventhubs-connection-string", action="store")
    parser.addoption("--input-csv-input-1", action="store")
    parser.addoption("--eventhub-input-1-name", action="store")
    parser.addoption("--input-csv-input-2", action="store")
    parser.addoption("--eventhub-input-2-name", action="store")
    parser.addoption("--eventhub-output-1-name", action="store")
    parser.addoption("--eventhub-output-1-consumer-group", action="store")
    parser.addoption("--receiving-duration-max-seconds", action="store")
    parser.addoption("--no-transmission-duration-seconds", action="store")
    parser.addoption("--junit-result-file", action="store")


def csv_to_json(csv_file_path: str) -> List[Dict]:
    with open(csv_file_path, encoding="utf-8") as csv_file_reader:
        csv_reader = csv.DictReader(csv_file_reader)
        return list(row for row in csv_reader)


async def send_to_eventhub(data: List[Dict], eventhub: str, conn_str: str) -> None:
    eventhubs_client = EventHubProducerClient.from_connection_string(
        conn_str, eventhub_name=eventhub
    )
    # For each event, send it to the eventhub (topic) provided in input
    for i in data:
        # events will be regroup in partitions based on the pattern appid+hostname
        partition_key = f"{i['appid']}{i['hostname']}"
        event_data_batch = await eventhubs_client.create_batch(
            partition_key=partition_key
        )
        event_data_batch.add(EventData(json.dumps(i)))
        async with eventhubs_client:
            await eventhubs_client.send_batch(event_data_batch)
        print(f"{datetime.utcnow()} EVENT SENT: {json.dumps(i)}")


async def send_to_eventhubs(eventhubs_client: any, data: List[Dict]) -> None:
    # For each event, send it to the eventhub (topic) provided in input
    for i in data:
        # events will be regroup in partitions based on the pattern appid+hostname
        partition_key = f"{i['appid']}{i['hostname']}"
        event_data_batch = await eventhubs_client.create_batch(
            partition_key=partition_key
        )
        event_data_batch.add(EventData(json.dumps(i)))
        async with eventhubs_client:
            await eventhubs_client.send_batch(event_data_batch)


def get_events(data: List[Dict], index: int) -> List[Dict]:
    result: List[Dict] = []
    # For each event, send it to the eventhub (topic) provided in input
    for i in data:
        # events will be regroup in partitions based on the pattern appid+hostname
        j = int(f"{i['index']}")
        if j == index:
            # Update the timestamp with current utc time
            i["ts"] = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S.%f")
            result.append(i)
        if j > index:
            return result
    return result


def get_events_with_delta(data: List[Dict], index: int, delta: timedelta) -> List[Dict]:
    result: List[Dict] = []
    # For each event, send it to the eventhub (topic) provided in input
    for i in data:
        # events will be regroup in partitions based on the pattern appid+hostname
        j = int(f"{i['index']}")
        if j == index:
            # Update the timestamp with current utc time
            d = datetime.strptime(f"{i['ts'][:26]}", "%Y-%m-%dT%H:%M:%S.%f") + delta
            i["ts"] = d.strftime("%Y-%m-%dT%H:%M:%S.%f0")
            result.append(i)
        if j > index:
            return result
    return result


def get_events_max_ts(logs: List[Dict], metrics: List[Dict], index: int) -> datetime:
    dmax = datetime.min
    for i in logs:
        d = datetime.strptime(f"{i['ts'][:26]}", "%Y-%m-%dT%H:%M:%S.%f")
        if d > dmax:
            dmax = d
    for i in metrics:
        d = datetime.strptime(f"{i['ts'][:26]}", "%Y-%m-%dT%H:%M:%S.%f")
        if d > dmax:
            dmax = d
    return dmax


def get_eventhub_consumer(
    eventhub: str, consumer_group: str, conn_str: str
) -> EventHubConsumerClient:
    consumer = EventHubConsumerClient.from_connection_string(
        conn_str=conn_str, consumer_group=consumer_group, eventhub_name=eventhub
    )
    return consumer
