#!/bin/bash
[[ -n "${ZBX_SERVER}" ]] || {
  echo "ERROR: ZBX_SERVER environment variable is not set!" >&2;
  exit 1;
};

[[ -n "${SMARTPLUG_HOST}" ]] || {
  echo "ERROR: SMARTPLUG_HOST environment variable is not set!" >&2;
  exit 2;
};
