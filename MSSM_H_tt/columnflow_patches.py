# coding: utf-8

"""
Collection of patches of underlying columnflow tasks.
"""

import os

import law
from columnflow.util import memoize


logger = law.logger.get_logger(__name__)


# Number of original NanoAOD files processed per branch.
#
# With EVENT_FILE_MERGING = 10:
#
#   original files 0-9   -> branch 0
#   original files 10-19 -> branch 1
#   ...
#
# The final branch can contain fewer than 10 files.
EVENT_FILE_MERGING = 10


@memoize
def patch_bundle_repo_exclude_files():
    from columnflow.tasks.framework.remote import BundleRepo

    # get the relative path to CF_BASE
    cf_rel = os.path.relpath(
        os.environ["CF_BASE"],
        os.environ["HTTCP_BASE"],
    )

    # amend exclude files to start with the relative path to CF_BASE
    exclude_files = [
        os.path.join(cf_rel, path)
        for path in BundleRepo.exclude_files
    ]

    # add additional files
    exclude_files.extend([
        "docs",
        "tests",
        "data",
        "assets",
        ".law",
        ".setups",
        ".data",
        ".github",
    ])

    # overwrite them
    BundleRepo.exclude_files[:] = exclude_files

    logger.debug(
        "patched exclude_files of cf.BundleRepo"
    )


@memoize
def patch_event_file_merging():
    """
    Process up to EVENT_FILE_MERGING original NanoAOD files in each
    CalibrateEvents, SelectEvents and ReduceEvents branch.

    This changes the branch structure from one branch per NanoAOD file
    to one branch per group of EVENT_FILE_MERGING NanoAOD files.
    """

    from columnflow.tasks.calibration import CalibrateEvents
    from columnflow.tasks.selection import SelectEvents
    from columnflow.tasks.reduction import ReduceEvents

    task_classes = (
        CalibrateEvents,
        SelectEvents,
        ReduceEvents,
    )

    for task_cls in task_classes:
        task_cls.file_merging = EVENT_FILE_MERGING

    logger.info(
        "patched event-level file merging: "
        f"CalibrateEvents={EVENT_FILE_MERGING}, "
        f"SelectEvents={EVENT_FILE_MERGING}, "
        f"ReduceEvents={EVENT_FILE_MERGING}"
    )


@memoize
def patch_all():
    patch_bundle_repo_exclude_files()
    patch_event_file_merging()