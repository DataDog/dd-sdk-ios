#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import os
import re
import sys
import argparse
import traceback
import subprocess
from dataclasses import dataclass

SCHEMAS_REPO = 'https://github.com/DataDog/rum-events-format.git'

# JSON Schema paths (relative to cwd)
RUM_SCHEMA_PATH = '/rum-events-format/schemas/rum-events-mobile-schema.json'
SR_SCHEMA_PATH = '/rum-events-format/schemas/session-replay-mobile-schema.json'

# RC schema lives in the private dd-go repo; cloned sparsely using GITHUB_TOKEN
DD_GO_REPO = 'https://github.com/DataDog/dd-go.git'
RC_SCHEMA_REPO_PATH = 'remote-config/apps/rc-schema-validation/schemas/rum-sdk-config/STAGING/ios.json'
RC_SCHEMA_SPARSE_DIR = 'remote-config/apps/rc-schema-validation/schemas'
RC_SCHEMA_LOCAL_PATH = f'dd-go/{RC_SCHEMA_REPO_PATH}'  # relative to cwd (script_dir)

# Generated file paths (relative to repository root)
RUM_SWIFT_GENERATED_FILE_PATH = '/DatadogInternal/Sources/Models/RUM/RUMDataModels.swift'
RUM_OBJC_GENERATED_FILE_PATH = '/DatadogRUM/Sources/DataModels/RUMDataModels+objc.swift'
SR_SWIFT_GENERATED_FILE_PATH = '/DatadogSessionReplay/Sources/Models/SRDataModels.swift'
RC_SWIFT_GENERATED_FILE_PATH = '/DatadogInternal/Sources/Models/RC/RCDataModels.swift'

@dataclass
class Context:
    # Executable path to Swift CLI (`rum-models-generator`)
    cli_executable_path: str

    # Resolved path to JSON schema describing RUM events
    rum_schema_path: str

    # Resolved path to JSON schema describing Session Replay events
    sr_schema_path: str

    # Resolved path to JSON schema describing Remote Configuration events (fetched from dd-go)
    rc_schema_path: str

    # Git reference to clone/fetch schemas at.
    git_ref: str

    # Resolved path to source code file with RUM model definitions (Swift)
    rum_swift_generated_file_path: str

    # Resolved path to source code file with RUM model definitions (Objc)
    rum_objc_generated_file_path: str

    # Resolved path to source code file with Session Replay model definitions (Swift)
    sr_swift_generated_file_path: str

    # Resolved path to source code file with Remote Configuration model definitions (Swift)
    rc_swift_generated_file_path: str

    # List of type names to skip from code generation in Objective-C
    skip_objc: [str]

    def __repr__(self):
        return f"""
        - cli_executable_path = {self.cli_executable_path},
        - rum_schema_path = {self.rum_schema_path}
        - git_ref = {self.git_ref}
        - sr_schema_path = {self.sr_schema_path}
        - rc_schema_path = {self.rc_schema_path}
        - rum_swift_generated_file_path = {self.rum_swift_generated_file_path}
        - rum_objc_generated_file_path = {self.rum_objc_generated_file_path}
        - sr_swift_generated_file_path = {self.sr_swift_generated_file_path}
        - rc_swift_generated_file_path = {self.rc_swift_generated_file_path}
        """


# Copied from `tools/nightly-unit-tests/src/utils.py`
# TODO: RUMM-1860 Share code between Python tools
def shell_output(command: str):
    """
    Runs shell command and returns its output. Raises an exception if exit code != 0.
    """
    process = subprocess.run(
        args=[command],
        capture_output=True,
        shell=True,
        text=True  # capture STDOUT as text
    )
    if process.returncode == 0:
        return process.stdout
    else:
        raise Exception(
            f'''
            Command {command} exited with status code {process.returncode}
            - STDOUT: {process.stdout if process.stdout != '' else '""'}
            - STDERR: {process.stderr if process.stderr != '' else '""'}
            '''
        )


def build_swift_cli():
    """
    Builds `rum-models-generator` package and returns executable path.
    :return: the CLI's executable path
    """
    print('⚙️ Building `rum-models-generator` Swift package...')
    shell_output('swift build --configuration release')
    cli_dir = shell_output('swift build --configuration release --show-bin-path').rstrip('\n')
    cli_path = cli_dir + '/rum-models-generator'
    return cli_path


def clone_schemas_repo(git_ref: str):
    """
    Clones `rum-events-format` repo at given `git_ref` into current location and reads the SHA of last commit.
    :return: the SHA of last commit
    """
    print(f'⚙️ Cloning `rum-events-format` repository at "{git_ref}"...')
    shell_output('rm -rf rum-events-format')
    shell_output(f'git clone {SCHEMAS_REPO}')
    shell_output(f'cd rum-events-format && git fetch origin {git_ref} && git checkout FETCH_HEAD')
    sha = shell_output(f'cd rum-events-format && git rev-parse HEAD')
    return sha


