# tplink_smartplug_zabbix
## Overview
This "project" provides a way of querying data from a TP-Link HS110 Smartplug [^1] and sending it to a Zabbix server via `zabbix_sender`.
It makes use of the excellent python-kasa framework [^2], which provides a convenient way of querying the smartplug via a simple binary (kasa)

Currently supported Smartplugs:
- TP-Link HS110 (EU)
- TP-Link KP115 (EU)

It is very likely that the same models, which have been produced for the market outside the EU are working as well, but since I have no means of testing that, they are explicitly listed as EU variants. Feel free to test other models and add them as contribution!

[^1]: https://www.tp-link.com/en/home-networking/smart-plug/hs110/
[^2]: https://github.com/python-kasa/python-kasa

## Getting started
### Command-line usage
*  Clone the repository using `git clone https://github.com/sscheib/tplink_smartplug_zabbix`
*  Install `python-kasa` via `pip install python-kasa`
*  Import `templates/tplink_smartplug_base.xml` to your Zabbix instance and additionally (if needed) `templates/tplink_smartplug_kp115.xml`
*  Assign the template to a host
*  Run `bash tplink_smartplug_hs110.sh --host <smartplug.ip.or.hostname> --zabbix-server <zabbix.ip.or.hostname>`

### Container usage
* A container is available at [hub.docker.com/r/steffenscheib/tplink_smartplug_zabbix](https://hub.docker.com/r/steffenscheib/tplink_smartplug_zabbix)

#### podman run
* Using `podman run`, the following command will spawn a container, gather the values, send it to Zabbix and gets destroyed afterwards:
`podman run --rm -e 'ZBX_SERVER=<zabbix.fqdn>' -e "SMARTPLUG_HOST=<smartplug.fqdn>" steffenscheib/tplink_smartplug_zabbix`

#### docker-compose
* Using `docker-compose`, the following example can be used to adapt it to your needs
```
version: '3'
services:
  my_smartplug_value_gatherer:
    image: 'steffenscheib/tplink_smartplug_zabbix'
    container_name: 'my_smartplug_value_gatherer'
    environment:
      - 'ZBX_SERVER=zabbix.example.com'
      - 'SMARTPLUG_HOST=smartplug.example.com'
      - 'VERBOSE=true'
```
* Using `docker-compose up -d`, the container will be spawned and gathers the values
* To destroy it again, use `docker-compose down`

### Building the container
* Clone the repository using `git clone https://github.com/sscheib/tplink_smartplug_zabbix`
* Run `buildah build -f tplink_smartplug_zabbix/Containerfile -t tplink_smartplug_zabbix:latest`

## Zabbix Template
* The template was exported from a Zabbix 5.0 LTS instance
* It contains two triggers
    * Firmware changed: Gets fired whenever the item `sw_ver` contains a different value compared to the previous value
    * No data received for `{$SMARTPLUG_MAX_NO_DATA}`: Gets fired when no data is received on the item `power_sw`
    * By default `{$SMARTPLUG_MAX_NO_DATA}` is set to 30 minutes - this can of course be overridden on both template and host layer
* Please note: Only `tplink_smartplug_base.xml` contains the triggers, as I consider `tplink_smartplug_kp115.xml` (or any other further model-specific templates) to be used as an add-on to the base template

## Repository contents
*  `./src/tplink_smartplug.sh` - Script to query a TP-Link smartplug and send the retrieved data to a remote Zabbix server
*  `./containerfiles/init.sh` - Init script for the container that takes care of transforming environment variables to actual commandline options for `tplink_smartplug.sh`
*  `./templates/tplink_smartplug_base.xml` - Zabbix base template to make use of already created items. This is the base set of items which seem to be common across multiple models (tested between HS110 and KP115 - both in the EU variant). Various inventory items are populated (such as MAC)
*  `./templates/tplink_smartplug_kp115.xml` - Zabbix template which basically extends the base template to support all items that are available on the KP115 (EU) variant
*  `Containerfile` - Containerfile used to build the actual container image available at [hub.docker.com/r/steffenscheib/tplink_smartplug_zabbix](https://hub.docker.com/r/steffenscheib/tplink_smartplug_zabbix)
*  `README.md` - This readme file
*  `LICENSE` - The GPLv2 license

## Todo
* Nothing?
 
## Contributing
Contributions and feature requests are always welcome!

If you have any additions, examples or bugfixes ready, feel free to create a pull request on GitHub. The pull requests will be reviewed and will be merged as soon as possible. To ease the process of merging the pull requests, please create one pull request per feature/fix, so those can be selectively included.

