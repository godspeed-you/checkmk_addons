# checkmk_addons

This repository should contain all my ideas and concepts adressing the very cool monitoring software check**mk**. I try to add to make transparent which parts are in a very experimental state or and which I do consider as usable (or even *stable*). 

List of subprojects:
* [Oracle on Windows](README_mk_oracle_win.md):
  * The idea is to write a new integration for Oracle in Windows based on Powershell and the usage of the shipped libraries by Oracle. At the moment it's kind of working... in some cases. 
  * Currently open problem is to forward the SQL queries to the API of Oracle without changing the original queries of the mk_oracle for Linux/AIX. The current code is only able to execute a single command and not a whole group of them. 
* [Special Agent for Fritz!Box](README_agent_fritzbox.md):
  * There is a very good module for the API of fritzbox devices called [fritzconnection](https://github.com/lukasklein/fritzconnection). The reworked agent does make use of that module and fetches a lot more information than the old implementation.
  * Currenty I added two very basic check plugins for the agent and the support is for the unreleased check**mk** version only.
  * You need to install fritzconnection as site user, to use this plugin: `pip install fritzconnection` - See the specific README for more information.
* [Monitoring of current Logins](README_mk_logins.md):
  * The regular checking is not sufficient enough. On some systems you may want to allow/deny specific origins from which it is allow to log in or users that are allowed to log in. Also a time specific mesearement is possible. This extension should handle these use cases in a first draft.
  * Currently open is the requirement to allow specific users of specific origins for a specific amount of time. Or vice versa. But that's complicated...
* [Notifcation via telegram](README_telegram):
  * There are several telegram extensions out there - And I was not completely happy with any of them. This one is using the latest improvements of Checkmk 2.0.0 so the extension itself is quite small. 
  * Currently not possible to modify the notification body on the web interface itself. Simply because I don't need it...
  * Currently not possible to ackn an event through telegram itself. Only had some ideas about a possible architecture...
