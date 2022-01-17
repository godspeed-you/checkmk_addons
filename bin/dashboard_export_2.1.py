#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""This tool converts user dashboards to local built in dashboards."""

from os import environ
from sys import argv, exit
import subprocess
from pathlib import Path
import logging
from pprint import pprint
from ast import literal_eval
import argparse

INTERNAL_DASHBOARDS = [
    'checkmk', 'checkmk_host', 'main', 'ntop_alerts', 'ntop_flows',
    'ntop_top_talkers', 'problems', 'simple_problems', 'site'
]


class BaseVars():
    """Provide some basic variables for exporting dashboards"""
    _omd_root = environ.get("OMD_ROOT")
    path = f"{_omd_root}/var/check_mk/web"
    legacy_local_path = f"{_omd_root}/local/share/check_mk/web/plugins/dashboard"
    lib_local_path = f"{_omd_root}/local/lib/check_mk"

    def __init__(self, user, board_name=None, legacy=False):
        self.user = user
        self.board_name = board_name
        self.dashboards = dict()
        self.local_path = str()

        if legacy:
            self.local_path = self.legacy_local_path
        else:
            # We cannot count on the existence of the sub directories... so we need to
            # create them, to be sure.
            Path("{self.lib_local_path}/gui/plugins").mkdir(parents=True,
                                                            exist_ok=True)
            self.local_path = f"{self.lib_local_path}/gui/plugins"

    def get_board_definition(self, name):
        """Return the definition of a given board"""
        return self.dashboards.get(name)


def parse_args(sysargv):
    """
    Compute all given arguments.
    Possible are:
      -u / --user
      -d / --dashboard
    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-u",
                        "--user",
                        required=True,
                        help="User from whom to extract the dashboards.")
    parser.add_argument(
        "-d",
        "--dashboard",
        required=False,
        help=
        "Dashboard to extract. If not provided, all dashboards will be extracted."
    )
    parser.add_argument(
        "-l",
        "--legacy",
        required=False,
        action="store_true",
        help="Create dashboards in the legacy local path instead of the new one"
    )
    parser.add_argument(
        "-i",
        "--include_builtin",
        required=False,
        action="store_true",
        help="Also extract customized builtin dashboards to the local paths.")
    parser.add_argument(
        "-a",
        "--restart_apache",
        required=False,
        action="store_true",
        help=
        "To see you new builtin dashboards, you need to restart the site apache. With this option, this is done automatically at the end."
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="count",
        default=0,
        help="Add debug output. Use several times for more output.")
    return parser.parse_args(sysargv)


def setup_logging(verbosity):
    """Minimal logging for debugging purposes"""
    if verbosity >= 3:
        lvl = logging.DEBUG
    elif verbosity == 2:
        lvl = logging.INFO
    elif verbosity == 1:
        lvl = logging.WARN
    else:
        logging.disable(logging.CRITICAL)
        lvl = logging.CRITICAL
    logging.basicConfig(level=lvl,
                        format="%(asctime)s %(levelname)s %(message)s")


def get_header():
    """Return the start of a dashboard definition"""
    return """#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from cmk.gui.i18n import _
from cmk.gui.plugins.dashboard.utils import builtin_dashboards, GROW, MAX


"""


def write_definition(base):
    """Write a file with the dashboard definition into the local structure of the site"""
    with open(f"{base.local_path}/{base.user}_dashboard_{base.board_name}.py",
              "w") as local_out:
        logging.info("Create '%s'", local_out.name)

        local_out.write(get_header())
        logging.debug("Write dashboard line")
        local_out.write(f"builtin_dashboards[\"{base.board_name}\"] = ")
        logging.debug("Write dashboard content")
        # use pprint to write content. It's better readable later on
        pprint(base.get_board_definition(base.board_name), local_out)


def main():
    """
    Create a local file for each dashboard found for the user.
    The file will be saved below ~/local/share/check_mk/web/plugins/dashboard/ as
    'custom_{dashboard_name}.py'
    """
    args = parse_args(argv[1:])
    incl_builtin = args.include_builtin
    exporter = BaseVars(args.user, args.dashboard, legacy=args.legacy)
    setup_logging(args.verbose)
    logging.debug("Parsed arguments: %s", args)

    dashboard_file = Path(
        f'{exporter.path}/{exporter.user}/user_dashboards.mk')
    if dashboard_file.exists():
        custom_boards = dashboard_file.read_text()
        custom_boards = custom_boards.replace('\n', '')
        exporter.dashboards = literal_eval(custom_boards)
    else:
        exit("No customized dashboards found. Nothing to do.")

    logging.debug("Starting")
    if exporter.board_name and incl_builtin:
        logging.info("Processing %s", exporter.board_name)
        write_definition(exporter)
    else:
        for board in exporter.dashboards:
            if board in INTERNAL_DASHBOARDS and not incl_builtin:
                continue
            logging.info("Processing %s", board)
            exporter.board_name = board
            write_definition(exporter)

    if args.restart_apache:
        subprocess.Popen(('omd', 'restart', 'apache'),
                         stdout=subprocess.PIPE).communicate()


if __name__ == "__main__":
    main()
