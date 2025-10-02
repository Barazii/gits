import os
import sys
import json
import base64
from datetime import datetime, timezone, timedelta
import importlib
import pytest

ENV_VARS = {
    'AWS_BUCKET_NAME': 'test-bucket',
    'AWS_CODEBUILD_PROJECT_NAME': 'project-x',
    'AWS_ACCOUNT_ID': '123456789012',
    'AWS_APP_REGION': 'eu-central-1',
    'EVENTBRIDGE_TARGET_ROLE_ARN': 'arn:aws:iam::123456789012:role/EBRole'
}

MODULE_PATH = 'lambda_function.lambda_handler'


class Recorder:
    def __init__(self):
        self.calls = []
    def put_object(self, **kwargs):
        self.calls.append(('put_object', kwargs))
    def put_rule(self, **kwargs):
        self.calls.append(('put_rule', kwargs))
        return {"RuleArn": "arn:aws:events:region:acct:rule/test"}
    def put_targets(self, **kwargs):
        self.calls.append(('put_targets', kwargs))


def _reload_module():
    if MODULE_PATH in sys.modules:
        del sys.modules[MODULE_PATH]
    return importlib.import_module(MODULE_PATH)


def future_time():
    return (datetime.now(timezone.utc) + timedelta(minutes=5)).strftime('%Y-%m-%dT%H:%M:%SZ')


@pytest.fixture(autouse=True)
def env_setup(monkeypatch):
    for k, v in ENV_VARS.items():
        monkeypatch.setenv(k, v)


@pytest.fixture
def recorders(monkeypatch):
    s3 = Recorder()
    events = Recorder()
    def fake_client(service, region_name=None):
        if service == 's3':
            return s3
        if service == 'events':
            return events
        raise ValueError(service)
    # Patch boto3.client globally
    import boto3
    monkeypatch.setattr(boto3, 'client', fake_client)
    return s3, events


def invoke(payload, proxy=True):
    mod = _reload_module()
    event = {'body': json.dumps(payload)} if proxy else payload
    return mod.lambda_handler(event, None)


def test_successful_schedule(recorders):
    s3, events = recorders
    body = {
        'schedule_time': future_time(),
        'repo_url': 'https://github.com/owner/repo.git',
        'zip_filename': 'changes.zip',
        'zip_base64': base64.b64encode(b'zipcontent').decode(),
        'github_token_secret': 'GH_SECRET_NAME'
    }
    resp = invoke(body)
    assert resp['statusCode'] == 200, resp
    out = json.loads(resp['body'])
    assert 'rule_name' in out and 's3_path' in out
    # Verify call order types
    call_names = [c[0] for c in s3.calls + events.calls]
    assert 'put_object' in call_names
    assert 'put_rule' in call_names
    assert 'put_targets' in call_names


def test_missing_fields(recorders):
    s3, events = recorders
    body = {
        'schedule_time': future_time(),
        'repo_url': 'https://github.com/owner/repo.git'
    }
    resp = invoke(body)
    assert resp['statusCode'] == 400
    assert 'Missing required fields' in resp['body']
    assert not s3.calls and not events.calls


def test_invalid_repo_url(recorders):
    s3, events = recorders
    body = {
        'schedule_time': future_time(),
        'repo_url': 'git@github.com:owner/repo.git',
        'zip_filename': 'f.zip',
        'zip_base64': base64.b64encode(b'data').decode(),
        'github_token_secret': 'x'
    }
    resp = invoke(body)
    assert resp['statusCode'] == 400
    assert 'HTTPS' in resp['body']
    assert not s3.calls and not events.calls


def test_past_time(recorders):
    s3, events = recorders
    past_time = (datetime.now(timezone.utc) - timedelta(minutes=1)).strftime('%Y-%m-%dT%H:%M:%SZ')
    body = {
        'schedule_time': past_time,
        'repo_url': 'https://github.com/owner/repo.git',
        'zip_filename': 'f.zip',
        'zip_base64': base64.b64encode(b'data').decode(),
        'github_token_secret': 'x'
    }
    resp = invoke(body)
    assert resp['statusCode'] == 400
    assert 'future' in resp['body']
    assert not s3.calls and not events.calls
