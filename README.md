# tplink_smartplug_zabbix
## Overview
This "project" provides a way of querying data from a TP-Link HS110 Smartplug [1] and sending it to a Zabbix server via zabbix_sender.
It makes use of the excellent python-kasa framework [2], which provides a convenient way of querying the smartplug via a simple binary (kasa)

[1]: https://www.tp-link.com/en/home-networking/smart-plug/hs110/
[2]: https://github.com/python-kasa/python-kasa

## Getting started
1. Clone the repository
2. Install `python-kasa` via `pip install python-kasa`
3. Import `tplink_smartplug.xml` to your Zabbix instance
4. Assign the template to a host
5. Run `tplink_smartplug_hs110.sh --hostname <smartplug.ip.or.hostname> --zabbix-server <zabbix.ip.or.hostname>`

## Repository contents
 *  ./tplink_smartplug_hs110.sh - Script to query smartplug and send to remote Zabbix server
 *  ./tplink_smartplug.xml - Zabbix template to make use of already created items
 *  README.md - This readme file.
 *  LICENSE - The GPLv2 license.

## Todo
 * Provide Containerfile to run this code in a container
 
## Contributing
Contributions and feature requests are always welcome!

If you have any additions, examples or bugfixes ready, feel free to create a pull request on GitHub. The pull requests will be reviewed and will be merged as soon as possible. To ease the process of merging the pull requests, please create one pull request per feature/fix, so those can be selectively included in the scripts.

