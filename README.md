# checkmk_addons

This repository should contain all my ideas and concepts adressing the very cool monitoring software check**mk**. I try to add to make transparent which parts are in a very experimental state or and which I do consider as usable (or even *stable*). 

List of subprojects:
* Oracle on Windows:
  * The idea is to write a new integration for Oracle in Windows based on Powershell and the usage of the shipped libraries by Oracle. At the moment it's kind of working... in some cases. 
  * Currently open problem is to forward the SQL queries to the API of Oracle without changing the original queries of the mk_oracle for Linux/AIX. The current code is only able to execute a single command and not a whole group of them. 
