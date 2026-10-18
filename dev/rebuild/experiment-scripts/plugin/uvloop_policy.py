"""pytest plugin: every test's event loop is uvloop's (pytest-asyncio takes the policy from this fixture)."""
import pytest
import uvloop


@pytest.fixture(scope="session")
def event_loop_policy():
    return uvloop.EventLoopPolicy()
