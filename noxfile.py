#
# MIT License
#
# (C) Copyright [2024] Hewlett Packard Enterprise Development LP
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
""" Nox definitations for tests, docs, and linting
"""
from __future__ import absolute_import
import os

import nox  # pylint: disable=import-error


COVERAGE_FAIL = 95

PYTHON = ['3']

EXTRA_INDEX = (
    "--extra-index-url="
    "https://artifactory.algol60.net/artifactory/csm-python-modules/simple"
)

@nox.session(python=PYTHON)
def lint(session):
    """Run linters.
    Returns a failure if the linters find linting errors or sufficiently
    serious code quality issues.
    """
    run_cmd = [
        'pylint',
        'vtds_application_openchami',
    ]
    if session.python:
        session.install(EXTRA_INDEX, '.[lint]')
    session.run(*run_cmd)


@nox.session(python=PYTHON)
def style(session):
    """Run code style checker.
    Returns a failure if the style checker fails.
    """
    run_cmd = [
        'pycodestyle',
        '--config=.pycodestyle',
        'vtds_application_openchami',
    ]
 
    if session.python:
        session.install(EXTRA_INDEX, '.[style]')
    session.run(*run_cmd)


@nox.session(python=PYTHON)
def tests(session):
    """Default unit test session.
    """
    # Install all test dependencies, then install this package in-place.
    path = 'tests'
    if session.python:
        session.install(EXTRA_INDEX, '.[test]')

    # XXX - disable tests until we have some...
    session.run('/usr/bin/true', external=True)
#    # Run py.test against the tests.
#    session.run(
#        'py.test',
#        '--quiet',
#        '-W',
#        'ignore::DeprecationWarning',
#        '--cov=vtds_base',
#        '--cov=tests',
#        '--cov-append',
#        '--cov-config=.coveragerc',
#        '--cov-report=',
#        '--cov-fail-under={}'.format(COVERAGE_FAIL),
#        os.path.join(path),
#        env={}
#    )



@nox.session(python=PYTHON)
def cover(session):
    """Run the final coverage report.
    This outputs the coverage report aggregating coverage from the unit
    test runs, and then erases coverage data.
    """
    if session.python:
        session.install(EXTRA_INDEX, '.[cover]')
    # Disable coverage tests until we have some...
    session.run('/usr/bin/true', external=True)
#    session.run('coverage', 'report', '--show-missing',
#                '--fail-under={}'.format(COVERAGE_FAIL))
#    session.run('coverage', 'erase')
