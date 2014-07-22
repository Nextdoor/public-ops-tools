# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Copyright 2014 Nextdoor.com, Inc

"""
Main RightScale Operator object that initiates RightScale actions
"""

import logging
import time
import re
import requests

from rightscale import commands as rightscale_commands
from rightscale import util as rightscale_util
import rightscale

log = logging.getLogger(__name__)


class OperatorException(Exception):
    pass


class RightScaleOperator(object):
    def __init__(self, token, api):
        """Initializes the RightScaleOperator Object for a RightScale Account.

        args:
            token: A RightScale RefreshToken
            api: API URL Endpoint
        """
        log.debug('Initializing RightScaleOperator(token=<hidden>, api=%s)' % api)
        self._api = rightscale.RightScale(refresh_token=token, api_endpoint=api)

    def run_script_on_server_array(self, name, script, noop=False, wait=0):
        """Executs a RightScript on an array.

        args:
            name: The name of the ServerArray
            script: The name of the Script
            noop: Boolean whether to run on all hosts or just one.
            wait: Seconds to wait until scripts finish before returning.
        """
        # Get a list of server arrays that match the name supplied
        sa = self._find_server_arrays(name, exact=False)

        if not type(sa) == rightscale_util.HookList:
            sa = [sa]

        # If the script has a :: in it, its a recipe and we can reference it
        # directly. Otherwise its a script and we have to search for it.
        recipe_name = None
        right_script_href = None
        if '::' in script:
            recipe_name = script
            script_name = script
        else:
            right_script = self._find_right_script(script)
            right_script_href = right_script.href
            script_name = right_script.soul['name']

        # Quick NoOp check.. if we are nooping, just output what we
        # would have done and then return.
        if noop:
            for array in sa:
                log.info('NOOP: Would have run %s on %s.' % (script_name, array.soul['name']))
            return

        # Execute our private method now to run the script
        self._run_script_on_server_array(arrays=sa, right_script_href=right_script_href, recipe_name=recipe_name, wait=wait)

    def _run_script_on_server_array(self, arrays, right_script_href=None, recipe_name=None, inputs=None, wait=0):
        """Directly executes the multi_run_executable call on a Server Array.

        This method bypasses the 'smart' objects in the RightScale object
        because that object balks if the API returns non-JSON (like an empty
        string). This follows the pattern in
        rightscale.commands.run_script_on_server().
        """

        if right_script_href:
            params = { 'right_script_href': right_script_href }
        elif recipe_name:
            params = { 'recipe_name': recipe_name }
        else:
            raise Exception('Did not supply a script or recipe')

        # Store the returned status-hrefs in this array
        status = {}

        # For every array passed in, execute the script
        for array in arrays:
            url = '%s/multi_run_executable' % array.href

            log.debug('Executing Script %s on ServerArray %s' % (url, array.soul['name']))
            try:
                response = self._api.client.post(url, data=params)
                array_status = { 'status': None,
                                 'path': (response.headers['location']) }
                status[array] = array_status
            except requests.exceptions.HTTPError:
                pass

        # If we're waiting for the results, we loop and over all
        # of the returned status paths until every one of them has returned
        # with a 'completed' status.
        for i in range(wait):
            for array, values in status.iteritems():
                dirty = False

                if not status[array]['status']:
                    status[array]['status'] = self._get_script_execution_status(values['path'])
                    dirty = True
                    continue

                if not re.match('(completed|failed)', status[array]['status']):
                    status[array]['status'] = self._get_script_execution_status(values['path'])
                    log.info('Waiting for script to finish on ServerArray %s: %s' %
                             (array.soul['name'], status[array]['status']))
                    dirty = True

            if not dirty:
                log.debug('All results are in, returning.')
                break

            time.sleep(1)

        return status

    def _get_script_execution_status(self, status_path):
        log.debug('Checking RightScript execution status: %s' % status_path)
        status = self._api.client.get(status_path).json()
        return status.get('summary', 'unknown')

    def _find_right_script(self, name, latest=True):
        """Search for RightScript resources by name.

        args:
            name: RightScale RightScript Name
            latest: Boolean of whether to return only the latest script or not.

        returns:
            rightscale.Resource object
        """
        log.debug('Searching for RightScript matching name %s' % name)
        # Get a list of matching scripts ... but, don't do exact-match because the
        # logic in the find_by_name() method returns the first matching resource,
        # which isn't the one we likely want.
        scripts = rightscale_util.find_by_name(self._api.right_scripts, name, exact=False)

        # Parse through the list of returned scripts. Only keep the scripts that
        # exactly match the name supplied by the user.
        scripts = [ x for x in scripts if x.soul['name'] in [name] ]

        if not scripts:
            err='Could not find RightScript matching name: %s' % name
            log.error(err)
            raise OperatorException(err)

        if latest:
            # Find the highest-revision number in the returned list
            script = max(scripts, key=lambda x: x.soul.get('revision'))
            log.debug('Got RightScript: %s' % script)
            return script

        log.debug('Got RightScripts: %s' % scripts)
        return scripts

    def _find_server_arrays(self, name, exact=True):
        """Search for a list of RightScale Server Array by name and return the resources.

        args:
            name: RightScale ServerArray Name
            exact: Return a single exact match, or multiple matching resources.

        returns:
            rightscale.Resource object
        """
        log.debug('Searching for ServerArray matching name %s' % name)
        sa = rightscale_util.find_by_name(self._api.server_arrays, name, exact=exact)

        if not sa:
            err='Could not find ServerArray matching name: %s' % name
            log.error(err)
            raise OperatorException(err)

        log.debug('Got ServerArray: %s' % sa)
        return sa
