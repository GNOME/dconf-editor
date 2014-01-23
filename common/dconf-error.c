/*
 * Copyright © 2013 Canonical Limited
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the licence, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, see <http://www.gnu.org/licenses/>.
 *
 * Author: Ryan Lortie <desrt@desrt.ca>
 */

#include "config.h"

#include "dconf-error.h"

/**
 * SECTION:error
 * @title: DConfError
 * @short_description: GError error codes
 *
 * These are the error codes that can be returned from dconf APIs.
 **/

/**
 * DCONF_ERROR:
 *
 * The error domain of DConf.
 *
 * Since: 0.20
 **/

/**
 * DConfError:
 * @DCONF_ERROR_FAILED: generic error
 * @DCONF_ERROR_PATH: the path given for the operation was a valid path
 *   or was not of the expected type (dir vs. key)
 * @DCONF_ERROR_NOT_WRITABLE: the given key was not writable
 *
 * Possible errors from DConf functions.
 *
 * Since: 0.20
 **/

G_DEFINE_QUARK (dconf_error, dconf_error)
