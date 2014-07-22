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

        # Quick NoOp check.. if we are nooping, just output what we
        # would have done and then return.
        if noop:
            for array in sa:
                log.info('NOOP: Would have run %s on %s.' % (script, array.soul['name']))
            return

        # Execute our private method now to run the script
        script_results = self._run_script_on_server_array(arrays=sa, script_name=script)

        # If the wait time is > 0, then lets poll for our execution result status
        if wait:
            results = self._get_script_execution_status(script_results, wait=wait)
            return results

    def _run_script_on_server_array(self, arrays, script_name, inputs=None):
        """Directly executes the multi_run_executable call on a Server Array.

        This method bypasses the 'smart' objects in the RightScale object
        because that object balks if the API returns non-JSON (like an empty
        string). This follows the pattern in
        rightscale.commands.run_script_on_server().

        args:
            arrays: A list of rightscale.Resource objects containing ServerArrays
            script: The script name to execute (or recipe)
            inputs: Custom inputs to pass to the script (or recipe)

        returns:
            A dictionary containing the execution status 'url' for each
            script that was executed over each node of each array.

            eg.

            { 'array1': {
                'instanceA': {
                    'status': True,
                    'status_path': '/some_status_url_to_check',
                },
                'instanceB': {
                    'status': False,
                }
            }
        """
        # Figure out if we're running a recipe or a rightscale script. If its
        # a RightScript, we have to go find its URL HREF.
        if '::' in script_name:
            script_name = script_name
            params = {'recipe_name': script_name}
        else:
            script = self._find_right_script(script_name)
            script_name = script.soul['name']
            params = {'right_script_href': script.href}

        # For every array passed in, iterate over the instances
        results = []
        for array in arrays:
            log.debug('Executing %s on %s' % (script_name, array.soul['name']))
            # For every instance in the array, execute the script
            for i in array.current_instances.index():
                log.debug('Executing %s on %s' % (script_name, i.soul['name']))
                url = '%s/run_executable' % i.links['self']
                try:
                    response = self._api.client.post(url, data=params)
                    results.append(response.headers['location'])
                except requests.exceptions.HTTPError:
                    pass

        # Return a raw list of the result URLs
        return results

    def _get_script_execution_status(self, locations, wait=30):
        """Get the script execution status of a list of tasks.

        This method iterates over a supplied list of task-status paths and
        polls for their updated status. It polls each one in in a loop until
        they have all either completed/failed, or the wait timer has expired.

        Any path that returns a results (completed/failed) is pulled
        from the loop and not polled again.

        args:
            locations: A list of task-status urls in RightScale.

        returns:
            A dict with the locations, and their results:

            {'/api/clouds/3/instances/4DQJVQG5I1LO7/live/tasks/ae-294224012003': u'completed:
            Connect instance to ELB',
             '/api/clouds/6/instances/40A8VL6MO1JSC/live/tasks/ae-294224007003': u'completed:
             Connect instance to ELB',
             '/api/clouds/6/instances/5SPSPJ0RTFH6P/live/tasks/ae-294224010003': u'completed:
              Connect instance to ELB'}
        """
        # Track our beginning start time...
        start_time = time.time()

        # Create a store for our results...
        results = {}

        log.debug('Beginning _get_script_execution_status loop...')
        # Iterate through all of the locations and check for updated results
        while (locations and ((time.time() - start_time) < wait)):
            log.debug('Iterating over %s task location paths..' % len(locations))

            # Pop a location off the list so we can work with it
            loc = locations.pop()

            # Check its status
            log.debug('Checking RightScript execution status: %s' % loc)
            status = self._api.client.get(loc).json()
            log.debug('%s status: %s' % (loc, status['summary']))

            # If the status is 'completed/failed', record the results.
            if re.match('^(completed|failed)', status['summary']):
                results[loc] = status['summary']
            else:
                locations.append(loc)

            # Sleep to avoid hammering the API
            time.sleep(1)

        log.debug('Done iterating .... returning what we have')
        return results

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
        scripts = [x for x in scripts if x.soul['name'] in [name]]

        if not scripts:
            err = 'Could not find RightScript matching name: %s' % name
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
            err = 'Could not find ServerArray matching name: %s' % name
            log.error(err)
            raise OperatorException(err)

        log.debug('Got ServerArray: %s' % sa)
        return sa