def read_sha_from_generated_file(path):
    """
    Reads SHA from the last line of existing (generated) file.
    :return: the SHA of schemas repo commit that was used to generate this file
    """
    sha_regex = r'([0-9a-f]{5,40})'

    with open(path) as generated_file:
        last_line = generated_file.readlines()[-1]
        if match := re.findall(sha_regex, last_line):
            return match[0]
        else:
            raise Exception(f'Failed to read SHA from last line of {path}. Last line is: "{last_line}"')


def generate_code(ctx: Context, language: str, convention: str, json_schema: str, source_url: str):
    """
    Generates code for given language and conventions from provided JSON schema.
    :param ctx: generation `Context`
    :param language: 'swift' or 'objc'
    :param convention: 'rum', 'sr', or 'rc'
    :param json_schema: the path to JSON schema
    :param source_url: URL appended as the final comment (e.g. GitHub permalink to the schema file)
    :return: generated code as it should be written to target `*.swift` file
    """
    skip = ""
    if language == 'objc':
        skip = f' --skip {" ".join(ctx.skip_objc)}'

    cli_command = f'{ctx.cli_executable_path} generate-{language} --convention {convention} --path "{json_schema}" {skip}'
    code = shell_output(cli_command)
    code += f'// Generated from {source_url}'
    return code


def validate_code(ctx: Context, language: str, convention: str, json_schema: str, target_file: str, source_url: str):
    """
    Verifies if code in given target file matches its definition generated from given JSON schema.
    :param ctx: generation `Context`
    :param language: 'swift' or 'objc'
    :param convention: 'rum', 'sr', or 'rc'
    :param json_schema: the path to JSON schema
    :param target_file: the file to verify
    :param source_url: URL used in the trailing comment; must match what was used during generation
    :return:
    """
    with open(target_file, 'r') as file:
        actual_code = file.read()
        expected_code = generate_code(
            ctx, language=language, convention=convention, json_schema=json_schema, source_url=source_url
        )
        if actual_code != expected_code:
            raise Exception(f'The code in {target_file} does not match models generated from {source_url}')


def rum_events_format_source_url(sha: str):
    return f'https://github.com/DataDog/rum-events-format/tree/{sha}'


def generate_rum_models(ctx: Context):
    sha = clone_schemas_repo(git_ref=ctx.git_ref)
    source_url = rum_events_format_source_url(sha)

    with open(ctx.rum_swift_generated_file_path, 'w') as file:
        file.write(generate_code(ctx, language='swift', convention='rum', json_schema=ctx.rum_schema_path, source_url=source_url))

    with open(ctx.rum_objc_generated_file_path, 'w') as file:
        file.write(generate_code(ctx, language='objc', convention='rum', json_schema=ctx.rum_schema_path, source_url=source_url))


def generate_sr_models(ctx: Context):
    sha = clone_schemas_repo(git_ref=ctx.git_ref)
    source_url = rum_events_format_source_url(sha)

    with open(ctx.sr_swift_generated_file_path, 'w') as file:
        file.write(generate_code(ctx, language='swift', convention='sr', json_schema=ctx.sr_schema_path, source_url=source_url))


def validate_rum_models(ctx: Context):
    swift_sha = read_sha_from_generated_file(path=ctx.rum_swift_generated_file_path)
    objc_sha = read_sha_from_generated_file(path=ctx.rum_objc_generated_file_path)

    if swift_sha != objc_sha:
        raise Exception(f'SHAs in generated RUM swift and objc code do not match ({swift_sha} != {objc_sha}).')

    sha = clone_schemas_repo(git_ref=swift_sha)
    source_url = rum_events_format_source_url(sha)

    validate_code(ctx, language='swift', convention='rum', json_schema=ctx.rum_schema_path,
                  target_file=ctx.rum_swift_generated_file_path, source_url=source_url)

    validate_code(ctx, language='objc', convention='rum', json_schema=ctx.rum_schema_path,
                  target_file=ctx.rum_objc_generated_file_path, source_url=source_url)


def validate_sr_models(ctx: Context):
    sha = read_sha_from_generated_file(path=ctx.sr_swift_generated_file_path)
    sha = clone_schemas_repo(git_ref=sha)
    source_url = rum_events_format_source_url(sha)

    validate_code(ctx, language='swift', convention='sr', json_schema=ctx.sr_schema_path,
                  target_file=ctx.sr_swift_generated_file_path, source_url=source_url)


