# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import random
from src.simulators_parser import Simulator
from src.semver import Version

# An estimated duration of installing simulator on Bitrise.
# It includes ~3-5min margin over measured duration.
SIMULATOR_INSTALLATION_TIME_IN_MINUTES = 15

# An estimated duration of unit tests step on Bitrise.
# It includes ~50% margin to include tests retry on flakiness.
UNIT_TESTS_EXECUTION_TIME_IN_MINUTES = 10

# The maximum time of running a build in Bitrise.
# It includes ~10min margin for set-up and tear-down jobs.
BITRISE_TIMEOUT_IN_MINUTES = 80

# The minimal supported iOS version for running unit tests.
MIN_SUPPORTED_IOS_VERSION = Version.parse('11.0.0')


class TestPlanStep:
    def __init__(self, simulator: Simulator):
        self.simulator = simulator

        if simulator.is_installed:
            self.estimated_duration_in_minutes = UNIT_TESTS_EXECUTION_TIME_IN_MINUTES
        else:
            self.estimated_duration_in_minutes = SIMULATOR_INSTALLATION_TIME_IN_MINUTES + \
                                                 UNIT_TESTS_EXECUTION_TIME_IN_MINUTES

    def __repr__(self):
        if self.simulator.is_installed:
            return f'TestPlanStep: run on {self.simulator} (est.: ~{self.estimated_duration_in_minutes}min)'
        else:
            return f'TestPlanStep: install + run on {self.simulator} (est.: ~{self.estimated_duration_in_minutes}min)'


class TestPlan:
    """
    Randomizes simulator installation and unit test run steps to plan workflows in generated `bitrise.yml`.
    It makes sure that overal duration of Bitrise build won't exceed the `BITRISE_TIMEOUT_IN_MINUTES`.
    """

    def __init__(self, steps: [TestPlanStep]):
        self.steps = steps

    @staticmethod
    def create_plan(simulators: [Simulator]):
        """
        :param simulators: list of Simulators supported on this host
        :return: a `TestPlan` object
        """
        planned_steps = list(map(lambda s: TestPlanStep(simulator=s), simulators))
        return TestPlan(steps=planned_steps)

    @staticmethod
    def create_randomized_plan(simulators: [Simulator]):
        """
        :param simulators: list of Simulators supported on this host
        :return: a `TestPlan` object
        """
        possible_steps = list(map(lambda s: TestPlanStep(simulator=s), simulators))
        possible_steps = list(filter(lambda step: is_using_supported_ios_version(step), possible_steps))

        planned_steps: [TestPlanStep] = []

        random.shuffle(possible_steps)
        arbitrary_attempts_left = 10

        while True:
            if len(possible_steps) > 0:
                next_step = possible_steps.pop(0)
                next_total_duration = total_duration_in_minutes(steps=planned_steps + [next_step])
                if next_total_duration <= BITRISE_TIMEOUT_IN_MINUTES:
                    planned_steps.append(next_step)
                else:
                    # if `next_step` doesn't fit the timeout limit, try `arbitrary_attempts_left` more times,
                    # so maybe the next one will fit in.
                    arbitrary_attempts_left -= 1
                    if arbitrary_attempts_left <= 0:
                        break
            else:
                break

        return TestPlan(steps=planned_steps)


def total_duration_in_minutes(steps: [TestPlanStep]):
    total = 0
    for step in steps:
        total += step.estimated_duration_in_minutes
    return total


def is_using_supported_ios_version(step: TestPlanStep) -> bool:
    return step.simulator.os_version.is_newer_than_or_equal(MIN_SUPPORTED_IOS_VERSION)
