#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Copyright (C) 2019 tribe29 GmbH - License: GNU General Public License v2
# This file is part of Checkmk (https://checkmk.com). It is subject to the terms and
# conditions defined in the file COPYING, which is part of this source code package.

from cmk.gui.i18n import _
from cmk.gui.valuespec import (
    Integer,
    Tuple,
    Dictionary,
    Transform,
    ListOfStrings,
    CascadingDropdown,
    RegExp
)

from cmk.gui.plugins.wato import (
    CheckParameterRulespecWithoutItem,
    rulespec_registry,
    RulespecGroupCheckParametersOperatingSystem,
)


def _parameter_valuespec_logins():
    return Transform(
        Dictionary(
            elements=[
                ("levels",
                 Tuple(
                     title=_("Total number of logins"),
                     help=_("Defines upper limits for the number of logins on a system."),
                     elements=[
                         Integer(title=_("Warning at"), unit=_("users"), default_value=20),
                         Integer(title=_("Critical at"), unit=_("users"), default_value=30)
                     ],
                 )),
                ("users",
                 CascadingDropdown(
                     title=_('Permitted or banned users'),
                     choices=[
                         ('permitted_users', _("Permitted users"),
                          ListOf(RegExp(mode=RegExp.prefix))),
                         ('banned_users', _("Banned users"),
                          ListOf(RegExp(mode=RegExp.prefix))),
                     ],
                     help=_("Matching is a regular expression matching the <i>beginning</i> of the pattern.")
                )),
                ("origins",
                 CascadingDropdown(
                     title=_('Permitted or banned origins'),
                     choices=[
                        ('permitted_origins', _('Permitted origins'),
                          ListOf(RegExp(mode=RegExp.prefix))),
                        ('banned_origins', _('Banned origins'),
                          ListOf(RegExp(mode=RegExp.prefix))),
                     ],
                     help=_("Matching is a regular expression matching the <i>beginning</i> of the pattern.")
                )),
                ("login_date", Tuple(
                    title=_("Maximum login duration"),
                    elements=[
                        Age(title=_('Warning at')),
                        Age(title=_('Critical at')),
                    ]),
                )
            ],
        ),
        forth=lambda params: params if isinstance(params, dict) else dict(levels=params),
    )


rulespec_registry.register(
    CheckParameterRulespecWithoutItem(
        check_group_name="logins",
        group=RulespecGroupCheckParametersOperatingSystem,
        parameter_valuespec=_parameter_valuespec_logins,
        title=lambda: _("Number of Logins on System"),
    ))
