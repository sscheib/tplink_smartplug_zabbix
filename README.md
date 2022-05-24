# tplink_smartplug_zabbix
## Overview
This "project" provides a way of querying data from a TP-Link HS110 Smartplug [1] and sending it to a Zabbix server via zabbix_sender.
It makes use of the excellent python-kasa framework [2], which provides a convenient way of querying the smartplug via a simple binary (kasa)

Currently supported Smartplugs:
- TP-Link HS110 (EU)
- TP-Link KP115 (EU)

It is very likely that the same models, which have been produced for the market outside the EU are working is well, but since I have no means of testing that, they are explicitly listed as EU variants. Feel free to test other models and add them as contribution!

[1]: https://www.tp-link.com/en/home-networking/smart-plug/hs110/
[2]: https://github.com/python-kasa/python-kasa

## Getting started
1. Clone the repository
2. Install `python-kasa` via `pip install python-kasa`
3. Import `tplink_smartplug.xml` to your Zabbix instance
4. Assign the template to a host
5. Run `tplink_smartplug_hs110.sh --hostname <smartplug.ip.or.hostname> --zabbix-server <zabbix.ip.or.hostname>`

## Repository contents
 *  ./tplink_smartplug.sh - Script to query smartplug and send to remote Zabbix server
 *  ./tplink_smartplug_base.xml - Zabbix base template to make use of already created items. This is the base set of items which seem to be common across multiple models (tested between HS110 and KP115 - both in the EU variant). Various inventory items are populated (such as MAC)
 *  ./tplink_smartplug_kp115.xml - Zabbix template which basically extends the base template to support all items that are available on the KP115 (EU) variant
 *  README.md - This readme file.
 *  LICENSE - The GPLv2 license.

## Todo
 * Provide Containerfile to run this code in a container
 
## Contributing
Contributions and feature requests are always welcome!

If you have any additions, examples or bugfixes ready, feel free to create a pull request on GitHub. The pull requests will be reviewed and will be merged as soon as possible. To ease the process of merging the pull requests, please create one pull request per feature/fix, so those can be selectively included in the scripts.

