from datetime import datetime
from typing import List, Dict
from xml.etree import ElementTree
from xml.dom import minidom
from xml.etree.ElementTree import Element, SubElement


def prettify(elem):
    """Returns a pretty-printed XML string for the Element."""
    rough_string = ElementTree.tostring(elem, "utf-8")
    reparsed = minidom.parseString(rough_string)
    return reparsed.toprettyxml(indent="  ")


def create_request_attrib(result_file: List[Dict]):
    """Returns a JSON with attributes for a JUnit testsuite: https://llg.cubic.org/docs/junit/
    The JMeter JTL file must be in CSV format.
    """
    request_time = float(result_file["LATENCY"])
    return {
        "name": "Index: "
        + str(result_file["INDEX"])
        + " appid: "
        + result_file["APMID"]
        + " timestamp: "
        + str(datetime.fromtimestamp(result_file["TIMESTAMP"])),
        "time": str(request_time),
        "error_message": "",
    }


def create_test_case_attrib(request_attrib):
    """Returns a JSON with attributes for a JUnit testcase: https://llg.cubic.org/docs/junit/
    The JMeter JTL file must be in CSV format.
    """
    return {
        "classname": "httpSample",
        "name": request_attrib["name"],
        "time": request_attrib["time"],
    }


def create_test_suite_attrib(junit_results, test_name):
    """Returns a JSON with attributes for JUnit testsuite: https://llg.cubic.org/docs/junit/
    The JMeter JTL file must be in CSV format.
    """
    return {
        "id": "1",
        "name": test_name,
        "package": test_name,
        "hostname": "Azure DevOps",
        "time": str(junit_results["time"]),
        "tests": str(junit_results["tests"]),
        "failures": str(len(junit_results["requests"]["failures"])),
        "errors": "0",
    }


def create_error_test_case_attrib(error_message):
    """Returns a JSON with attributes for JUnit testcase for failed requests: https://llg.cubic.org/docs/junit/
    The JMeter JTL file must be in CSV format.
    """
    return {"message": error_message, "type": "exception"}


def requests(jmeter_results):
    """Returns a JSON with successful and failed HTTP requests.
    The JMeter JTL file must be in CSV format.
    """
    failed_requests = []
    successful_requests = []

    for result in jmeter_results:
        request_attrib = create_request_attrib(result)
        successful_requests.append(request_attrib)
    return {"success": successful_requests, "failures": failed_requests}


def total_time_seconds(jmeter_results):
    """Returns the total test duration in seconds.
    The JMeter JTL file must be in CSV format.
    """
    max_timestamp = max(jmeter_results, key=lambda result: int(result["TIMESTAMP"]))
    min_timestamp = min(jmeter_results, key=lambda result: int(result["TIMESTAMP"]))
    total_timestamp = int(max_timestamp["TIMESTAMP"]) - int(min_timestamp["TIMESTAMP"])

    return float(total_timestamp)


def create_junit_results(result_list):
    time = total_time_seconds(result_list)

    return {
        "tests": len(result_list),
        "time": time,
        "requests": requests(result_list),
    }


def create_properties(test_suite):
    """Creates a JUnit properties element for testsuite: https://llg.cubic.org/docs/junit/
    The JMeter JTL file must be in CSV format.
    """
    return SubElement(test_suite, "properties")


def create_test_suite(test_suites, junit_results, test_name):
    """Creates a JUnit testsuite: https://llg.cubic.org/docs/junit/
    The JMeter JTL file must be in CSV format.
    """
    test_suite_attrib = create_test_suite_attrib(junit_results, test_name)
    test_suite = SubElement(test_suites, "testsuite", test_suite_attrib)

    create_properties(test_suite)

    successful_requests = len(junit_results["requests"]["success"])

    for success_index in range(successful_requests):
        successful_request = junit_results["requests"]["success"][success_index]
        create_successful_test_case(test_suite, successful_request)


def create_successful_test_case(test_suite, successful_request):
    """Creates a JUnit test case for successful HTTP requests: https://llg.cubic.org/docs/junit/
    The JMeter JTL file must be in CSV format.
    """
    test_case_attrib = create_test_case_attrib(successful_request)
    SubElement(test_suite, "testcase", test_case_attrib)


def create_test_suites(result_list, test_name):
    """Creates a JUnit testsuites element: https://llg.cubic.org/docs/junit/
    The JMeter JTL file must be in CSV format.
    """
    test_suites = Element("testsuites")
    junit_results = create_junit_results(result_list)
    create_test_suite(test_suites, junit_results, test_name)

    return prettify(test_suites)