def clone_rc_schema_repo(git_ref: str):
    """
    Sparsely clones the dd-go repo at the given git_ref, checking out only the RC schema directory.
    Requires a GITHUB_TOKEN environment variable for authentication.
    :param git_ref: branch name, tag, or commit SHA in dd-go (e.g. 'prod')
    :return: the SHA of the checked-out commit
    """
    token = os.environ.get('GITHUB_TOKEN')
    if not token:
        raise Exception('GITHUB_TOKEN environment variable is required to clone the private dd-go repository.')

    print(f'⚙️ Cloning `dd-go` repository (sparse) at "{git_ref}"...')
    # Authenticate via a credential helper that reads `GITHUB_TOKEN` from the environment at
    # runtime, so the token itself never appears in the cloned URL, the process command line,
    # or `shell_output`'s failure output (which echoes the command it ran).
    credential_helper = '!f() { echo "username=x-access-token"; echo "password=$GITHUB_TOKEN"; }; f'
    shell_output('rm -rf dd-go')
    shell_output(f'git -c credential.helper="{credential_helper}" clone --depth=1 --filter=blob:none --sparse {DD_GO_REPO}')
    shell_output(f'cd dd-go && git sparse-checkout set {RC_SCHEMA_SPARSE_DIR}')
    shell_output(f'cd dd-go && git fetch origin {git_ref} && git checkout FETCH_HEAD')
    sha = shell_output('cd dd-go && git rev-parse HEAD').strip()
    return sha


def dd_go_source_url(sha: str):
    return f'https://github.com/DataDog/dd-go/blob/{sha}/{RC_SCHEMA_REPO_PATH}'


def generate_rc_models(ctx: Context):
    sha = clone_rc_schema_repo(git_ref=ctx.git_ref)

    os.makedirs(os.path.dirname(ctx.rc_swift_generated_file_path), exist_ok=True)
    with open(ctx.rc_swift_generated_file_path, 'w') as file:
        file.write(generate_code(ctx, language='swift', convention='rc', json_schema=ctx.rc_schema_path,
                                 source_url=dd_go_source_url(sha)))


def validate_rc_models(ctx: Context):
    sha = read_sha_from_generated_file(path=ctx.rc_swift_generated_file_path)
    clone_rc_schema_repo(git_ref=sha)

    validate_code(ctx, language='swift', convention='rc', json_schema=ctx.rc_schema_path,
                  target_file=ctx.rc_swift_generated_file_path, source_url=dd_go_source_url(sha))


if __name__ == "__main__":
    # Change working directory to `/tools/rum-models-generator/`
    print(f'ℹ️ Launch dir: {sys.argv[0]}')
    script_path = os.path.abspath(sys.argv[0])
    script_dir = os.path.dirname(script_path)
    repository_root = os.path.abspath(f'{script_dir}/../..')
    os.chdir(script_dir)

    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=['generate', 'verify'], help="Run mode")
    parser.add_argument("product", choices=['rum', 'sr', 'rc'], help="'rum' (RUM), 'sr' (Session Replay), or 'rc' (Remote Configuration)")
    parser.add_argument("--git_ref", help="Git reference to use: branch/tag/SHA in rum-events-format for 'rum'/'sr', or branch/tag/SHA in dd-go for 'rc' (e.g. 'prod').")
    parser.add_argument("--skip_objc", help="List of type names to skip in Objective-C generation", nargs='*', type=str, default=[])
    args = parser.parse_args()

    try:
        context = Context(
            cli_executable_path=build_swift_cli(),
            rum_schema_path=os.path.abspath(f'{script_dir}/{RUM_SCHEMA_PATH}'),
            sr_schema_path=os.path.abspath(f'{script_dir}/{SR_SCHEMA_PATH}'),
            rc_schema_path=os.path.abspath(f'{script_dir}/{RC_SCHEMA_LOCAL_PATH}'),
            git_ref=args.git_ref if args.command else None,
            rum_swift_generated_file_path=os.path.abspath(f'{repository_root}/{RUM_SWIFT_GENERATED_FILE_PATH}'),
            rum_objc_generated_file_path=os.path.abspath(f'{repository_root}/{RUM_OBJC_GENERATED_FILE_PATH}'),
            sr_swift_generated_file_path=os.path.abspath(f'{repository_root}/{SR_SWIFT_GENERATED_FILE_PATH}'),
            rc_swift_generated_file_path=os.path.abspath(f'{repository_root}/{RC_SWIFT_GENERATED_FILE_PATH}'),
            skip_objc=args.skip_objc
        )

        print(f'⚙️ Generation context: {context}')

        if args.command == 'generate':
            if args.product == 'rum':
                print(f'⚙️ Generating RUM models...')
                generate_rum_models(ctx=context)

            elif args.product == 'sr':
                print(f'⚙️ Generating Session Replay models...')
                generate_sr_models(ctx=context)

            elif args.product == 'rc':
                print(f'⚙️ Generating Remote Configuration models...')
                generate_rc_models(ctx=context)

        elif args.command == 'verify':
            if args.product == 'rum':
                print(f'⚙️ Verifying RUM models...')
                validate_rum_models(ctx=context)

            elif args.product == 'sr':
                print(f'⚙️ Verifying Session Replay models...')
                validate_sr_models(ctx=context)

            elif args.product == 'rc':
                print(f'⚙️ Verifying Remote Configuration models...')
                validate_rc_models(ctx=context)

        print(f'✅️ OK')

    except Exception as error:
        print(f'❌ Failed on: {error}')
        print('-' * 60)
        traceback.print_exc(file=sys.stdout)
        print('-' * 60)
        sys.exit(1)

    sys.exit(0)
