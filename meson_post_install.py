#!/usr/bin/env python3

import os
import subprocess

if not os.environ.get('DESTDIR'):
  prefix = os.environ.get('MESON_INSTALL_PREFIX', '/usr/local')
  datadir = os.path.join(prefix, 'share')

  print('Updating icon cache...')
  icon_cache_dir = os.path.join(datadir, 'icons', 'hicolor')
  if not os.path.exists(icon_cache_dir):
    os.makedirs(icon_cache_dir)
  subprocess.call(['gtk-update-icon-cache',
                   '--quiet', '--force', '--ignore-theme-index',
                   icon_cache_dir])

  print('Compiling GSettings schemas...')
  schemas_dir = os.path.join(datadir, 'glib-2.0', 'schemas')
  if not os.path.exists(schemas_dir):
    os.makedirs(schemas_dir)
  subprocess.call(['glib-compile-schemas', schemas_dir])
