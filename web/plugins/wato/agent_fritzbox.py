#!/usr/bin/python
import cmk.gui.watolib as watolib
from cmk.gui.exceptions import MKUserError
from cmk.gui.i18n import _
from cmk.gui.plugins.wato import (
    IndividualOrStoredPassword,
    RulespecGroup,
    rulespec_group_registry,
    rulespec_registry,
    HostRulespec,
)
from cmk.gui.valuespec import (
    Dictionary,
    Password,
    TextAscii,
)


@rulespec_group_registry.register
class RulespecGroupDatasourcePrograms(RulespecGroup):
    @property
    def name(self):
        return "datasource_programs"

    @property
    def title(self):
        return _("Datasource Programs")

    @property
    def help(self):
        return _("Specialized agents, e.g. check via SSH, ESX vSphere, SAP R/3")


@rulespec_registry.register
class RulespecSpecialAgentsFritzbox(HostRulespec):
    @property
    def group(self):
        return RulespecGroupDatasourcePrograms

    @property
    def name(self):
        return "special_agents:fritzbox"

    @property
    def factory_default(self):
        # No default, do not use setting if no rule matches
        return watolib.Rulespec.FACTORY_DEFAULT_UNUSED

    @property
    def valuespec(self):
        return Dictionary(
            title=_("Agent Fritz!Box"),
            help=_("This rule selects the Fritz!Box agent, which uses UPNP to gather information "
                   "about configuration and connection status information."),
            elements=[
                ('user', TextAscii(title=_('User'))),
                ('password', Password(title=_('Password'))),
            ],
            optional_keys=["user", "password"],
        )
