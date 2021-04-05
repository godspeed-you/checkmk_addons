#!/usr/bin/env python3
# -*- coding: utf-8 -*-


# Copyright (C) 2021 Marcel Arentz <marcel.arentz@tribe29.com>
# License: GNU General Public License v2
# This file is an extension of Checkmk (https://checkmk.com). It is subject to the terms and
# conditions defined in the file COPYING, which is part of this source code package.

from cmk.gui.valuespec import (
    TextUnicode,
    FixedValue,
    CascadingDropdown,
)

from cmk.gui.plugins.wato import (
    notification_parameter_registry,
    NotificationParameter,
    HTTPProxyReference,
    IndividualOrStoredPassword,
)

@notification_parameter_registry.register
class NotificationParameterTelegram(NotificationParameter):
    @property
    def ident(self):
        return "telegram"

    @property
    def spec(self):
        return Dictionary(
            title=_("Create notification with the following parameters"),
            optional_keys=["proxy_url"],
            elements=[
                ("token",
                 IndividualOrStoredPassword(
                     title=_("Token"),
                     allow_empty=False
                )),
                ("chatid", CascadingDropdown(
                    title=_("Source of chat ID"),
                    choices=[
                        ("pager", _("Pager address"),
                         FixedValue('CONTACTPAGER',
                         _("User pager address is used to get the chat ID"))),
                        ("custom", _("Custom field"),
                         TextUnicode(title=_("Custom user attribute "), default_value=""))
                    ],
                    help=_("You may use the user pager address as source for "
                           "the chat id or a custom user attribute. If you do "
                           "so, please specficy the attribute as "
                           "<i>CONTACT_{ID of attribute}</i>.")
                )),
                ("proxy_url", HTTPProxyReference()),
            ]
        )
