"""Observe XCTest loading while reusing an existing framework-test product."""
import copy
import re
from pathlib import PurePosixPath


class EvidenceError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise EvidenceError(message)


def logged_spec(original, target, products_directory):
    """Preserve test settings; relocate TESTROOT and enable loader observations."""
    require(isinstance(original, dict), 'test specification must be a dictionary')
    require(set(original) == {target, '__xctestrun_metadata__'}, 'foreign test target')
    require(original['__xctestrun_metadata__'].get('FormatVersion') == 1, 'unsupported test specification')
    root = PurePosixPath(products_directory)
    require(root.is_absolute() and '..' not in root.parts, 'absolute product root required')
    require(original[target].get('TestHostPath') ==
            '__PLATFORMS__/iPhoneSimulator.platform/Developer/Library/Xcode/Agents/xctest',
            'only existing iOS Simulator framework tests are supported')

    def relocate(value):
        if isinstance(value, str):
            return value.replace('__TESTROOT__', str(root))
        if isinstance(value, list):
            return [relocate(item) for item in value]
        if isinstance(value, dict):
            return {key: relocate(item) for key, item in value.items()}
        return copy.deepcopy(value)

    result = relocate(original)
    for key in ('EnvironmentVariables', 'TestingEnvironmentVariables'):
        values = result[target].setdefault(key, {})
        require(isinstance(values, dict) and all(isinstance(k, str) and isinstance(v, str)
                for k, v in values.items()), 'invalid test environment')
        require('DYLD_PRINT_LIBRARIES' not in values, 'loader logging already configured')
        values['DYLD_PRINT_LIBRARIES'] = '1'
    return result


UUID = r'[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}'
IMAGE = re.compile(r'^dyld\[(\d+)\]:\s*<(' + UUID + r')>\s+(/[^\r\n]+?)\s*$')


def image_rows(console):
    rows = []
    for number, line in enumerate(console.splitlines(), 1):
        match = IMAGE.fullmatch(line)
        if match:
            pid, image_uuid, path = match.groups()
            rows.append(dict(pid=int(pid), uuid=image_uuid.upper(), path=path, line=number))
    return rows


def loaded_image_verdict(console, test_image, utilities_image, xctest_image):
    """Grade loader evidence only; test assertions/terminal results are separate."""
    rows = image_rows(console)
    try:
        for image in (test_image, utilities_image, xctest_image):
            require(isinstance(image, dict) and image.get('path', '').startswith('/'), 'missing actual image path')
            require(re.fullmatch(UUID, image.get('uuid', '')) is not None, 'missing actual image UUID')
            require(re.fullmatch(r'[0-9a-f]{64}', image.get('sha256', '')) is not None, 'missing actual image hash')
            require(image.get('architecture') == 'arm64', 'unexpected image architecture')
            require(image.get('platform') == 'IOSSIMULATOR', 'non-simulator image')
        require(test_image['path'].endswith('.xctest/' + test_image.get('name', '')), 'invalid test image')
        require(utilities_image['path'].endswith('/TestUtilities.framework/TestUtilities'), 'invalid support image')
        require(xctest_image['path'].endswith('/XCTest.framework/XCTest'), 'invalid XCTest image')
        selected = [r for r in rows if r['path'] == test_image['path'] and
                    r['uuid'] == test_image['uuid'].upper()]
        pids = {r['pid'] for r in selected}
        require(len(pids) == 1, 'missing or restarted selected test process')
        pid = pids.pop()
        for image in (utilities_image, xctest_image):
            same_process = [r for r in rows if r['pid'] == pid and r['path'] == image['path'] and
                            r['uuid'] == image['uuid'].upper()]
            require(bool(same_process), 'missing same-process image observation')
        candidates = {(r['path'], r['uuid']) for r in rows if r['pid'] == pid and
                      r['path'].endswith('/XCTest.framework/XCTest')}
        require(candidates == {(xctest_image['path'], xctest_image['uuid'].upper())},
                'ambiguous loaded XCTest image')
        return dict(verdict='PASS_LOADED_IMAGE_ONLY', pid=pid, images=rows, gate_credit=False)
    except EvidenceError as error:
        return dict(verdict='INCOMPLETE_LOADED_IMAGE', fault=str(error), images=rows, gate_credit=False)
