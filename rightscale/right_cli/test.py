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
Main entry-point script for our RightScale Operational Scripts.
"""

__author__ = 'Matt Wise (matt@nextdoor.com)'

import logging
import optparse

from right_cli import utils
from right_cli import operators
from right_cli.version import __version__ as VERSION

log = logging.getLogger(__name__)

# Initial option handler to set up the basic app environment.
usage = 'usage: %prog <options>'
parser = optparse.OptionParser(usage=usage, version=VERSION,
                               add_help_option=True)
parser.set_defaults(verbose=True)

# Initial RightScale Connection Settings
parser.add_option('-u', '--url', dest='url',
                  default='https://my.rightscale.com',
                  help='RightScale API Endpoint (def: https://my.rightscale.com)')
parser.add_option('-r', '--refresh-token', dest='token',
                  help='RightScale API Refresh Token')

# Options for defining the array we're working on, the script we're executing,
# and any parameters we're supplying (in JSON).
parser.add_option('-s', '--server', dest='server',
                  help='RightScale Server Array or Server name')
parser.add_option('-S', '--script', dest='script',
                  help='RightScript Name to Execute')
parser.add_option('-w', '--wait', dest='wait', default=300,
                  help='Time to wait for scripts to finish (def: 300)')


# Misc Settings
parser.add_option('-n', '--noop', dest="noop", default=False, action='store_true',
                          help='Run script in NoOp mode')
parser.add_option('-l', '--level', dest="level", default='warn',
                          help='Set logging level (INFO|WARN|DEBUG|ERROR)')
(options, args) = parser.parse_args()


def getRootLogger(level, syslog=None):
    level_string = 'logging.%s' % level.upper()
    level_constant = utils.strToClass(level_string)
    return utils.setupLogger(level=level_constant, syslog=syslog)


def main():
    getRootLogger(options.level)
    api = operators.RightScaleOperator(token=options.token, api=options.url)

    api.run_script_on_server_array(
            name=options.server,
            script=options.script,
            noop=options.noop,
            wait=int(options.wait))

if __name__ == '__main__':
    main()
